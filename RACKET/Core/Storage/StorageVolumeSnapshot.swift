import Darwin
import Foundation

/// Filesystem capacity at an observation time. APFS volumes may share a container;
/// these figures must not be summed across volumes or treated as cleanup estimates.
public struct StorageVolumeSnapshot: Sendable {
    public let url: URL
    public let observedAt: Date
    public let totalBytes: UInt64
    /// All filesystem free blocks, including space reserved from ordinary users.
    public let freeBytes: UInt64
    /// Blocks available to the current user, excluding reserved blocks.
    public let availableBytes: UInt64
    /// Apple's estimates can include purgeable space. Nil means unavailable.
    public let availableForImportantUsageBytes: UInt64?
    public let availableForOpportunisticUsageBytes: UInt64?
    public var usedBytes: UInt64 { totalBytes - min(freeBytes, totalBytes) }

    public static func read(at url: URL = FileManager.default.homeDirectoryForCurrentUser) async throws -> StorageVolumeSnapshot {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) { try readSynchronously(at: url) }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }

    private static func readSynchronously(at url: URL) throws -> StorageVolumeSnapshot {
        let path = try storagePath(url)
        return try withoutDatalessMaterialization {
            let directory = try StorageOpenDirectory.open(path: path, calculator: SizeCalculator())
            try Task.checkCancellation()
            var filesystem = statfs()
            guard Darwin.fstatfs(directory.descriptor.value, &filesystem) == 0 else { throw scanSystemError(errno) }
            guard filesystem.f_bsize > 0 else { throw ScanMetadataError.unsupportedMetadata }
            let total = try capacity(blocks: filesystem.f_blocks, blockSize: filesystem.f_bsize)
            let free = try capacity(blocks: filesystem.f_bfree, blockSize: filesystem.f_bsize)
            let available = try capacity(blocks: filesystem.f_bavail, blockSize: filesystem.f_bsize)
            guard free <= total, available <= free else { throw ScanMetadataError.unsupportedMetadata }
            var target = storageURL(path, isDirectory: true)
            target.removeAllCachedResourceValues()
            // Optional estimates remain absent when unsupported; they never
            // replace physical free bytes with a potentially purgeable estimate.
            let estimates = try? target.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityForOpportunisticUsageKey
            ])
            try directory.verify()
            return StorageVolumeSnapshot(url: target, observedAt: Date(), totalBytes: total, freeBytes: free,
                availableBytes: available,
                availableForImportantUsageBytes: nonnegative(estimates?.volumeAvailableCapacityForImportantUsage),
                availableForOpportunisticUsageBytes: nonnegative(estimates?.volumeAvailableCapacityForOpportunisticUsage))
        }
    }

    static func capacity(blocks: UInt64, blockSize: UInt32) throws -> UInt64 {
        let value = blocks.multipliedReportingOverflow(by: UInt64(blockSize))
        guard !value.overflow else { throw ScanMetadataError.unsupportedMetadata }
        return value.partialValue
    }

    private static func nonnegative(_ value: Int64?) -> UInt64? {
        guard let value, value >= 0 else { return nil }
        return UInt64(value)
    }
}
