import Foundation
import XCTest
@testable import RacketCore

final class BackupExclusionTests: XCTestCase {
    private func decode(flag: Any? = nil) throws -> Rule {
        var object: [String: Any] = [
            "id": "fixture.backup.cache", "module": "creative", "title": "Fixture cache",
            "producers": ["org.example.Fixture"], "paths": ["~/Library/Caches/fixture"],
            "match": ["kind": "directoryContents", "maxDepth": 1], "conditions": [],
            "risk": "regenerable", "reason": "Synthetic cache reason.",
            "regenerationCost": "Synthetic regeneration cost.", "citation": "https://example.org/fixture"
        ]
        object["skipExcludedFromBackup"] = flag
        return try JSONDecoder().decode(Rule.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testMissingBackupExclusionFlagDefaultsToFalse() throws {
        XCTAssertFalse(try decode().skipExcludedFromBackup)
    }

    func testExplicitBackupExclusionFlagRoundTripsBothStates() throws {
        for value in [false, true] {
            let rule = try decode(flag: value)
            XCTAssertEqual(rule.skipExcludedFromBackup, value)
            let copy = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(rule))
            XCTAssertEqual(copy.skipExcludedFromBackup, value)
        }
    }

    func testNullAndNonBooleanBackupExclusionFlagsAreRejected() throws {
        for value: Any in [NSNull(), "true", 1, [], [:]] {
            XCTAssertThrowsError(try decode(flag: value))
        }
    }
}
