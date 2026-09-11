import Foundation

public enum RemovalOutcome: String, Sendable {
    case trashed, refused, skipped, failed, recoveryRequired
}

public struct RemovalResult: Sendable {
    public let itemID: UUID
    public let originalPath: String
    public let outcome: RemovalOutcome
    public let recoveryPath: String?
    public let detail: String?
}

public struct RemovalReport: Sendable {
    public let sessionID: UUID
    public let results: [RemovalResult]
    public let cancelled: Bool
    /// A non-nil value means processing stopped; the last filesystem action may
    /// have completed without a durable outcome record. Preserve the manifest.
    public let journalFailure: String?
}

/// Internal seams exercise failures around real namespace operations on fixtures.
/// The shipping transport is the only location that invokes Foundation Trash.
struct RemovalOperations: Sendable {
    var trash: @Sendable (String) throws -> String
    var isInTrash: @Sendable (String) throws -> Bool
    var beforeCapture: @Sendable (String) throws -> Void = { _ in }
    var beforeCaptureRename: @Sendable (String) throws -> Void = { _ in }
    var afterCapture: @Sendable (String) throws -> Void = { _ in }
    var beforeTrash: @Sendable (String) throws -> Void = { _ in }
    var beforeRestore: @Sendable (String) throws -> Void = { _ in }
    var beforeJournal: @Sendable (ManifestEvent) throws -> Void = { _ in }

    static let live = RemovalOperations(
        trash: { path in
            var destination: NSURL?
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path, isDirectory: false), resultingItemURL: &destination)
            guard let destination else { throw RemovalSafetyError.unsafeRecoveryLocation }
            return destination.path ?? ""
        },
        isInTrash: { path in
            var relationship: FileManager.URLRelationship = .other
            try FileManager.default.getRelationship(&relationship, of: .trashDirectory, in: [],
                                                    toItemAt: URL(fileURLWithPath: path, isDirectory: false))
            return relationship == .contains
        }
    )
}

/// Removal is serial and requires a caller-supplied explicit reviewed selection.
/// There is no timer, automatic selection, directory removal, or elevation path.
public actor RemovalEngine {
    private let policy: SafeRoots
    private let fileSystem: RemovalFileSystem
    private let manifest: ManifestStore
    private let operations: RemovalOperations

    public init(manifest: ManifestStore) throws {
        let policy = try SafeRoots.currentUser()
        self.init(policy: policy, manifest: manifest)
    }

    init(policy: SafeRoots, manifest: ManifestStore, operations: RemovalOperations = .live,
         calculator: SizeCalculator = SizeCalculator()) {
        self.policy = policy
        self.fileSystem = RemovalFileSystem(policy: policy, calculator: calculator)
        self.manifest = manifest
        self.operations = operations
    }

    public func moveToTrash(reviewedFindings: [Finding], ruleSet: RuleSet, appVersion: String,
                            now: Date = Date()) throws -> RemovalReport {
        try Task.checkCancellation()
        guard !reviewedFindings.isEmpty, reviewedFindings.count <= 256,
              now.timeIntervalSinceReferenceDate.isFinite else { throw RemovalSafetyError.invalidSelection }
        var paths = Set<Data>()
        for finding in reviewedFindings {
            guard paths.insert(Data(finding.resolvedPath.utf8)).inserted, finding.observation != nil else {
                throw RemovalSafetyError.invalidSelection
            }
        }
        return try withoutDatalessMaterialization {
            try manifest.withExclusiveOperation {
                let sessionID = try manifest.createSession(appVersion: appVersion, ruleSetVersion: ruleSet.version, now: now)
                var results: [RemovalResult] = []
                for finding in reviewedFindings {
                    if Task.isCancelled { return RemovalReport(sessionID: sessionID, results: results, cancelled: true, journalFailure: nil) }
                    let item = ManifestItem(id: UUID(), originalPath: finding.resolvedPath, ruleID: finding.ruleID,
                                            allocatedSize: finding.allocatedSize, identity: ManifestIdentity(finding.observation!))
                    let attempt = process(finding, item: item, sessionID: sessionID, rules: ruleSet, now: now)
                    results.append(attempt.result)
                    if let failure = attempt.journalFailure {
                        return RemovalReport(sessionID: sessionID, results: results, cancelled: Task.isCancelled, journalFailure: failure)
                    }
                }
                return RemovalReport(sessionID: sessionID, results: results, cancelled: Task.isCancelled, journalFailure: nil)
            }
        }
    }

    private func process(_ finding: Finding, item: ManifestItem, sessionID: UUID, rules: RuleSet, now: Date) -> Attempt {
        var stagePath: String?
        var trashPath: String?
        var captured = false
        var trashStarted = false
        var source: RemovalLocation?
        do {
            let rule = try matchingRule(finding, rules: rules, now: now)
            let opened = try fileSystem.open(finding.resolvedPath, includeSize: true, skipBackup: rule.skipExcludedFromBackup)
            try fileSystem.requireOrdinaryOwnedFile(opened, expected: item.identity)
            guard opened.metadata.fingerprint == finding.observation, opened.metadata.allocatedSize == finding.allocatedSize else {
                throw RemovalSafetyError.changed
            }
            let guarder = PathGuard(policy: policy)
            let receipt = try guarder.validate(item.originalPath)
            source = opened
            stagePath = try fileSystem.stagingPath(for: item, sessionID: sessionID)
            // This record is durable before even creating a transaction directory.
            try record(.prepared, item: item, sessionID: sessionID, stagingPath: stagePath)
            let staging = try fileSystem.makeStagingParent(for: item, sessionID: sessionID)
            try operations.beforeCapture(item.originalPath)
            _ = try guarder.revalidate(receipt)
            let last = try fileSystem.open(item.originalPath, includeSize: true, skipBackup: rule.skipExcludedFromBackup)
            try fileSystem.requireOrdinaryOwnedFile(last, expected: item.identity)
            guard last.metadata.fingerprint == finding.observation,
                  last.metadata.allocatedSize == finding.allocatedSize else { throw RemovalSafetyError.changed }
            try fileSystem.verify(opened.anchors)
            try fileSystem.move(last, into: staging, name: item.id.uuidString) {
                try operations.beforeCaptureRename(item.originalPath)
            }
            captured = true
            try operations.afterCapture(stagePath!)
            let staged = try fileSystem.verifiedStage(stagePath!, item: item, sessionID: sessionID)
            let retained = try fileSystem.calculator.inspect(descriptor: opened.descriptor.value, path: stagePath!, includeSize: false)
            guard retained.fingerprint == staged.metadata.fingerprint else { throw RemovalSafetyError.changed }
            try fileSystem.verify(opened.anchors)
            try record(.staged, item: item, sessionID: sessionID, stagingPath: stagePath)
            try operations.beforeTrash(stagePath!)
            let ready = try fileSystem.verifiedStage(stagePath!, item: item, sessionID: sessionID)
            guard ready.metadata.fingerprint == staged.metadata.fingerprint else { throw RemovalSafetyError.changed }
            try fileSystem.verify(opened.anchors)
            trashStarted = true
            trashPath = try operations.trash(stagePath!)
            let trashed = try fileSystem.open(trashPath!)
            try fileSystem.requireOrdinaryOwnedFile(trashed, expected: item.identity)
            guard try operations.isInTrash(trashPath!) else { throw RemovalSafetyError.unsafeRecoveryLocation }
            try fileSystem.verify(trashed.anchors)
            try trashed.descriptor.requirePath(trashPath!)
            try record(.trashed, item: item, sessionID: sessionID, stagingPath: stagePath, trashPath: trashPath)
            return Attempt(result: result(item, .trashed, path: trashPath), journalFailure: nil)
        } catch let failure as JournalFailure {
            return Attempt(result: result(item, captured ? .recoveryRequired : .failed, path: trashPath ?? stagePath,
                                          detail: "The operation record could not be saved. Preserve the manifest and recorded locations."),
                           journalFailure: failure.detail)
        } catch {
            let detail = removalExplanation(error)
            var outcome: RemovalOutcome = captured ? .recoveryRequired : refusalOutcome(error)
            var path: String? = captured ? (trashPath ?? stagePath) : nil
            // Only a verified original object may be rolled back. EXCL and the
            // retained parent chain refuse a replacement file or moved ancestor.
            if captured, trashPath == nil, let stagePath {
                do {
                    try fileSystem.restoreStage(stagePath, item: item, sessionID: sessionID, expectedParents: source?.anchors)
                    outcome = .failed
                    path = nil
                } catch { /* The recorded staging item is preserved for review. */ }
            }
            // A transport may have succeeded without returning a usable URL.
            // Missing stage after a started call is uncertain, never "not moved".
            if trashStarted && outcome != .failed { outcome = .recoveryRequired }
            let action: ManifestAction = outcome == .recoveryRequired ? .recoveryRequired : (captured ? .failed : .refused)
            do {
                try record(action, item: item, sessionID: sessionID, stagingPath: stagePath, trashPath: trashPath, detail: detail)
                return Attempt(result: result(item, outcome, path: path, detail: detail), journalFailure: nil)
            } catch {
                return Attempt(result: result(item, outcome, path: path, detail: detail), journalFailure: "The failure outcome could not be saved. Preserve the session record.")
            }
        }
    }

    private func matchingRule(_ finding: Finding, rules: RuleSet, now: Date) throws -> Rule {
        _ = try policy.validateCandidate(finding.resolvedPath)
        guard let rule = rules.rules.first(where: { $0.id == finding.ruleID }), rule.enabled && rule.verified,
              rule.module == finding.module, rule.risk == finding.risk, rule.reason == finding.reason,
              rule.regenerationCost == finding.regenerationCost else { throw RemovalSafetyError.invalidSelection }
        var matches = false
        for declared in rule.paths {
            let root = try policy.validateScanRoot(declared)
            if SafeRoots.isWithin(finding.resolvedPath, root: root), !SafeRoots.sameBytes(finding.resolvedPath, root) {
                let depth = finding.resolvedPath.split(separator: "/").count - root.split(separator: "/").count
                if (1...rule.match.maxDepth).contains(depth) { matches = true }
            }
        }
        guard matches, finding.modifiedAt.timeIntervalSinceReferenceDate.isFinite else { throw RemovalSafetyError.invalidSelection }
        if let days = rule.conditions.first?.olderThanDays,
           finding.modifiedAt >= now.addingTimeInterval(-Double(days) * 86_400) { throw RemovalSafetyError.invalidSelection }
        return rule
    }

    private func record(_ action: ManifestAction, item: ManifestItem, sessionID: UUID,
                        stagingPath: String? = nil, trashPath: String? = nil, detail: String? = nil) throws {
        do {
            let event = ManifestEvent(timestamp: Date(), action: action, item: item,
                                      stagingPath: stagingPath, trashPath: trashPath, detail: detail)
            try operations.beforeJournal(event)
            try manifest.append(event, to: sessionID)
        } catch { throw JournalFailure(detail: "The session journal could not be written durably. No further items were processed.") }
    }

    private func result(_ item: ManifestItem, _ outcome: RemovalOutcome, path: String? = nil, detail: String? = nil) -> RemovalResult {
        RemovalResult(itemID: item.id, originalPath: item.originalPath, outcome: outcome, recoveryPath: path, detail: detail)
    }

    private func refusalOutcome(_ error: any Error) -> RemovalOutcome {
        switch error {
        case ScanMetadataError.dataless, ScanMetadataError.excludedFromBackup, RemovalSafetyError.ownership,
             RemovalSafetyError.multipleLinks, RemovalSafetyError.missing, PathGuardError.missing: .skipped
        default: .refused
        }
    }
}

private struct Attempt {
    let result: RemovalResult
    let journalFailure: String?
}

private struct JournalFailure: Error {
    let detail: String
}
