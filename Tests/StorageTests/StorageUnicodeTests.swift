import Darwin
import Foundation
import XCTest
@testable import RacketCore

final class StorageUnicodeTests: XCTestCase, @unchecked Sendable {
    func testEquivalentUnicodeNamesKeepDistinctByteIdentitiesAndFilesystemURLs() {
        let composed = "/private/tmp/caf\u{00e9}"
        let decomposed = "/private/tmp/cafe\u{0301}"
        XCTAssertEqual(composed, decomposed, "Swift String deliberately compares canonical equivalence")
        let first = StorageExplorerEntry(rawPath: composed, name: "caf\u{00e9}", kind: .directory, allocatedBytes: 0, issueCount: 0)
        let second = StorageExplorerEntry(rawPath: decomposed, name: "cafe\u{0301}", kind: .directory, allocatedBytes: 0, issueCount: 0)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.id, Data(composed.utf8))
        XCTAssertEqual(second.id, Data(decomposed.utf8))
        for (path, url) in [(composed, first.url), (decomposed, second.url),
                            (composed, freshScanURL(composed)), (decomposed, freshScanURL(decomposed))] {
            XCTAssertEqual(Data(url.path.utf8), Data(path.utf8))
            XCTAssertEqual(filesystemBytes(url), Data(path.utf8))
        }
    }

    func testRealRawUnicodeSiblingFoldersRetainPathsSizesAndDrilldown() async throws {
        let root = "/private/tmp/RacketStorageUnicode-" + UUID().uuidString
        XCTAssertEqual(mkdir(root, mode_t(0o700)), 0)
        // APFS is normalization-insensitive and cannot store both canonically
        // equivalent siblings. Prefixes let the real fixture exercise both raw
        // encodings; the identity test above covers the canonical collision.
        let names = ["composed-caf\u{00e9}", "decomposed-cafe\u{0301}"]
        let counts = [8_192, 16_384]
        for (index, name) in names.enumerated() {
            let directory = root + "/" + name
            XCTAssertEqual(mkdir(directory, mode_t(0o700)), 0)
            try writeRaw(directory + "/leaf.bin", count: counts[index])
        }
        let report = try await StorageExplorer().explore(at: storageURL(root, isDirectory: true))
        XCTAssertTrue(report.isComplete, String(describing: report.issues))
        XCTAssertEqual(report.entries.count, 2)
        XCTAssertEqual(Set(report.entries.map(\.id)).count, 2)
        var expectedTotal: UInt64 = 0
        for name in names {
            let path = root + "/" + name
            let entry = try XCTUnwrap(report.entries.first { $0.id == Data(path.utf8) })
            XCTAssertEqual(Data(entry.rawPath.utf8), Data(path.utf8))
            XCTAssertEqual(Data(entry.url.path.utf8), Data(path.utf8))
            XCTAssertEqual(filesystemBytes(entry.url), Data(path.utf8))
            let bytes = UInt64(try XCTUnwrap(freshScanURL(path + "/leaf.bin").resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize))
            XCTAssertEqual(entry.allocatedBytes, bytes)
            expectedTotal += bytes
            let nested = try await StorageExplorer().explore(at: entry.url)
            XCTAssertTrue(nested.isComplete, String(describing: nested.issues))
            XCTAssertEqual(Data(nested.rawRootPath.utf8), Data(path.utf8))
            XCTAssertEqual(nested.entries.map(\.id), [Data((path + "/leaf.bin").utf8)])
            XCTAssertEqual(nested.allocatedBytes, bytes)
        }
        XCTAssertEqual(report.allocatedBytes, expectedTotal)
    }

    func testCleanupWalkerUsesExactRawUnicodePathsForAllocation() throws {
        let home = "/private/tmp/RacketWalkerUnicode-" + UUID().uuidString
        let origin = home + "/Library/Caches/Unicode"
        try FileManager.default.createDirectory(at: storageURL(origin, isDirectory: true), withIntermediateDirectories: true)
        let names = ["composed-caf\u{00e9}.bin", "decomposed-cafe\u{0301}.bin"]
        for (index, name) in names.enumerated() { try writeRaw(origin + "/" + name, count: (index + 1) * 8_192) }
        let allocations = UnicodeAllocationObservations()
        var operations = ScanMetadataOperations.live
        operations.allocatedSize = { path in
            allocations.record(path)
            XCTAssertEqual(Data(freshScanURL(path).path.utf8), Data(path.utf8))
            XCTAssertEqual(filesystemBytes(freshScanURL(path)), Data(path.utf8))
            return try ScanMetadataOperations.live.allocatedSize(path)
        }
        let walker = DirectoryWalker(policy: try SafeRoots(homeDirectory: home), calculator: SizeCalculator(operations: operations))
        let result = try walker.walk(path: origin, maxDepth: 2)
        XCTAssertTrue(result.issues.isEmpty, String(describing: result.issues))
        XCTAssertEqual(Set(result.files.map { Data($0.resolvedPath.utf8) }), Set(names.map { Data((origin + "/" + $0).utf8) }))
        XCTAssertEqual(Set(allocations.paths), Set(names.map { Data((origin + "/" + $0).utf8) }))
        for file in result.files {
            let actual = try freshScanURL(file.resolvedPath).resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            XCTAssertEqual(file.allocatedSize, UInt64(try XCTUnwrap(actual.totalFileAllocatedSize)))
        }
    }
}

private func filesystemBytes(_ url: URL) -> Data {
    url.withUnsafeFileSystemRepresentation { pointer in
        guard let pointer else { return Data() }
        return Data(bytes: pointer, count: strlen(pointer))
    }
}

private func writeRaw(_ path: String, count: Int) throws {
    let descriptor = path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600)) }
    guard descriptor >= 0 else { throw ScanMetadataError.system(errno) }
    defer { _ = Darwin.close(descriptor) }
    let data = Data(repeating: 0x52, count: count)
    let written = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress!, $0.count) }
    guard written == count else { throw ScanMetadataError.system(errno) }
}

private final class UnicodeAllocationObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [Data] = []
    var paths: [Data] { lock.withLock { captured } }
    func record(_ path: String) { lock.withLock { captured.append(Data(path.utf8)) } }
}
