import Darwin
import Foundation
import XCTest
@testable import RacketCore

// Concurrent checks capture Sendable fixtures; the case has no mutable fields.
final class DirectoryWalkerTests: XCTestCase, @unchecked Sendable {
    func testCheckedInFixtureProducesExactRegularFileFindings() throws {
        let fixture = try WalkerFixture()
        let result = try fixture.walker.walk(path: fixture.vendor, maxDepth: 4)
        XCTAssertEqual(result.files.map { fixture.relative($0.resolvedPath) }, [
            "Library/Caches/Vendor/cache.bin", "Library/Caches/Vendor/nested/audio.cache"
        ])
        XCTAssertEqual(Set(result.issues.map { fixture.relative($0.path) }), [
            "Library/Caches/Vendor/Original Media", "Library/Caches/Vendor/.git", "Library/Caches/Vendor/Project.drp"
        ])
        XCTAssertTrue(result.issues.allSatisfy { $0.reason == .pathRefused(.protectedPath) && $0.disposition == .refused })
        for file in result.files {
            let actual = try URL(fileURLWithPath: file.resolvedPath).resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            XCTAssertEqual(file.allocatedSize, UInt64(try XCTUnwrap(actual.totalFileAllocatedSize)))
        }
    }

    func testSafeRootMayBeEnumeratedButNeverBecomesAFinding() throws {
        let fixture = try WalkerFixture()
        let result = try fixture.walker.walk(path: fixture.caches, maxDepth: 4)
        XCTAssertEqual(result.files.count, 2)
        XCTAssertFalse(result.files.contains { $0.resolvedPath == fixture.caches || $0.resolvedPath == fixture.vendor })
    }

    func testDepthLimitIsVisibleAndDoesNotIncludeDeeperFiles() throws {
        let fixture = try WalkerFixture()
        let result = try fixture.walker.walk(path: fixture.vendor, maxDepth: 1)
        XCTAssertEqual(result.files.map(\.resolvedPath), [fixture.vendor + "/cache.bin"])
        XCTAssertTrue(result.issues.contains { $0.path == fixture.vendor + "/nested" && $0.reason == .depthLimit && $0.disposition == .incomplete })
    }

    func testEntryBudgetBoundsEnumerationAndReportsIncomplete() throws {
        let fixture = try WalkerFixture()
        let walker = DirectoryWalker(policy: fixture.policy, entryLimit: 1)
        let result = try walker.walk(path: fixture.vendor, maxDepth: 4)
        XCTAssertEqual(result.visitedEntryCount, 1)
        XCTAssertTrue(result.issues.contains { $0.reason == .entryLimit && $0.disposition == .incomplete })
    }

    func testUnsafePathsAreRejectedBeforeTraversal() throws {
        let fixture = try WalkerFixture()
        for path in [fixture.home + "/Documents", fixture.caches + "Extra", fixture.vendor + "/../Vendor", "relative", fixture.vendor + "/Original Media"] {
            let result = try fixture.walker.walk(path: path, maxDepth: 3)
            XCTAssertTrue(result.files.isEmpty)
            XCTAssertEqual(result.visitedEntryCount, 0)
            XCTAssertEqual(result.issues.count, 1)
            XCTAssertEqual(result.issues.first?.disposition, .refused)
        }
    }

    func testInvalidDepthFailsClosed() throws {
        let fixture = try WalkerFixture()
        for depth in [-1, 0, 33, Int.max] {
            let result = try fixture.walker.walk(path: fixture.vendor, maxDepth: depth)
            XCTAssertTrue(result.files.isEmpty)
            XCTAssertEqual(result.issues.first?.reason, .pathRefused(.invalidPath))
        }
    }

    func testMissingOriginIsReportedAsSkip() throws {
        let fixture = try WalkerFixture()
        let result = try fixture.walker.walk(path: fixture.caches + "/missing", maxDepth: 2)
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.issues.first?.reason, .pathRefused(.missing))
        XCTAssertEqual(result.issues.first?.disposition, .skipped)
    }

    func testFileCannotBeUsedAsDirectoryOrigin() throws {
        let fixture = try WalkerFixture()
        let result = try fixture.walker.walk(path: fixture.vendor + "/cache.bin", maxDepth: 2)
        XCTAssertEqual(result.issues.first?.reason, .pathRefused(.notDirectory))
        XCTAssertTrue(result.files.isEmpty)
    }

    func testSymlinkFarmHasDistinctRefusalsAndNoTargetFindings() throws {
        let fixture = try WalkerFixture()
        let links = [
            "outward": fixture.home + "/Documents", "inward": fixture.vendor + "/nested",
            "dangling": fixture.home + "/absent", "loop-a": fixture.vendor + "/loop-b", "loop-b": fixture.vendor + "/loop-a"
        ]
        for (name, target) in links {
            try FileManager.default.createSymbolicLink(atPath: fixture.vendor + "/" + name, withDestinationPath: target)
        }
        let result = try fixture.walker.walk(path: fixture.vendor, maxDepth: 8)
        XCTAssertEqual(result.files.count, 2)
        for name in links.keys {
            XCTAssertTrue(result.issues.contains { $0.path == fixture.vendor + "/" + name && $0.reason == .pathRefused(.symbolicLink) && $0.disposition == .refused })
        }
    }

    func testSymlinkOriginAndSafeRootAreRefused() throws {
        let fixture = try WalkerFixture()
        try FileManager.default.createSymbolicLink(atPath: fixture.caches + "/alias", withDestinationPath: fixture.vendor)
        let alias = try fixture.walker.walk(path: fixture.caches + "/alias", maxDepth: 3)
        XCTAssertEqual(alias.issues.first?.reason, .pathRefused(.symbolicLink))
        try FileManager.default.moveItem(atPath: fixture.caches, toPath: fixture.home + "/preserved-caches")
        try FileManager.default.createSymbolicLink(atPath: fixture.caches, withDestinationPath: fixture.home + "/preserved-caches")
        let root = try fixture.walker.walk(path: fixture.caches, maxDepth: 3)
        XCTAssertEqual(root.issues.first?.reason, .pathRefused(.symbolicLink))
        XCTAssertTrue(root.files.isEmpty)
    }

    func testFIFOIsRefusedWithoutReadingOrBlocking() throws {
        let fixture = try WalkerFixture()
        XCTAssertEqual(mkfifo(fixture.vendor + "/pipe", mode_t(0o600)), 0)
        let result = try fixture.walker.walk(path: fixture.vendor, maxDepth: 3)
        XCTAssertTrue(result.issues.contains { $0.path == fixture.vendor + "/pipe" && $0.reason == .pathRefused(.unsupportedFileType) })
        XCTAssertEqual(result.files.count, 2)
    }

    func testSparseFileUsesAllocationRatherThanLogicalLength() throws {
        let fixture = try WalkerFixture()
        let path = try fixture.write("Library/Caches/Sparse/holey.bin", data: Data([1]))
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.truncate(atOffset: 64 * 1_024 * 1_024)
        try handle.synchronize()
        let result = try fixture.walker.walk(path: fixture.caches + "/Sparse", maxDepth: 1)
        let finding = try XCTUnwrap(result.files.first)
        let actual = try URL(fileURLWithPath: path).resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        XCTAssertEqual(finding.allocatedSize, UInt64(try XCTUnwrap(actual.totalFileAllocatedSize)))
        XCTAssertLessThan(finding.allocatedSize, UInt64(try XCTUnwrap(actual.fileSize)))
    }

    func testHardLinksRetainSharedIdentityForEngineDeduplication() throws {
        let fixture = try WalkerFixture()
        let source = fixture.vendor + "/cache.bin"
        let alias = fixture.vendor + "/hard-link.bin"
        XCTAssertEqual(link(source, alias), 0)
        let result = try fixture.walker.walk(path: fixture.vendor, maxDepth: 3)
        let diagnostics = String(describing: result.issues.map { ($0.path, $0.reason) })
        let first = try XCTUnwrap(result.files.first { $0.resolvedPath == source }, diagnostics)
        let second = try XCTUnwrap(result.files.first { $0.resolvedPath == alias }, diagnostics)
        XCTAssertEqual(first.identity, second.identity)
    }

    func testOtherHardLinkLookupsCannotRenameAValidatedLeafObservation() throws {
        let fixture = try WalkerFixture()
        let source = try fixture.write("Library/Caches/Aliases/cache.bin", data: Data([1]))
        let alias = fixture.home + "/Documents/other-name.bin"
        XCTAssertEqual(link(source, alias), 0)
        var operations = ScanMetadataOperations.live
        operations.allocatedSize = { path in
            let size = try ScanMetadataOperations.live.allocatedSize(path)
            let descriptor = Darwin.open(alias, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw ScanMetadataError.system(errno) }
            _ = Darwin.close(descriptor)
            return size
        }
        let walker = DirectoryWalker(policy: fixture.policy, calculator: SizeCalculator(operations: operations))
        // Exercise name-cache churn without filesystem mutation or test retries.
        for _ in 0..<20 {
            let result = try walker.walk(path: fixture.caches + "/Aliases", maxDepth: 1)
            XCTAssertEqual(result.files.map(\.resolvedPath), [source], String(describing: result.issues.map(\.reason)))
            XCTAssertTrue(result.issues.isEmpty)
        }
    }

    func testScanLeavesSyntheticFileContentsUnchanged() throws {
        let fixture = try WalkerFixture()
        let paths = [fixture.vendor + "/cache.bin", fixture.vendor + "/Original Media/clip.mov", fixture.home + "/Documents/valuable.txt"]
        let before = try paths.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        _ = try fixture.walker.walk(path: fixture.caches, maxDepth: 4)
        XCTAssertEqual(try paths.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }, before)
    }

    func testPreCancelledWalkThrowsWithoutPartialSuccess() async throws {
        let fixture = try WalkerFixture()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try fixture.walker.walk(path: fixture.vendor, maxDepth: 4)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled scan must not return a successful report")
        } catch is CancellationError {
            // Expected: the caller receives cancellation, not an empty success.
        }
    }

    func testInjectedDatalessLeafIsReportedWithoutStatOrSizeAccess() throws {
        let fixture = try WalkerFixture()
        let offline = try fixture.write("Library/Caches/CloudTest/offline.bin", data: Data([1]))
        let counter = MetadataAccessCounter()
        var operations = ScanMetadataOperations.live
        operations.flags = { descriptor in
            if try scanDescriptorPath(descriptor) == offline { return UInt32(SF_DATALESS) }
            return try ScanMetadataOperations.live.flags(descriptor)
        }
        operations.metadata = { descriptor in
            if try scanDescriptorPath(descriptor) == offline { counter.increment() }
            return try ScanMetadataOperations.live.metadata(descriptor)
        }
        operations.allocatedSize = { path in
            if path == offline { counter.increment() }
            return try ScanMetadataOperations.live.allocatedSize(path)
        }
        let walker = DirectoryWalker(policy: fixture.policy, calculator: SizeCalculator(operations: operations))
        let result = try walker.walk(path: fixture.caches + "/CloudTest", maxDepth: 2)
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.issues.first?.reason, .dataless)
        XCTAssertEqual(result.issues.first?.disposition, .skipped)
        XCTAssertEqual(counter.value, 0)
    }

    func testSymlinkSubstitutionDuringSizeLookupCannotProduceFinding() throws {
        let fixture = try WalkerFixture()
        let target = try fixture.write("Library/Caches/Race/cache.bin", data: Data([1]))
        let counter = MetadataAccessCounter()
        var operations = ScanMetadataOperations.live
        operations.allocatedSize = { path in
            if path == target && counter.increment() == 1 {
                try FileManager.default.moveItem(atPath: target, toPath: target + ".preserved")
                try FileManager.default.createSymbolicLink(atPath: target, withDestinationPath: fixture.home + "/Documents/valuable.txt")
                return 4_096
            }
            return try ScanMetadataOperations.live.allocatedSize(path)
        }
        let walker = DirectoryWalker(policy: fixture.policy, calculator: SizeCalculator(operations: operations))
        let result = try walker.walk(path: fixture.caches + "/Race", maxDepth: 2)
        XCTAssertFalse(result.files.contains { $0.resolvedPath == target })
        XCTAssertTrue(result.issues.contains { $0.path == target && $0.reason == .pathRefused(.symbolicLink) })
    }

    func testDirectoryReplacementDiscardsItsEarlierObservations() throws {
        let fixture = try WalkerFixture()
        let target = try fixture.write("Library/Caches/Moving/cache.bin", data: Data([1]))
        let moving = fixture.caches + "/Moving"
        let counter = MetadataAccessCounter()
        var operations = ScanMetadataOperations.live
        operations.allocatedSize = { path in
            let size = try ScanMetadataOperations.live.allocatedSize(path)
            if path == target && counter.increment() == 1 {
                try FileManager.default.moveItem(atPath: moving, toPath: moving + ".preserved")
            }
            return size
        }
        let walker = DirectoryWalker(policy: fixture.policy, calculator: SizeCalculator(operations: operations))
        let result = try walker.walk(path: moving, maxDepth: 2)
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertTrue(result.issues.contains { $0.reason == .pathRefused(.changed) })
    }

    func testRegularFileSubstitutionDuringSizeLookupCannotProduceFinding() throws {
        let fixture = try WalkerFixture()
        let target = try fixture.write("Library/Caches/FileRace/cache.bin", data: Data([1]))
        let counter = MetadataAccessCounter()
        var operations = ScanMetadataOperations.live
        operations.allocatedSize = { path in
            if path == target && counter.increment() == 1 {
                try FileManager.default.moveItem(atPath: target, toPath: target + ".preserved")
                try Data([2]).write(to: URL(fileURLWithPath: target))
                return 4_096
            }
            return try ScanMetadataOperations.live.allocatedSize(path)
        }
        let walker = DirectoryWalker(policy: fixture.policy, calculator: SizeCalculator(operations: operations))
        let result = try walker.walk(path: fixture.caches + "/FileRace", maxDepth: 2)
        XCTAssertFalse(result.files.contains { $0.resolvedPath == target })
        XCTAssertTrue(result.issues.contains { $0.path == target && $0.reason == .pathRefused(.changed) })
    }

    func testEngineAndRealWalkerMatchCheckedInFixtureEndToEnd() async throws {
        let fixture = try WalkerFixture()
        let data = Data("""
        {"schemaVersion":1,"version":"1.0.0","rules":[{
        "id":"fixture.cache","title":"Synthetic cache","module":"creative",
        "producers":["io.racket.fixture"],"paths":["~/Library/Caches/Vendor"],
        "match":{"kind":"directoryContents","maxDepth":4},"conditions":[],
        "risk":"judgement","reason":"Synthetic fixture only.",
        "regenerationCost":"Created by the test.","citation":"https://example.invalid/fixture",
        "enabled":true,"verified":true}]}
        """.utf8)
        let rules = try RuleSet.decode(data, validatePath: fixture.policy.validateRulePath)
        let engine = ScanEngine(policy: fixture.policy, concurrencyLimit: 2) { path, depth, skip in
            try fixture.walker.walk(path: path, maxDepth: depth, skipExcludedFromBackup: skip)
        }
        let report = try await engine.scan(ruleSet: rules)
        XCTAssertEqual(report.findings.map { fixture.relative($0.resolvedPath) }, [
            "Library/Caches/Vendor/cache.bin", "Library/Caches/Vendor/nested/audio.cache"
        ])
        XCTAssertTrue(report.findings.allSatisfy { $0.ruleID == "fixture.cache" && !$0.isPreselectable })
        XCTAssertEqual(report.issues.count, 3)
        XCTAssertEqual(report.reportedAllocatedBytes, report.findings.reduce(UInt64(0)) { $0 + $1.allocatedSize })
    }
}

private struct WalkerFixture: Sendable {
    let home: String
    let policy: SafeRoots
    let walker: DirectoryWalker
    var caches: String { home + "/Library/Caches" }
    var vendor: String { caches + "/Vendor" }

    init() throws {
        home = "/private/tmp/RACKET-ScanFixture-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        policy = try SafeRoots(homeDirectory: home)
        walker = DirectoryWalker(policy: policy)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/scan-tree.json")
        let tree = try JSONDecoder().decode(FixtureTree.self, from: Data(contentsOf: source))
        for directory in tree.directories {
            try FileManager.default.createDirectory(atPath: home + "/" + directory, withIntermediateDirectories: true)
        }
        for (path, contents) in tree.files { try write(path, data: Data(contents.utf8)) }
    }

    @discardableResult
    func write(_ relative: String, data: Data) throws -> String {
        let path = home + "/" + relative
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    func relative(_ path: String) -> String { String(path.dropFirst(home.count + 1)) }
}

private struct FixtureTree: Decodable {
    let directories: [String]
    let files: [String: String]
}

private final class MetadataAccessCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    @discardableResult func increment() -> Int { lock.withLock { count += 1; return count } }
}

private func scanDescriptorPath(_ descriptor: Int32) throws -> String {
    var bytes = [CChar](repeating: 0, count: Int(PATH_MAX))
    let result = bytes.withUnsafeMutableBufferPointer { Darwin.fcntl(descriptor, F_GETPATH, $0.baseAddress!) }
    guard result == 0 else { throw ScanMetadataError.system(errno) }
    return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
