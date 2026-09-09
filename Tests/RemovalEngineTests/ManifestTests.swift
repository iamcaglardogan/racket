import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import RacketCore

final class ManifestTests: XCTestCase {
    func testCreatesPrivateSessionWithVersionsAndExactDate() throws {
        let fixture = try ManifestFixture()
        let now = Date(timeIntervalSince1970: 1_700_000_000.125)
        let id = try fixture.store.createSession(appVersion: "0.1", ruleSetVersion: "core-v1", now: now)
        let session = try fixture.store.read(id)
        XCTAssertEqual(session.id, id)
        XCTAssertEqual(session.createdAt, now)
        XCTAssertEqual(session.appVersion, "0.1")
        XCTAssertEqual(session.ruleSetVersion, "core-v1")
        XCTAssertTrue(session.events.isEmpty)
        XCTAssertEqual(try fixture.permissions(fixture.directory), 0o700)
        XCTAssertEqual(try fixture.permissions(fixture.path(id)), 0o600)
        let bytes = try fixture.store.export(id)
        XCTAssertEqual(bytes.last, 10)
        XCTAssertEqual(bytes.filter { $0 == 10 }.count, 1)
    }

    func testEveryEventAndUInt64MaximumSurviveAuthenticatedRoundTrip() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        let actions: [ManifestAction] = [.prepared, .staged, .trashed, .failed, .refused, .recoveryRequired, .restorePrepared, .restored, .restoreFailed]
        let events = actions.map { fixture.event($0) }
        for event in events { try fixture.store.append(event, to: id) }
        XCTAssertEqual(try fixture.store.read(id).events, events)
        XCTAssertEqual(try fixture.store.export(id).filter { $0 == 10 }.count, 10)
        let reopened = try ManifestStore(directory: fixture.directory, authenticationKey: fixture.key)
        XCTAssertEqual(try reopened.read(id).events, events)
    }

    func testExportContainsReadablePathsAndVersionsInJSONPayloadText() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.store.createSession(appVersion: "0.1-readable", ruleSetVersion: "rules-readable")
        let event = fixture.event()
        try fixture.store.append(event, to: id)
        let bytes = try fixture.store.export(id)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertTrue(text.contains("0.1-readable"))
        XCTAssertTrue(text.contains("rules-readable"))
        XCTAssertTrue(text.contains(event.item.originalPath))
        XCTAssertTrue(text.contains(event.item.ruleID))
        let payloads = try bytes.split(separator: 10).map { line -> [String: Any] in
            let record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
            let payload = try XCTUnwrap(record["payload"] as? String)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        }
        let header = try XCTUnwrap(payloads[0]["header"] as? [String: Any])
        XCTAssertEqual(header["appVersion"] as? String, "0.1-readable")
        XCTAssertEqual(header["ruleSetVersion"] as? String, "rules-readable")
        let restoredEvent = try XCTUnwrap(payloads[1]["event"] as? [String: Any])
        let item = try XCTUnwrap(restoredEvent["item"] as? [String: Any])
        XCTAssertEqual(item["originalPath"] as? String, event.item.originalPath)
        XCTAssertEqual(item["ruleID"] as? String, event.item.ruleID)
    }

    func testInvalidHeaderIsRejectedBeforeCreatingAnyJournal() throws {
        let fixture = try ManifestFixture()
        let invalidVersions = ["", " \n\t", String(repeating: "x", count: ManifestStore.maximumVersionBytes + 1),
                               String(repeating: "é", count: ManifestStore.maximumVersionBytes / 2 + 1)]
        for version in invalidVersions {
            for values in [(version, "rules"), ("app", version)] {
                XCTAssertThrowsError(try fixture.store.createSession(appVersion: values.0, ruleSetVersion: values.1)) {
                    XCTAssertEqual($0 as? ManifestError, .invalidHeader)
                }
            }
        }
        for seconds in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try fixture.store.createSession(appVersion: "app", ruleSetVersion: "rules",
                                                                  now: Date(timeIntervalSinceReferenceDate: seconds))) {
                XCTAssertEqual($0 as? ManifestError, .invalidHeader)
            }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.directory).isEmpty)
    }

    func testVersionByteLimitAcceptsExactBoundary() throws {
        let fixture = try ManifestFixture()
        let version = String(repeating: "é", count: ManifestStore.maximumVersionBytes / 2)
        let id = try fixture.store.createSession(appVersion: version, ruleSetVersion: version)
        let session = try fixture.store.read(id)
        XCTAssertEqual(session.appVersion, version)
        XCTAssertEqual(session.ruleSetVersion, version)
    }

    func testAuthenticatedInvalidHeaderIsRejectedOnReadAndAppend() throws {
        for field in ["appVersion", "ruleSetVersion"] {
            for value in [" \n\t", String(repeating: "x", count: ManifestStore.maximumVersionBytes + 1)] {
                let fixture = try ManifestFixture()
                let id = try fixture.session()
                try fixture.replaceAuthenticatedHeader(id, field: field, value: value)
                XCTAssertThrowsError(try fixture.store.read(id)) { XCTAssertEqual($0 as? ManifestError, .corruptJournal) }
                XCTAssertThrowsError(try fixture.store.append(fixture.event(), to: id)) {
                    XCTAssertEqual($0 as? ManifestError, .corruptJournal)
                }
            }
        }
    }

    func testEquivalentJSONPayloadWithChangedBytesIsRejected() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        let line = try XCTUnwrap(try fixture.bytes(id).split(separator: 10).first)
        var record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
        let payload = try XCTUnwrap(record["payload"] as? String)
        record["payload"] = " " + payload
        var changed = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        changed.append(10)
        try fixture.replace(id, bytes: changed)
        XCTAssertThrowsError(try fixture.store.read(id)) { XCTAssertEqual($0 as? ManifestError, .corruptJournal) }
    }

    func testPersistentKeyReopensJournalWithoutGeneratingAnotherKey() throws {
        let directory = ManifestFixture.freshPath()
        let first = try ManifestStore(persistentDirectory: directory)
        let keyPath = directory + "/authentication.key"
        let key = try Data(contentsOf: URL(fileURLWithPath: keyPath))
        XCTAssertEqual(key.count, 32)
        let id = try first.createSession(appVersion: "1", ruleSetVersion: "1")
        let second = try ManifestStore(persistentDirectory: directory)
        XCTAssertEqual(try second.read(id).id, id)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: keyPath)), key)
    }

    func testWrongKeyCannotReadOrAppendAndPreservesEvidence() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        let before = try fixture.bytes(id)
        let other = try ManifestStore(directory: fixture.directory, authenticationKey: Data(repeating: 8, count: 32))
        XCTAssertThrowsError(try other.read(id)) { XCTAssertEqual($0 as? ManifestError, .corruptJournal) }
        XCTAssertThrowsError(try other.append(fixture.event(), to: id))
        XCTAssertEqual(try fixture.bytes(id), before)
    }

    func testInvalidKeyLengthIsRefused() throws {
        for count in [0, 31, 33] {
            XCTAssertThrowsError(try ManifestStore(directory: ManifestFixture.freshPath(), authenticationKey: Data(repeating: 1, count: count))) {
                XCTAssertEqual($0 as? ManifestError, .invalidKey)
            }
        }
    }

    func testPayloadTamperingIsRejected() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        let line = try XCTUnwrap(try fixture.bytes(id).split(separator: 10).first)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
        object["payload"] = "tampered"
        var corrupted = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        corrupted.append(10)
        try fixture.replace(id, bytes: corrupted)
        XCTAssertThrowsError(try fixture.store.read(id)) { XCTAssertEqual($0 as? ManifestError, .corruptJournal) }
        XCTAssertThrowsError(try fixture.store.export(id))
    }

    func testRemovedMiddleRecordAndReorderedRecordsAreRejected() throws {
        for reorder in [false, true] {
            let fixture = try ManifestFixture()
            let id = try fixture.session()
            try fixture.store.append(fixture.event(.prepared), to: id)
            try fixture.store.append(fixture.event(.staged), to: id)
            var lines = try fixture.bytes(id).split(separator: 10).map { Data($0) }
            if reorder { lines.swapAt(1, 2) } else { lines.remove(at: 1) }
            var changed = Data()
            for line in lines { changed.append(line); changed.append(10) }
            try fixture.replace(id, bytes: changed)
            XCTAssertThrowsError(try fixture.store.read(id)) { XCTAssertEqual($0 as? ManifestError, .corruptJournal) }
        }
    }

    func testDuplicateValidRecordIsRejected() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        try fixture.store.append(fixture.event(), to: id)
        var duplicate = Data(try XCTUnwrap(try fixture.bytes(id).split(separator: 10).last))
        duplicate.append(10)
        try fixture.appendRaw(id, bytes: duplicate)
        XCTAssertThrowsError(try fixture.store.read(id))
    }

    func testCrossSessionReplayIsRejectedEvenWithSameKey() throws {
        let fixture = try ManifestFixture()
        let first = try fixture.session()
        let second = try fixture.session()
        try fixture.replace(second, bytes: fixture.bytes(first))
        XCTAssertThrowsError(try fixture.store.read(second)) { XCTAssertEqual($0 as? ManifestError, .corruptJournal) }
    }

    func testPartialTailPreventsReadExportAndFurtherAppendWithoutDiscardingBytes() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        try fixture.appendRaw(id, bytes: Data("{\"sequence\":".utf8))
        let damaged = try fixture.bytes(id)
        XCTAssertThrowsError(try fixture.store.read(id))
        XCTAssertThrowsError(try fixture.store.export(id))
        XCTAssertThrowsError(try fixture.store.append(fixture.event(), to: id))
        XCTAssertEqual(try fixture.bytes(id), damaged)
    }

    func testBlankOrMalformedCompleteTailIsRejected() throws {
        for tail in ["\n", "{}\n", "not-json\n"] {
            let fixture = try ManifestFixture()
            let id = try fixture.session()
            try fixture.appendRaw(id, bytes: Data(tail.utf8))
            XCTAssertThrowsError(try fixture.store.read(id))
        }
    }

    func testOversizedRecordIsRefusedBeforeAppending() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        let before = try fixture.bytes(id)
        XCTAssertThrowsError(try fixture.store.append(fixture.event(detail: String(repeating: "x", count: ManifestStore.maximumRecordBytes)), to: id)) {
            XCTAssertEqual($0 as? ManifestError, .limitExceeded)
        }
        XCTAssertEqual(try fixture.bytes(id), before)
    }

    func testOversizedJournalReadIsBounded() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        let descriptor = Darwin.open(fixture.path(id), O_WRONLY | O_APPEND | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { Darwin.close(descriptor) }
        let block = [UInt8](repeating: 0x20, count: 1_024 * 1_024)
        for _ in 0..<32 { XCTAssertEqual(Darwin.write(descriptor, block, block.count), block.count) }
        XCTAssertThrowsError(try fixture.store.read(id)) { XCTAssertEqual($0 as? ManifestError, .limitExceeded) }
    }

    func testJournalSymlinkIsRefusedWithoutTouchingItsTarget() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        let target = fixture.path(id) + ".preserved"
        XCTAssertEqual(Darwin.rename(fixture.path(id), target), 0)
        XCTAssertEqual(Darwin.symlink(target, fixture.path(id)), 0)
        let before = try Data(contentsOf: URL(fileURLWithPath: target))
        XCTAssertThrowsError(try fixture.store.append(fixture.event(), to: id))
        XCTAssertThrowsError(try fixture.store.read(id))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: target)), before)
    }

    func testHardLinkedJournalIsRefused() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        XCTAssertEqual(Darwin.link(fixture.path(id), fixture.path(id) + ".alias"), 0)
        XCTAssertThrowsError(try fixture.store.read(id)) { XCTAssertEqual($0 as? ManifestError, .unsafeMetadata) }
        XCTAssertThrowsError(try fixture.store.append(fixture.event(), to: id))
    }

    func testGroupOrWorldReadableJournalIsRefusedWithoutRepairingPermissions() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        XCTAssertEqual(Darwin.chmod(fixture.path(id), 0o644), 0)
        XCTAssertThrowsError(try fixture.store.read(id)) { XCTAssertEqual($0 as? ManifestError, .unsafeMetadata) }
        XCTAssertEqual(try fixture.permissions(fixture.path(id)), 0o644)
    }

    func testDirectorySymlinkAndUnsafeModeAreRefused() throws {
        let fixture = try ManifestFixture()
        let alias = ManifestFixture.freshPath()
        XCTAssertEqual(Darwin.symlink(fixture.directory, alias), 0)
        XCTAssertThrowsError(try ManifestStore(directory: alias, authenticationKey: fixture.key))
        XCTAssertEqual(Darwin.chmod(fixture.directory, 0o755), 0)
        XCTAssertThrowsError(try ManifestStore(directory: fixture.directory, authenticationKey: fixture.key)) {
            XCTAssertEqual($0 as? ManifestError, .unsafeMetadata)
        }
        XCTAssertEqual(try fixture.permissions(fixture.directory), 0o755)
    }

    func testReplacementOfManifestDirectoryIsRefused() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        XCTAssertEqual(Darwin.rename(fixture.directory, fixture.directory + ".preserved"), 0)
        XCTAssertEqual(Darwin.mkdir(fixture.directory, 0o700), 0)
        XCTAssertThrowsError(try fixture.store.read(id)) { XCTAssertEqual($0 as? ManifestError, .changed) }
        XCTAssertThrowsError(try fixture.store.createSession(appVersion: "1", ruleSetVersion: "1"))
    }

    func testSymlinkAndHardLinkedPersistentKeysAreRefused() throws {
        for useSymlink in [false, true] {
            let directory = ManifestFixture.freshPath()
            _ = try ManifestStore(persistentDirectory: directory)
            let path = directory + "/authentication.key"
            let preserved = path + ".preserved"
            if useSymlink {
                XCTAssertEqual(Darwin.rename(path, preserved), 0)
                XCTAssertEqual(Darwin.symlink(preserved, path), 0)
            } else { XCTAssertEqual(Darwin.link(path, preserved), 0) }
            XCTAssertThrowsError(try ManifestStore(persistentDirectory: directory))
        }
    }

    func testMalformedPersistentKeyIsPreservedAndRefused() throws {
        let directory = ManifestFixture.freshPath()
        _ = try ManifestStore(persistentDirectory: directory)
        let path = directory + "/authentication.key"
        try Data("short".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(Darwin.chmod(path, 0o600), 0)
        XCTAssertThrowsError(try ManifestStore(persistentDirectory: directory)) { XCTAssertEqual($0 as? ManifestError, .invalidKey) }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data("short".utf8))
    }

    func testSyncFailureIsReportedWhileAttemptedRecordRemains() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        let failing = try ManifestStore(directory: fixture.directory, authenticationKey: fixture.key, synchronize: { _ in throw ManifestError.system(EIO) })
        let event = fixture.event()
        XCTAssertThrowsError(try failing.append(event, to: id)) { XCTAssertEqual($0 as? ManifestError, .system(EIO)) }
        XCTAssertEqual(try fixture.store.read(id).events, [event])
    }

    func testOperationLockPreventsOtherStoreAndPermitsJournalCallsInsideBody() throws {
        let fixture = try ManifestFixture()
        let other = try ManifestStore(directory: fixture.directory, authenticationKey: fixture.key)
        let id = try fixture.session()
        try fixture.store.withExclusiveOperation {
            XCTAssertThrowsError(try other.withExclusiveOperation {}) { XCTAssertEqual($0 as? ManifestError, .busy) }
            try fixture.store.append(fixture.event(), to: id)
            XCTAssertEqual(try fixture.store.read(id).events.count, 1)
        }
        try other.withExclusiveOperation {}
    }

    func testOperationLockReleasesAfterThrownBody() throws {
        let fixture = try ManifestFixture()
        XCTAssertThrowsError(try fixture.store.withExclusiveOperation { throw ManifestError.changed })
        try fixture.store.withExclusiveOperation {}
    }

    func testDatalessMetadataStopsBeforeCloudAndStat() throws {
        let probe = ManifestMetadataProbe()
        var operations = ScanMetadataOperations.live
        operations.flags = { _ in probe.record("flags"); return UInt32(SF_DATALESS) }
        operations.cloud = { _ in probe.record("cloud"); return .init(isUbiquitous: nil, downloadingStatus: nil) }
        operations.metadata = { _ in probe.record("stat"); return stat() }
        XCTAssertThrowsError(try ManifestStore(directory: ManifestFixture.freshPath(), authenticationKey: Data(repeating: 1, count: 32), operations: operations)) {
            XCTAssertEqual($0 as? ScanMetadataError, .dataless)
        }
        XCTAssertEqual(probe.events, ["flags"])
    }

    func testACLGrantIsRefusedDespitePrivateMode() throws {
        let fixture = try ManifestFixture()
        let id = try fixture.session()
        let path = fixture.path(id)
        let text = "!#acl 1\ngroup:ABCDEFAB-CDEF-ABCD-EFAB-CDEF0000000C:everyone:12:allow:read\n"
        let acl = try XCTUnwrap(text.withCString { acl_from_text($0) })
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        XCTAssertEqual(acl_set_file(path, ACL_TYPE_EXTENDED, acl), 0)
        XCTAssertEqual(try fixture.permissions(path), 0o600)
        XCTAssertThrowsError(try fixture.store.read(id)) { XCTAssertEqual($0 as? ManifestError, .unsafeMetadata) }
    }

    func testNoncanonicalDirectoryPathsAreRefused() throws {
        for path in ["relative", "/private/tmp/../tmp/racket", "/private//tmp/racket", "/private/tmp/racket/"] {
            XCTAssertThrowsError(try ManifestStore(directory: path, authenticationKey: Data(repeating: 1, count: 32))) {
                XCTAssertEqual($0 as? ManifestError, .unsafePath)
            }
        }
    }
}

private struct ManifestFixture {
    let directory: String
    let key = Data(repeating: 7, count: 32)
    let store: ManifestStore

    init() throws {
        directory = Self.freshPath()
        store = try ManifestStore(directory: directory, authenticationKey: key)
    }

    static func freshPath() -> String { "/private/tmp/racket-manifest-tests-" + UUID().uuidString }
    func path(_ id: UUID) -> String { directory + "/" + id.uuidString.lowercased() + ".jsonl" }
    func session() throws -> UUID { try store.createSession(appVersion: "test", ruleSetVersion: "fixture") }
    func bytes(_ id: UUID) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: path(id))) }

    func event(_ action: ManifestAction = .prepared, detail: String? = "fixture") -> ManifestEvent {
        ManifestEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000.5), action: action,
            item: ManifestItem(id: UUID(), originalPath: directory + "/fake-home/Library/Caches/example.bin", ruleID: "fixture.rule", allocatedSize: .max,
                identity: ManifestIdentity(device: 1, inode: 2, generation: 3, owner: getuid(), group: getgid(), mode: UInt16(S_IFREG) | 0o600, flags: 0, links: 1, bornSeconds: 123, bornNanoseconds: 456, modifiedSeconds: 789, modifiedNanoseconds: 123)),
            stagingPath: directory + "/staging/example.bin", trashPath: directory + "/fake-trash/example.bin", detail: detail
        )
    }

    func permissions(_ path: String) throws -> UInt16 {
        var value = stat()
        guard Darwin.lstat(path, &value) == 0 else { throw ManifestError.system(errno) }
        return value.st_mode & 0o7777
    }

    func appendRaw(_ id: UUID, bytes: Data) throws {
        let descriptor = Darwin.open(path(id), O_WRONLY | O_APPEND | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ManifestError.system(errno) }
        defer { Darwin.close(descriptor) }
        let count = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        guard count == bytes.count else { throw ManifestError.system(errno) }
    }

    func replace(_ id: UUID, bytes: Data) throws {
        // Preserve the original signed evidence before constructing corrupt input.
        try self.bytes(id).write(to: URL(fileURLWithPath: path(id) + ".original-" + UUID().uuidString))
        try bytes.write(to: URL(fileURLWithPath: path(id)))
        guard Darwin.chmod(path(id), 0o600) == 0 else { throw ManifestError.system(errno) }
    }

    func replaceAuthenticatedHeader(_ id: UUID, field: String, value: String) throws {
        let line = try XCTUnwrap(try bytes(id).split(separator: 10).first)
        var record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
        let originalPayload = try XCTUnwrap(record["payload"] as? String)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(originalPayload.utf8)) as? [String: Any])
        var header = try XCTUnwrap(payload["header"] as? [String: Any])
        header[field] = value
        payload["header"] = header
        let payloadBytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        record["payload"] = try XCTUnwrap(String(data: payloadBytes, encoding: .utf8))
        var authenticated = Data("RACKET.Manifest.v1\0".utf8)
        authenticated.append(Data(repeating: 0, count: 8 + 32)) // Sequence zero and the initial previous MAC.
        authenticated.append(payloadBytes)
        let mac = Data(HMAC<SHA256>.authenticationCode(for: authenticated, using: SymmetricKey(data: key)))
        record["mac"] = mac.base64EncodedString()
        var changed = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        changed.append(10)
        try replace(id, bytes: changed)
    }
}

private final class ManifestMetadataProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    var events: [String] { lock.lock(); defer { lock.unlock() }; return values }
    func record(_ value: String) { lock.lock(); defer { lock.unlock() }; values.append(value) }
}
