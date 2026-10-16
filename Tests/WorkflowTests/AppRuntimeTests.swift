import Foundation
import XCTest
@testable import RacketCore

#if DEBUG
final class AppRuntimeTests: XCTestCase {
    func testReviewedScanRemovalAndReopenedHistoryUndoPreserveSyntheticFiles() async throws {
        let runtime = try AppRuntime.verification()
        let report = try await runtime.scanner.scan(ruleSet: runtime.rules)
        XCTAssertEqual(report.findings.count, 4)
        XCTAssertTrue(report.findings.allSatisfy { $0.resolvedPath.hasPrefix("/private/tmp/RACKET-UI-") })
        let before = try report.findings.map { try Data(contentsOf: URL(fileURLWithPath: $0.resolvedPath)) }
        let removed = try await runtime.remover.moveToTrash(reviewedFindings: report.findings, ruleSet: runtime.rules,
                                                          appVersion: "verification")
        XCTAssertTrue(removed.results.allSatisfy { $0.outcome == .trashed })
        XCTAssertEqual(try runtime.manifest.sessionIDs(), [removed.sessionID])
        XCTAssertEqual(try runtime.manifest.read(removed.sessionID).events.count, 12)
        let afterScan = try await runtime.scanner.scan(ruleSet: runtime.rules)
        XCTAssertTrue(afterScan.findings.isEmpty)
        let restored = try await runtime.undo.restore(sessionID: removed.sessionID)
        XCTAssertTrue(restored.results.allSatisfy { $0.outcome == .restored })
        for (index, finding) in report.findings.enumerated() {
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: finding.resolvedPath)), before[index])
        }
        XCTAssertEqual(try runtime.manifest.read(removed.sessionID).events.count, 20)
    }

    func testSessionEnumerationIsBoundedAndIgnoresNonJournalFiles() throws {
        let runtime = try AppRuntime.verification()
        _ = try runtime.manifest.createSession(appVersion: "test", ruleSetVersion: "1.0.0")
        _ = try runtime.manifest.createSession(appVersion: "test", ruleSetVersion: "1.0.0")
        XCTAssertThrowsError(try runtime.manifest.sessionIDs(limit: 1))
        XCTAssertEqual(try runtime.manifest.sessionIDs().count, 2)
    }
}
#endif
