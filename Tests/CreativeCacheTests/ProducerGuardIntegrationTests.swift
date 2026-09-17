import Foundation
import XCTest
@testable import RacketCore

final class ProducerGuardIntegrationTests: XCTestCase, @unchecked Sendable {
    private static let producer = "io.racket.fixture"
    private static let identity = ProducerExecutableIdentity(producer: producer, executableNames: ["Producer"])

    private func activity(_ state: GuardProbe) -> AppActivity {
        AppActivity(snapshot: {
            state.checked()
            if state.unknown { throw RemovalSafetyError.unsupported }
            return [AppActivityProcess(executablePath: state.running ? "/synthetic/Producer" : "/synthetic/runner")]
        }, identities: [Self.identity])
    }

    func testRuleActivityFlagDefaultsFalseRoundTripsAndRejectsMalformedValues() throws {
        let fixture = try RemovalFixture()
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(fixture.ruleJSON.utf8)) as? [String: Any])
        var rules = try XCTUnwrap(document["rules"] as? [[String: Any]])
        rules[0].removeValue(forKey: "requiresClosedApplications")
        document["rules"] = rules
        let absent = try RuleSet.decode(JSONSerialization.data(withJSONObject: document)) { _ in }
        XCTAssertFalse(try XCTUnwrap(absent.rules.first).requiresClosedApplications)
        for value in [false, true] {
            rules[0]["requiresClosedApplications"] = value
            document["rules"] = rules
            let set = try RuleSet.decode(JSONSerialization.data(withJSONObject: document)) { _ in }
            let rule = try XCTUnwrap(set.rules.first)
            XCTAssertEqual(rule.requiresClosedApplications, value)
            XCTAssertEqual(try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(rule)), rule)
        }
        for value: Any in [NSNull(), "true", 1, [], [:]] {
            rules[0]["requiresClosedApplications"] = value
            document["rules"] = rules
            XCTAssertThrowsError(try RuleSet.decode(JSONSerialization.data(withJSONObject: document)) { _ in })
        }
    }

    func testRunningAndUnknownProducersPreventAnyWalk() async throws {
        let fixture = try RemovalFixture(requiresClosedApplications: true)
        for unknown in [false, true] {
            let state = GuardProbe(running: !unknown, unknown: unknown)
            let scanner = ScanEngine(policy: fixture.policy, concurrencyLimit: 1, appActivity: activity(state)) { _, _, _ in
                XCTFail("Blocked producers must prevent the walker call")
                return DirectoryWalk(files: [], issues: [], visitedEntryCount: 0)
            }
            let report = try await scanner.scan(ruleSet: fixture.rules)
            XCTAssertTrue(report.findings.isEmpty)
            XCTAssertEqual(report.visitedEntryCount, 0)
            XCTAssertEqual(report.issues.map(\.reason), [unknown ? .producerActivityUnknown : .producerRunning([Self.producer])])
            XCTAssertEqual(report.issues.first?.disposition, unknown ? .incomplete : .skipped)
        }
    }

    func testProducerStartingDuringWalkDiscardsFindingsButPreservesVisitCount() async throws {
        let fixture = try RemovalFixture(requiresClosedApplications: true)
        let state = GuardProbe()
        let walker = DirectoryWalker(policy: fixture.policy)
        let scanner = ScanEngine(policy: fixture.policy, concurrencyLimit: 1, appActivity: activity(state)) { path, depth, skip in
            let result = try walker.walk(path: path, maxDepth: depth, skipExcludedFromBackup: skip)
            state.running = true
            return result
        }
        let report = try await scanner.scan(ruleSet: fixture.rules)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertGreaterThan(report.visitedEntryCount, 0)
        XCTAssertEqual(report.issues.last?.reason, .producerRunning([Self.producer]))
    }

    func testScanPreservesProducerRequirementAndRemovalRechecksAfterReview() async throws {
        let fixture = try RemovalFixture(requiresClosedApplications: true)
        let state = GuardProbe()
        let findings = try await fixture.findings(appActivity: activity(state))
        XCTAssertEqual(findings.first?.requiredClosedProducers, [Self.producer])
        state.running = true
        let report = try await remove(fixture, findings: findings, state: state)
        XCTAssertEqual(report.results.first?.outcome, .skipped)
        XCTAssertEqual(try fixture.manifest.read(report.sessionID).events.map(\.action), [.refused])
        try assertOriginalPreserved(fixture)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root + "/.racket-staging"))
    }

    func testUnknownActivityRefusesRemovalWithoutCapture() async throws {
        let fixture = try RemovalFixture(requiresClosedApplications: true)
        let state = GuardProbe()
        let findings = try await fixture.findings(appActivity: activity(state))
        state.unknown = true
        let report = try await remove(fixture, findings: findings, state: state)
        XCTAssertEqual(report.results.first?.outcome, .refused)
        try assertOriginalPreserved(fixture)
    }

    func testProducerStartingAfterPreparedRecordPreventsStagingCreation() async throws {
        let fixture = try RemovalFixture(requiresClosedApplications: true)
        let state = GuardProbe()
        let findings = try await fixture.findings(appActivity: activity(state))
        var operations = fixture.operations
        operations.beforeJournal = { event in if event.action == .prepared { state.running = true } }
        let report = try await remove(fixture, findings: findings, state: state, operations: operations)
        XCTAssertEqual(report.results.first?.outcome, .skipped)
        XCTAssertEqual(try fixture.manifest.read(report.sessionID).events.map(\.action), [.prepared, .refused])
        try assertOriginalPreserved(fixture)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root + "/.racket-staging"))
    }

    func testProducerStartingImmediatelyBeforeCapturePreventsRename() async throws {
        let fixture = try RemovalFixture(requiresClosedApplications: true)
        let state = GuardProbe()
        let findings = try await fixture.findings(appActivity: activity(state))
        var operations = fixture.operations
        operations.beforeCaptureRename = { _ in state.running = true }
        let report = try await remove(fixture, findings: findings, state: state, operations: operations)
        XCTAssertEqual(report.results.first?.outcome, .skipped)
        try assertOriginalPreserved(fixture)
    }

    func testProducerStartingBeforeTrashPreservesFileViaExclusiveRollback() async throws {
        let fixture = try RemovalFixture(requiresClosedApplications: true)
        let state = GuardProbe()
        let findings = try await fixture.findings(appActivity: activity(state))
        var operations = fixture.operations
        operations.beforeTrash = { _ in state.running = true }
        let report = try await remove(fixture, findings: findings, state: state, operations: operations)
        XCTAssertEqual(report.results.first?.outcome, .failed)
        XCTAssertEqual(try fixture.manifest.read(report.sessionID).events.map(\.action), [.prepared, .staged, .failed])
        try assertOriginalPreserved(fixture)
    }

    func testGuardCannotBeStrippedFromRuleAfterReview() async throws {
        let fixture = try RemovalFixture(requiresClosedApplications: true)
        let state = GuardProbe()
        let findings = try await fixture.findings(appActivity: activity(state))
        let weakened = fixture.ruleJSON.replacingOccurrences(of: "\"requiresClosedApplications\":true", with: "\"requiresClosedApplications\":false")
        let rules = try RuleSet.decode(Data(weakened.utf8), validatePath: fixture.policy.validateRulePath)
        let report = try await RemovalEngine(policy: fixture.policy, manifest: fixture.manifest,
                                            operations: fixture.operations, appActivity: activity(state))
            .moveToTrash(reviewedFindings: findings, ruleSet: rules, appVersion: "test")
        XCTAssertEqual(report.results.first?.outcome, .refused)
        try assertOriginalPreserved(fixture)
    }

    func testUnguardedRulesDoNotReadProcessState() async throws {
        let fixture = try RemovalFixture()
        let state = GuardProbe(unknown: true)
        let findings = try await fixture.findings(appActivity: activity(state))
        let report = try await RemovalEngine(policy: fixture.policy, manifest: fixture.manifest,
                                            operations: fixture.operations, appActivity: activity(state))
            .moveToTrash(reviewedFindings: findings, ruleSet: fixture.rules, appVersion: "test")
        XCTAssertEqual(report.results.first?.outcome, .trashed)
        XCTAssertEqual(state.calls, 0)
    }

    func testGuardedObservedFileCanCompleteFakeTrashAndUndoRoundTrip() async throws {
        let fixture = try RemovalFixture(requiresClosedApplications: true)
        let state = GuardProbe()
        let findings = try await fixture.findings(appActivity: activity(state))
        let removed = try await RemovalEngine(policy: fixture.policy, manifest: fixture.manifest,
                                             operations: fixture.operations, appActivity: activity(state))
            .moveToTrash(reviewedFindings: findings, ruleSet: fixture.rules, appVersion: "test")
        XCTAssertEqual(removed.results.first?.outcome, .trashed)
        let restored = try await UndoService(policy: fixture.policy, manifest: fixture.manifest,
                                            operations: fixture.operations).restore(sessionID: removed.sessionID)
        XCTAssertEqual(restored.results.first?.outcome, .restored)
        XCTAssertGreaterThanOrEqual(state.calls, 6)
        try assertOriginalPreserved(fixture)
    }

    private func remove(_ fixture: RemovalFixture, findings: [Finding], state: GuardProbe,
                        operations: RemovalOperations? = nil) async throws -> RemovalReport {
        var transport = operations ?? fixture.operations
        transport.trash = { _ in XCTFail("Refused activity must never reach Trash"); throw RemovalSafetyError.unsupported }
        return try await RemovalEngine(policy: fixture.policy, manifest: fixture.manifest,
                                       operations: transport, appActivity: activity(state))
            .moveToTrash(reviewedFindings: findings, ruleSet: fixture.rules, appVersion: "test")
    }

    private func assertOriginalPreserved(_ fixture: RemovalFixture) throws {
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: fixture.file)), fixture.contents)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.trash).isEmpty)
    }
}

private final class GuardProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var active: Bool
    private var uncertain: Bool
    private var count = 0
    init(running: Bool = false, unknown: Bool = false) { active = running; uncertain = unknown }
    var running: Bool {
        get { lock.withLock { active } }
        set { lock.withLock { active = newValue } }
    }
    var unknown: Bool {
        get { lock.withLock { uncertain } }
        set { lock.withLock { uncertain = newValue } }
    }
    var calls: Int { lock.withLock { count } }
    func checked() { lock.withLock { count += 1 } }
}
