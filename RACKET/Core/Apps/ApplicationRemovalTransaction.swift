import Darwin
import Foundation

/// Dedicated app-only sessions reuse the authenticated durable journal while
/// keeping directory authority entirely separate from ordinary file cleanup.
struct ApplicationRemovalTransaction: Sendable {
    let policy: ApplicationPolicy
    let manifest: ManifestStore
    var operations: RemovalOperations = .live
    var calculator = SizeCalculator()
    var activity = ApplicationProcessActivity()

    private var fileSystem: ApplicationFileSystem { ApplicationFileSystem(policy: policy, calculator: calculator) }
    private static let rulePrefix = "application-bundle|"

    func remove(_ selection: ApplicationRemovalSelection, appVersion: String, now: Date) throws -> RemovalReport {
        try Task.checkCancellation()
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw RemovalSafetyError.invalidSelection }
        try policy.validateRemovalPath(selection.application.path)
        guard selection.application.canUninstall, ApplicationPolicy.validBundleIdentifier(selection.application.bundleIdentifier),
              Self.validDigest(selection.digest) else { throw RemovalSafetyError.invalidSelection }
        return try withoutDatalessMaterialization {
            try manifest.withExclusiveOperation {
                let sessionID = try manifest.createSession(appVersion: appVersion,
                                                          ruleSetVersion: ApplicationRemovalSelection.manifestVersion, now: now)
                let item = ManifestItem(id: UUID(), originalPath: selection.application.path,
                                        ruleID: Self.rulePrefix + selection.application.bundleIdentifier + "|" + selection.digest,
                                        allocatedSize: selection.allocatedSize, identity: selection.identity)
                return process(selection, item: item, sessionID: sessionID)
            }
        }
    }

    private func process(_ selection: ApplicationRemovalSelection, item: ManifestItem, sessionID: UUID) -> RemovalReport {
        var captured = false
        var trashStarted = false
        var trashPath: String?
        var stagingPath: String?
        do {
            stagingPath = try fileSystem.stagingPath(item: item, sessionID: sessionID)
            let source = try verified(item.originalPath, item: item)
            let current = try fileSystem.application(at: source)
            guard current.identity == selection.application.identity, current.bundleIdentifier == selection.application.bundleIdentifier,
                  current.name == selection.application.name, current.version == selection.application.version,
                  current.canUninstall else { throw ApplicationManagementError.changed }
            try activity.requireClosed(paths: [item.originalPath])
            try record(.prepared, item: item, sessionID: sessionID, stagingPath: stagingPath)
            let stageParent = try fileSystem.stagingParent(item: item, sessionID: sessionID)
            try operations.beforeCapture(item.originalPath)
            let fresh = try verified(item.originalPath, item: item)
            try fileSystem.verify(source.anchors)
            try fileSystem.move(fresh, into: stageParent, name: item.id.uuidString + ".app") {
                try operations.beforeCaptureRename(item.originalPath)
                try activity.requireClosed(paths: [item.originalPath])
            }
            captured = true
            try operations.afterCapture(stagingPath!)
            _ = try verifiedStage(stagingPath!, item: item, sessionID: sessionID)
            try fileSystem.verify(source.anchors)
            try record(.staged, item: item, sessionID: sessionID, stagingPath: stagingPath)
            try operations.beforeTrash(stagingPath!)
            _ = try verifiedStage(stagingPath!, item: item, sessionID: sessionID)
            try activity.requireClosed(paths: [item.originalPath, stagingPath!])
            try fileSystem.verify(source.anchors)
            trashStarted = true
            trashPath = try operations.trash(stagingPath!)
            guard let trashPath, try operations.isInTrash(trashPath) else { throw RemovalSafetyError.unsafeRecoveryLocation }
            _ = try verified(trashPath, item: item)
            try record(.trashed, item: item, sessionID: sessionID, stagingPath: stagingPath, trashPath: trashPath)
            return removalReport(sessionID, item: item, outcome: .trashed, path: trashPath)
        } catch is ApplicationJournalFailure {
            return removalReport(sessionID, item: item, outcome: captured ? .recoveryRequired : .failed,
                                 path: captured ? trashPath ?? stagingPath : nil,
                                 detail: "The application operation record could not be saved. Preserve the journal and recorded locations.",
                                 journalFailure: "The authenticated application journal could not be saved. Processing stopped.")
        } catch {
            let detail = explanation(error)
            var outcome: RemovalOutcome = captured ? .recoveryRequired : .refused
            var path = captured ? trashPath ?? stagingPath : nil
            if captured, trashPath == nil, let stagingPath {
                do {
                    let stage = try verifiedStage(stagingPath, item: item, sessionID: sessionID)
                    try restoreLocation(stage, item: item, paths: [item.originalPath, stagingPath])
                    path = item.originalPath
                    _ = try verified(item.originalPath, item: item)
                    outcome = .failed
                    path = nil
                } catch { /* Authenticated prepared location remains available for review. */ }
            }
            if trashStarted, outcome != .failed { outcome = .recoveryRequired }
            do {
                try record(outcome == .recoveryRequired ? .recoveryRequired : (captured ? .failed : .refused),
                           item: item, sessionID: sessionID, stagingPath: stagingPath, trashPath: trashPath, detail: detail)
                return removalReport(sessionID, item: item, outcome: outcome, path: path, detail: detail)
            } catch {
                return removalReport(sessionID, item: item, outcome: outcome, path: path, detail: detail,
                                     journalFailure: "The application failure outcome could not be saved. Preserve the session journal.")
            }
        }
    }

    func restore(sessionID: UUID) throws -> UndoReport {
        try withoutDatalessMaterialization {
            try manifest.withExclusiveOperation {
                let session = try manifest.read(sessionID)
                let history = try validate(session)
                let item = history.item
                if history.lastAction == .restored { return undoReport(sessionID, item: item, outcome: .alreadyRestored) }
                if history.lastAction == .failed || history.lastAction == .refused {
                    return undoReport(sessionID, item: item, outcome: .refused, detail: "This application removal did not complete.")
                }
                if Task.isCancelled { return UndoReport(sessionID: sessionID, results: [], cancelled: true, journalFailure: nil) }
                var prepared = false
                var moved = false
                let sourcePath = history.trashPath ?? history.stagingPath
                do {
                    // Recover an interrupted restore only with the original
                    // entire tree and the authenticated source now absent.
                    if history.lastAction == .restorePrepared, try missing(sourcePath) {
                        _ = try verified(item.originalPath, item: item)
                        moved = true
                        try record(.restored, item: item, sessionID: sessionID, stagingPath: history.stagingPath, trashPath: history.trashPath)
                        return undoReport(sessionID, item: item, outcome: .restored)
                    }
                    if history.trashPath != nil {
                        guard try operations.isInTrash(sourcePath) else { throw RemovalSafetyError.unsafeRecoveryLocation }
                    }
                    let source = history.trashPath == nil
                        ? try verifiedStage(sourcePath, item: item, sessionID: sessionID)
                        : try verified(sourcePath, item: item)
                    try activity.requireClosed(paths: [item.originalPath, sourcePath])
                    try record(.restorePrepared, item: item, sessionID: sessionID,
                               stagingPath: history.stagingPath, trashPath: history.trashPath)
                    prepared = true
                    try operations.beforeRestore(sourcePath)
                    let fresh = history.trashPath == nil
                        ? try verifiedStage(sourcePath, item: item, sessionID: sessionID)
                        : try verified(sourcePath, item: item)
                    try fileSystem.verify(source.anchors)
                    try restoreLocation(fresh, item: item, paths: [item.originalPath, sourcePath])
                    moved = true
                    _ = try verified(item.originalPath, item: item)
                    try record(.restored, item: item, sessionID: sessionID,
                               stagingPath: history.stagingPath, trashPath: history.trashPath)
                    return undoReport(sessionID, item: item, outcome: .restored)
                } catch is ApplicationJournalFailure {
                    return undoReport(sessionID, item: item, outcome: .recoveryRequired,
                                      path: moved ? item.originalPath : sourcePath,
                                      detail: "The application restore record could not be saved. Preserve the journal and recorded locations.",
                                      journalFailure: "The authenticated application restore journal could not be saved.")
                } catch {
                    let detail = explanation(error)
                    let outcome: UndoOutcome
                    if moved { outcome = .recoveryRequired }
                    else {
                        switch error {
                        case RemovalSafetyError.conflict: outcome = .conflict
                        case RemovalSafetyError.missing, PathGuardError.missing: outcome = .missing
                        default: outcome = .refused
                        }
                    }
                    if prepared {
                        do {
                            try record(moved ? .restorePrepared : .restoreFailed, item: item, sessionID: sessionID,
                                       stagingPath: history.stagingPath, trashPath: history.trashPath, detail: detail)
                        } catch {
                            return undoReport(sessionID, item: item, outcome: .recoveryRequired,
                                              path: moved ? item.originalPath : sourcePath, detail: detail,
                                              journalFailure: "The application restore failure outcome could not be saved.")
                        }
                    }
                    return undoReport(sessionID, item: item, outcome: outcome,
                                      path: moved ? item.originalPath : sourcePath, detail: detail)
                }
            }
        }
    }

    private func restoreLocation(_ source: RemovalLocation, item: ManifestItem, paths: [String]) throws {
        try policy.validateRemovalPath(item.originalPath)
        let parent = try fileSystem.open((item.originalPath as NSString).deletingLastPathComponent)
        guard parent.metadata.kind == .directory, parent.metadata.identity.device == item.identity.device else {
            throw PathGuardError.mountBoundary
        }
        try fileSystem.move(source, into: parent, name: (item.originalPath as NSString).lastPathComponent) {
            try activity.requireClosed(paths: paths)
        }
    }

    private func verified(_ path: String, item: ManifestItem) throws -> RemovalLocation {
        let location = try fileSystem.open(path)
        guard ManifestIdentity(location.metadata.fingerprint) == item.identity else { throw ApplicationManagementError.changed }
        let snapshot = try fileSystem.snapshot(location)
        let parsed = try Self.parseRuleID(item.ruleID)
        guard snapshot.digest == parsed.digest, snapshot.allocatedSize == item.allocatedSize else {
            throw ApplicationManagementError.changed
        }
        try location.descriptor.requirePath(path)
        return location
    }

    private func verifiedStage(_ path: String, item: ManifestItem, sessionID: UUID) throws -> RemovalLocation {
        guard SafeRoots.sameBytes(path, try fileSystem.stagingPath(item: item, sessionID: sessionID)) else {
            throw RemovalSafetyError.unsafeRecoveryLocation
        }
        let location = try verified(path, item: item)
        let stagingRoot = (item.originalPath as NSString).deletingLastPathComponent + "/.racket-app-staging-" + String(geteuid())
        for anchor in location.anchors where SafeRoots.isWithin(anchor.path, root: stagingRoot) {
            let fresh = try calculator.inspect(descriptor: anchor.descriptor.value, path: anchor.path, includeSize: false)
            try anchor.descriptor.requirePrivateDirectory(fresh)
        }
        return location
    }

    private func validate(_ session: ManifestSession) throws -> ApplicationUndoHistory {
        guard session.ruleSetVersion == ApplicationRemovalSelection.manifestVersion, let first = session.events.first,
              first.action == .prepared || first.action == .refused, first.trashPath == nil else {
            throw RemovalSafetyError.invalidHistory
        }
        let item = first.item
        try policy.validateRemovalPath(item.originalPath)
        _ = try Self.parseRuleID(item.ruleID)
        guard item.identity.owner == geteuid(), geteuid() != 0,
              item.identity.mode & UInt16(S_IFMT) == UInt16(S_IFDIR), let staging = first.stagingPath,
              SafeRoots.sameBytes(staging, try fileSystem.stagingPath(item: item, sessionID: session.id)) else {
            throw RemovalSafetyError.invalidHistory
        }
        var last = first.action
        var trash: String?
        for event in session.events.dropFirst() {
            guard event.item == item, event.stagingPath == staging, event.timestamp.timeIntervalSinceReferenceDate.isFinite,
                  allowed(event.action, after: last) else { throw RemovalSafetyError.invalidHistory }
            if let known = trash { guard event.trashPath == known else { throw RemovalSafetyError.invalidHistory } }
            else if let path = event.trashPath {
                guard event.action == .trashed || event.action == .recoveryRequired,
                      SafeRoots.sameBytes(try SafeRoots.normalizeAbsolute(path), path), path != "/",
                      !SafeRoots.sameBytes(path, staging), !SafeRoots.sameBytes(path, item.originalPath) else {
                    throw RemovalSafetyError.invalidHistory
                }
                trash = path
            }
            if event.action == .trashed, trash == nil { throw RemovalSafetyError.invalidHistory }
            last = event.action
        }
        return ApplicationUndoHistory(item: item, stagingPath: staging, trashPath: trash, lastAction: last)
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

    private static func parseRuleID(_ value: String) throws -> (bundleID: String, digest: String) {
        let parts = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "application-bundle", ApplicationPolicy.validBundleIdentifier(parts[1]),
              !parts[1].lowercased().hasPrefix("com.apple."), parts[1] != "io.github.iamcaglardogan.racket",
              validDigest(parts[2]) else { throw RemovalSafetyError.invalidHistory }
        return (parts[1], parts[2])
    }

    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private func missing(_ path: String) throws -> Bool {
        do { _ = try fileSystem.open(path); return false }
        catch RemovalSafetyError.missing { return true }
        catch PathGuardError.missing { return true }
    }

    private func record(_ action: ManifestAction, item: ManifestItem, sessionID: UUID, stagingPath: String?,
                        trashPath: String? = nil, detail: String? = nil) throws {
        do {
            let event = ManifestEvent(timestamp: Date(), action: action, item: item, stagingPath: stagingPath,
                                      trashPath: trashPath, detail: detail)
            try operations.beforeJournal(event)
            try manifest.append(event, to: sessionID)
        } catch { throw ApplicationJournalFailure() }
    }

    private func explanation(_ error: any Error) -> String {
        if let error = error as? ApplicationManagementError { return error.localizedDescription }
        return removalExplanation(error)
    }

    private func removalReport(_ sessionID: UUID, item: ManifestItem, outcome: RemovalOutcome, path: String? = nil,
                               detail: String? = nil, journalFailure: String? = nil) -> RemovalReport {
        RemovalReport(sessionID: sessionID, results: [RemovalResult(itemID: item.id, originalPath: item.originalPath,
                                                                  outcome: outcome, recoveryPath: path, detail: detail)],
                      cancelled: Task.isCancelled, journalFailure: journalFailure)
    }

    private func undoReport(_ sessionID: UUID, item: ManifestItem, outcome: UndoOutcome, path: String? = nil,
                            detail: String? = nil, journalFailure: String? = nil) -> UndoReport {
        UndoReport(sessionID: sessionID, results: [UndoResult(itemID: item.id, originalPath: item.originalPath,
                                                           outcome: outcome, recoveryPath: path, detail: detail)],
                   cancelled: Task.isCancelled, journalFailure: journalFailure)
    }
}

private struct ApplicationJournalFailure: Error {}
private struct ApplicationUndoHistory {
    let item: ManifestItem
    let stagingPath: String
    let trashPath: String?
    let lastAction: ManifestAction
}
