import Foundation

/// An observed ordinary file and the rule that explains why it was included.
/// A finding is not removal authority, a directory approval, or a space promise.
public struct Finding: Equatable, Sendable {
    public let resolvedPath: String
    public let allocatedSize: UInt64
    public let modifiedAt: Date
    public let ruleID: String
    public let module: Rule.Module
    public let risk: Rule.Risk
    public let reason: String
    public let regenerationCost: String

    public var isPreselectable: Bool { risk != .judgement }
}

public struct ScanIssue: Equatable, Sendable {
    public let path: String
    public let ruleID: String
    public let module: Rule.Module
    public let reason: ScanIssueReason

    public var disposition: ScanIssueDisposition {
        WalkIssue(path: path, reason: reason).disposition
    }
}

/// Completed path jobs are counted honestly; no estimate of bytes or work left.
public struct ScanProgress: Equatable, Sendable {
    public let module: Rule.Module
    public let completedPaths: Int
    public let totalPaths: Int
}

public struct ScanReport: Sendable {
    public let ruleSetVersion: String
    public let findings: [Finding]
    public let issues: [ScanIssue]
    /// Sum of the deduplicated file observations. APFS sharing and later changes
    /// mean this is not a claim of bytes that removal would physically reclaim.
    public let reportedAllocatedBytes: UInt64
    /// Includes repeated observations when declared paths overlap.
    public let visitedEntryCount: UInt64
}

public enum ScanEngineError: Error, Equatable, Sendable {
    case sizeOverflow
    case visitedEntryOverflow
    case resourceLimitExceeded
    case invalidReferenceDate
}

extension ScanEngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sizeOverflow:
            "The observed allocated-byte total exceeds the supported range. No complete scan report was produced."
        case .visitedEntryOverflow:
            "The visited-entry count exceeds the supported range. No complete scan report was produced."
        case .resourceLimitExceeded:
            "The scan exceeded its bounded result limit. Use fewer or narrower rule paths and scan again."
        case .invalidReferenceDate:
            "The scan reference date is invalid. Supply a finite date and scan again."
        }
    }
}
