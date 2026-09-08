import Darwin
import Foundation
import XCTest
@testable import RacketCore

final class SizeCalculatorTests: XCTestCase {
    func testDatalessFlagsStopBeforeCloudStatAndSize() throws {
        let probe = MetadataProbe(flags: [UInt32(SF_DATALESS)])
        assertFailure(.dataless, probe)
        XCTAssertEqual(probe.events, ["flags"])
    }

    func testCloudPlaceholderStopsBeforeStatAndSize() throws {
        let probe = MetadataProbe(cloud: .init(isUbiquitous: true, downloadingStatus: .notDownloaded))
        assertFailure(.dataless, probe)
        XCTAssertEqual(probe.events, ["flags", "cloud"])
    }

    func testUnknownUbiquitousStatusStopsBeforeStatAndSize() throws {
        for status: ScanCloudMetadata.DownloadingStatus? in [nil, .unknown] {
            let probe = MetadataProbe(cloud: .init(isUbiquitous: true, downloadingStatus: status))
            assertFailure(.unsupportedMetadata, probe)
            XCTAssertEqual(probe.events, ["flags", "cloud"])
        }
    }

    func testAbsentCloudValuesRemainSubjectToFlagsAndSizeGates() throws {
        let probe = MetadataProbe(cloud: .init(isUbiquitous: nil, downloadingStatus: nil))
        let value = try inspect(probe)
        XCTAssertEqual(value.allocatedSize, 4_096)
        XCTAssertEqual(probe.events, ["flags", "cloud", "stat", "flags", "size"])
    }

    func testConflictingCloudValuesFailClosed() throws {
        for cloud in [
            ScanCloudMetadata(isUbiquitous: nil, downloadingStatus: .current),
            ScanCloudMetadata(isUbiquitous: false, downloadingStatus: .current),
            ScanCloudMetadata(isUbiquitous: false, downloadingStatus: .unknown)
        ] {
            let probe = MetadataProbe(cloud: cloud)
            assertFailure(.unsupportedMetadata, probe)
            XCTAssertEqual(probe.events, ["flags", "cloud"])
        }
    }

    func testDownloadedCloudStatusesStillRequireDescriptorChecks() throws {
        for status: ScanCloudMetadata.DownloadingStatus in [.downloaded, .current] {
            let probe = MetadataProbe(cloud: .init(isUbiquitous: true, downloadingStatus: status))
            XCTAssertEqual(try inspect(probe).allocatedSize, 4_096)
            XCTAssertEqual(probe.events, ["flags", "cloud", "stat", "flags", "size"])
        }
    }

    func testFlagsChangingToDatalessAtStatPreventSize() throws {
        var metadata = ordinaryMetadata()
        metadata.st_flags = UInt32(SF_DATALESS)
        let probe = MetadataProbe(metadata: metadata)
        assertFailure(.dataless, probe)
        XCTAssertEqual(probe.events, ["flags", "cloud", "stat"])
    }

    func testDatalessRecheckImmediatelyBeforeSizeStopsSize() throws {
        let probe = MetadataProbe(flags: [0, UInt32(SF_DATALESS)])
        assertFailure(.dataless, probe)
        XCTAssertEqual(probe.events, ["flags", "cloud", "stat", "flags"])
    }

    func testOtherFlagChangesPreventSize() throws {
        let probe = MetadataProbe(flags: [0, UInt32(UF_HIDDEN)])
        assertFailure(.changed, probe)
        XCTAssertEqual(probe.events, ["flags", "cloud", "stat", "flags"])
    }

    func testMissingAndNegativeAllocatedSizeNeverFallBackToLogicalSize() throws {
        for size: Int? in [nil, -1] {
            let probe = MetadataProbe(size: size)
            assertFailure(.unsupportedMetadata, probe)
            XCTAssertEqual(probe.events, ["flags", "cloud", "stat", "flags", "size"])
        }
    }

    func testZeroAndLargeAllocatedSizesUseUInt64Exactly() throws {
        for size in [0, Int.max] {
            XCTAssertEqual(try inspect(MetadataProbe(size: size)).allocatedSize, UInt64(size))
        }
    }

    func testIdentityOnlyInspectionNeverRequestsSize() throws {
        let probe = MetadataProbe()
        let value = try inspect(probe, includeSize: false)
        XCTAssertEqual(value.allocatedSize, 0)
        XCTAssertEqual(value.identity, ScanFileIdentity(device: 9, inode: 42))
        XCTAssertEqual(value.modifiedAt, Date(timeIntervalSince1970: 1_700_000_000.25))
        XCTAssertEqual(probe.events, ["flags", "cloud", "stat"])
    }

    func testDirectoryInspectionNeverRequestsAFileSize() throws {
        var metadata = ordinaryMetadata()
        metadata.st_mode = mode_t(S_IFDIR) | 0o700
        let probe = MetadataProbe(metadata: metadata)
        let value = try inspect(probe)
        XCTAssertEqual(value.kind, .directory)
        XCTAssertEqual(value.allocatedSize, 0)
        XCTAssertEqual(probe.events, ["flags", "cloud", "stat"])
    }

    func testUnsupportedFileTypeNeverReachesSize() throws {
        for kind in [S_IFIFO, S_IFLNK, S_IFSOCK, S_IFCHR, S_IFBLK] {
            var metadata = ordinaryMetadata()
            metadata.st_mode = mode_t(kind) | 0o600
            let probe = MetadataProbe(metadata: metadata)
            assertFailure(.unsupportedFileType, probe)
            XCTAssertEqual(probe.events, ["flags", "cloud", "stat"])
        }
    }

    func testInvalidTimestampFailsBeforeSize() throws {
        var metadata = ordinaryMetadata()
        metadata.st_mtimespec.tv_nsec = 1_000_000_000
        let probe = MetadataProbe(metadata: metadata)
        assertFailure(.unsupportedMetadata, probe)
        XCTAssertEqual(probe.events, ["flags", "cloud", "stat"])
    }

    func testBackupExclusionIsNotQueriedByDefault() throws {
        let probe = MetadataProbe(excluded: true)
        XCTAssertEqual(try inspect(probe).allocatedSize, 4_096)
        XCTAssertFalse(probe.events.contains("backup"))
    }

    func testExplicitBackupExclusionStopsBeforeStatAndSize() throws {
        let probe = MetadataProbe(excluded: true)
        assertFailure(.excludedFromBackup, probe, skipExcludedFromBackup: true)
        XCTAssertEqual(probe.events, ["flags", "cloud", "backup"])
    }

    func testUnknownRequestedBackupStatusIsReported() throws {
        let probe = MetadataProbe(excluded: nil)
        assertFailure(.unsupportedMetadata, probe, skipExcludedFromBackup: true)
        XCTAssertEqual(probe.events, ["flags", "cloud", "backup"])
    }

    func testBackupIncludedFileStillRequiresAllMetadataGates() throws {
        let probe = MetadataProbe(excluded: false)
        XCTAssertEqual(try inspect(probe, skipExcludedFromBackup: true).allocatedSize, 4_096)
        XCTAssertEqual(probe.events, ["flags", "cloud", "backup", "stat", "flags", "size"])
    }

    func testFlagsMetadataFailureDoesNotRequestOtherAttributes() throws {
        let probe = MetadataProbe(failure: .init(stage: "flags", error: .system(EACCES)))
        assertFailure(.system(EACCES), probe)
        XCTAssertEqual(probe.events, ["flags"])
    }

    func testFoundationWrappedMaterializationErrorIsReportedAsDataless() throws {
        var operations = MetadataProbe().operations
        operations.cloud = { _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EDEADLK))
            ])
        }
        XCTAssertThrowsError(try SizeCalculator(operations: operations).inspect(descriptor: -1, path: "/synthetic", includeSize: true)) {
            XCTAssertEqual($0 as? ScanMetadataError, .dataless)
        }
    }

    func testFingerprintDetectsInPlaceMutationAndPermissionChange() throws {
        let original = ordinaryMetadata()
        let first = try inspect(MetadataProbe(metadata: original), includeSize: false)
        var modified = original
        modified.st_ctimespec.tv_nsec += 1
        let changed = try inspect(MetadataProbe(metadata: modified), includeSize: false)
        XCTAssertEqual(first.identity, changed.identity)
        XCTAssertNotEqual(first.fingerprint, changed.fingerprint)
        modified = original
        modified.st_mode ^= 0o100
        XCTAssertNotEqual(first.fingerprint, try inspect(MetadataProbe(metadata: modified), includeSize: false).fingerprint)
    }

    func testMaterializationPolicyIsRestoredAfterSuccess() throws {
        let original = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        XCTAssertGreaterThanOrEqual(original, 0)
        let value = try withoutDatalessMaterialization {
            XCTAssertEqual(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD), IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
            return 19
        }
        XCTAssertEqual(value, 19)
        XCTAssertEqual(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD), original)
    }

    func testMaterializationPolicyIsRestoredAfterThrownError() throws {
        let original = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        XCTAssertThrowsError(try withoutDatalessMaterialization { throw ScanMetadataError.changed }) {
            XCTAssertEqual($0 as? ScanMetadataError, .changed)
        }
        XCTAssertEqual(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD), original)
    }

    func testNestedMaterializationScopesRestoreTheirCallersPolicy() throws {
        let original = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        try withoutDatalessMaterialization {
            try withoutDatalessMaterialization {
                XCTAssertEqual(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD), IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
            }
            XCTAssertEqual(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD), IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        }
        XCTAssertEqual(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD), original)
    }

    func testLiveSparseFileReportsAllocationRatherThanLogicalLength() throws {
        let fixture = try SizeFixture()
        let descriptor = Darwin.open(fixture.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ScanMetadataError.system(errno) }
        defer { _ = Darwin.close(descriptor) }
        var byte: UInt8 = 11
        XCTAssertEqual(Darwin.write(descriptor, &byte, 1), 1)
        let logicalLength: off_t = 64 * 1_024 * 1_024
        XCTAssertEqual(Darwin.ftruncate(descriptor, logicalLength), 0)
        let result = try withoutDatalessMaterialization {
            try SizeCalculator().inspect(descriptor: descriptor, path: fixture.path, includeSize: true)
        }
        XCTAssertEqual(result.kind, .regularFile)
        XCTAssertGreaterThan(result.allocatedSize, 0)
        XCTAssertLessThan(result.allocatedSize, UInt64(logicalLength))
    }

    func testLiveResourceForkContributesToTotalAllocatedSize() throws {
        let fixture = try SizeFixture()
        let descriptor = Darwin.open(fixture.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ScanMetadataError.system(errno) }
        defer { _ = Darwin.close(descriptor) }
        let before = try withoutDatalessMaterialization {
            try SizeCalculator().inspect(descriptor: descriptor, path: fixture.path, includeSize: true)
        }
        let resourceDescriptor = Darwin.open(fixture.path + "/..namedfork/rsrc", O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard resourceDescriptor >= 0 else { throw ScanMetadataError.system(errno) }
        defer { _ = Darwin.close(resourceDescriptor) }
        let data = [UInt8](repeating: 83, count: 65_536)
        try data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let amount = Darwin.write(resourceDescriptor, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                guard amount > 0 else { throw ScanMetadataError.system(errno) }
                written += amount
            }
        }
        XCTAssertEqual(Darwin.fsync(resourceDescriptor), 0)
        let after = try withoutDatalessMaterialization {
            try SizeCalculator().inspect(descriptor: descriptor, path: fixture.path, includeSize: true)
        }
        XCTAssertGreaterThan(after.allocatedSize, before.allocatedSize)
        XCTAssertGreaterThanOrEqual(after.allocatedSize, UInt64(data.count))
    }

    func testLiveDirectoryIsAnIdentityObservationWithoutSize() throws {
        let fixture = try SizeFixture()
        let descriptor = Darwin.open(fixture.directory, O_EVTONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ScanMetadataError.system(errno) }
        defer { _ = Darwin.close(descriptor) }
        let result = try withoutDatalessMaterialization {
            try SizeCalculator().inspect(descriptor: descriptor, path: fixture.directory, includeSize: true)
        }
        XCTAssertEqual(result.kind, .directory)
        XCTAssertEqual(result.allocatedSize, 0)
    }

    private func inspect(_ probe: MetadataProbe, includeSize: Bool = true, skipExcludedFromBackup: Bool = false) throws -> ScanMetadata {
        try SizeCalculator(operations: probe.operations).inspect(descriptor: -1, path: "/synthetic/cache", includeSize: includeSize, skipExcludedFromBackup: skipExcludedFromBackup)
    }

    private func assertFailure(_ expected: ScanMetadataError, _ probe: MetadataProbe, skipExcludedFromBackup: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try inspect(probe, skipExcludedFromBackup: skipExcludedFromBackup), file: file, line: line) {
            XCTAssertEqual($0 as? ScanMetadataError, expected, file: file, line: line)
        }
    }
}

private func ordinaryMetadata() -> stat {
    var value = stat()
    value.st_dev = 9
    value.st_ino = 42
    value.st_mode = mode_t(S_IFREG) | 0o600
    value.st_nlink = 1
    value.st_uid = 501
    value.st_gid = 20
    value.st_gen = 8
    value.st_mtimespec = timespec(tv_sec: 1_700_000_000, tv_nsec: 250_000_000)
    value.st_ctimespec = value.st_mtimespec
    value.st_birthtimespec = timespec(tv_sec: 1_600_000_000, tv_nsec: 0)
    return value
}

/// Configuration is immutable. The only mutable state (event order and the flags
/// cursor) is protected by a lock for the operations' Sendable closures.
private final class MetadataProbe: @unchecked Sendable {
    struct Failure { let stage: String; let error: ScanMetadataError }
    private let lock = NSLock()
    private var recorded: [String] = []
    private var flagIndex = 0
    private let flagValues: [UInt32]
    private let cloudValue: ScanCloudMetadata
    private let metadataValue: stat
    private let sizeValue: Int?
    private let excludedValue: Bool?
    private let failure: Failure?

    init(flags: [UInt32] = [0], cloud: ScanCloudMetadata = .init(isUbiquitous: false, downloadingStatus: nil), metadata: stat = ordinaryMetadata(), size: Int? = 4_096, excluded: Bool? = false, failure: Failure? = nil) {
        flagValues = flags
        cloudValue = cloud
        metadataValue = metadata
        sizeValue = size
        excludedValue = excluded
        self.failure = failure
    }

    var events: [String] { lock.withLock { recorded } }

    var operations: ScanMetadataOperations {
        ScanMetadataOperations(
            flags: { _ in try self.lock.withLock {
                try self.record("flags")
                let value = self.flagValues[min(self.flagIndex, self.flagValues.count - 1)]
                self.flagIndex += 1
                return value
            } },
            cloud: { _ in try self.lock.withLock { try self.record("cloud"); return self.cloudValue } },
            metadata: { _ in try self.lock.withLock { try self.record("stat"); return self.metadataValue } },
            allocatedSize: { _ in try self.lock.withLock { try self.record("size"); return self.sizeValue } },
            excludedFromBackup: { _ in try self.lock.withLock { try self.record("backup"); return self.excludedValue } }
        )
    }

    private func record(_ stage: String) throws {
        recorded.append(stage)
        if let failure, failure.stage == stage { throw failure.error }
    }
}

/// Synthetic fixtures are retained. No cleanup deletes files or their forks.
private struct SizeFixture {
    let directory: String
    var path: String { directory + "/sample.bin" }

    init() throws {
        directory = "/private/tmp/RACKET-Size-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
}
