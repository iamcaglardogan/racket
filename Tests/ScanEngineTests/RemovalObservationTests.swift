import Darwin
import Foundation
import XCTest
@testable import RacketCore

final class RemovalObservationTests: XCTestCase, @unchecked Sendable {
    func testLiveWalkerAndEngineRetainTheFullObservedFingerprint() async throws {
        let fixture = try ObservationFixture()
        let initial = try fixture.fileMetadata()
        let walk = try fixture.walker.walk(path: fixture.root, maxDepth: 1)
        let file = try XCTUnwrap(walk.files.first)
        XCTAssertTrue(walk.issues.isEmpty)
        XCTAssertEqual(file.observation, ScanMetadataFingerprint(initial))
        XCTAssertEqual(file.observation?.identity, file.identity)

        let report = try await fixture.scan()
        let finding = try XCTUnwrap(report.findings.first)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(finding.observation, file.observation)
        XCTAssertEqual(finding.resolvedPath, file.resolvedPath)
        XCTAssertEqual(finding.allocatedSize, file.allocatedSize)
        XCTAssertEqual(finding.modifiedAt, file.modifiedAt)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.path)), fixture.contents)
    }

    func testSyntheticDefaultsRemainUnobservedThroughTheEngine() async throws {
        let fixture = try ObservationFixture()
        let file = ScannedFile(
            resolvedPath: fixture.path, allocatedSize: 4_096,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            identity: ScanFileIdentity(device: 1, inode: 1)
        )
        XCTAssertNil(file.observation)
        let engine = ScanEngine(policy: fixture.policy, concurrencyLimit: 1) { _, _, _ in
            DirectoryWalk(files: [file], issues: [], visitedEntryCount: 1)
        }
        let report = try await engine.scan(ruleSet: fixture.rules)
        let finding = try XCTUnwrap(report.findings.first)
        XCTAssertNil(finding.observation)
        let synthetic = Finding(
            resolvedPath: finding.resolvedPath, allocatedSize: finding.allocatedSize,
            modifiedAt: finding.modifiedAt, ruleID: finding.ruleID, module: finding.module,
            risk: finding.risk, reason: finding.reason, regenerationCost: finding.regenerationCost
        )
        XCTAssertNil(synthetic.observation)
        XCTAssertEqual(finding, synthetic)
    }

    func testReplacingAFileWithTheSameSizeAndRestoredModificationTimeChangesItsObservation() async throws {
        let fixture = try ObservationFixture()
        let beforeReport = try await fixture.scan()
        let before = try XCTUnwrap(beforeReport.findings.first)
        let initial = try fixture.fileMetadata()
        let preserved = fixture.home + "/preserved-original.bin"
        try FileManager.default.moveItem(atPath: fixture.path, toPath: preserved)
        try Data(repeating: 0x62, count: fixture.contents.count).write(to: URL(fileURLWithPath: fixture.path))
        let times = [initial.st_atimespec, initial.st_mtimespec]
        XCTAssertEqual(times.withUnsafeBufferPointer { Darwin.utimensat(AT_FDCWD, fixture.path, $0.baseAddress, 0) }, 0)

        let replacement = try fixture.fileMetadata()
        XCTAssertEqual(replacement.st_size, initial.st_size)
        XCTAssertEqual(replacement.st_mtimespec.tv_sec, initial.st_mtimespec.tv_sec)
        XCTAssertEqual(replacement.st_mtimespec.tv_nsec, initial.st_mtimespec.tv_nsec)
        let afterReport = try await fixture.scan()
        let after = try XCTUnwrap(afterReport.findings.first)
        XCTAssertTrue(afterReport.issues.isEmpty)
        XCTAssertEqual(before.resolvedPath, after.resolvedPath)
        XCTAssertEqual(before.modifiedAt, after.modifiedAt)
        let previousObservation = try XCTUnwrap(before.observation)
        let currentObservation = try XCTUnwrap(after.observation)
        XCTAssertNotEqual(previousObservation.identity, currentObservation.identity)
        XCTAssertNotEqual(previousObservation, currentObservation)
        XCTAssertEqual(currentObservation, ScanMetadataFingerprint(replacement))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: preserved)), fixture.contents)
    }

    func testFindingEqualityIncludesTheInternalObservation() async throws {
        let fixture = try ObservationFixture()
        let report = try await fixture.scan()
        let finding = try XCTUnwrap(report.findings.first)
        let observation = try XCTUnwrap(finding.observation)
        func copy(observation: ScanMetadataFingerprint?) -> Finding {
            Finding(
                resolvedPath: finding.resolvedPath, allocatedSize: finding.allocatedSize,
                modifiedAt: finding.modifiedAt, ruleID: finding.ruleID, module: finding.module,
                risk: finding.risk, reason: finding.reason, regenerationCost: finding.regenerationCost,
                observation: observation
            )
        }
        XCTAssertEqual(finding, copy(observation: observation))
        XCTAssertNotEqual(finding, copy(observation: nil))
    }
}

/// Every file belongs to a unique synthetic home. Fixtures and replaced originals
/// are preserved; these tests neither scan the real home nor perform removal.
private struct ObservationFixture: Sendable {
    let home: String
    let policy: SafeRoots
    let walker: DirectoryWalker
    let rules: RuleSet
    let contents = Data(repeating: 0x61, count: 4_096)
    var root: String { home + "/Library/Caches/Observation" }
    var path: String { root + "/cache.bin" }

    init() throws {
        home = "/private/tmp/RACKET-ObservationFixture-" + UUID().uuidString
        policy = try SafeRoots(homeDirectory: home)
        walker = DirectoryWalker(policy: policy)
        let data = Data("""
        {"schemaVersion":1,"version":"1.0.0","rules":[{
        "id":"fixture.observation","title":"Synthetic observation","module":"creative",
        "producers":["io.racket.fixture"],"paths":["~/Library/Caches/Observation"],
        "match":{"kind":"directoryContents","maxDepth":1},"conditions":[],
        "risk":"regenerable","reason":"Synthetic fixture only.",
        "regenerationCost":"Created by the test.","citation":"https://example.invalid/fixture",
        "enabled":true,"verified":true}]}
        """.utf8)
        rules = try RuleSet.decode(data, validatePath: policy.validateRulePath)
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try contents.write(to: URL(fileURLWithPath: path))
    }

    func scan() async throws -> ScanReport {
        let engine = ScanEngine(policy: policy, concurrencyLimit: 1) { path, depth, skip in
            try walker.walk(path: path, maxDepth: depth, skipExcludedFromBackup: skip)
        }
        return try await engine.scan(ruleSet: rules)
    }

    func fileMetadata() throws -> stat {
        var result = stat()
        guard Darwin.lstat(path, &result) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return result
    }
}
