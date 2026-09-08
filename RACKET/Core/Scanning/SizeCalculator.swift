import Darwin
import Foundation

/// Scanner metadata is an observation. In particular, Foundation's URL values
/// do not grant path authority; the walker brackets them with descriptor checks.
struct ScanMetadata: Sendable {
    enum Kind: Equatable, Sendable { case regularFile, directory }

    let kind: Kind
    let identity: ScanFileIdentity
    let modifiedAt: Date
    let allocatedSize: UInt64
    let fingerprint: ScanMetadataFingerprint
}

struct ScanMetadataFingerprint: Equatable, Sendable {
    let identity: ScanFileIdentity
    let generation: UInt32
    let mode: UInt16
    let flags: UInt32
    let links: UInt16
    let owner: UInt32
    let group: UInt32
    let bornSeconds: Int
    let bornNanoseconds: Int
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    init(_ value: stat) {
        identity = ScanFileIdentity(device: value.st_dev, inode: value.st_ino)
        generation = value.st_gen
        mode = value.st_mode
        flags = value.st_flags
        links = value.st_nlink
        owner = value.st_uid
        group = value.st_gid
        bornSeconds = value.st_birthtimespec.tv_sec
        bornNanoseconds = value.st_birthtimespec.tv_nsec
        modifiedSeconds = value.st_mtimespec.tv_sec
        modifiedNanoseconds = value.st_mtimespec.tv_nsec
        changedSeconds = value.st_ctimespec.tv_sec
        changedNanoseconds = value.st_ctimespec.tv_nsec
    }
}

enum ScanMetadataError: Error, Equatable, Sendable {
    case dataless
    case excludedFromBackup
    case unsupportedMetadata
    case system(Int32)
    case unsupportedFileType
    case changed
}

struct ScanCloudMetadata: Sendable {
    enum DownloadingStatus: Sendable { case notDownloaded, downloaded, current, unknown }
    let isUbiquitous: Bool?
    let downloadingStatus: DownloadingStatus?
}

/// Narrow operation seams let tests prove that rejected placeholders never reach
/// stat or size access. None of the live operations opens or reads file contents.
struct ScanMetadataOperations: Sendable {
    var flags: @Sendable (Int32) throws -> UInt32
    var cloud: @Sendable (String) throws -> ScanCloudMetadata
    var metadata: @Sendable (Int32) throws -> stat
    var allocatedSize: @Sendable (String) throws -> Int?
    var excludedFromBackup: @Sendable (String) throws -> Bool?

    static let live = ScanMetadataOperations(
        flags: { descriptor in
            var attributes = attrlist()
            attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
            attributes.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_FLAGS)
            var result = ScanFlagsBuffer()
            guard Darwin.fgetattrlist(descriptor, &attributes, &result, MemoryLayout<ScanFlagsBuffer>.size, 0) == 0 else {
                throw metadataSystemError(errno)
            }
            guard result.length == MemoryLayout<ScanFlagsBuffer>.size,
                  result.returned.commonattr & attrgroup_t(ATTR_CMN_FLAGS) != 0 else {
                throw ScanMetadataError.unsupportedMetadata
            }
            return result.flags
        },
        cloud: { path in
            // Supplying directory knowledge avoids an existence lookup during
            // URL construction. Only the two cloud keys are requested here.
            let values = try freshScanURL(path).resourceValues(forKeys: [
                .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
            ])
            let status: ScanCloudMetadata.DownloadingStatus?
            switch values.ubiquitousItemDownloadingStatus {
            case nil: status = nil
            case .notDownloaded: status = .notDownloaded
            case .downloaded: status = .downloaded
            case .current: status = .current
            default: status = .unknown
            }
            return ScanCloudMetadata(isUbiquitous: values.isUbiquitousItem, downloadingStatus: status)
        },
        metadata: { descriptor in
            var result = stat()
            guard Darwin.fstat(descriptor, &result) == 0 else { throw metadataSystemError(errno) }
            return result
        },
        allocatedSize: { path in
            // This is deliberately the exact Foundation total, which may also
            // account for metadata. There is no logical-size fallback.
            try freshScanURL(path).resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
        },
        excludedFromBackup: { path in
            try freshScanURL(path).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        }
    )
}

struct SizeCalculator: Sendable {
    private let operations: ScanMetadataOperations

    init(operations: ScanMetadataOperations = .live) { self.operations = operations }

    /// The caller must keep this entire synchronous operation, including its
    /// path-validation work, inside withoutDatalessMaterialization. The directory
    /// walker owns that scope so no Swift suspension can move it to another thread.
    func inspect(descriptor: Int32, path: String, includeSize: Bool, skipExcludedFromBackup: Bool = false) throws -> ScanMetadata {
        do {
            let initialFlags = try operations.flags(descriptor)
            try refuseDataless(initialFlags)
            try requireLocalContent(operations.cloud(path))

            if skipExcludedFromBackup {
                guard let excluded = try operations.excludedFromBackup(path) else {
                    throw ScanMetadataError.unsupportedMetadata
                }
                if excluded { throw ScanMetadataError.excludedFromBackup }
            }

            let value = try operations.metadata(descriptor)
            try refuseDataless(value.st_flags)
            guard value.st_flags == initialFlags else { throw ScanMetadataError.changed }
            let kind: ScanMetadata.Kind
            switch value.st_mode & mode_t(S_IFMT) {
            case mode_t(S_IFREG): kind = .regularFile
            case mode_t(S_IFDIR): kind = .directory
            default: throw ScanMetadataError.unsupportedFileType
            }
            guard validTimestamp(value.st_mtimespec), validTimestamp(value.st_ctimespec), validTimestamp(value.st_birthtimespec) else {
                throw ScanMetadataError.unsupportedMetadata
            }

            var allocatedSize: UInt64 = 0
            if includeSize && kind == .regularFile {
                let currentFlags = try operations.flags(descriptor)
                try refuseDataless(currentFlags)
                guard currentFlags == value.st_flags else { throw ScanMetadataError.changed }
                guard let bytes = try operations.allocatedSize(path), bytes >= 0 else {
                    throw ScanMetadataError.unsupportedMetadata
                }
                allocatedSize = UInt64(bytes)
            }
            let fingerprint = ScanMetadataFingerprint(value)
            return ScanMetadata(
                kind: kind,
                identity: fingerprint.identity,
                modifiedAt: Date(timeIntervalSince1970: Double(value.st_mtimespec.tv_sec) + Double(value.st_mtimespec.tv_nsec) / 1_000_000_000),
                allocatedSize: allocatedSize,
                fingerprint: fingerprint
            )
        } catch {
            throw normalizedScanMetadataError(error)
        }
    }

    private func refuseDataless(_ flags: UInt32) throws {
        if flags & UInt32(SF_DATALESS) != 0 { throw ScanMetadataError.dataless }
    }

    private func requireLocalContent(_ cloud: ScanCloudMetadata) throws {
        if case .notDownloaded = cloud.downloadingStatus { throw ScanMetadataError.dataless }
        // Foundation omits both cloud values for ordinary local files on macOS.
        // Absence is not proof of residency: descriptor flags and the enclosing
        // kernel policy remain mandatory independently of this advisory query.
        if cloud.isUbiquitous == nil && cloud.downloadingStatus == nil { return }
        guard let ubiquitous = cloud.isUbiquitous else { throw ScanMetadataError.unsupportedMetadata }
        if ubiquitous {
            switch cloud.downloadingStatus {
            case .downloaded, .current: return
            default: throw ScanMetadataError.unsupportedMetadata
            }
        } else {
            // A missing cloud status is expected for an ordinary local file.
            // Conflicting provider metadata must not silently become local.
            guard cloud.downloadingStatus == nil else { throw ScanMetadataError.unsupportedMetadata }
        }
    }

    private func validTimestamp(_ value: timespec) -> Bool { value.tv_nsec >= 0 && value.tv_nsec < 1_000_000_000 }
}

/// Apple TN3150 recommends this policy to prevent intermediate dataless folders
/// from materializing during path lookup or enumeration. This scope is strictly
/// synchronous: it must never enclose an await or transfer work to another thread.
/// https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files
func withoutDatalessMaterialization<T>(_ body: () throws -> T) throws -> T {
    let original = Darwin.getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
    guard original >= 0 else { throw metadataSystemError(errno) }
    guard Darwin.setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0 else {
        throw metadataSystemError(errno)
    }
    let result = Result(catching: body)
    // Restore before propagating either the result or its error. A failed
    // restoration is observable and must not be presented as a completed scan.
    guard Darwin.setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, original) == 0 else {
        throw metadataSystemError(errno)
    }
    return try result.get()
}

private struct ScanFlagsBuffer {
    var length: UInt32 = 0
    var returned = attribute_set_t()
    var flags: UInt32 = 0
}

private func freshScanURL(_ path: String) -> URL {
    var url = URL(fileURLWithPath: path, isDirectory: true)
    url.removeAllCachedResourceValues()
    return url
}

private func metadataSystemError(_ number: Int32) -> ScanMetadataError {
    number == EDEADLK ? .dataless : .system(number)
}

private func normalizedScanMetadataError(_ error: Error) -> ScanMetadataError {
    if let error = error as? ScanMetadataError { return error }
    var value = error as NSError
    // Foundation can wrap a refused materialization in a Cocoa read error.
    // Bound traversal even if an unusual provider supplies cyclic error data.
    for _ in 0..<4 {
        if value.domain == NSPOSIXErrorDomain, let number = Int32(exactly: value.code) { return metadataSystemError(number) }
        guard let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
        value = underlying
    }
    return .unsupportedMetadata
}
