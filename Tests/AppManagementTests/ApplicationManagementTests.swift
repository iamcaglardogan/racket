import Darwin
import Foundation
import XCTest
@testable import RacketCore

/// Synthetic application bundles and fake Trash only. No real application,
/// developer home, running process, cloud provider, or Trash is inspected.
final class ApplicationManagementTests: XCTestCase, @unchecked Sendable {
    func testInventoryReadsBoundedBundleMetadataAndProtectsAppleAndSelf() async throws {
        let fixture = try ApplicationFixture()
        try fixture.makeApplication("Apple Tool.app", id: "com.apple.TestTool")
        try fixture.makeApplication("RACKET.app", id: "io.github.iamcaglardogan.racket")
        try fixture.makeApplication("Invalid.app", id: "../invalid")
        let result = try await fixture.inventory().scan()
        XCTAssertEqual(result.applications.count, 3)
        let sample = try XCTUnwrap(result.applications.first { $0.path == fixture.app })
        XCTAssertEqual(sample.name, "Sample Tool")
        XCTAssertEqual(sample.version, "1.2.3")
        XCTAssertEqual(sample.bundleIdentifier, "org.example.SampleTool")
        XCTAssertTrue(sample.canUninstall)
        XCTAssertNil(sample.allocatedSize)
        XCTAssertFalse(try XCTUnwrap(result.applications.first { $0.bundleIdentifier == "com.apple.TestTool" }).canUninstall)
        XCTAssertFalse(try XCTUnwrap(result.applications.first { $0.bundleIdentifier == "io.github.iamcaglardogan.racket" }).canUninstall)
        XCTAssertEqual(result.issues.count, 1)
    }

    func testInventoryStopsAtAppBundlesAndFindsNestedVendorApplication() async throws {
        let fixture = try ApplicationFixture()
        try fixture.makeApplication("Vendor/Nested.app", id: "org.example.Nested")
        try fixture.makeApplication("Sample Tool.app/Contents/Helpers/Helper.app", id: "org.example.Helper")
        let result = try await fixture.inventory().scan()
        XCTAssertEqual(Set(result.applications.map(\.bundleIdentifier)), ["org.example.SampleTool", "org.example.Nested"])
    }

    func testInventoryDoesNotFollowApplicationOrPlistSymlinks() async throws {
        let fixture = try ApplicationFixture()
        try FileManager.default.createSymbolicLink(atPath: fixture.applications + "/Alias.app", withDestinationPath: fixture.app)
        try fixture.makeApplication("Linked Metadata.app", id: "org.example.Linked")
        let linkedPlist = fixture.applications + "/Linked Metadata.app/Contents/Info.plist"
        try FileManager.default.moveItem(atPath: linkedPlist, toPath: linkedPlist + ".preserved")
        try FileManager.default.createSymbolicLink(atPath: linkedPlist, withDestinationPath: fixture.plist)
        let result = try await fixture.inventory().scan()
        XCTAssertEqual(result.applications.map(\.path), [fixture.app])
        XCTAssertEqual(result.issues.count, 2)
    }

    func testExactRelatedCacheLocationsExcludeSiblingNamesAndPreferences() async throws {
        let fixture = try ApplicationFixture()
        let inventory = fixture.inventory()
        let app = try await fixture.onlyApplication(inventory)
        for suffix in ["/Library/Caches/org.example.SampleTool", "/Library/Caches/org.example.SampleTool.extra", "/Library/Logs/org.example.SampleTool", "/Library/Preferences/org.example.SampleTool"] {
            try FileManager.default.createDirectory(atPath: fixture.home + suffix, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let result = try await inventory.relatedCacheLocations(for: app)
        XCTAssertEqual(Set(result.map(\.path)), [fixture.home + "/Library/Caches/org.example.SampleTool", fixture.home + "/Library/Logs/org.example.SampleTool"])
    }

    func testReviewBindsWholeApplicationAndRefusesRunningOrUnknownActivity() async throws {
        let fixture = try ApplicationFixture()
        let application = try await fixture.onlyApplication()
        let selection = try await fixture.inventory().reviewRemoval(of: application)
        XCTAssertGreaterThan(selection.descendantCount, 2)
        XCTAssertGreaterThan(selection.allocatedSize, 0)
        XCTAssertEqual(selection.digest.count, 64)
        for activity in [ApplicationProcessActivity(snapshot: { [AppActivityProcess(executablePath: fixture.executable)] }),
                         ApplicationProcessActivity(snapshot: { throw ApplicationManagementError.activityUnknown }),
                         ApplicationProcessActivity(snapshot: { [] })] {
            do { _ = try await fixture.inventory(activity: activity).reviewRemoval(of: application); XCTFail("Expected refusal") }
            catch let error as ApplicationManagementError {
                XCTAssertTrue(error == .runningApplication || error == .activityUnknown)
            }
        }
    }

    func testReviewRefusesLinkedAndProtectedDescendantsWithoutFollowingThem() async throws {
        for kind in ["symlink", "hardlink", "protected", "shared", "fifo"] {
            let fixture = try ApplicationFixture()
            let application = try await fixture.onlyApplication()
            let path = fixture.app + "/Contents/Additional"
            switch kind {
            case "symlink": try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: fixture.valuable)
            case "hardlink": XCTAssertEqual(Darwin.link(fixture.valuable, path), 0)
            case "protected": try FileManager.default.createDirectory(atPath: fixture.app + "/Contents/Original Media", withIntermediateDirectories: false)
            case "shared": try Data([1]).write(to: URL(fileURLWithPath: path)); XCTAssertEqual(Darwin.chmod(path, 0o666), 0)
            default: XCTAssertEqual(Darwin.mkfifo(path, 0o600), 0)
            }
            do { _ = try await fixture.inventory().reviewRemoval(of: application); XCTFail("Expected refusal for \(kind)") }
            catch { XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.valuable)) }
        }
    }

    func testRootOwnedApplicationIsVisibleButCannotBeReviewedForRemoval() async throws {
        let fixture = try ApplicationFixture()
        var metadata = ScanMetadataOperations.live
        let live = metadata.metadata
        metadata.metadata = { descriptor in
            var value = try live(descriptor)
            let location = try fixture.descriptorPath(descriptor)
            if location == fixture.app { value.st_uid = 0 }
            return value
        }
        let inventory = ApplicationInventory(policy: fixture.appPolicy, calculator: SizeCalculator(operations: metadata), activity: fixture.closedActivity)
        let application = try await fixture.onlyApplication(inventory)
        XCTAssertFalse(application.canUninstall)
        do { _ = try await inventory.reviewRemoval(of: application); XCTFail("Expected refusal") }
        catch ApplicationManagementError.protectedApplication { }
    }

    func testDatalessApplicationIsRefusedBeforeMetadataRead() async throws {
        let fixture = try ApplicationFixture()
        var metadata = ScanMetadataOperations.live
        let live = metadata.flags
        metadata.flags = { descriptor in
            if try fixture.descriptorPath(descriptor) == fixture.app { return UInt32(SF_DATALESS) }
            return try live(descriptor)
        }
        let inventory = ApplicationInventory(policy: fixture.appPolicy, calculator: SizeCalculator(operations: metadata), activity: fixture.closedActivity)
        let result = try await inventory.scan()
        XCTAssertTrue(result.applications.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
    }

    func testReviewedBundleRoundTripsThroughFakeTrashAndAuthenticatedAppUndo() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        var operations = fixture.operations
        let trash = operations.trash
        operations.trash = { path in
            let events = try fixture.onlySession().events
            XCTAssertEqual(events.map(\.action), [.prepared, .staged])
            XCTAssertEqual(events.first?.stagingPath, path)
            return try trash(path)
        }
        let engine = fixture.engine(operations)
        let result = try await engine.moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        XCTAssertEqual(result.results.map(\.outcome), [.trashed])
        XCTAssertNil(result.journalFailure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.app))
        let undo = try await engine.restoreApplication(sessionID: result.sessionID)
        XCTAssertEqual(undo.results.map(\.outcome), [.restored])
        XCTAssertNil(undo.journalFailure)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.executable)), fixture.contents)
        XCTAssertEqual(try fixture.manifest.read(result.sessionID).events.map(\.action), [.prepared, .staged, .trashed, .restorePrepared, .restored])
        let secondUndo = try await engine.restoreApplication(sessionID: result.sessionID)
        XCTAssertEqual(secondUndo.results.map(\.outcome), [.alreadyRestored])
    }

    func testChangedDescendantAfterReviewNeverCallsTrash() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        try Data("replacement content".utf8).write(to: URL(fileURLWithPath: fixture.executable))
        var operations = fixture.operations
        operations.trash = { _ in XCTFail("Trash must not run"); throw ApplicationManagementError.changed }
        let report = try await fixture.engine(operations).moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        XCTAssertEqual(report.results.map(\.outcome), [.refused])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.app))
    }

    func testSymlinkSubstitutionBeforeCaptureNeverCallsTrash() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        var operations = fixture.operations
        operations.beforeCapture = { path in
            try FileManager.default.moveItem(atPath: path, toPath: path + ".preserved")
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: fixture.valuable)
        }
        operations.trash = { _ in XCTFail("Trash must not run"); throw ApplicationManagementError.changed }
        let report = try await fixture.engine(operations).moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        XCTAssertEqual(report.results.map(\.outcome), [.refused])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.app + ".preserved/Contents/Info.plist"))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.valuable)), Data("valuable".utf8))
    }

    func testTrashFailureRestoresWholeBundleWithoutOverwrite() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        var operations = fixture.operations
        operations.trash = { _ in throw RemovalSafetyError.system(EACCES) }
        let report = try await fixture.engine(operations).moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        XCTAssertEqual(report.results.map(\.outcome), [.failed])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.executable)), fixture.contents)
        XCTAssertEqual(try fixture.manifest.read(report.sessionID).events.map(\.action), [.prepared, .staged, .failed])
    }

    func testPreparedJournalFailureDoesNotCreateStageOrCallTrash() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        var operations = fixture.operations
        operations.beforeJournal = { event in if event.action == .prepared { throw RemovalSafetyError.system(ENOSPC) } }
        operations.trash = { _ in XCTFail("Trash must not run"); throw ApplicationManagementError.changed }
        let report = try await fixture.engine(operations).moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        XCTAssertNotNil(report.journalFailure)
        XCTAssertEqual(report.results.map(\.outcome), [.failed])
        XCTAssertEqual(try fixture.manifest.read(report.sessionID).events.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.applications + "/.racket-app-staging-" + String(geteuid())))
    }

    func testStagedJournalFailureLeavesRecordedBundleForAppUndo() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        var operations = fixture.operations
        operations.beforeJournal = { event in if event.action == .staged { throw RemovalSafetyError.system(ENOSPC) } }
        let report = try await fixture.engine(operations).moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        XCTAssertNotNil(report.journalFailure)
        XCTAssertEqual(report.results.map(\.outcome), [.recoveryRequired])
        let undo = try await fixture.engine().restoreApplication(sessionID: report.sessionID)
        XCTAssertEqual(undo.results.map(\.outcome), [.restored])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.executable)), fixture.contents)
    }

    func testFinalJournalFailureDoesNotGuessMissingTrashPath() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        var operations = fixture.operations
        operations.beforeJournal = { event in if event.action == .trashed { throw RemovalSafetyError.system(ENOSPC) } }
        let report = try await fixture.engine(operations).moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        XCTAssertNotNil(report.journalFailure)
        XCTAssertEqual(report.results.map(\.outcome), [.recoveryRequired])
        let undo = try await fixture.engine().restoreApplication(sessionID: report.sessionID)
        XCTAssertEqual(undo.results.map(\.outcome), [.missing])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.app))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(report.results.first?.recoveryPath)))
    }

    func testUndoRefusesDestinationConflictChangedDescendantAndWrongSessionType() async throws {
        for kind in ["conflict", "changed"] {
            let fixture = try ApplicationFixture()
            let selection = try await fixture.selection()
            let report = try await fixture.engine().moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
            let trashPath = try XCTUnwrap(report.results.first?.recoveryPath)
            if kind == "conflict" { try fixture.makeApplication("Sample Tool.app", id: "org.example.Replacement") }
            else { try Data("changed".utf8).write(to: URL(fileURLWithPath: trashPath + "/Contents/MacOS/Sample Tool")) }
            let undo = try await fixture.engine().restoreApplication(sessionID: report.sessionID)
            XCTAssertEqual(undo.results.map(\.outcome), kind == "conflict" ? [.conflict] : [.refused])
            XCTAssertTrue(FileManager.default.fileExists(atPath: trashPath))
        }
        let fixture = try ApplicationFixture()
        let session = try fixture.manifest.createSession(appVersion: "tests", ruleSetVersion: "ordinary-files")
        do { _ = try await fixture.engine().restoreApplication(sessionID: session); XCTFail("Expected refusal") }
        catch RemovalSafetyError.invalidHistory { }
    }

    func testRunningAppAtLastCaptureCheckIsRefusedAndNeverTrashed() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        let activity = ApplicationActivitySequence(path: fixture.executable)
        let checker = ApplicationProcessActivity(snapshot: { activity.next() })
        var operations = fixture.operations
        operations.trash = { _ in XCTFail("Trash must not run"); throw ApplicationManagementError.changed }
        let report = try await fixture.engine(operations, activity: checker).moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        XCTAssertEqual(report.results.map(\.outcome), [.refused])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.app))
    }

    func testChangedBundleBetweenInventoryAndReviewIsRefused() async throws {
        let fixture = try ApplicationFixture()
        let application = try await fixture.onlyApplication()
        try FileManager.default.moveItem(atPath: fixture.app, toPath: fixture.app + ".preserved")
        try fixture.makeApplication("Sample Tool.app", id: "org.example.SampleTool")
        do { _ = try await fixture.inventory().reviewRemoval(of: application); XCTFail("Expected changed bundle refusal") }
        catch ApplicationManagementError.changed { }
    }

    func testCloudAndForeignOwnedDescendantsPreventRemovalReview() async throws {
        for cloud in [true, false] {
            let fixture = try ApplicationFixture()
            let application = try await fixture.onlyApplication()
            var operations = ScanMetadataOperations.live
            if cloud {
                let live = operations.cloud
                operations.cloud = { path in
                    if path == fixture.executable { return ScanCloudMetadata(isUbiquitous: true, downloadingStatus: .notDownloaded) }
                    return try live(path)
                }
            } else {
                let live = operations.metadata
                operations.metadata = { descriptor in
                    var value = try live(descriptor)
                    if try fixture.descriptorPath(descriptor) == fixture.executable { value.st_uid = 0 }
                    return value
                }
            }
            let inventory = ApplicationInventory(policy: fixture.appPolicy, calculator: SizeCalculator(operations: operations), activity: fixture.closedActivity)
            do { _ = try await inventory.reviewRemoval(of: application); XCTFail("Expected descendant refusal") }
            catch { XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.executable)) }
        }
    }

    func testChangedBundleAfterCaptureNeverReachesTrashAndKeepsRecoveryRecord() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        var operations = fixture.operations
        operations.afterCapture = { stage in
            try Data("changed after capture".utf8).write(to: URL(fileURLWithPath: stage + "/Contents/MacOS/Sample Tool"))
        }
        operations.trash = { _ in XCTFail("Trash must not run"); throw ApplicationManagementError.changed }
        let report = try await fixture.engine(operations).moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        XCTAssertEqual(report.results.map(\.outcome), [.recoveryRequired])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.app))
        let stage = try XCTUnwrap(report.results.first?.recoveryPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stage + "/Contents/Info.plist"))
        XCTAssertEqual(try fixture.manifest.read(report.sessionID).events.map(\.action), [.prepared, .recoveryRequired])
    }

    func testChangedBundleImmediatelyBeforeTrashNeverCallsTransport() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        var operations = fixture.operations
        operations.beforeTrash = { stage in
            try FileManager.default.createSymbolicLink(atPath: stage + "/Contents/Unsafe", withDestinationPath: fixture.valuable)
        }
        operations.trash = { _ in XCTFail("Trash must not run"); throw ApplicationManagementError.changed }
        let report = try await fixture.engine(operations).moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        XCTAssertEqual(report.results.map(\.outcome), [.recoveryRequired])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.valuable)), Data("valuable".utf8))
    }

    func testUndoPreparedJournalFailureNeverMovesApplication() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        let removal = try await fixture.engine().moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        let trash = try XCTUnwrap(removal.results.first?.recoveryPath)
        var operations = fixture.operations
        operations.beforeJournal = { event in if event.action == .restorePrepared { throw RemovalSafetyError.system(ENOSPC) } }
        let undo = try await fixture.engine(operations).restoreApplication(sessionID: removal.sessionID)
        XCTAssertNotNil(undo.journalFailure)
        XCTAssertEqual(undo.results.map(\.outcome), [.recoveryRequired])
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.app))
    }

    func testUndoFinalJournalFailureCanRecoverOriginalBundleIdentity() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        let removal = try await fixture.engine().moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        var operations = fixture.operations
        operations.beforeJournal = { event in if event.action == .restored { throw RemovalSafetyError.system(ENOSPC) } }
        let undo = try await fixture.engine(operations).restoreApplication(sessionID: removal.sessionID)
        XCTAssertNotNil(undo.journalFailure)
        XCTAssertEqual(undo.results.map(\.outcome), [.recoveryRequired])
        XCTAssertEqual(undo.results.first?.recoveryPath, fixture.app)
        let recovery = try await fixture.engine().restoreApplication(sessionID: removal.sessionID)
        XCTAssertEqual(recovery.results.map(\.outcome), [.restored])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.executable)), fixture.contents)
    }

    func testUndoDoesNotRecreateMissingApplicationParent() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        let removal = try await fixture.engine().moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        try FileManager.default.moveItem(atPath: fixture.applications, toPath: fixture.applications + ".preserved")
        let undo = try await fixture.engine().restoreApplication(sessionID: removal.sessionID)
        XCTAssertEqual(undo.results.map(\.outcome), [.missing])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.applications))
    }

    func testOrdinaryFileUndoCannotRestoreAnApplicationSession() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        let removal = try await fixture.engine().moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        let ordinaryUndo = UndoService(policy: fixture.cleanupPolicy, manifest: fixture.manifest, operations: fixture.operations)
        do { _ = try await ordinaryUndo.restore(sessionID: removal.sessionID); XCTFail("Expected capability separation") }
        catch { XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.app)) }
    }

    func testDescendantChangeTimeRefusesInPlaceChangesEvenWhenModificationTimeIsRestored() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        var before = stat()
        XCTAssertEqual(Darwin.lstat(fixture.executable, &before), 0)
        let descriptor = Darwin.open(fixture.executable, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { Darwin.close(descriptor) }
        let replacement = Data(repeating: 0x5A, count: fixture.contents.count)
        XCTAssertEqual(replacement.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress!, $0.count) }, replacement.count)
        let times = [before.st_atimespec, before.st_mtimespec]
        XCTAssertEqual(times.withUnsafeBufferPointer { Darwin.futimens(descriptor, $0.baseAddress!) }, 0)
        var after = stat()
        XCTAssertEqual(Darwin.fstat(descriptor, &after), 0)
        XCTAssertEqual(ManifestIdentity(ScanMetadataFingerprint(before)), ManifestIdentity(ScanMetadataFingerprint(after)),
                       "This regression must preserve the metadata represented by ManifestIdentity")
        XCTAssertTrue(before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec || before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec)
        var operations = fixture.operations
        operations.trash = { _ in XCTFail("Changed descendant must not reach Trash"); throw ApplicationManagementError.changed }
        let removal = try await fixture.engine(operations).moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        XCTAssertEqual(removal.results.map(\.outcome), [.refused])
        XCTAssertEqual(try Data(contentsOf: removalFileURL(fixture.executable)), replacement)
    }

    func testPostRenameRestoreVerificationFailureKeepsReconciliableIntent() async throws {
        let fixture = try ApplicationFixture()
        let selection = try await fixture.selection()
        let removal = try await fixture.engine().moveApplicationToTrash(reviewedApplication: selection, appVersion: "tests")
        let failure = ApplicationMetadataFailureGate(expectedPath: fixture.app)
        var operations = fixture.operations
        operations.beforeRestore = { _ in failure.arm() }
        var metadata = ScanMetadataOperations.live
        let live = metadata.metadata
        metadata.metadata = { descriptor in
            if failure.shouldFail(try fixture.descriptorPath(descriptor)) { throw RemovalSafetyError.system(EIO) }
            return try live(descriptor)
        }
        let undo = try await fixture.engine(operations, calculator: SizeCalculator(operations: metadata)).restoreApplication(sessionID: removal.sessionID)
        XCTAssertNil(undo.journalFailure)
        XCTAssertEqual(undo.results.map(\.outcome), [.recoveryRequired])
        XCTAssertEqual(undo.results.first?.recoveryPath, fixture.app)
        XCTAssertEqual(try fixture.manifest.read(removal.sessionID).events.map(\.action),
                       [.prepared, .staged, .trashed, .restorePrepared, .restorePrepared])
        let reconciled = try await fixture.engine().restoreApplication(sessionID: removal.sessionID)
        XCTAssertEqual(reconciled.results.map(\.outcome), [.restored])
        XCTAssertEqual(try Data(contentsOf: removalFileURL(fixture.executable)), fixture.contents)
    }

    func testRemovalFileURLAndApplicationIDsPreserveExactUnicodeBytes() async throws {
        for name in ["Caf\u{e9}.app", "Cafe\u{301}.app", "\u{0130}stanbul.app", "100% # Tool.app"] {
            let path = "/private/tmp/" + name
            let url = removalFileURL(path, isDirectory: true)
            XCTAssertEqual(Data(url.path.utf8), Data(path.utf8))
            let representation = url.withUnsafeFileSystemRepresentation { $0.map { Data(String(cString: $0).utf8) } }
            XCTAssertEqual(representation, Data(path.utf8))
        }
        let fixture = try ApplicationFixture()
        try fixture.makeApplication("Caf\u{e9}.app", id: "org.example.Unicode")
        let report = try await fixture.inventory().scan()
        let application = try XCTUnwrap(report.applications.first { $0.bundleIdentifier == "org.example.Unicode" })
        XCTAssertEqual(application.id, Data(application.path.utf8))
        let location = ApplicationRelatedLocation(path: fixture.home + "/Library/Caches/Caf\u{e9}", kind: .cache)
        XCTAssertEqual(location.id, Data(location.path.utf8))
    }

    #if DEBUG
    func testVerificationInventorySharesRuntimeHomeAndRoundTripsSampleApplication() async throws {
        let runtime = try AppRuntime.verification()
        let root = try XCTUnwrap(runtime.verificationRoot)
        let inventory = try ApplicationInventory.verification(root: root)
        let report = try await inventory.scan()
        let application = try XCTUnwrap(report.applications.first)
        XCTAssertEqual(report.applications.count, 1)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(Data(application.path.utf8), Data((root.path + "/Home/Applications/Sample Tool.app").utf8))
        let reviewed = try await inventory.reviewRemoval(of: application)
        let removed = try await runtime.remover.moveApplicationToTrash(reviewedApplication: reviewed, appVersion: "verification-integration")
        XCTAssertEqual(removed.results.map(\.outcome), [.trashed])
        XCTAssertNil(removed.journalFailure)
        let restored = try await runtime.remover.restoreApplication(sessionID: removed.sessionID)
        XCTAssertEqual(restored.results.map(\.outcome), [.restored])
        XCTAssertNil(restored.journalFailure)
    }
    func testVerificationInventoryRejectsAliasNonFixtureAndSymlinkHome() throws {
        let runtime = try AppRuntime.verification()
        let root = try XCTUnwrap(runtime.verificationRoot)
        let alias = "/tmp/" + (root.path as NSString).lastPathComponent
        XCTAssertThrowsError(try ApplicationInventory.verification(root: removalFileURL(alias, isDirectory: true)))
        XCTAssertThrowsError(try ApplicationInventory.verification(root: removalFileURL("/private/tmp/RACKET-UI-not-a-uuid", isDirectory: true)))
        XCTAssertThrowsError(try ApplicationInventory.verification(root: URL(string: "https://example.invalid/RACKET-UI-fixture")!))
        let home = root.path + "/Home"
        let preserved = root.path + "/PreservedHome"
        try FileManager.default.moveItem(atPath: home, toPath: preserved)
        try FileManager.default.createSymbolicLink(atPath: home, withDestinationPath: preserved)
        XCTAssertThrowsError(try ApplicationInventory.verification(root: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: preserved + "/Applications"))
    }
    #endif

    func testBundleIdentifierValidationNeverGrantsAPathEscape() {
        for id in ["", "../foo", "org.example/Tool", "org..Tool", ".org.tool", "org.tool.", "org.example\nTool", "org.example\\Tool", "org.éxample"] {
            XCTAssertFalse(ApplicationPolicy.validBundleIdentifier(id), id)
        }
        for id in ["org.example.Tool", "com.vendor.tool-2", "io.github.iamcaglardogan.racket"] {
            XCTAssertTrue(ApplicationPolicy.validBundleIdentifier(id))
        }
    }
}

private final class ApplicationFixture: @unchecked Sendable {
    let base: String
    let home: String
    let applications: String
    let app: String
    let plist: String
    let executable: String
    let valuable: String
    let contents = Data("synthetic application executable".utf8)
    let manifest: ManifestStore
    let appPolicy: ApplicationPolicy
    let cleanupPolicy: SafeRoots
    var closedActivity: ApplicationProcessActivity { ApplicationProcessActivity(snapshot: { [AppActivityProcess(executablePath: "/synthetic/runner")] }) }

    init() throws {
        base = "/private/tmp/RACKET-AppTests-" + UUID().uuidString
        home = base + "/Home"
        applications = home + "/Applications"
        app = applications + "/Sample Tool.app"
        plist = app + "/Contents/Info.plist"
        executable = app + "/Contents/MacOS/Sample Tool"
        valuable = base + "/valuable"
        for path in [home + "/Library/Caches", home + "/Library/Logs", home + "/.Trash", applications, base + "/Manifests"] {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        try Data("valuable".utf8).write(to: URL(fileURLWithPath: valuable))
        manifest = try ManifestStore(directory: base + "/Manifests", authenticationKey: Data(repeating: 73, count: 32))
        appPolicy = ApplicationPolicy(homeDirectory: home, inventoryRoots: [applications], removalRoots: [applications])
        cleanupPolicy = try SafeRoots(homeDirectory: home)
        try makeApplication("Sample Tool.app", id: "org.example.SampleTool")
    }

    func makeApplication(_ name: String, id: String) throws {
        let path = applications + "/" + name + "/Contents"
        try FileManager.default.createDirectory(atPath: path + "/MacOS", withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let metadata = ["CFBundlePackageType": "APPL", "CFBundleIdentifier": id, "CFBundleName": "Sample Tool",
                        "CFBundleExecutable": "Sample Tool", "CFBundleShortVersionString": "1.2.3"]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0).write(to: URL(fileURLWithPath: path + "/Info.plist"))
        try contents.write(to: URL(fileURLWithPath: path + "/MacOS/Sample Tool"))
    }

    func inventory(activity: ApplicationProcessActivity? = nil) -> ApplicationInventory {
        ApplicationInventory(policy: appPolicy, activity: activity ?? closedActivity)
    }
    func onlyApplication(_ supplied: ApplicationInventory? = nil) async throws -> InstalledApplication {
        let result = try await (supplied ?? inventory()).scan()
        return try XCTUnwrap(result.applications.first { $0.path == app })
    }
    func selection() async throws -> ApplicationRemovalSelection {
        let inventory = inventory()
        return try await inventory.reviewRemoval(of: onlyApplication(inventory))
    }
    var operations: RemovalOperations {
        RemovalOperations(trash: { path in
            let destination = self.home + "/.Trash/" + (path as NSString).lastPathComponent + "-trashed.app"
            try FileManager.default.moveItem(atPath: path, toPath: destination)
            return destination
        }, isInTrash: { SafeRoots.isWithin($0, root: self.home + "/.Trash") })
    }
    func engine(_ operations: RemovalOperations? = nil, activity: ApplicationProcessActivity? = nil,
                calculator: SizeCalculator = SizeCalculator()) -> RemovalEngine {
        RemovalEngine(policy: cleanupPolicy, manifest: manifest, operations: operations ?? self.operations,
                      calculator: calculator, applicationActivity: activity ?? closedActivity)
    }
    func onlySession() throws -> ManifestSession {
        let files = try FileManager.default.contentsOfDirectory(atPath: base + "/Manifests").filter { $0.hasSuffix(".jsonl") }
        return try manifest.read(XCTUnwrap(UUID(uuidString: String(try XCTUnwrap(files.first).dropLast(6)))))
    }
    func descriptorPath(_ descriptor: Int32) throws -> String {
        var bytes = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard bytes.withUnsafeMutableBufferPointer({ Darwin.fcntl(descriptor, F_GETPATH, $0.baseAddress!) }) == 0 else {
            throw ApplicationManagementError.changed
        }
        return String(bytes: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
    }
}

private final class ApplicationActivitySequence: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let path: String
    init(path: String) { self.path = path }
    func next() -> [AppActivityProcess] {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return [AppActivityProcess(executablePath: count == 1 ? "/synthetic/runner" : path)]
    }
}

private final class ApplicationMetadataFailureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    private let expectedPath: String
    init(expectedPath: String) { self.expectedPath = expectedPath }
    func arm() { lock.lock(); defer { lock.unlock() }; armed = true }
    func shouldFail(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard armed, Data(path.utf8) == Data(expectedPath.utf8) else { return false }
        armed = false
        return true
    }
}
