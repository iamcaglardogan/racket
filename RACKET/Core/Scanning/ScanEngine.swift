import Darwin
import Foundation

/// Headless, read-only orchestration. Each module has one bounded task group;
/// modules run sequentially so their combined concurrency stays bounded too.
public struct ScanEngine: Sendable {
    private let policy: SafeRoots
    private let concurrencyLimit: Int
    private let resultLimit: Int
    private let walk: @Sendable (String, Int, Bool) throws -> DirectoryWalk

    public init() throws {
        let policy = try SafeRoots.currentUser()
        let walker = DirectoryWalker(policy: policy)
        self.init(policy: policy, concurrencyLimit: Self.physicalCoreCount()) { path, depth, skip in
            try walker.walk(path: path, maxDepth: depth, skipExcludedFromBackup: skip)
        }
    }

    /// Only tests inside the module can replace walking or the home policy.
    init(
        policy: SafeRoots,
        concurrencyLimit: Int,
        resultLimit: Int = 100_000,
        walk: @escaping @Sendable (String, Int, Bool) throws -> DirectoryWalk
    ) {
        self.policy = policy
        self.concurrencyLimit = min(64, max(1, concurrencyLimit))
        self.resultLimit = min(100_000, max(1, resultLimit))
        self.walk = walk
    }

    public func scan(
        ruleSet: RuleSet,
        now: Date = Date(),
        progress: @Sendable (ScanProgress) async -> Void = { _ in }
    ) async throws -> ScanReport {
        try Task.checkCancellation()
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw ScanEngineError.invalidReferenceDate }
        let orderedRules = ruleSet.rules.filter { $0.enabled && $0.verified }.sorted {
            if $0.module != $1.module { return Self.before($0.module.rawValue, $1.module.rawValue) }
            return Self.before($0.id, $1.id)
        }
        // RuleSet supports injected validators for explicit Data fixtures. The
        // engine independently applies its own compiled policy before any walk.
        for rule in orderedRules {
            for path in rule.paths {
                try Task.checkCancellation()
                try policy.validateRulePath(path)
            }
        }

        var state = CollectedScan(resultLimit: resultLimit)
        let modules = Array(Set(orderedRules.map(\.module))).sorted { Self.before($0.rawValue, $1.rawValue) }
        for module in modules {
            try Task.checkCancellation()
            let jobs = orderedRules.filter { $0.module == module }.flatMap { rule in
                rule.paths.sorted(by: Self.before).map { ScanJob(rule: rule, path: $0) }
            }
            await progress(ScanProgress(module: module, completedPaths: 0, totalPaths: jobs.count))
            try Task.checkCancellation()
            let remaining = resultLimit - state.observationCount
            let results = try await collect(jobs, module: module, remainingLimit: remaining, progress: progress)
            // Task completion order must not decide the winning explanation.
            for result in results.sorted(by: { $0.index < $1.index }) {
                try Task.checkCancellation()
                try state.consume(result.walk, job: jobs[result.index], now: now, policy: policy)
            }
        }
        try Task.checkCancellation()
        return ScanReport(
            ruleSetVersion: ruleSet.version, findings: state.findings, issues: state.issues,
            reportedAllocatedBytes: state.bytes, visitedEntryCount: state.visited
        )
    }

    private func collect(
        _ jobs: [ScanJob], module: Rule.Module, remainingLimit: Int,
        progress: @Sendable (ScanProgress) async -> Void
    ) async throws -> [CompletedWalk] {
        try await withThrowingTaskGroup(of: CompletedWalk.self) { group in
            var next = 0
            var results: [CompletedWalk] = []
            var observations = 0
            func start(_ index: Int) {
                let job = jobs[index]
                group.addTask {
                    try Task.checkCancellation()
                    let result = try walk(job.path, job.rule.match.maxDepth, job.rule.skipExcludedFromBackup)
                    try Task.checkCancellation()
                    return CompletedWalk(index: index, walk: result)
                }
            }
            while next < min(concurrencyLimit, jobs.count) {
                start(next)
                next += 1
            }
            while let result = try await group.next() {
                try Task.checkCancellation()
                let files = result.walk.files.count
                let issues = result.walk.issues.count
                guard files <= remainingLimit - observations,
                      issues <= remainingLimit - observations - files else {
                    group.cancelAll()
                    throw ScanEngineError.resourceLimitExceeded
                }
                observations += files + issues
                results.append(result)
                await progress(ScanProgress(module: module, completedPaths: results.count, totalPaths: jobs.count))
                try Task.checkCancellation()
                if next < jobs.count {
                    start(next)
                    next += 1
                }
            }
            return results
        }
    }

    private static func before(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    private static func physicalCoreCount() -> Int {
        var count: Int32 = 1
        var size = MemoryLayout<Int32>.size
        let result = "hw.physicalcpu".withCString { sysctlbyname($0, &count, &size, nil, 0) }
        guard result == 0, count > 0 else { return 1 }
        return Int(count)
    }
}

private struct ScanJob: Sendable {
    let rule: Rule
    let path: String
}

private struct CompletedWalk: Sendable {
    let index: Int
    let walk: DirectoryWalk
}

private struct CollectedScan {
    let resultLimit: Int
    var observationCount = 0
    var findings: [Finding] = []
    var issues: [ScanIssue] = []
    var bytes: UInt64 = 0
    var visited: UInt64 = 0
    private var paths: Set<Data> = []
    private var identities: Set<ScanFileIdentity> = []

    init(resultLimit: Int) { self.resultLimit = resultLimit }

    mutating func consume(_ result: DirectoryWalk, job: ScanJob, now: Date, policy: SafeRoots) throws {
        let (newVisited, overflow) = visited.addingReportingOverflow(result.visitedEntryCount)
        guard !overflow else { throw ScanEngineError.visitedEntryOverflow }
        visited = newVisited
        guard result.files.count <= resultLimit - observationCount,
              result.issues.count <= resultLimit - observationCount - result.files.count else {
            throw ScanEngineError.resourceLimitExceeded
        }
        observationCount += result.files.count + result.issues.count
        for issue in result.issues.sorted(by: { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }) {
            try Task.checkCancellation()
            appendIssue(issue.path, reason: issue.reason, rule: job.rule)
        }
        for file in result.files.sorted(by: { $0.resolvedPath.utf8.lexicographicallyPrecedes($1.resolvedPath.utf8) }) {
            try Task.checkCancellation()
            do {
                _ = try policy.validateCandidate(file.resolvedPath)
            } catch let refusal as PathGuardError {
                appendIssue(file.resolvedPath, reason: .pathRefused(refusal), rule: job.rule)
                continue
            }
            guard file.modifiedAt.timeIntervalSinceReferenceDate.isFinite else {
                appendIssue(file.resolvedPath, reason: .unsupportedMetadata, rule: job.rule)
                continue
            }
            if let days = job.rule.conditions.first?.olderThanDays,
               file.modifiedAt >= now.addingTimeInterval(-Double(days) * 86_400) {
                appendIssue(file.resolvedPath, reason: .notOldEnough, rule: job.rule)
                continue
            }
            let path = Data(file.resolvedPath.utf8)
            guard !paths.contains(path), !identities.contains(file.identity) else {
                appendIssue(file.resolvedPath, reason: .duplicate, rule: job.rule)
                continue
            }
            let (sum, sizeOverflow) = bytes.addingReportingOverflow(file.allocatedSize)
            guard !sizeOverflow else { throw ScanEngineError.sizeOverflow }
            paths.insert(path)
            identities.insert(file.identity)
            bytes = sum
            findings.append(Finding(
                resolvedPath: file.resolvedPath, allocatedSize: file.allocatedSize,
                modifiedAt: file.modifiedAt, ruleID: job.rule.id, module: job.rule.module,
                risk: job.rule.risk, reason: job.rule.reason, regenerationCost: job.rule.regenerationCost,
                observation: file.observation
            ))
        }
    }

    private mutating func appendIssue(_ path: String, reason: ScanIssueReason, rule: Rule) {
        issues.append(ScanIssue(path: path, ruleID: rule.id, module: rule.module, reason: reason))
    }
}
