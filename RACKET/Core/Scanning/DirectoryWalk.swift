import Foundation

/// Counts are observations, never a promise of reclaimable physical space.
public struct ScannedFile: Sendable {
    public let resolvedPath: String
    public let allocatedSize: UInt64
    public let modifiedAt: Date
    let identity: ScanFileIdentity
    let observation: ScanMetadataFingerprint?

    init(
        resolvedPath: String, allocatedSize: UInt64, modifiedAt: Date,
        identity: ScanFileIdentity, observation: ScanMetadataFingerprint? = nil
    ) {
        self.resolvedPath = resolvedPath
        self.allocatedSize = allocatedSize
        self.modifiedAt = modifiedAt
        self.identity = identity
        self.observation = observation
    }
}

struct ScanFileIdentity: Hashable, Sendable {
    let device: Int32
    let inode: UInt64
}

public enum ScanIssueReason: Equatable, Sendable {
    case pathRefused(PathGuardError)
    case dataless
    case metadataUnavailable(Int32)
    case unsupportedMetadata
    case depthLimit
    case entryLimit
    case excludedFromBackup
    case notOldEnough
    case duplicate
    case sizeOverflow
}

public enum ScanIssueDisposition: String, Sendable {
    case skipped
    case refused
    case incomplete
}

public struct WalkIssue: Sendable {
    public let path: String
    public let reason: ScanIssueReason

    public var disposition: ScanIssueDisposition {
        switch reason {
        case .pathRefused(let error):
            switch error {
            case .dataless, .missing: .skipped
            case .inaccessible: .incomplete
            default: .refused
            }
        case .dataless, .excludedFromBackup, .notOldEnough, .duplicate: .skipped
        case .metadataUnavailable, .unsupportedMetadata, .depthLimit, .entryLimit, .sizeOverflow: .incomplete
        }
    }
}

public struct DirectoryWalk: Sendable {
    public let files: [ScannedFile]
    public let issues: [WalkIssue]
    public let visitedEntryCount: UInt64
}
