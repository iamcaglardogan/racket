import Foundation
import XCTest
@testable import RacketCore

final class StorageVolumeSnapshotTests: XCTestCase, @unchecked Sendable {
    func testSnapshotUsesInternallyConsistentPhysicalCapacity() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/RacketVolume-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let before = Date()
        let result = try await StorageVolumeSnapshot.read(at: root)
        XCTAssertGreaterThan(result.totalBytes, 0)
        XCTAssertLessThanOrEqual(result.availableBytes, result.freeBytes)
        XCTAssertLessThanOrEqual(result.freeBytes, result.totalBytes)
        XCTAssertEqual(result.usedBytes + result.freeBytes, result.totalBytes)
        XCTAssertGreaterThanOrEqual(result.observedAt, before)
        XCTAssertEqual(result.url.path, root.path)
    }

    func testMultiplicationRejectsOverflow() throws {
        XCTAssertEqual(try StorageVolumeSnapshot.capacity(blocks: 10, blockSize: 4_096), 40_960)
        XCTAssertThrowsError(try StorageVolumeSnapshot.capacity(blocks: UInt64.max, blockSize: 4_096))
    }

    func testInvalidLocationThrows() async throws {
        do { _ = try await StorageVolumeSnapshot.read(at: URL(string: "https://example.invalid")!); XCTFail("Invalid location must fail") }
        catch PathGuardError.invalidPath { }
    }

    func testCancellationPropagates() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await StorageVolumeSnapshot.read(at: URL(fileURLWithPath: "/private/tmp", isDirectory: true))
        }
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch is CancellationError { }
    }
}
