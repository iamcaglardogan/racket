import Foundation

public enum UndoOutcome: String, Sendable {
    case restored, conflict, missing, refused, recoveryRequired, alreadyRestored
}

public struct UndoResult: Sendable {
    public let itemID: UUID
    public let originalPath: String
    public let outcome: UndoOutcome
    public let recoveryPath: String?
    public let detail: String?
}

public struct UndoReport: Sendable {
    public let sessionID: UUID
    public let results: [UndoResult]
    public let cancelled: Bool
    public let journalFailure: String?
}

/// Restores authenticated, individually verified one-link files. A journal is
/// evidence of an operation, never authority to overwrite or create a directory.
public actor UndoService {
    private let policy: SafeRoots
    private let manifest: ManifestStore
    private let operations: RemovalOperations
    private let fileSystem: RemovalFileSystem

    public init(manifest: ManifestStore) throws {
        self.init(policy: try SafeRoots.currentUser(), manifest: manifest)
    }

    init(policy: SafeRoots, manifest: ManifestStore, operations: RemovalOperations = .live,
         calculator: SizeCalculator = SizeCalculator()) {
        self.policy = policy
        self.manifest = manifest
        self.operations = operations
        fileSystem = RemovalFileSystem(policy: policy, calculator: calculator)
    }

    public func restore(sessionID: UUID) throws -> UndoReport {
        try withoutDatalessMaterialization {
            try manifest.withExclusiveOperation {
                // Authentication and the whole session's transition validation
                // complete before any item is allowed to change the namespace.
                let session = try manifest.read(sessionID)
                let histories = try validateHistory(session)
                var results: [UndoResult] = []
                for history in histories {
                    if Task.isCancelled {
                        return UndoReport(sessionID: sessionID, results: results, cancelled: true, journalFailure: nil)
                    }
                    let attempt = restore(history, sessionID: sessionID)
                    results.append(attempt.result)
                    if let failure = attempt.journalFailure {
                        return UndoReport(sessionID: sessionID, results: results,
                                          cancelled: Task.isCancelled, journalFailure: failure)
                    }
                }
                return UndoReport(sessionID: sessionID, results: results,
                                  cancelled: Task.isCancelled, journalFailure: nil)
            }
        }
    }

    private func validateHistory(_ session: ManifestSession) throws -> [UndoHistory] {
        var histories: [UUID: UndoHistory] = [:]
        var order: [UUID] = []
        var pathOwners: [Data: UUID] = [:]
        for event in session.events {
            guard event.timestamp.timeIntervalSinceReferenceDate.isFinite else { throw RemovalSafetyError.invalidHistory }
            let item = event.item
            for path in [item.originalPath, event.stagingPath, event.trashPath].compactMap({ $0 }) {
                guard SafeRoots.sameBytes(try SafeRoots.normalizeAbsolute(path), path), path != "/" else {
                    throw RemovalSafetyError.invalidHistory
                }
                let bytes = Data(path.utf8)
                if let owner = pathOwners[bytes], owner != item.id { throw RemovalSafetyError.invalidHistory }
                pathOwners[bytes] = item.id
            }
            if let staging = event.stagingPath {
                guard SafeRoots.sameBytes(staging, try fileSystem.stagingPath(for: item, sessionID: session.id)),
                      !SafeRoots.sameBytes(staging, item.originalPath) else { throw RemovalSafetyError.invalidHistory }
            }
            if let trash = event.trashPath {
                guard !SafeRoots.sameBytes(trash, item.originalPath),
                      event.stagingPath.map({ !SafeRoots.sameBytes(trash, $0) }) ?? true else {
                    throw RemovalSafetyError.invalidHistory
                }
            }
            if var history = histories[item.id] {
                guard history.item == item, allowed(event.action, after: history.lastAction),
                      event.stagingPath == history.stagingPath else { throw RemovalSafetyError.invalidHistory }
                if let trash = history.trashPath {
                    guard event.trashPath == trash else { throw RemovalSafetyError.invalidHistory }
                } else if event.trashPath != nil && event.action != .trashed && event.action != .recoveryRequired {
                    throw RemovalSafetyError.invalidHistory
                }
                if event.action == .trashed && event.trashPath == nil { throw RemovalSafetyError.invalidHistory }
                history.lastAction = event.action
                history.trashPath = event.trashPath
                histories[item.id] = history
            } else {
                guard event.action == .prepared || event.action == .refused,
                      event.trashPath == nil,
                      event.action != .prepared || event.stagingPath != nil else { throw RemovalSafetyError.invalidHistory }
                histories[item.id] = UndoHistory(item: item, stagingPath: event.stagingPath,
                                                trashPath: nil, lastAction: event.action)
                order.append(item.id)
            }
        }
        return order.compactMap { histories[$0] }
    }

    private func allowed(_ next: ManifestAction, after previous: ManifestAction) -> Bool {
        switch previous {
        case .prepared: [.staged, .failed, .refused, .recoveryRequired, .restorePrepared].contains(next)
        case .staged: [.trashed, .failed, .recoveryRequired, .restorePrepared].contains(next)
        case .trashed, .recoveryRequired: next == .restorePrepared
        case .restorePrepared: [.restored, .restoreFailed, .restorePrepared].contains(next)
        case .restoreFailed: next == .restorePrepared
        case .restored, .failed, .refused: false
        }
    }

    private func restore(_ history: UndoHistory, sessionID: UUID) -> UndoAttempt {
        let item = history.item
        if history.lastAction == .restored {
            return UndoAttempt(result: result(item, .alreadyRestored), journalFailure: nil)
        }
        if history.lastAction == .failed || history.lastAction == .refused {
            return UndoAttempt(result: result(item, .refused, detail: "The removal did not complete. This item is not eligible for undo."), journalFailure: nil)
        }
        let sourcePath = history.trashPath ?? history.stagingPath
        var prepared = false
        var moved = false
        do {
            _ = try policy.validateCandidate(item.originalPath)
            guard let sourcePath else { throw RemovalSafetyError.invalidHistory }
            // A interrupted restore may have moved the file before saving its
            // outcome. Accept only the original inode, and only with the known
            // source now absent; an arbitrary same-name file is never evidence.
            if history.lastAction == .restorePrepared,
               try sourceIsMissing(sourcePath), try originalMatches(item) {
                moved = true
                try record(.restored, history: history, sessionID: sessionID,
                           detail: "Verified the original item after an interrupted restore.")
                return UndoAttempt(result: result(item, .restored), journalFailure: nil)
            }

            let source = try verifiedSource(history, sessionID: sessionID)
            let parent = try fileSystem.originalParent(for: item)
            try refuseOccupiedOriginal(item)
            try record(.restorePrepared, history: history, sessionID: sessionID)
            prepared = true
            try operations.beforeRestore(item.originalPath)
            let fresh = try verifiedSource(history, sessionID: sessionID)
            guard fresh.metadata.fingerprint == source.metadata.fingerprint else { throw RemovalSafetyError.changed }
            try fileSystem.verify(source.anchors)
            try fileSystem.move(fresh, into: parent, name: (item.originalPath as NSString).lastPathComponent)
            moved = true
            let restored = try fileSystem.open(item.originalPath)
            try fileSystem.requireOrdinaryOwnedFile(restored, expected: item.identity)
            let retained = try fileSystem.calculator.inspect(descriptor: fresh.descriptor.value,
                                                              path: item.originalPath, includeSize: false)
            guard retained.fingerprint == restored.metadata.fingerprint else { throw RemovalSafetyError.changed }
            try fileSystem.verify(parent.anchors)
            try parent.descriptor.requirePath(parent.path)
            try record(.restored, history: history, sessionID: sessionID)
            return UndoAttempt(result: result(item, .restored), journalFailure: nil)
        } catch let failure as UndoJournalFailure {
            return UndoAttempt(result: result(item, moved ? .recoveryRequired : .refused,
                                               path: moved ? item.originalPath : sourcePath,
                                               detail: "The restore record could not be saved. Preserve the recorded locations."),
                               journalFailure: failure.detail)
        } catch {
            let outcome: UndoOutcome
            if moved { outcome = .recoveryRequired }
            else {
                switch error {
                case RemovalSafetyError.conflict: outcome = .conflict
                case RemovalSafetyError.missing, PathGuardError.missing: outcome = .missing
                default: outcome = .refused
                }
            }
            let failureResult = result(item, outcome, path: moved ? item.originalPath : sourcePath,
                                       detail: removalExplanation(error))
            if prepared {
                // A completed rename with failed post-verification stays an
                // unresolved intent, so the next run can reconcile its identity.
                do { try record(moved ? .restorePrepared : .restoreFailed, history: history, sessionID: sessionID, detail: failureResult.detail) }
                catch {
                    return UndoAttempt(result: failureResult, journalFailure: "The restore failure could not be saved. No further items were processed.")
                }
            }
            return UndoAttempt(result: failureResult, journalFailure: nil)
        }
    }

    private func verifiedSource(_ history: UndoHistory, sessionID: UUID) throws -> RemovalLocation {
        if let trash = history.trashPath {
            let source = try fileSystem.open(trash)
            try fileSystem.requireOrdinaryOwnedFile(source, expected: history.item.identity)
            guard try operations.isInTrash(trash) else { throw RemovalSafetyError.unsafeRecoveryLocation }
            try fileSystem.verify(source.anchors)
            try source.descriptor.requirePath(trash)
            return source
        }
        guard let stage = history.stagingPath else { throw RemovalSafetyError.invalidHistory }
        return try fileSystem.verifiedStage(stage, item: history.item, sessionID: sessionID)
    }

    private func sourceIsMissing(_ path: String) throws -> Bool {
        do { _ = try fileSystem.open(path); return false }
        catch RemovalSafetyError.missing { return true }
        catch PathGuardError.missing { return true }
    }

    private func originalMatches(_ item: ManifestItem) throws -> Bool {
        let original = try fileSystem.open(item.originalPath)
        try fileSystem.requireOrdinaryOwnedFile(original, expected: item.identity)
        _ = try fileSystem.originalParent(for: item)
        return true
    }

    private func refuseOccupiedOriginal(_ item: ManifestItem) throws {
        do {
            _ = try fileSystem.open(item.originalPath)
        } catch RemovalSafetyError.missing { return }
        catch PathGuardError.missing { return }
        throw RemovalSafetyError.conflict
    }

    private func record(_ action: ManifestAction, history: UndoHistory, sessionID: UUID, detail: String? = nil) throws {
        do {
            let event = ManifestEvent(timestamp: Date(), action: action, item: history.item,
                                      stagingPath: history.stagingPath, trashPath: history.trashPath, detail: detail)
            try operations.beforeJournal(event)
            try manifest.append(event, to: sessionID)
        } catch { throw UndoJournalFailure(detail: "The restore journal could not be written durably. No further items were processed.") }
    }

    private func result(_ item: ManifestItem, _ outcome: UndoOutcome, path: String? = nil, detail: String? = nil) -> UndoResult {
        UndoResult(itemID: item.id, originalPath: item.originalPath, outcome: outcome, recoveryPath: path, detail: detail)
    }
}

private struct UndoHistory {
    let item: ManifestItem
    let stagingPath: String?
    var trashPath: String?
    var lastAction: ManifestAction
}

private struct UndoAttempt {
    let result: UndoResult
    let journalFailure: String?
}

private struct UndoJournalFailure: Error { let detail: String }
