import Darwin
import Foundation
import XCTest
@testable import RacketCore

/// Exercises the actual bundled developer declarations with synthetic homes,
/// real descriptor walking, and the preserved fixture Trash transport. No
/// current-user cache or real Trash is inspected or changed.
final class DeveloperRuleIntegrationTests: XCTestCase, @unchecked Sendable {
    func testBundledRulesScanReviewTrashAndUndoOldFilesAcrossAllEnabledRoots() async throws {
        let fixture = try DeveloperRuleFixture()
        let report = try await fixture.scan()
        XCTAssertEqual(Set(report.findings.map(\.resolvedPath)), Set(fixture.oldFiles))
        XCTAssertEqual(Set(report.findings.map(\.ruleID)), Set(fixture.rules.enabledRules.map(\.id)))
        XCTAssertEqual(report.issues.filter { $0.reason == .notOldEnough }.count, fixture.rules.enabledRules.count)
        XCTAssertTrue(report.findings.allSatisfy { !$0.requiredClosedProducers.isEmpty && $0.observation != nil })

        let removal = RemovalEngine(policy: fixture.policy, manifest: fixture.manifest,
                                    operations: fixture.operations, appActivity: fixture.inactive)
        let removed = try await removal.moveToTrash(reviewedFindings: report.findings,
                                                   ruleSet: fixture.rules, appVersion: "developer-fixture", now: fixture.now)
        XCTAssertNil(removed.journalFailure)
        XCTAssertEqual(removed.results.map(\.outcome), Array(repeating: .trashed, count: fixture.oldFiles.count))
        for result in removed.results {
            XCTAssertFalse(FileManager.default.fileExists(atPath: result.originalPath))
            let destination = try XCTUnwrap(result.recoveryPath)
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: destination)), fixture.contents)
        }
        try fixture.requirePreservedFiles()

        let undo = UndoService(policy: fixture.policy, manifest: fixture.manifest, operations: fixture.operations)
        let restored = try await undo.restore(sessionID: removed.sessionID)
        XCTAssertNil(restored.journalFailure)
        XCTAssertEqual(restored.results.map(\.outcome), Array(repeating: .restored, count: fixture.oldFiles.count))
        for file in fixture.oldFiles {
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: file)), fixture.contents)
        }
        XCTAssertEqual(try fixture.manifest.read(removed.sessionID).events.count, fixture.oldFiles.count * 5)
        try fixture.requirePreservedFiles()
    }

    func testProducerStartingAfterReviewRefusesEachDeveloperCategory() async throws {
        let fixture = try DeveloperRuleFixture()
        let findings = try await fixture.scan().findings
        let running = AppActivity(snapshot: {
            ["/synthetic/ruby", "/synthetic/node", "/synthetic/xcodebuild"].map(AppActivityProcess.init)
        })
        let removal = RemovalEngine(policy: fixture.policy, manifest: fixture.manifest,
                                    operations: fixture.operations, appActivity: running)
        let report = try await removal.moveToTrash(reviewedFindings: findings, ruleSet: fixture.rules,
                                                  appVersion: "developer-fixture", now: fixture.now)
        XCTAssertEqual(report.results.map(\.outcome), Array(repeating: .skipped, count: fixture.oldFiles.count))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.trash).isEmpty)
        for file in fixture.oldFiles {
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: file)), fixture.contents)
        }
        try fixture.requirePreservedFiles()
    }

    func testUnknownProducerObservationPreventsEveryBundledDeveloperWalk() async throws {
        let fixture = try DeveloperRuleFixture()
        let report = try await fixture.scan(activity: AppActivity(snapshot: { [] }))
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.visitedEntryCount, 0)
        XCTAssertEqual(report.issues.map(\.reason), Array(repeating: .producerActivityUnknown,
                                                        count: fixture.rules.enabledRules.count))
        try fixture.requirePreservedFiles()
    }
}

private struct DeveloperRuleFixture: Sendable {
    let home: String
    let policy: SafeRoots
    let rules: RuleSet
    let manifest: ManifestStore
    let now = Date(timeIntervalSince1970: 1_792_089_600)
    let contents = Data(repeating: 0x5a, count: 8_192)
    let oldFiles: [String]
    let preservedFiles: [String]
    var trash: String { home + "/FixtureTrash" }
    var inactive: AppActivity {
        AppActivity(snapshot: { [AppActivityProcess(executablePath: "/synthetic/fixture-runner")] })
    }

    init() throws {
        home = "/private/tmp/RACKET-DeveloperRules-" + UUID().uuidString
        policy = try SafeRoots(homeDirectory: home)
        rules = try RuleSet.loadBundled(validatePath: policy.validateRulePath).filtered(modules: [.developer])
        let manager = FileManager.default
        try manager.createDirectory(atPath: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try manager.createDirectory(atPath: home + "/FixtureTrash", withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        manifest = try ManifestStore(directory: home + "/Manifest", authenticationKey: Data(repeating: 0x73, count: 32))
        var oldFiles: [String] = []
        var preservedFiles: [String] = []
        for rule in rules.enabledRules {
            let declared = try XCTUnwrap(rule.paths.first)
            let root = home + String(declared.dropFirst())
            try manager.createDirectory(atPath: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let old = root + "/old-generated-cache.bin"
            try contents.write(to: URL(fileURLWithPath: old))
            let days = try XCTUnwrap(rule.conditions.first?.olderThanDays)
            try manager.setAttributes([.modificationDate: now.addingTimeInterval(-Double(days + 1) * 86_400)], ofItemAtPath: old)
            oldFiles.append(old)
            let recent = root + "/recent-generated-cache.bin"
            try contents.write(to: URL(fileURLWithPath: recent))
            try manager.setAttributes([.modificationDate: now], ofItemAtPath: recent)
            preservedFiles.append(recent)
            let protected = root + "/.git/objects/valuable"
            try manager.createDirectory(atPath: (protected as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try contents.write(to: URL(fileURLWithPath: protected))
            preservedFiles.append(protected)
        }
        for relative in ["Documents/source.swift", ".npmrc", ".npm/_npx/source.js",
                         "Library/Developer/Xcode/DerivedData/Project/SourcePackages/checkouts/Library/source.swift"] {
            let path = home + "/" + relative
            try manager.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try contents.write(to: URL(fileURLWithPath: path))
            preservedFiles.append(path)
        }
        self.oldFiles = oldFiles
        self.preservedFiles = preservedFiles
    }

    var operations: RemovalOperations {
        RemovalOperations(trash: { path in
            let destination = trash + "/" + (path as NSString).lastPathComponent
            guard renamex_np(path, destination, UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY)) == 0 else {
                throw RemovalSafetyError.system(errno)
            }
            return destination
        }, isInTrash: { SafeRoots.isWithin($0, root: trash) && $0 != trash })
    }

    func scan(activity: AppActivity? = nil) async throws -> ScanReport {
        let walker = DirectoryWalker(policy: policy)
        let scanner = ScanEngine(policy: policy, concurrencyLimit: 2, appActivity: activity ?? inactive) { path, depth, skip in
            try walker.walk(path: path, maxDepth: depth, skipExcludedFromBackup: skip)
        }
        return try await scanner.scan(ruleSet: rules, now: now)
    }

    func requirePreservedFiles() throws {
        for path in preservedFiles {
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), contents)
        }
    }
}
