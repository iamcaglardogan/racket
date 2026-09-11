import Darwin
import Foundation
import XCTest
@testable import RacketCore

final class UndoServiceTests: XCTestCase, @unchecked Sendable {
    func testTrashRoundTripRecordsIntentBeforeMoveAndDoesNotRetryRestoredItems() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        var operations = fixture.operations
        operations.beforeRestore = { _ in
            let events = try fixture.manifest.read(fixture.sessionID).events
            guard events.last?.action == .restorePrepared,
                  FileManager.default.fileExists(atPath: fixture.trashPath(item)) else { throw UndoTestError.injected }
        }
        let service = fixture.service(operations)
        let report = try await service.restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.restored])
        XCTAssertNil(report.journalFailure)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: item.originalPath)), fixture.contents)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.trashPath(item)))
        XCTAssertEqual(try fixture.manifest.read(fixture.sessionID).events.suffix(2).map(\.action), [.restorePrepared, .restored])
        let again = try await service.restore(sessionID: fixture.sessionID)
        XCTAssertEqual(again.results.map(\.outcome), [.alreadyRestored])
        XCTAssertEqual(try fixture.manifest.read(fixture.sessionID).events.count, 5)
    }

    func testStagedAndPreparedItemsRecoverFromOnlyTheirDeterministicStagePaths() async throws {
        for action in [ManifestAction.prepared, .staged, .recoveryRequired] {
            let fixture = try UndoFixture()
            let item = try fixture.addItem("cache.bin", through: action)
            let report = try await fixture.service().restore(sessionID: fixture.sessionID)
            XCTAssertEqual(report.results.map(\.outcome), [.restored])
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: item.originalPath)), fixture.contents)
        }
    }

    func testOccupiedDestinationPreservesBothFiles() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        let replacement = Data("replacement".utf8)
        try replacement.write(to: URL(fileURLWithPath: item.originalPath))
        let report = try await fixture.service().restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.conflict])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: item.originalPath)), replacement)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.trashPath(item))), fixture.contents)
        XCTAssertEqual(try fixture.manifest.read(fixture.sessionID).events.last?.action, .trashed)
    }

    func testDestinationCreatedAfterIntentStillCannotBeOverwritten() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        var operations = fixture.operations
        operations.beforeRestore = { path in try Data("new file".utf8).write(to: URL(fileURLWithPath: path)) }
        let report = try await fixture.service(operations).restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.conflict])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: item.originalPath)), Data("new file".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.trashPath(item)))
        XCTAssertEqual(try fixture.manifest.read(fixture.sessionID).events.last?.action, .restoreFailed)
    }

    func testMissingTrashItemIsReportedWithoutCreatingDestination() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        try FileManager.default.moveItem(atPath: fixture.trashPath(item), toPath: fixture.home + "/preserved.bin")
        let report = try await fixture.service().restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.missing])
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.originalPath))
    }

    func testMissingOriginalParentIsNeverRecreated() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        try FileManager.default.moveItem(atPath: fixture.originalDirectory, toPath: fixture.home + "/preserved-parent")
        let report = try await fixture.service().restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.missing])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.originalDirectory))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.trashPath(item)))
    }

    func testChangedTrashInodeIsRefusedEvenWithMatchingName() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        try FileManager.default.moveItem(atPath: fixture.trashPath(item), toPath: fixture.home + "/preserved.bin")
        try fixture.contents.write(to: URL(fileURLWithPath: fixture.trashPath(item)))
        let report = try await fixture.service().restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.refused])
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.originalPath))
    }

    func testSourceReplacementAfterIntentIsRefused() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        var operations = fixture.operations
        operations.beforeRestore = { _ in
            try FileManager.default.moveItem(atPath: fixture.trashPath(item), toPath: fixture.home + "/preserved.bin")
            try fixture.contents.write(to: URL(fileURLWithPath: fixture.trashPath(item)))
        }
        let report = try await fixture.service(operations).restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.refused])
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.originalPath))
        XCTAssertEqual(try fixture.manifest.read(fixture.sessionID).events.last?.action, .restoreFailed)
    }

    func testParentSymlinkSubstitutionAfterIntentIsRefused() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        let outside = fixture.home + "/outside"
        try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: false)
        var operations = fixture.operations
        operations.beforeRestore = { _ in
            try FileManager.default.moveItem(atPath: fixture.originalDirectory, toPath: fixture.home + "/preserved-parent")
            try FileManager.default.createSymbolicLink(atPath: fixture.originalDirectory, withDestinationPath: outside)
        }
        let report = try await fixture.service(operations).restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.refused])
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside + "/cache.bin"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.trashPath(item)))
    }

    func testSymlinkTrashSourceIsRefusedWithoutFollowingIt() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        let preserved = fixture.home + "/preserved.bin"
        try FileManager.default.moveItem(atPath: fixture.trashPath(item), toPath: preserved)
        try FileManager.default.createSymbolicLink(atPath: fixture.trashPath(item), withDestinationPath: preserved)
        let report = try await fixture.service().restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.refused])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: preserved)), fixture.contents)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.originalPath))
    }

    func testExtraHardLinkPreventsRestore() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        try FileManager.default.linkItem(atPath: fixture.trashPath(item), toPath: fixture.home + "/linked.bin")
        let report = try await fixture.service().restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.refused])
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.originalPath))
    }

    func testUnrecognizedTrashLocationIsRefused() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        var operations = fixture.operations
        operations.isInTrash = { _ in false }
        let report = try await fixture.service(operations).restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.refused])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.trashPath(item)))
    }

    func testDatalessSourceStopsBeforeExplicitMetadataAndSize() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        let counter = UndoCounter()
        var metadata = ScanMetadataOperations.live
        metadata.cloud = { path in
            if path == fixture.trashPath(item) { return ScanCloudMetadata(isUbiquitous: true, downloadingStatus: .notDownloaded) }
            return try ScanMetadataOperations.live.cloud(path)
        }
        metadata.metadata = { descriptor in
            var bytes = [CChar](repeating: 0, count: Int(PATH_MAX))
            _ = bytes.withUnsafeMutableBufferPointer { Darwin.fcntl(descriptor, F_GETPATH, $0.baseAddress!) }
            let path = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if path == fixture.trashPath(item) { counter.increment() }
            return try ScanMetadataOperations.live.metadata(descriptor)
        }
        metadata.allocatedSize = { _ in counter.increment(); throw UndoTestError.injected }
        var operations = fixture.operations
        operations.isInTrash = { _ in counter.increment(); return true }
        let service = UndoService(policy: fixture.policy, manifest: fixture.manifest,
                                  operations: operations, calculator: SizeCalculator(operations: metadata))
        let report = try await service.restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.refused])
        XCTAssertEqual(counter.value, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.trashPath(item)))
    }

    func testIntentJournalFailureLeavesAllSourcesAndStopsSession() async throws {
        let fixture = try UndoFixture()
        let first = try fixture.addItem("one.bin")
        let second = try fixture.addItem("two.bin")
        var operations = fixture.operations
        operations.beforeJournal = { event in if event.action == .restorePrepared { throw UndoTestError.injected } }
        let report = try await fixture.service(operations).restore(sessionID: fixture.sessionID)
        XCTAssertNotNil(report.journalFailure)
        XCTAssertEqual(report.results.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.trashPath(first)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.trashPath(second)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.originalPath))
    }

    func testOutcomeJournalFailurePreservesKnownOriginalAndCanResumeInterruptedRestore() async throws {
        let fixture = try UndoFixture()
        let first = try fixture.addItem("one.bin")
        let second = try fixture.addItem("two.bin")
        var operations = fixture.operations
        operations.beforeJournal = { event in if event.action == .restored { throw UndoTestError.injected } }
        let report = try await fixture.service(operations).restore(sessionID: fixture.sessionID)
        XCTAssertNotNil(report.journalFailure)
        XCTAssertEqual(report.results.map(\.outcome), [.recoveryRequired])
        XCTAssertEqual(report.results.first?.recoveryPath, first.originalPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.originalPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.trashPath(second)))
        let resumed = try await fixture.service().restore(sessionID: fixture.sessionID)
        XCTAssertEqual(resumed.results.map(\.outcome), [.restored, .restored])
    }

    func testInterruptedRestoreStillAtSourceRetriesWithoutOverwrite() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        try fixture.append(.restorePrepared, item: item, trash: fixture.trashPath(item))
        let report = try await fixture.service().restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.restored])
    }

    func testPostMoveMetadataFailureRemainsReconcilableOnNextRestore() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        var metadata = ScanMetadataOperations.live
        metadata.cloud = { path in
            if path == item.originalPath { throw UndoTestError.injected }
            return try ScanMetadataOperations.live.cloud(path)
        }
        let service = UndoService(policy: fixture.policy, manifest: fixture.manifest,
                                  operations: fixture.operations, calculator: SizeCalculator(operations: metadata))
        let first = try await service.restore(sessionID: fixture.sessionID)
        XCTAssertEqual(first.results.map(\.outcome), [.recoveryRequired])
        XCTAssertEqual(try fixture.manifest.read(fixture.sessionID).events.last?.action, .restorePrepared)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: item.originalPath)), fixture.contents)
        let second = try await fixture.service().restore(sessionID: fixture.sessionID)
        XCTAssertEqual(second.results.map(\.outcome), [.restored])
    }

    func testInterruptedRestoreDoesNotInferIdentityFromOriginalName() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        try fixture.append(.restorePrepared, item: item, trash: fixture.trashPath(item))
        try FileManager.default.moveItem(atPath: fixture.trashPath(item), toPath: fixture.home + "/preserved.bin")
        try fixture.contents.write(to: URL(fileURLWithPath: item.originalPath))
        let report = try await fixture.service().restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.refused])
        XCTAssertEqual(try fixture.manifest.read(fixture.sessionID).events.last?.action, .restorePrepared)
    }

    func testInvalidLaterHistoryPreventsEarlierValidItemFromMoving() async throws {
        let fixture = try UndoFixture()
        let valid = try fixture.addItem("valid.bin")
        let invalid = try fixture.unmovedItem("invalid.bin")
        try fixture.append(.trashed, item: invalid, trash: fixture.trashPath(invalid))
        do {
            _ = try await fixture.service().restore(sessionID: fixture.sessionID)
            XCTFail("An unauthorised event sequence must invalidate the whole session")
        } catch { XCTAssertEqual(error as? RemovalSafetyError, .invalidHistory) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: valid.originalPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.trashPath(valid)))
    }

    func testChangedItemMetadataInvalidatesHistory() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.addItem("cache.bin")
        let changed = ManifestItem(id: item.id, originalPath: item.originalPath, ruleID: "different",
                                   allocatedSize: item.allocatedSize, identity: item.identity)
        try fixture.append(.restorePrepared, item: changed, trash: fixture.trashPath(item))
        do { _ = try await fixture.service().restore(sessionID: fixture.sessionID); XCTFail("Expected invalid history") }
        catch { XCTAssertEqual(error as? RemovalSafetyError, .invalidHistory) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.originalPath))
    }

    func testArbitraryStagingPathIsRejectedBeforeAnyRestore() async throws {
        let fixture = try UndoFixture()
        let item = try fixture.unmovedItem("cache.bin")
        let event = ManifestEvent(timestamp: Date(), action: .prepared, item: item,
                                  stagingPath: fixture.home + "/arbitrary.bin", trashPath: nil, detail: nil)
        try fixture.manifest.append(event, to: fixture.sessionID)
        do { _ = try await fixture.service().restore(sessionID: fixture.sessionID); XCTFail("Expected invalid stage") }
        catch { XCTAssertEqual(error as? RemovalSafetyError, .invalidHistory) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.originalPath))
    }

    func testFailedAndPureRefusedItemsAreNotRetried() async throws {
        let fixture = try UndoFixture()
        let refused = try fixture.unmovedItem("refused.bin")
        try fixture.manifest.append(ManifestEvent(timestamp: Date(), action: .refused, item: refused,
                                                  stagingPath: nil, trashPath: nil, detail: "No removal"), to: fixture.sessionID)
        let failed = try fixture.unmovedItem("failed.bin")
        try fixture.append(.prepared, item: failed)
        try fixture.append(.failed, item: failed)
        let report = try await fixture.service().restore(sessionID: fixture.sessionID)
        XCTAssertEqual(report.results.map(\.outcome), [.refused, .refused])
        XCTAssertTrue(FileManager.default.fileExists(atPath: refused.originalPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.originalPath))
    }

    func testCancellationBetweenItemsStopsFurtherNamespaceChanges() async throws {
        let fixture = try UndoFixture()
        let first = try fixture.addItem("one.bin")
        let second = try fixture.addItem("two.bin")
        let holder = UndoTaskHolder()
        let ready = DispatchSemaphore(value: 0)
        var operations = fixture.operations
        operations.beforeRestore = { _ in ready.wait(); holder.cancel() }
        let service = fixture.service(operations)
        let task = Task { try await service.restore(sessionID: fixture.sessionID) }
        holder.set(task)
        ready.signal()
        let report = try await task.value
        XCTAssertTrue(report.cancelled)
        XCTAssertEqual(report.results.map(\.outcome), [.restored])
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.originalPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.trashPath(second)))
    }
}

private enum UndoTestError: Error { case injected }

/// Tests preserve every synthetic file and use a synthetic Trash transport.
/// No operation touches the actual home directory or invokes Foundation Trash.
private struct UndoFixture: Sendable {
    let home: String
    let policy: SafeRoots
    let manifest: ManifestStore
    let sessionID: UUID
    let contents = Data("RACKET undo fixture".utf8)
    var originalDirectory: String { home + "/Library/Caches/Test" }
    var trashDirectory: String { home + "/SyntheticTrash" }
    var fileSystem: RemovalFileSystem { RemovalFileSystem(policy: policy) }

    init() throws {
        home = "/private/tmp/RACKET-UndoFixture-" + UUID().uuidString
        policy = try SafeRoots(homeDirectory: home)
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(atPath: home + "/Library/Caches/Test", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: home + "/SyntheticTrash", withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        manifest = try ManifestStore(directory: home + "/Manifests", authenticationKey: Data(repeating: 0x75, count: 32))
        sessionID = try manifest.createSession(appVersion: "test", ruleSetVersion: "test")
    }

    var operations: RemovalOperations {
        RemovalOperations(trash: { _ in throw UndoTestError.injected },
                          isInTrash: { path in SafeRoots.isWithin(path, root: trashDirectory) && path != trashDirectory })
    }

    func service(_ overrides: RemovalOperations? = nil) -> UndoService {
        UndoService(policy: policy, manifest: manifest, operations: overrides ?? operations)
    }

    func trashPath(_ item: ManifestItem) -> String { trashDirectory + "/" + item.id.uuidString }

    func unmovedItem(_ name: String) throws -> ManifestItem {
        let path = originalDirectory + "/" + name
        try contents.write(to: URL(fileURLWithPath: path))
        return try withoutDatalessMaterialization {
            let source = try fileSystem.open(path, includeSize: true)
            return ManifestItem(id: UUID(), originalPath: path, ruleID: "fixture.undo", allocatedSize: source.metadata.allocatedSize,
                                identity: ManifestIdentity(source.metadata.fingerprint))
        }
    }

    func append(_ action: ManifestAction, item: ManifestItem, trash: String? = nil) throws {
        try manifest.append(ManifestEvent(timestamp: Date(), action: action, item: item,
                                           stagingPath: fileSystem.stagingPath(for: item, sessionID: sessionID),
                                           trashPath: trash, detail: nil), to: sessionID)
    }

    func addItem(_ name: String, through action: ManifestAction = .trashed) throws -> ManifestItem {
        let item = try unmovedItem(name)
        try append(.prepared, item: item)
        try withoutDatalessMaterialization {
            let source = try fileSystem.open(item.originalPath)
            let parent = try fileSystem.makeStagingParent(for: item, sessionID: sessionID)
            try fileSystem.move(source, into: parent, name: item.id.uuidString)
            if action == .prepared { return }
            try append(.staged, item: item)
            if action == .staged { return }
            if action == .recoveryRequired { try append(.recoveryRequired, item: item); return }
            let stage = try fileSystem.verifiedStage(fileSystem.stagingPath(for: item, sessionID: sessionID), item: item, sessionID: sessionID)
            let trash = try fileSystem.open(trashDirectory)
            try fileSystem.move(stage, into: trash, name: item.id.uuidString)
            try append(.trashed, item: item, trash: trashPath(item))
        }
        return item
    }
}

private final class UndoCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class UndoTaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<UndoReport, any Error>?
    func set(_ value: Task<UndoReport, any Error>) { lock.withLock { task = value } }
    func cancel() { lock.withLock { task?.cancel() } }
}
