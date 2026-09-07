import Darwin
import Foundation
import XCTest
@testable import RacketCore

/// Fixtures deliberately remain in /private/tmp. Test cleanup must obey the same
/// no-permanent-deletion contract as the application.
final class PathGuardTests: XCTestCase {
    func testNormalCacheFileAndLogDirectoryAreAccepted() throws {
        let fixture = try GuardFixture()
        let file = try fixture.file("Library/Caches/vendor/cache.bin")
        let directory = try fixture.directory("Library/Logs/vendor")
        XCTAssertEqual(try fixture.guardrail.validate(file).resolvedPath, file)
        XCTAssertEqual(try fixture.guardrail.validate(directory).resolvedPath, directory)
    }

    func testRepeatedSeparatorsAndDotComponentsNormalizeInsideRoot() throws {
        let fixture = try GuardFixture()
        let file = try fixture.file("Library/Caches/vendor/cache.bin")
        let spelling = fixture.home + "//Library/./Caches//vendor/./cache.bin"
        XCTAssertEqual(try fixture.guardrail.validate(spelling).resolvedPath, file)
        XCTAssertEqual(try fixture.policy.validateCandidate(spelling), file)
    }

    func testTildeExpansionUsesConfiguredHome() throws {
        let fixture = try GuardFixture()
        let file = try fixture.file("Library/Caches/vendor/cache.bin")
        XCTAssertEqual(try fixture.guardrail.validate("~/Library/Caches/vendor/cache.bin").resolvedPath, file)
        try fixture.policy.validateRulePath("~/Library/Caches")
        try fixture.policy.validateRulePath("~/Library/Logs/vendor")
    }

    func testSafeRootsAreRuleLocationsButNeverCandidates() throws {
        let fixture = try GuardFixture()
        for root in [fixture.caches, fixture.logs] {
            try fixture.policy.validateRulePath(root)
            XCTAssertThrowsError(try fixture.guardrail.validate(root)) { error in
                guard case PathGuardError.safeRoot = error else {
                    return XCTFail("Expected safeRoot, received \(error)")
                }
            }
            assertRejected { _ = try fixture.policy.validateCandidate(root + "/./") }
        }
    }

    func testHomeVolumeRootAndParentFoldersAreRefused() throws {
        let fixture = try GuardFixture()
        for path in ["/", "/private", "/private/tmp", fixture.home, fixture.home + "/Library"] {
            assertRejected { _ = try fixture.guardrail.validate(path) }
        }
    }

    func testRootPrefixWithoutComponentBoundaryIsRefused() throws {
        let fixture = try GuardFixture()
        for relative in ["Library/CachesBackup/item", "Library/Caches2/item", "Library/Logs.old/item", "Library/LogsSuffix/item"] {
            let path = try fixture.file(relative)
            assertRejected { _ = try fixture.guardrail.validate(path) }
            assertRejected { _ = try fixture.policy.validateCandidate(path) }
        }
    }

    func testRelativeEmptyAndNamedUserTildePathsAreRefused() throws {
        let fixture = try GuardFixture()
        for path in ["", ".", "..", "Library/Caches/item", "Caches/item", "~", "~someone/Library/Caches/item"] {
            assertRejected { _ = try fixture.policy.validateCandidate(path) }
            assertRejected { try fixture.policy.validateRulePath(path) }
        }
    }

    func testEveryDotDotComponentIsRefusedEvenWhenItWouldStayInsideRoot() throws {
        let fixture = try GuardFixture()
        let paths = [
            fixture.caches + "/vendor/../item",
            fixture.caches + "/../Preferences/item",
            fixture.caches + "/vendor/../../Caches/item",
            fixture.caches + "/..",
            "~/Library/Caches/vendor/../item"
        ]
        for path in paths {
            assertRejected { _ = try fixture.policy.validateCandidate(path) }
            assertRejected { try fixture.policy.validateRulePath(path) }
        }
    }

    func testNulControlCharactersAndOverlongPathsAreRefused() throws {
        let fixture = try GuardFixture()
        let invalid = ["\0", "\n", "\r", "\t", "\u{001B}", "\u{007F}"]
        for character in invalid {
            let path = fixture.caches + "/before" + character + "after"
            assertRejected { _ = try fixture.policy.validateCandidate(path) }
            assertRejected { try fixture.policy.validateRulePath(path) }
        }
        let overlong = fixture.caches + "/" + String(repeating: "x", count: 4_097)
        assertRejected { _ = try fixture.policy.validateCandidate(overlong) }
        assertRejected { try fixture.policy.validateRulePath(overlong) }
    }

    func testRulePathsCannotContainGlobs() throws {
        let fixture = try GuardFixture()
        for suffix in ["*", "**/item", "vendor?", "[ab]", "{a,b}"] {
            assertRejected { try fixture.policy.validateRulePath("~/Library/Caches/" + suffix) }
        }
    }

    func testUnapprovedHomeLibrariesAreRefused() throws {
        let fixture = try GuardFixture()
        for name in ["Preferences", "Keychains", "Mail", "Messages", "Calendars", "AddressBook", "Blackmagic", "Application Support/Blackmagic Design"] {
            let path = try fixture.file("Library/" + name + "/valuable.data")
            assertRejected { _ = try fixture.guardrail.validate(path) }
        }
    }

    func testProtectedProjectComponentsAreRefusedAtEveryDepth() throws {
        let fixture = try GuardFixture()
        for name in [".git", "Original Media", "Auto-Save", "Adobe Premiere Pro Auto-Save", "CloudStorage", "Mobile Documents"] {
            for prefix in ["Library/Caches/", "Library/Logs/vendor/"] {
                let path = try fixture.file(prefix + name + "/important.bin")
                assertRejected { _ = try fixture.guardrail.validate(path) }
                assertRejected { _ = try fixture.policy.validateCandidate(path) }
            }
        }
    }

    func testProtectedDocumentAndPackageExtensionsAreRefused() throws {
        let fixture = try GuardFixture()
        for suffix in ["photoslibrary", "drp", "dra", "lrcat", "cocatalog"] {
            let package = try fixture.directory("Library/Caches/vendor/Project." + suffix)
            let member = try fixture.file("Library/Caches/vendor/Project." + suffix + "/asset.bin")
            assertRejected { _ = try fixture.guardrail.validate(package) }
            assertRejected { _ = try fixture.guardrail.validate(member) }
        }
    }

    func testCaseVariantsOfProtectedNamesRemainProtected() throws {
        let fixture = try GuardFixture()
        for name in [".GIT", "original media", "AUTO-SAVE", "adobe premiere pro auto-save", "cloudstorage", "MOBILE DOCUMENTS", "Project.DRP", "Project.PhOtOsLiBrArY"] {
            let path = fixture.caches + "/vendor/" + name + "/asset"
            assertRejected { _ = try fixture.policy.validateCandidate(path) }
        }
    }

    func testCaseVariantsOfAllowListRootsFailClosed() throws {
        let fixture = try GuardFixture()
        for suffix in ["library/Caches/item", "Library/caches/item", "Library/LOGS/item", "LIBRARY/Caches/item"] {
            assertRejected { _ = try fixture.policy.validateCandidate(fixture.home + "/" + suffix) }
        }
    }

    func testUnicodeNamesRemainWithinExactAllowListBoundaries() throws {
        let fixture = try GuardFixture()
        for name in ["café", "cafe\u{0301}", "çekim", "日本語", "🎬", "a\u{2215}b", "a\u{FF0F}b", "..cache"] {
            let path = fixture.caches + "/" + name + "/cache.bin"
            let candidate = try fixture.policy.validateCandidate(path)
            XCTAssertTrue(rawDescendant(candidate, of: fixture.caches))
        }
        for root in ["Cachés", "Cache\u{0301}s", "Ｃaches", "Cachеs"] {
            assertRejected { _ = try fixture.policy.validateCandidate(fixture.home + "/Library/" + root + "/item") }
        }
    }

    func testTenThousandGeneratedPathsCannotExpandAuthority() throws {
        let fixture = try GuardFixture()
        var generator = DeterministicGenerator(state: 0x5241434B4554)
        let roots = [fixture.caches, fixture.logs, fixture.home + "/Library/Preferences", fixture.caches + "Extra", "/", "relative", "~/Library/Caches"]
        let pieces = ["vendor", "cache.bin", "..", ".", "", ".git", "Original Media", "Mobile Documents", "project.drp", "caf\u{00E9}", "cafe\u{0301}", "\0", "\n", "..suffix"]
        var accepted = 0
        var rejected = 0
        for index in 0..<10_000 {
            var path = roots[generator.index(roots.count)]
            for _ in 0..<(1 + generator.index(5)) {
                path += (generator.index(3) == 0 ? "//" : "/") + pieces[generator.index(pieces.count)]
            }
            do {
                let candidate = try fixture.policy.validateCandidate(path)
                accepted += 1
                XCTAssertTrue(rawDescendant(candidate, of: fixture.caches) || rawDescendant(candidate, of: fixture.logs), "Escaped authority at case \(index)")
                XCTAssertFalse(candidate.split(separator: "/").contains(".."))
                XCTAssertFalse(candidate.utf8.contains(0))
            } catch is PathGuardError {
                rejected += 1
            } catch {
                XCTFail("Unexpected error type for generated path: \(error)")
            }
        }
        XCTAssertGreaterThan(accepted, 100)
        XCTAssertGreaterThan(rejected, 1_000)
        XCTAssertEqual(accepted + rejected, 10_000)
    }

    func testMissingPathIsRefused() throws {
        let fixture = try GuardFixture()
        XCTAssertThrowsError(try fixture.guardrail.validate(fixture.caches + "/absent")) { error in
            guard case PathGuardError.missing = error else {
                return XCTFail("Expected missing, received \(error)")
            }
        }
    }

    func testRegularFileCannotBeUsedAsAnAncestor() throws {
        let fixture = try GuardFixture()
        let file = try fixture.file("Library/Caches/not-a-directory")
        assertRejected { _ = try fixture.guardrail.validate(file + "/child") }
    }

    func testSymbolicLinksOutwardAndInwardAreBothRefused() throws {
        let fixture = try GuardFixture()
        let outside = try fixture.file("Documents/valuable.bin")
        let inside = try fixture.file("Library/Caches/vendor/cache.bin")
        for (name, destination) in [("outward", outside), ("inward", inside)] {
            let link = fixture.caches + "/" + name
            try fixture.manager.createSymbolicLink(atPath: link, withDestinationPath: destination)
            assertSymlinkRejected { _ = try fixture.guardrail.validate(link) }
        }
    }

    func testDanglingAndLoopingSymbolicLinksAreRefused() throws {
        let fixture = try GuardFixture()
        let dangling = fixture.caches + "/dangling"
        let loopA = fixture.caches + "/loop-a"
        let loopB = fixture.caches + "/loop-b"
        try fixture.manager.createSymbolicLink(atPath: dangling, withDestinationPath: fixture.home + "/missing")
        try fixture.manager.createSymbolicLink(atPath: loopA, withDestinationPath: loopB)
        try fixture.manager.createSymbolicLink(atPath: loopB, withDestinationPath: loopA)
        for path in [dangling, loopA, loopB] {
            assertSymlinkRejected { _ = try fixture.guardrail.validate(path) }
        }
    }

    func testSymlinkAncestorIsRefusedEvenWhenDestinationIsSafe() throws {
        let fixture = try GuardFixture()
        _ = try fixture.file("Library/Caches/vendor/cache.bin")
        let link = fixture.caches + "/alias"
        try fixture.manager.createSymbolicLink(atPath: link, withDestinationPath: fixture.caches + "/vendor")
        assertSymlinkRejected { _ = try fixture.guardrail.validate(link + "/cache.bin") }
    }

    func testSymlinkSafeRootIsRefused() throws {
        let fixture = try GuardFixture()
        let preserved = fixture.home + "/preserved-caches"
        try fixture.manager.moveItem(atPath: fixture.caches, toPath: preserved)
        try fixture.manager.createSymbolicLink(atPath: fixture.caches, withDestinationPath: preserved)
        _ = try fixture.file("preserved-caches/item")
        assertSymlinkRejected { _ = try fixture.guardrail.validate(fixture.caches + "/item") }
    }

    func testFIFOIsRefusedWithoutOpeningIt() throws {
        let fixture = try GuardFixture()
        let fifo = fixture.caches + "/pipe"
        let result = fifo.withCString { mkfifo($0, mode_t(0o600)) }
        XCTAssertEqual(result, 0, "Could not create synthetic FIFO")
        guard result == 0 else { return }
        XCTAssertThrowsError(try fixture.guardrail.validate(fifo)) { error in
            guard case PathGuardError.unsupportedFileType = error else {
                return XCTFail("Expected unsupportedFileType, received \(error)")
            }
        }
    }

    func testUnchangedReceiptCanBeRevalidated() throws {
        let fixture = try GuardFixture()
        let file = try fixture.file("Library/Caches/vendor/cache.bin")
        let receipt = try fixture.guardrail.validate(file)
        XCTAssertEqual(try fixture.guardrail.revalidate(receipt).resolvedPath, file)
    }

    func testReceiptRefusesItemReplacedWithSymlink() throws {
        let fixture = try GuardFixture()
        let file = try fixture.file("Library/Caches/vendor/cache.bin")
        let outside = try fixture.file("Documents/valuable.bin")
        let receipt = try fixture.guardrail.validate(file)
        try fixture.manager.moveItem(atPath: file, toPath: file + ".preserved")
        try fixture.manager.createSymbolicLink(atPath: file, withDestinationPath: outside)
        assertRejected { _ = try fixture.guardrail.revalidate(receipt) }
    }

    func testReceiptRefusesReplacementWithAnotherRegularFile() throws {
        let fixture = try GuardFixture()
        let file = try fixture.file("Library/Caches/vendor/cache.bin")
        let receipt = try fixture.guardrail.validate(file)
        try fixture.manager.moveItem(atPath: file, toPath: file + ".preserved")
        _ = try fixture.file("Library/Caches/vendor/cache.bin", data: Data("replacement".utf8))
        XCTAssertThrowsError(try fixture.guardrail.revalidate(receipt)) { error in
            guard case PathGuardError.changed = error else {
                return XCTFail("Expected changed, received \(error)")
            }
        }
    }

    func testReceiptRefusesInPlaceModificationOfTheSameFile() throws {
        let fixture = try GuardFixture()
        let file = try fixture.file("Library/Caches/vendor/cache.bin")
        let receipt = try fixture.guardrail.validate(file)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: file))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("additional synthetic cache content".utf8))
        try handle.synchronize()
        XCTAssertThrowsError(try fixture.guardrail.revalidate(receipt)) { error in
            guard case PathGuardError.changed = error else {
                return XCTFail("Expected changed, received \(error)")
            }
        }
    }

    func testReceiptRefusesReplacedSafeRootEvenWhenLeafInodeIsPreserved() throws {
        let fixture = try GuardFixture()
        let file = try fixture.file("Library/Caches/vendor/cache.bin")
        let receipt = try fixture.guardrail.validate(file)
        let preserved = fixture.home + "/preserved-caches"
        try fixture.manager.moveItem(atPath: fixture.caches, toPath: preserved)
        _ = try fixture.directory("Library/Caches")
        try fixture.manager.moveItem(atPath: preserved + "/vendor", toPath: fixture.caches + "/vendor")
        XCTAssertThrowsError(try fixture.guardrail.revalidate(receipt)) { error in
            guard case PathGuardError.changed = error else {
                return XCTFail("Expected changed, received \(error)")
            }
        }
    }

    func testReceiptRefusesReplacedAncestorEvenWhenLeafInodeIsPreserved() throws {
        let fixture = try GuardFixture()
        let file = try fixture.file("Library/Caches/vendor/cache.bin")
        let receipt = try fixture.guardrail.validate(file)
        let original = fixture.caches + "/vendor"
        let preserved = fixture.caches + "/vendor.preserved"
        try fixture.manager.moveItem(atPath: original, toPath: preserved)
        _ = try fixture.directory("Library/Caches/vendor")
        try fixture.manager.moveItem(atPath: preserved + "/cache.bin", toPath: file)
        XCTAssertThrowsError(try fixture.guardrail.revalidate(receipt)) { error in
            guard case PathGuardError.changed = error else {
                return XCTFail("Expected changed, received \(error)")
            }
        }
    }

    func testReceiptRefusesAncestorReplacedWithSymlink() throws {
        let fixture = try GuardFixture()
        let file = try fixture.file("Library/Caches/vendor/cache.bin")
        let receipt = try fixture.guardrail.validate(file)
        let ancestor = fixture.caches + "/vendor"
        let preserved = fixture.caches + "/vendor.preserved"
        try fixture.manager.moveItem(atPath: ancestor, toPath: preserved)
        try fixture.manager.createSymbolicLink(atPath: ancestor, withDestinationPath: preserved)
        assertRejected { _ = try fixture.guardrail.revalidate(receipt) }
    }

    private func assertRejected(file: StaticString = #filePath, line: UInt = #line, _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertTrue(error is PathGuardError, "Unexpected error type: \(error)", file: file, line: line)
        }
    }

    private func assertSymlinkRejected(file: StaticString = #filePath, line: UInt = #line, _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard case PathGuardError.symbolicLink = error else {
                return XCTFail("Expected symbolicLink, received \(error)", file: file, line: line)
            }
        }
    }
}

private struct GuardFixture {
    let manager = FileManager.default
    let home: String
    let policy: SafeRoots
    let guardrail: PathGuard

    var caches: String { home + "/Library/Caches" }
    var logs: String { home + "/Library/Logs" }

    init() throws {
        home = "/private/tmp/RACKET-PathGuard-" + UUID().uuidString
        try manager.createDirectory(atPath: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try manager.createDirectory(atPath: home + "/Library/Caches", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: home + "/Library/Logs", withIntermediateDirectories: true)
        policy = try SafeRoots(homeDirectory: home)
        guardrail = PathGuard(policy: policy)
    }

    @discardableResult
    func directory(_ relative: String) throws -> String {
        let path = home + "/" + relative
        try manager.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @discardableResult
    func file(_ relative: String, data: Data = Data("synthetic cache fixture".utf8)) throws -> String {
        let path = home + "/" + relative
        let parent = (path as NSString).deletingLastPathComponent
        try manager.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }
}

private struct DeterministicGenerator {
    var state: UInt64

    mutating func index(_ upperBound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 32) % UInt64(upperBound))
    }
}

private func rawDescendant(_ candidate: String, of root: String) -> Bool {
    candidate.utf8.starts(with: (root + "/").utf8) && candidate.utf8.count > root.utf8.count + 1
}
