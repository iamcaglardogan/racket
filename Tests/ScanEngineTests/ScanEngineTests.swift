import Foundation
import XCTest
@testable import RacketCore

// XCTest creates independent instances. All concurrent fixture state below is
// isolated in actors or a lock-protected probe, never mutable test-case fields.
final class ScanEngineTests: XCTestCase, @unchecked Sendable {
    private static let home = "/synthetic-scan-home"
    private static let root = home + "/Library/Caches"
    private static let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func rule(
        _ id: String = "fixture.a", module: String = "creative", paths: [String]? = nil,
        age: Int? = nil, risk: String = "regenerable", enabled: Bool = true,
        verified: Bool = true, skip: Bool = false
    ) -> [String: Any] {
        [
            "id": id, "module": module, "title": "Synthetic cache",
            "producers": ["org.example.Fixture"], "paths": paths ?? [Self.root + "/" + id],
            "match": ["kind": "directoryContents", "maxDepth": 2],
            "conditions": age.map { [["olderThanDays": $0]] } ?? [],
            "risk": risk, "reason": "Reason for " + id,
            "regenerationCost": "Regeneration cost for " + id,
            "citation": "https://example.org/fixture", "enabled": enabled,
            "verified": verified, "skipExcludedFromBackup": skip
        ]
    }

    private func rules(_ objects: [[String: Any]]) throws -> RuleSet {
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "version": "1.0.0", "rules": objects])
        // Deliberately permissive to prove the engine applies compiled policy.
        return try RuleSet.decode(data) { _ in }
    }

    private func engine(
        concurrency: Int = 2, limit: Int = 100_000,
        walk: @escaping @Sendable (String, Int, Bool) throws -> DirectoryWalk
    ) throws -> ScanEngine {
        ScanEngine(policy: try SafeRoots(homeDirectory: Self.home), concurrencyLimit: concurrency, resultLimit: limit, walk: walk)
    }

    private static func file(
        _ path: String, bytes: UInt64 = 4_096, inode: UInt64 = 1,
        device: Int32 = 1, date: Date = now
    ) -> ScannedFile {
        ScannedFile(resolvedPath: path, allocatedSize: bytes, modifiedAt: date, identity: ScanFileIdentity(device: device, inode: inode))
    }

    private static func walk(_ files: [ScannedFile] = [], issues: [WalkIssue] = [], visited: UInt64 = 1) -> DirectoryWalk {
        DirectoryWalk(files: files, issues: issues, visitedEntryCount: visited)
    }

    func testEmptyBundledRulesProduceAnEmptyReportWithoutWalking() async throws {
        let set = try RuleSet.loadBundled { _ in }
        let probe = EngineProbe()
        let scanner = try engine { _, _, _ in probe.record(); return Self.walk() }
        let report = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(report.reportedAllocatedBytes, 0)
        XCTAssertEqual(report.visitedEntryCount, 0)
        XCTAssertEqual(probe.calls, 0)
    }

    func testOnlyVerifiedEnabledRulesAreWalked() async throws {
        let set = try rules([rule("fixture.active"), rule("fixture.disabled", enabled: false), rule("fixture.unverified", enabled: false, verified: false)])
        let probe = EngineProbe()
        let scanner = try engine { path, depth, skip in
            probe.record(path: path, depth: depth, skip: skip)
            return Self.walk([Self.file(path + "/cache")])
        }
        let report = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(report.findings.map(\.ruleID), ["fixture.active"])
    }

    func testUnsafeDeclarationIsRefusedBeforeAnyWalkerCallDespitePermissiveRuleLoader() async throws {
        let set = try rules([rule("fixture.a"), rule("fixture.unsafe", paths: [Self.home + "/Library/Preferences"])])
        let probe = EngineProbe()
        let scanner = try engine { _, _, _ in probe.record(); return Self.walk() }
        do {
            _ = try await scanner.scan(ruleSet: set, now: Self.now)
            XCTFail("Unsafe declaration must fail before scanning")
        } catch let error as PathGuardError {
            XCTAssertEqual(error, .protectedPath)
        }
        XCTAssertEqual(probe.calls, 0)
    }

    func testOlderThanDaysUsesStrictBoundaryAndReportsEachNonmatch() async throws {
        let cutoff = Self.now.addingTimeInterval(-14 * 86_400)
        let set = try rules([rule(age: 14)])
        let scanner = try engine { path, _, _ in
            Self.walk([
                Self.file(path + "/older", inode: 1, date: cutoff.addingTimeInterval(-1)),
                Self.file(path + "/boundary", inode: 2, date: cutoff),
                Self.file(path + "/newer", inode: 3, date: cutoff.addingTimeInterval(1)),
                Self.file(path + "/future", inode: 4, date: Self.now.addingTimeInterval(1))
            ], visited: 4)
        }
        let report = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertEqual(report.findings.map { ($0.resolvedPath as NSString).lastPathComponent }, ["older"])
        XCTAssertEqual(report.issues.count, 3)
        XCTAssertTrue(report.issues.allSatisfy { $0.reason == .notOldEnough && $0.disposition == .skipped })
        XCTAssertEqual(report.reportedAllocatedBytes, 4_096)
    }

    func testFindingPreservesRuleExplanationRiskModuleAndObservedMetadata() async throws {
        let set = try rules([rule("fixture.media", module: "developer", risk: "recreatable")])
        let date = Self.now.addingTimeInterval(-60)
        let scanner = try engine { path, _, _ in Self.walk([Self.file(path + "/cache", bytes: 8_192, date: date)]) }
        let report = try await scanner.scan(ruleSet: set, now: Self.now)
        let finding = try XCTUnwrap(report.findings.first)
        XCTAssertEqual(finding.ruleID, "fixture.media")
        XCTAssertEqual(finding.module, .developer)
        XCTAssertEqual(finding.risk, .recreatable)
        XCTAssertEqual(finding.reason, "Reason for fixture.media")
        XCTAssertEqual(finding.regenerationCost, "Regeneration cost for fixture.media")
        XCTAssertEqual(finding.modifiedAt, date)
        XCTAssertEqual(finding.allocatedSize, 8_192)
        XCTAssertEqual(report.reportedAllocatedBytes, 8_192)
        XCTAssertEqual(report.ruleSetVersion, "1.0.0")
    }

    func testJudgementFindingsAreNeverPreselectable() async throws {
        let set = try rules([rule(risk: "judgement")])
        let scanner = try engine { path, _, _ in Self.walk([Self.file(path + "/cache")]) }
        let report = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertFalse(try XCTUnwrap(report.findings.first).isPreselectable)
    }

    func testOverlappingRulesHaveDeterministicWinnerIndependentOfCompletionOrder() async throws {
        let shared = Self.root + "/shared/cache"
        let set = try rules([rule("fixture.z", paths: [Self.root + "/shared"]), rule("fixture.a", paths: [Self.root])])
        let scanner = try engine { path, _, _ in
            if path == Self.root { Thread.sleep(forTimeInterval: 0.03) }
            return Self.walk([Self.file(shared)])
        }
        let report = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertEqual(report.findings.map(\.ruleID), ["fixture.a"])
        XCTAssertEqual(report.reportedAllocatedBytes, 4_096)
        XCTAssertEqual(report.issues.map(\.reason), [.duplicate])
        XCTAssertEqual(report.issues.first?.ruleID, "fixture.z")
    }

    func testHardlinksAndRepeatedBytePathsAreDeduplicated() async throws {
        let set = try rules([rule()])
        let scanner = try engine { path, _, _ in
            Self.walk([
                Self.file(path + "/a", inode: 10), Self.file(path + "/b", inode: 10),
                Self.file(path + "/c", inode: 20), Self.file(path + "/c", inode: 30)
            ], visited: 4)
        }
        let report = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertEqual(report.findings.count, 2)
        XCTAssertEqual(report.reportedAllocatedBytes, 8_192)
        XCTAssertEqual(report.issues.map(\.reason), [.duplicate, .duplicate])
        XCTAssertEqual(report.visitedEntryCount, 4)
    }

    func testDistinctUnicodeBytePathsAndSameInodeOnDifferentDevicesAreNotCollapsed() async throws {
        let set = try rules([rule()])
        let scanner = try engine { path, _, _ in
            Self.walk([Self.file(path + "/café", inode: 1, device: 1), Self.file(path + "/cafe\u{0301}", inode: 1, device: 2)])
        }
        let report = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertEqual(report.findings.count, 2)
        XCTAssertEqual(report.reportedAllocatedBytes, 8_192)
    }

    func testNonmatchingEarlierRuleDoesNotClaimFileFromLaterMatchingRule() async throws {
        let path = Self.root + "/shared"
        let set = try rules([rule("fixture.a", paths: [path], age: 14), rule("fixture.z", paths: [path])])
        let scanner = try engine { path, _, _ in Self.walk([Self.file(path + "/cache")]) }
        let report = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertEqual(report.findings.map(\.ruleID), ["fixture.z"])
        XCTAssertEqual(report.issues.map(\.reason), [.notOldEnough])
    }

    func testModulesRunSequentiallyWithHonestCompletedPathProgress() async throws {
        let set = try rules([rule("fixture.system", module: "system"), rule("fixture.creative.b"), rule("fixture.creative.a")])
        let progress = ProgressRecorder()
        let scanner = try engine { _, _, _ in Self.walk() }
        _ = try await scanner.scan(ruleSet: set, now: Self.now) { await progress.record($0) }
        let updates = await progress.values
        XCTAssertEqual(updates.map(\.module), [.creative, .creative, .creative, .system, .system])
        XCTAssertEqual(updates.map(\.completedPaths), [0, 1, 2, 0, 1])
        XCTAssertEqual(updates.map(\.totalPaths), [2, 2, 2, 1, 1])
    }

    func testConcurrentWalkJobsNeverExceedInjectedBound() async throws {
        let paths = (0..<8).map { Self.root + "/job\($0)" }
        let set = try rules([rule(paths: paths)])
        let probe = EngineProbe()
        let scanner = try engine(concurrency: 2) { _, _, _ in
            probe.enter()
            defer { probe.leave() }
            Thread.sleep(forTimeInterval: 0.015)
            return Self.walk()
        }
        _ = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertEqual(probe.calls, 8)
        XCTAssertGreaterThan(probe.maximumActive, 0)
        XCTAssertLessThanOrEqual(probe.maximumActive, 2)
    }

    func testNonpositiveConcurrencyClampsToOne() async throws {
        let set = try rules([rule(paths: (0..<3).map { Self.root + "/job\($0)" })])
        let probe = EngineProbe()
        let scanner = try engine(concurrency: 0) { _, _, _ in
            probe.enter()
            defer { probe.leave() }
            return Self.walk()
        }
        _ = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertEqual(probe.calls, 3)
        XCTAssertEqual(probe.maximumActive, 1)
    }

    func testBackupExclusionAndDepthArePassedToWalker() async throws {
        let set = try rules([rule("fixture.a", skip: true), rule("fixture.b", skip: false)])
        let probe = EngineProbe()
        let scanner = try engine(concurrency: 1) { path, depth, skip in
            probe.record(path: path, depth: depth, skip: skip)
            return Self.walk()
        }
        _ = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertEqual(probe.options.map(\.0), [2, 2])
        XCTAssertEqual(probe.options.map(\.1), [true, false])
    }

    func testWalkIssuesKeepDistinctRefusalSkipAndIncompleteDispositions() async throws {
        let set = try rules([rule()])
        let scanner = try engine { path, _, _ in
            Self.walk(issues: [
                WalkIssue(path: path + "/a", reason: .pathRefused(.symbolicLink)),
                WalkIssue(path: path + "/b", reason: .dataless),
                WalkIssue(path: path + "/c", reason: .metadataUnavailable(13)),
                WalkIssue(path: path + "/d", reason: .excludedFromBackup)
            ])
        }
        let report = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertEqual(report.issues.map(\.disposition), [.refused, .skipped, .incomplete, .skipped])
        XCTAssertTrue(report.issues.allSatisfy { $0.ruleID == "fixture.a" && $0.module == .creative })
    }

    func testUnexpectedUnsafeWalkerResultIsRefusedAndNotCounted() async throws {
        let set = try rules([rule()])
        let scanner = try engine { _, _, _ in Self.walk([Self.file(Self.home + "/Library/Preferences/settings")]) }
        let report = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.reportedAllocatedBytes, 0)
        XCTAssertEqual(report.issues.first?.reason, .pathRefused(.protectedPath))
    }

    func testByteOverflowThrowsInsteadOfWrappingOrReturningPartialReport() async throws {
        let set = try rules([rule()])
        let scanner = try engine { path, _, _ in
            Self.walk([Self.file(path + "/a", bytes: .max, inode: 1), Self.file(path + "/b", bytes: 1, inode: 2)])
        }
        do { _ = try await scanner.scan(ruleSet: set, now: Self.now); XCTFail("Expected overflow") }
        catch let error as ScanEngineError { XCTAssertEqual(error, .sizeOverflow) }
    }

    func testVisitedEntryOverflowThrowsInsteadOfWrapping() async throws {
        let set = try rules([rule(paths: [Self.root + "/a", Self.root + "/b"])])
        let scanner = try engine { path, _, _ in Self.walk(visited: path.hasSuffix("/a") ? .max : 1) }
        do { _ = try await scanner.scan(ruleSet: set, now: Self.now); XCTFail("Expected count overflow") }
        catch let error as ScanEngineError { XCTAssertEqual(error, .visitedEntryOverflow) }
    }

    func testAggregateResourceLimitStopsSchedulingBeforeAllJobsComplete() async throws {
        let set = try rules([rule(paths: (0..<5).map { Self.root + "/job\($0)" })])
        let probe = EngineProbe()
        let scanner = try engine(concurrency: 1, limit: 2) { path, _, _ in
            probe.record()
            return Self.walk(issues: (0..<3).map { WalkIssue(path: path + "/\($0)", reason: .dataless) })
        }
        do { _ = try await scanner.scan(ruleSet: set, now: Self.now); XCTFail("Expected resource limit") }
        catch let error as ScanEngineError { XCTAssertEqual(error, .resourceLimitExceeded) }
        XCTAssertEqual(probe.calls, 1)
    }

    func testResourceBudgetIncludesEarlierModulesAndDuplicateObservations() async throws {
        let path = Self.root + "/shared"
        let set = try rules([rule("fixture.a", paths: [path]), rule("fixture.b", module: "system", paths: [path])])
        let scanner = try engine(limit: 1) { path, _, _ in Self.walk([Self.file(path + "/cache")]) }
        do { _ = try await scanner.scan(ruleSet: set, now: Self.now); XCTFail("Duplicate observations still consume a resource budget") }
        catch let error as ScanEngineError { XCTAssertEqual(error, .resourceLimitExceeded) }
    }

    func testCancellationFromProgressReturnsNoPartialSuccessAndStopsNewJobs() async throws {
        let set = try rules([rule(paths: (0..<4).map { Self.root + "/job\($0)" })])
        let probe = EngineProbe()
        let scanner = try engine(concurrency: 1) { path, _, _ in
            probe.record()
            return Self.walk([Self.file(path + "/cache")])
        }
        let task = Task {
            try await scanner.scan(ruleSet: set, now: Self.now) { progress in
                if progress.completedPaths == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await task.value; XCTFail("Cancellation must not return a report") }
        catch is CancellationError {}
        XCTAssertEqual(probe.calls, 1)
    }

    func testWalkerCancellationPropagatesWithoutSuccessReport() async throws {
        let set = try rules([rule()])
        let scanner = try engine { _, _, _ in throw CancellationError() }
        do { _ = try await scanner.scan(ruleSet: set, now: Self.now); XCTFail("Expected cancellation") }
        catch is CancellationError {}
    }

    func testInvalidReferenceDateIsRefusedBeforeWalking() async throws {
        let set = try rules([rule()])
        let probe = EngineProbe()
        let scanner = try engine { _, _, _ in probe.record(); return Self.walk() }
        do { _ = try await scanner.scan(ruleSet: set, now: Date(timeIntervalSinceReferenceDate: .infinity)); XCTFail("Expected invalid date") }
        catch let error as ScanEngineError { XCTAssertEqual(error, .invalidReferenceDate) }
        XCTAssertEqual(probe.calls, 0)
    }

    func testInvalidFileDateIsReportedAsUnavailableMetadata() async throws {
        let set = try rules([rule()])
        let scanner = try engine { path, _, _ in Self.walk([Self.file(path + "/cache", date: Date(timeIntervalSinceReferenceDate: .nan))]) }
        let report = try await scanner.scan(ruleSet: set, now: Self.now)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.issues.first?.reason, .unsupportedMetadata)
    }
}

private actor ProgressRecorder {
    var values: [ScanProgress] = []
    func record(_ progress: ScanProgress) { values.append(progress) }
}

private final class EngineProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var active = 0
    private var maximum = 0
    private var recordedOptions: [(Int, Bool)] = []

    var calls: Int { lock.withLock { callCount } }
    var maximumActive: Int { lock.withLock { maximum } }
    var options: [(Int, Bool)] { lock.withLock { recordedOptions } }

    func record(path: String = "", depth: Int = 0, skip: Bool = false) {
        lock.withLock { callCount += 1; recordedOptions.append((depth, skip)) }
    }
    func enter() {
        lock.withLock { callCount += 1; active += 1; maximum = max(maximum, active) }
    }
    func leave() { lock.withLock { active -= 1 } }
}
