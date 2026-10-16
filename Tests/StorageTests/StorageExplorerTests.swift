import Darwin
import Foundation
import XCTest
@testable import RacketCore

final class StorageExplorerTests: XCTestCase, @unchecked Sendable {
    func testAllocationsAreGroupedAtTopLevelAndDrilldownWorks() async throws {
        let fixture = try StorageFixture()
        let alpha = try fixture.write("alpha.bin", count: 8_192)
        let beta = try fixture.write("nested/beta.bin", count: 16_384)
        try fixture.directory("empty")
        let report = try await StorageExplorer().explore(at: fixture.root)
        XCTAssertTrue(report.isComplete, String(describing: report.issues))
        XCTAssertEqual(report.visitedEntryCount, 4)
        XCTAssertEqual(Set(report.entries.map(\.name)), ["alpha.bin", "nested", "empty"])
        XCTAssertEqual(report.allocatedBytes, try fixture.allocation(alpha) + fixture.allocation(beta))
        XCTAssertEqual(report.entries.first { $0.name == "nested" }?.allocatedBytes, try fixture.allocation(beta))
        XCTAssertTrue(report.entries.allSatisfy(\.isComplete))
        let child = try await StorageExplorer().explore(at: fixture.root.appendingPathComponent("nested", isDirectory: true))
        XCTAssertEqual(child.entries.map(\.name), ["beta.bin"])
        XCTAssertTrue(child.isComplete)
    }

    func testSparseFileUsesAllocatedSpaceAndScanNeverChangesContents() async throws {
        let fixture = try StorageFixture()
        let file = try fixture.write("sparse.bin", count: 1)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 64 * 1_024 * 1_024)
        try handle.synchronize()
        try handle.close()
        let before = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let report = try await StorageExplorer().explore(at: fixture.root)
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.allocatedBytes, try fixture.allocation(file))
        XCTAssertLessThan(report.allocatedBytes, UInt64(try XCTUnwrap(before.fileSize)))
        let after = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        XCTAssertEqual(before.fileSize, after.fileSize)
        XCTAssertEqual(before.contentModificationDate, after.contentModificationDate)
    }

    func testSymlinksAreReportedWithoutEnteringTargets() async throws {
        let fixture = try StorageFixture()
        let outside = try StorageFixture()
        _ = try outside.write("valuable.bin", count: 8_192)
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("alias"), withDestinationURL: outside.root)
        try FileManager.default.createSymbolicLink(atPath: fixture.root.appendingPathComponent("loop").path,
            withDestinationPath: fixture.root.appendingPathComponent("loop").path)
        let report = try await StorageExplorer().explore(at: fixture.root)
        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(report.entries.isEmpty)
        XCTAssertEqual(report.allocatedBytes, 0)
        XCTAssertEqual(report.issues.count, 2)
        XCTAssertTrue(report.issues.allSatisfy { $0.reason == .symbolicLink })
    }

    func testPackageContentsAreSkippedAndRootPackageIsRefused() async throws {
        let fixture = try StorageFixture()
        _ = try fixture.write("Sample.app/Contents/content.bin", count: 8_192)
        let package = fixture.root.appendingPathComponent("Sample.app", isDirectory: true)
        let report = try await StorageExplorer().explore(at: fixture.root)
        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.entries.map(\.kind), [.package])
        XCTAssertEqual(report.allocatedBytes, 0)
        XCTAssertEqual(report.issues.map(\.reason), [.package])
        XCTAssertEqual(report.entries.first?.isComplete, false)
        let direct = try await StorageExplorer().explore(at: package)
        XCTAssertFalse(direct.isComplete)
        XCTAssertTrue(direct.entries.isEmpty)
        XCTAssertEqual(direct.issues.first?.reason, .package)
        let inside = try await StorageExplorer().explore(at: package.appendingPathComponent("Contents", isDirectory: true))
        XCTAssertEqual(inside.issues.first?.reason, .package)
    }

    func testEntryLimitIsVisibleAndBoundsVisitedCount() async throws {
        let fixture = try StorageFixture()
        for index in 0..<5 { _ = try fixture.write("file-\(index)", count: 1) }
        let report = try await StorageExplorer().explore(at: fixture.root, options: .init(maxEntries: 2))
        XCTAssertEqual(report.visitedEntryCount, 2)
        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(report.issues.contains { $0.reason == .entryLimit })
    }

    func testDepthLimitIsVisibleOnDirectoryEntry() async throws {
        let fixture = try StorageFixture()
        _ = try fixture.write("nested/deeper.bin", count: 1)
        let report = try await StorageExplorer().explore(at: fixture.root, options: .init(maxDepth: 1))
        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.allocatedBytes, 0)
        XCTAssertEqual(report.entries.first?.kind, .directory)
        XCTAssertEqual(report.entries.first?.isComplete, false)
        XCTAssertEqual(report.issues.map(\.reason), [.depthLimit])
    }

    func testHardLinksAreNotDoubleCountedAndSharedNamesAreReported() async throws {
        let fixture = try StorageFixture()
        let source = try fixture.write("original.bin", count: 8_192)
        XCTAssertEqual(link(source.path, fixture.root.appendingPathComponent("second.bin").path), 0)
        let report = try await StorageExplorer().explore(at: fixture.root)
        XCTAssertEqual(report.entries.count, 2)
        XCTAssertEqual(report.allocatedBytes, try fixture.allocation(source))
        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.issues.map(\.reason), [.duplicateHardLink])
    }

    func testDatalessLeafIsSkippedBeforeStatAndSize() async throws {
        let fixture = try StorageFixture()
        let offline = try fixture.write("offline.bin", count: 1)
        let accesses = StorageCounter()
        var operations = ScanMetadataOperations.live
        operations.flags = { descriptor in
            if try storageTestDescriptorPath(descriptor) == offline.path { return UInt32(SF_DATALESS) }
            return try ScanMetadataOperations.live.flags(descriptor)
        }
        operations.metadata = { descriptor in
            if try storageTestDescriptorPath(descriptor) == offline.path { accesses.increment() }
            return try ScanMetadataOperations.live.metadata(descriptor)
        }
        operations.allocatedSize = { path in
            if path == offline.path { accesses.increment() }
            return try ScanMetadataOperations.live.allocatedSize(path)
        }
        let explorer = StorageExplorer(calculator: SizeCalculator(operations: operations))
        let report = try await explorer.explore(at: fixture.root)
        XCTAssertEqual(accesses.value, 0)
        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(report.entries.isEmpty)
        XCTAssertEqual(report.issues.map(\.reason), [.dataless])
    }

    func testDatalessOriginIsSkippedBeforeStat() async throws {
        let fixture = try StorageFixture()
        let accesses = StorageCounter()
        var operations = ScanMetadataOperations.live
        operations.flags = { descriptor in
            if try storageTestDescriptorPath(descriptor) == fixture.root.path { return UInt32(SF_DATALESS) }
            return try ScanMetadataOperations.live.flags(descriptor)
        }
        operations.metadata = { descriptor in
            if try storageTestDescriptorPath(descriptor) == fixture.root.path { accesses.increment() }
            return try ScanMetadataOperations.live.metadata(descriptor)
        }
        let report = try await StorageExplorer(calculator: SizeCalculator(operations: operations)).explore(at: fixture.root)
        XCTAssertEqual(accesses.value, 0)
        XCTAssertEqual(report.visitedEntryCount, 0)
        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.issues.map(\.reason), [.dataless])
    }

    func testChangingLeafNeverAppearsAsAValidObservation() async throws {
        let fixture = try StorageFixture()
        let target = try fixture.write("cache.bin", count: 8_192)
        let accesses = StorageCounter()
        var operations = ScanMetadataOperations.live
        operations.allocatedSize = { path in
            let original = try ScanMetadataOperations.live.allocatedSize(path)
            if path == target.path && accesses.increment() == 1 {
                try FileManager.default.moveItem(at: target, to: fixture.root.appendingPathComponent("preserved.bin"))
                try Data([1]).write(to: target)
            }
            return original
        }
        let report = try await StorageExplorer(calculator: SizeCalculator(operations: operations)).explore(at: fixture.root)
        XCTAssertFalse(report.isComplete)
        XCTAssertFalse(report.entries.contains { $0.url.path == target.path })
        XCTAssertTrue(report.issues.contains { $0.reason == .changed })
    }

    func testMissingInvalidAndFileOriginsCannotReportSuccess() async throws {
        let fixture = try StorageFixture()
        let file = try fixture.write("file.bin", count: 1)
        for (url, reason) in [
            (fixture.root.appendingPathComponent("missing"), StorageExplorerIssue.Reason.metadataUnavailable(ENOENT)),
            (URL(string: "https://example.invalid")!, .invalidPath), (file, .notDirectory)
        ] {
            let report = try await StorageExplorer().explore(at: url)
            XCTAssertFalse(report.isComplete)
            XCTAssertTrue(report.entries.isEmpty)
            XCTAssertEqual(report.issues.first?.reason, reason)
        }
    }

    func testFIFOIsSkippedWithoutBlocking() async throws {
        let fixture = try StorageFixture()
        XCTAssertEqual(mkfifo(fixture.root.appendingPathComponent("pipe").path, mode_t(0o600)), 0)
        let report = try await StorageExplorer().explore(at: fixture.root)
        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.issues.map(\.reason), [.unsupportedFileType])
        XCTAssertTrue(report.entries.isEmpty)
    }

    func testOverflowCannotProduceACompleteTotal() async throws {
        let fixture = try StorageFixture()
        for index in 0..<3 { _ = try fixture.write("file-\(index)", count: 1) }
        var operations = ScanMetadataOperations.live
        operations.allocatedSize = { _ in Int.max }
        let report = try await StorageExplorer(calculator: SizeCalculator(operations: operations)).explore(at: fixture.root)
        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(report.issues.contains { $0.reason == .sizeOverflow })
    }

    func testPreCancelledRequestThrowsInsteadOfReportingPartialSuccess() async throws {
        let fixture = try StorageFixture()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await StorageExplorer().explore(at: fixture.root)
        }
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch is CancellationError { }
    }

    func testCancellationOfRunningWorkerPropagates() async throws {
        let fixture = try StorageFixture()
        for index in 0..<100 { _ = try fixture.write("file-\(index)", count: 1) }
        let started = StorageCounter()
        var operations = ScanMetadataOperations.live
        operations.allocatedSize = { path in
            started.increment()
            Thread.sleep(forTimeInterval: 0.005)
            return try ScanMetadataOperations.live.allocatedSize(path)
        }
        let explorer = StorageExplorer(calculator: SizeCalculator(operations: operations))
        let task = Task { try await explorer.explore(at: fixture.root) }
        while started.value == 0 { try await Task.sleep(for: .milliseconds(1)) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch is CancellationError { }
    }

    func testOptionBoundsPreventUnboundedTraversal() {
        let small = StorageExplorerOptions(maxEntries: -1, maxDepth: -1, maxDurationSeconds: -1)
        XCTAssertEqual(small.maxEntries, 1)
        XCTAssertEqual(small.maxDepth, 1)
        XCTAssertEqual(small.maxDurationSeconds, 1)
        let large = StorageExplorerOptions(maxEntries: Int.max, maxDepth: Int.max, maxDurationSeconds: Int.max)
        XCTAssertEqual(large.maxEntries, 100_000)
        XCTAssertEqual(large.maxDepth, 32)
        XCTAssertEqual(large.maxDurationSeconds, 120)
    }
}

private struct StorageFixture: Sendable {
    let root: URL
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp/RacketStorage-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func directory(_ path: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(path, isDirectory: true), withIntermediateDirectories: true)
    }

    @discardableResult func write(_ path: String, count: Int) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: count).write(to: url)
        return url
    }

    func allocation(_ url: URL) throws -> UInt64 {
        UInt64(try XCTUnwrap(url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize))
    }
}

private final class StorageCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    @discardableResult func increment() -> Int { lock.withLock { count += 1; return count } }
}

private func storageTestDescriptorPath(_ descriptor: Int32) throws -> String {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard buffer.withUnsafeMutableBufferPointer({ Darwin.fcntl(descriptor, F_GETPATH, $0.baseAddress!) }) == 0 else {
        throw ScanMetadataError.system(errno)
    }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
