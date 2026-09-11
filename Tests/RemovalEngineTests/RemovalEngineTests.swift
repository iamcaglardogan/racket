import Darwin
import Foundation
import XCTest
@testable import RacketCore

final class RemovalEngineTests: XCTestCase, @unchecked Sendable {
    func testReviewedScanMovesThroughDurableManifestAndReturnsActualTrashName() async throws {
        let fixture = try RemovalFixture()
        let findings = try await fixture.findings()
        var operations = fixture.operations
        let base = operations.trash
        operations.trash = { path in
            let session = try fixture.onlySession()
            XCTAssertEqual(session.events.map(\.action), [.prepared, .staged])
            XCTAssertEqual(session.events.first?.stagingPath, path)
            XCTAssertEqual(session.events.first?.item.originalPath, fixture.file)
            return try base(path)
        }
        let result = try await fixture.engine(operations).moveToTrash(reviewedFindings: findings, ruleSet: fixture.rules, appVersion: "test")
        XCTAssertNil(result.journalFailure)
        XCTAssertEqual(result.results.map(\.outcome), [.trashed])
        let destination = try XCTUnwrap(result.results.first?.recoveryPath)
        XCTAssertTrue(destination.hasSuffix("-renamed-by-trash"))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: destination)), fixture.contents)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.file))
        let events = try fixture.manifest.read(result.sessionID).events
        XCTAssertEqual(events.map(\.action), [.prepared, .staged, .trashed])
        XCTAssertEqual(events.last?.trashPath, destination)
        XCTAssertEqual(events.last?.item.allocatedSize, findings.first?.allocatedSize)
    }

    func testTrashFailureKeepsPreCallRecordAndRollsBackWithoutOverwriting() async throws {
        let fixture = try RemovalFixture()
        var operations = fixture.operations
        operations.trash = { _ in
            XCTAssertEqual(try fixture.onlySession().events.map(\.action), [.prepared, .staged])
            throw RemovalSafetyError.system(EACCES)
        }
        let result = try await fixture.run(operations)
        XCTAssertEqual(result.results.first?.outcome, .failed)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.file)), fixture.contents)
        XCTAssertEqual(try fixture.manifest.read(result.sessionID).events.map(\.action), [.prepared, .staged, .failed])
        XCTAssertNil(result.journalFailure)
    }

    func testActualEngineJournalCanBeRestoredEndToEnd() async throws {
        let fixture = try RemovalFixture()
        let removed = try await fixture.run()
        XCTAssertEqual(removed.results.map(\.outcome), [.trashed])
        let undo = UndoService(policy: fixture.policy, manifest: fixture.manifest, operations: fixture.operations)
        let restored = try await undo.restore(sessionID: removed.sessionID)
        XCTAssertEqual(restored.results.map(\.outcome), [.restored])
        XCTAssertNil(restored.journalFailure)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.file)), fixture.contents)
        XCTAssertEqual(try fixture.manifest.read(removed.sessionID).events.map(\.action),
                       [.prepared, .staged, .trashed, .restorePrepared, .restored])
    }

    func testCapturedItemWithMissingStagedRecordCanBeRestoredEndToEnd() async throws {
        let fixture = try RemovalFixture()
        var operations = fixture.operations
        operations.beforeJournal = { event in if event.action == .staged { throw RemovalSafetyError.system(ENOSPC) } }
        let removed = try await fixture.run(operations)
        XCTAssertNotNil(removed.journalFailure)
        let undo = UndoService(policy: fixture.policy, manifest: fixture.manifest, operations: fixture.operations)
        let restored = try await undo.restore(sessionID: removed.sessionID)
        XCTAssertEqual(restored.results.map(\.outcome), [.restored])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.file)), fixture.contents)
    }

    func testPreparedWriteFailureNeverCapturesOrCallsTrash() async throws {
        let fixture = try RemovalFixture()
        let calls = RemovalCounter()
        var operations = fixture.operations
        operations.beforeJournal = { event in if event.action == .prepared { throw RemovalSafetyError.system(ENOSPC) } }
        operations.trash = { _ in calls.increment(); throw RemovalSafetyError.unsupported }
        let result = try await fixture.run(operations)
        XCTAssertNotNil(result.journalFailure)
        XCTAssertEqual(calls.value, 0)
        XCTAssertEqual(result.results.first?.outcome, .failed)
        XCTAssertEqual(try fixture.manifest.read(result.sessionID).events.count, 0)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.file)), fixture.contents)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root + "/.racket-staging"))
    }

    func testStagedWriteFailureRetainsRecordedRecoverableLocation() async throws {
        let fixture = try RemovalFixture()
        var operations = fixture.operations
        operations.beforeJournal = { event in if event.action == .staged { throw RemovalSafetyError.system(ENOSPC) } }
        let result = try await fixture.run(operations)
        XCTAssertNotNil(result.journalFailure)
        XCTAssertEqual(result.results.first?.outcome, .recoveryRequired)
        let events = try fixture.manifest.read(result.sessionID).events
        XCTAssertEqual(events.map(\.action), [.prepared])
        let stage = try XCTUnwrap(events.first?.stagingPath)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: stage)), fixture.contents)
    }

    func testFinalJournalFailureReportsMovedButUnrecordedAndStopsBatch() async throws {
        let fixture = try RemovalFixture(extraFile: true)
        var operations = fixture.operations
        operations.beforeJournal = { event in if event.action == .trashed { throw RemovalSafetyError.system(ENOSPC) } }
        let result = try await fixture.run(operations)
        XCTAssertNotNil(result.journalFailure)
        XCTAssertEqual(result.results.count, 1)
        XCTAssertEqual(result.results.first?.outcome, .recoveryRequired)
        let location = try XCTUnwrap(result.results.first?.recoveryPath)
        XCTAssertTrue(try fixture.operations.isInTrash(location))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: location)), fixture.contents)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.secondFile))
        XCTAssertEqual(try fixture.manifest.read(result.sessionID).events.map(\.action), [.prepared, .staged])
    }

    func testSymlinkSubstitutionBeforeCaptureIsRefused() async throws {
        let fixture = try RemovalFixture()
        let findings = try await fixture.findings()
        var operations = fixture.operations
        operations.beforeCapture = { path in
            try FileManager.default.moveItem(atPath: path, toPath: fixture.preserved)
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: fixture.valuable)
        }
        let result = try await fixture.engine(operations).moveToTrash(reviewedFindings: findings, ruleSet: fixture.rules, appVersion: "test")
        XCTAssertEqual(result.results.first?.outcome, .refused)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.valuable)), Data("valuable".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.preserved)), fixture.contents)
        XCTAssertEqual(try fixture.manifest.read(result.sessionID).events.map(\.action), [.prepared, .refused])
    }

    func testLastMomentOrdinaryReplacementIsCapturedButNeverTrashed() async throws {
        let fixture = try RemovalFixture()
        let calls = RemovalCounter()
        var operations = fixture.operations
        operations.beforeCaptureRename = { path in
            try FileManager.default.moveItem(atPath: path, toPath: fixture.preserved)
            try Data("replacement".utf8).write(to: URL(fileURLWithPath: path))
        }
        operations.trash = { _ in calls.increment(); throw RemovalSafetyError.unsupported }
        let result = try await fixture.run(operations)
        XCTAssertEqual(result.results.first?.outcome, .recoveryRequired)
        XCTAssertEqual(calls.value, 0)
        let retained = try XCTUnwrap(result.results.first?.recoveryPath)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: retained)), Data("replacement".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.preserved)), fixture.contents)
    }

    func testLastMomentSymlinkIsNeverFollowedOrTrashed() async throws {
        let fixture = try RemovalFixture()
        let calls = RemovalCounter()
        var operations = fixture.operations
        operations.beforeCaptureRename = { path in
            try FileManager.default.moveItem(atPath: path, toPath: fixture.preserved)
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: fixture.valuable)
        }
        operations.trash = { _ in calls.increment(); throw RemovalSafetyError.unsupported }
        let result = try await fixture.run(operations)
        XCTAssertEqual(calls.value, 0)
        XCTAssertNotEqual(result.results.first?.outcome, .trashed)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.valuable)), Data("valuable".utf8))
    }

    func testStagingReplacementCannotReachTrash() async throws {
        let fixture = try RemovalFixture()
        let calls = RemovalCounter()
        var operations = fixture.operations
        operations.beforeTrash = { path in
            try FileManager.default.moveItem(atPath: path, toPath: fixture.preserved)
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: fixture.valuable)
        }
        operations.trash = { _ in calls.increment(); throw RemovalSafetyError.unsupported }
        let result = try await fixture.run(operations)
        XCTAssertEqual(result.results.first?.outcome, .recoveryRequired)
        XCTAssertEqual(calls.value, 0)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.preserved)), fixture.contents)
    }

    func testRollbackConflictKeepsBothFiles() async throws {
        let fixture = try RemovalFixture()
        var operations = fixture.operations
        operations.trash = { _ in
            try Data("new cache".utf8).write(to: URL(fileURLWithPath: fixture.file))
            throw RemovalSafetyError.system(EACCES)
        }
        let result = try await fixture.run(operations)
        XCTAssertEqual(result.results.first?.outcome, .recoveryRequired)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.file)), Data("new cache".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: XCTUnwrap(result.results.first?.recoveryPath))), fixture.contents)
    }

    func testMovedSourceParentPreventsRollbackOutsideReviewedRoot() async throws {
        let fixture = try RemovalFixture()
        var operations = fixture.operations
        operations.beforeTrash = { _ in
            try FileManager.default.moveItem(atPath: fixture.vendor, toPath: fixture.home + "/Documents/moved-vendor")
        }
        let result = try await fixture.run(operations)
        XCTAssertEqual(result.results.first?.outcome, .recoveryRequired)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.home + "/Documents/moved-vendor/cache.bin"))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: XCTUnwrap(result.results.first?.recoveryPath))), fixture.contents)
    }

    func testAlreadyChangedScanObservationIsRefused() async throws {
        let fixture = try RemovalFixture()
        let findings = try await fixture.findings()
        var metadata = stat()
        XCTAssertEqual(lstat(fixture.file, &metadata), 0)
        try FileManager.default.moveItem(atPath: fixture.file, toPath: fixture.preserved)
        try fixture.contents.write(to: URL(fileURLWithPath: fixture.file))
        let times = [metadata.st_atimespec, metadata.st_mtimespec]
        XCTAssertEqual(times.withUnsafeBufferPointer { utimensat(AT_FDCWD, fixture.file, $0.baseAddress, 0) }, 0)
        let result = try await fixture.engine().moveToTrash(reviewedFindings: findings, ruleSet: fixture.rules, appVersion: "test")
        XCTAssertEqual(result.results.first?.outcome, .refused)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.file))
    }

    func testRulesAreRecheckedForEnabledStatePathDepthAndAge() async throws {
        let fixture = try RemovalFixture()
        let findings = try await fixture.findings()
        let variants = [
            fixture.ruleJSON.replacingOccurrences(of: "\"enabled\":true", with: "\"enabled\":false"),
            fixture.ruleJSON.replacingOccurrences(of: "~/Library/Caches/Vendor", with: "~/Library/Logs"),
            fixture.ruleJSON.replacingOccurrences(of: "\"conditions\":[]", with: "\"conditions\":[{\"olderThanDays\":14}]")
        ]
        for json in variants {
            let rules = try RuleSet.decode(Data(json.utf8), validatePath: fixture.policy.validateRulePath)
            let result = try await fixture.engine().moveToTrash(reviewedFindings: findings, ruleSet: rules, appVersion: "test")
            XCTAssertEqual(result.results.first?.outcome, .refused)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.file))
        }
    }

    func testHardLinksAreSkippedWithoutMovingEitherName() async throws {
        let fixture = try RemovalFixture()
        XCTAssertEqual(link(fixture.file, fixture.preserved), 0)
        let result = try await fixture.run()
        XCTAssertEqual(result.results.first?.outcome, .skipped)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.file))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.preserved))
    }

    func testOtherUserWritableFileAndParentAreRefused() async throws {
        for changeParent in [false, true] {
            let fixture = try RemovalFixture()
            XCTAssertEqual(chmod(changeParent ? fixture.vendor : fixture.file, changeParent ? 0o777 : 0o666), 0)
            let result = try await fixture.run()
            XCTAssertEqual(result.results.map(\.outcome), [.skipped])
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.file))
        }
    }

    func testHardLinkAliasLookupStillProducesAnExplicitSkip() async throws {
        let fixture = try RemovalFixture()
        XCTAssertEqual(link(fixture.file, fixture.preserved), 0)
        let findings = try await fixture.findings()
        var metadata = ScanMetadataOperations.live
        metadata.allocatedSize = { path in
            let bytes = try ScanMetadataOperations.live.allocatedSize(path)
            let alias = Darwin.open(fixture.preserved, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
            guard alias >= 0 else { throw RemovalSafetyError.system(errno) }
            _ = Darwin.close(alias)
            return bytes
        }
        let engine = RemovalEngine(policy: fixture.policy, manifest: fixture.manifest,
                                   operations: fixture.operations, calculator: SizeCalculator(operations: metadata))
        let result = try await engine.moveToTrash(reviewedFindings: findings, ruleSet: fixture.rules, appVersion: "test")
        XCTAssertEqual(result.results.map(\.outcome), [.skipped])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.file))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.preserved))
    }

    func testDatalessGatePrecedesStatSizeAndTrash() async throws {
        let fixture = try RemovalFixture()
        let findings = try await fixture.findings()
        let calls = RemovalCounter()
        var metadata = ScanMetadataOperations.live
        metadata.flags = { descriptor in
            var bytes = [CChar](repeating: 0, count: Int(PATH_MAX))
            _ = bytes.withUnsafeMutableBufferPointer { fcntl(descriptor, F_GETPATH, $0.baseAddress!) }
            let path = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if path == fixture.file { return UInt32(SF_DATALESS) }
            return try ScanMetadataOperations.live.flags(descriptor)
        }
        metadata.metadata = { descriptor in
            var bytes = [CChar](repeating: 0, count: Int(PATH_MAX))
            _ = bytes.withUnsafeMutableBufferPointer { fcntl(descriptor, F_GETPATH, $0.baseAddress!) }
            let path = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if path == fixture.file { calls.increment() }
            return try ScanMetadataOperations.live.metadata(descriptor)
        }
        metadata.allocatedSize = { _ in calls.increment(); return 0 }
        var operations = fixture.operations
        operations.trash = { _ in calls.increment(); throw RemovalSafetyError.unsupported }
        let engine = RemovalEngine(policy: fixture.policy, manifest: fixture.manifest, operations: operations, calculator: SizeCalculator(operations: metadata))
        let result = try await engine.moveToTrash(reviewedFindings: findings, ruleSet: fixture.rules, appVersion: "test")
        XCTAssertEqual(result.results.first?.outcome, .skipped)
        XCTAssertEqual(calls.value, 0)
    }

    func testCancellationDuringItemFinishesItsRecordAndStopsNextItem() async throws {
        let fixture = try RemovalFixture(extraFile: true)
        let findings = try await fixture.findings()
        var operations = fixture.operations
        operations.beforeTrash = { _ in withUnsafeCurrentTask { $0?.cancel() } }
        let engine = fixture.engine(operations)
        let task = Task { try await engine.moveToTrash(reviewedFindings: findings, ruleSet: fixture.rules, appVersion: "test") }
        let result = try await task.value
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.results.map(\.outcome), [.trashed])
        XCTAssertEqual(try fixture.manifest.read(result.sessionID).events.last?.action, .trashed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.secondFile))
    }

    func testUnobservedOrDuplicateSelectionsFailBeforeSessionCreation() async throws {
        let fixture = try RemovalFixture()
        let findings = try await fixture.findings()
        let finding = try XCTUnwrap(findings.first)
        let unobserved = Finding(resolvedPath: finding.resolvedPath, allocatedSize: finding.allocatedSize,
                                 modifiedAt: finding.modifiedAt, ruleID: finding.ruleID, module: finding.module,
                                 risk: finding.risk, reason: finding.reason, regenerationCost: finding.regenerationCost)
        for selection in [[unobserved], [finding, finding], []] {
            do {
                _ = try await fixture.engine().moveToTrash(reviewedFindings: selection, ruleSet: fixture.rules, appVersion: "test")
                XCTFail("Invalid selection must fail before creating a session")
            } catch { XCTAssertEqual(error as? RemovalSafetyError, .invalidSelection) }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.manifests).isEmpty)
    }

    func testStagingIsReservedFromRulesAndFutureScans() async throws {
        let fixture = try RemovalFixture()
        XCTAssertThrowsError(try fixture.policy.validateRulePath("~/Library/Caches/.racket-staging"))
        let result = try await fixture.run()
        XCTAssertEqual(result.results.first?.outcome, .trashed)
        let walk = try DirectoryWalker(policy: fixture.policy).walk(path: fixture.root, maxDepth: 8)
        XCTAssertTrue(walk.files.isEmpty)
        XCTAssertTrue(walk.issues.contains { $0.path == fixture.root + "/.racket-staging" && $0.disposition == .refused })
    }
}

private struct RemovalFixture: Sendable {
    let home: String
    let policy: SafeRoots
    let manifest: ManifestStore
    let contents = Data(repeating: 0x61, count: 8_192)
    var root: String { home + "/Library/Caches" }
    var vendor: String { root + "/Vendor" }
    var file: String { vendor + "/cache.bin" }
    var secondFile: String { vendor + "/second.bin" }
    var preserved: String { home + "/preserved.bin" }
    var valuable: String { home + "/Documents/valuable.txt" }
    var trash: String { home + "/SyntheticTrash" }
    var manifests: String { home + "/Manifests" }
    var ruleJSON: String {
        """
        {"schemaVersion":1,"version":"1.0.0","rules":[{"id":"fixture.cache","module":"creative",
        "title":"Fixture cache","producers":["io.racket.fixture"],"paths":["~/Library/Caches/Vendor"],
        "match":{"kind":"directoryContents","maxDepth":1},"conditions":[],"risk":"judgement",
        "reason":"Synthetic files only.","regenerationCost":"Created by the test.",
        "citation":"https://example.invalid/fixture","enabled":true,"verified":true}]}
        """
    }
    var rules: RuleSet { get throws { try RuleSet.decode(Data(ruleJSON.utf8), validatePath: policy.validateRulePath) } }

    init(extraFile: Bool = false) throws {
        home = "/private/tmp/RACKET-RemovalFixture-" + UUID().uuidString
        policy = try SafeRoots(homeDirectory: home)
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for name in ["Library/Caches/Vendor", "Library/Logs", "Documents", "SyntheticTrash"] {
            try FileManager.default.createDirectory(atPath: home + "/" + name, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        manifest = try ManifestStore(directory: home + "/Manifests", authenticationKey: Data(repeating: 0x42, count: 32))
        try contents.write(to: URL(fileURLWithPath: file))
        if extraFile { try contents.write(to: URL(fileURLWithPath: secondFile)) }
        try Data("valuable".utf8).write(to: URL(fileURLWithPath: valuable))
    }

    var operations: RemovalOperations {
        RemovalOperations(trash: { path in
            let destination = trash + "/" + (path as NSString).lastPathComponent + "-renamed-by-trash"
            let code = renamex_np(path, destination, UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY))
            guard code == 0 else { throw RemovalSafetyError.system(errno) }
            return destination
        }, isInTrash: { path in SafeRoots.isWithin(path, root: trash) && path != trash })
    }
    func engine(_ custom: RemovalOperations? = nil) -> RemovalEngine {
        RemovalEngine(policy: policy, manifest: manifest, operations: custom ?? operations)
    }
    func findings() async throws -> [Finding] {
        let walker = DirectoryWalker(policy: policy)
        let engine = ScanEngine(policy: policy, concurrencyLimit: 1) { path, depth, skip in
            try walker.walk(path: path, maxDepth: depth, skipExcludedFromBackup: skip)
        }
        return try await engine.scan(ruleSet: rules).findings
    }
    func run(_ custom: RemovalOperations? = nil) async throws -> RemovalReport {
        try await engine(custom).moveToTrash(reviewedFindings: findings(), ruleSet: rules, appVersion: "test")
    }
    func onlySession() throws -> ManifestSession {
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: manifests).first { $0.hasSuffix(".jsonl") })
        let id = try XCTUnwrap(UUID(uuidString: String(file.dropLast(6))))
        return try manifest.read(id)
    }
}

private final class RemovalCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var value: Int { lock.withLock { storage } }
    func increment() { lock.withLock { storage += 1 } }
}
