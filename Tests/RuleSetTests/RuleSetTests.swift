import Foundation
import XCTest
@testable import RacketCore

final class RuleSetTests: XCTestCase {
    private enum FixturePolicyError: Error, Equatable {
        case outsideSyntheticRoot
    }

    private static let fixtureHome = "/synthetic-home"
    private static let fixturePath = fixtureHome + "/Library/Caches/fixture-app"

    private func rule(
        id: String = "fixture.creative.cache",
        risk: String = "regenerable",
        verified: Bool = true,
        enabled: Bool = true
    ) -> [String: Any] {
        [
            "id": id,
            "module": "creative",
            "title": "Synthetic fixture cache",
            "producers": ["org.example.FixtureApp"],
            "paths": [Self.fixturePath],
            "match": ["kind": "directoryContents", "maxDepth": 2],
            "conditions": [["olderThanDays": 14]],
            "risk": risk,
            "reason": "The synthetic producer writes reproducible test cache data.",
            "regenerationCost": "The fixture producer rebuilds this data when requested.",
            "citation": "https://example.org/fixture-cache-specification",
            "verified": verified,
            "enabled": enabled
        ]
    }

    private func document(rules: [[String: Any]]) -> [String: Any] {
        ["schemaVersion": 1, "version": "1.0.0", "rules": rules]
    }

    private func decode(_ object: [String: Any]) throws -> RuleSet {
        // The internal initializer is accessible only through @testable here.
        // This exercises compiled policy without filesystem reads or live home discovery.
        let policy = try SafeRoots(homeDirectory: Self.fixtureHome)
        return try RuleSet.decode(JSONSerialization.data(withJSONObject: object)) { path in
            try policy.validateRulePath(path)
        }
    }

    func testValidRuleRetainsAuditableExplanationAndVersion() throws {
        let result = try decode(document(rules: [rule()]))
        XCTAssertEqual(result.schemaVersion, 1)
        XCTAssertEqual(result.version, "1.0.0")
        XCTAssertEqual(result.rules.count, 1)
        let loaded = try XCTUnwrap(result.rules.first)
        XCTAssertEqual(loaded.id, "fixture.creative.cache")
        XCTAssertEqual(loaded.paths, [Self.fixturePath])
        XCTAssertEqual(loaded.match.kind, .directoryContents)
        XCTAssertEqual(loaded.match.maxDepth, 2)
        XCTAssertEqual(loaded.conditions.first?.olderThanDays, 14)
        XCTAssertEqual(loaded.reason, rule()["reason"] as? String)
        XCTAssertEqual(loaded.regenerationCost, rule()["regenerationCost"] as? String)
        XCTAssertEqual(loaded.citation, rule()["citation"] as? String)
        XCTAssertTrue(loaded.isPreselectable)
        XCTAssertEqual(result.enabledRules, result.rules)
    }

    func testShippedRuleDocumentIsVersionedAndHasNoEnabledOrUnverifiedCacheClaims() throws {
        let policy = try SafeRoots(homeDirectory: Self.fixtureHome)
        let result = try RuleSet.loadBundled { path in
            try policy.validateRulePath(path)
        }
        XCTAssertEqual(result.schemaVersion, RuleSet.supportedSchemaVersion)
        XCTAssertEqual(result.version, "1.0.0")
        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.enabledRules.isEmpty)
    }

    func testMissingEnableAndVerificationFlagsDefaultToDisabled() throws {
        var example = rule()
        example["verified"] = nil
        example["enabled"] = nil
        let result = try decode(document(rules: [example]))
        let loaded = try XCTUnwrap(result.rules.first)
        XCTAssertFalse(loaded.verified)
        XCTAssertFalse(loaded.enabled)
        XCTAssertFalse(loaded.isPreselectable)
        XCTAssertTrue(result.enabledRules.isEmpty)
    }

    func testEnabledUnverifiedRulesAreRejected() throws {
        XCTAssertThrowsError(try decode(document(rules: [rule(verified: false)])))
        var missingVerification = rule()
        missingVerification["verified"] = nil
        XCTAssertThrowsError(try decode(document(rules: [missingVerification])))
        XCTAssertNoThrow(try decode(document(rules: [rule(verified: false, enabled: false)])))
    }

    func testJudgementIsNeverPreselectableForAnyAllowedFlagCombination() throws {
        for flags in [(false, false), (true, false), (true, true)] {
            let result = try decode(document(rules: [rule(risk: "judgement", verified: flags.0, enabled: flags.1)]))
            XCTAssertFalse(try XCTUnwrap(result.rules.first).isPreselectable)
        }
    }

    func testEveryKnownRiskIsDecodedAndOnlyActiveNonJudgementRulesAreEligible() throws {
        for risk in Rule.Risk.allCases {
            for enabled in [false, true] {
                let result = try decode(document(rules: [rule(risk: risk.rawValue, enabled: enabled)]))
                let loaded = try XCTUnwrap(result.rules.first)
                XCTAssertEqual(loaded.risk, risk)
                XCTAssertEqual(loaded.isPreselectable, enabled && risk != .judgement)
            }
        }
    }

    func testMissingRequiredRuleFieldsAreRejected() throws {
        for field in ["id", "module", "title", "producers", "paths", "match", "conditions", "risk", "reason", "regenerationCost", "citation"] {
            var example = rule()
            example[field] = nil
            XCTAssertThrowsError(try decode(document(rules: [example])), "Missing \(field)")
        }
    }

    func testBlankExplanationsAndMetadataAreRejected() throws {
        for field in ["id", "title", "reason", "regenerationCost", "citation"] {
            for value in ["", "   ", "\n\t", "\u{2003}"] {
                var example = rule()
                example[field] = value
                XCTAssertThrowsError(try decode(document(rules: [example])), "Blank \(field)")
            }
        }
    }

    func testDuplicateRuleIdentifiersAreRejected() throws {
        XCTAssertThrowsError(try decode(document(rules: [rule(), rule()]))) { error in
            XCTAssertEqual(error as? RuleValidationError, .duplicateID("fixture.creative.cache"))
        }
        XCTAssertNoThrow(try decode(document(rules: [rule(), rule(id: "fixture.other.cache")])))
    }

    func testInjectedPolicyRefusalIsPropagatedForEnabledAndDisabledRules() throws {
        for enabled in [false, true] {
            let bytes = try JSONSerialization.data(withJSONObject: document(rules: [rule(enabled: enabled)]))
            XCTAssertThrowsError(try RuleSet.decode(bytes) { _ in
                throw FixturePolicyError.outsideSyntheticRoot
            }) { error in
                XCTAssertEqual(error as? FixturePolicyError, .outsideSyntheticRoot)
            }
        }
    }

    func testCompiledPolicyAcceptsCacheAndLogDeclarationsWithSyntheticTildeExpansion() throws {
        var example = rule()
        let paths = [
            "~/Library/Caches", "~/Library/Logs/fixture-app",
            Self.fixturePath, Self.fixtureHome + "/Library/Logs"
        ]
        example["paths"] = paths
        XCTAssertEqual(try decode(document(rules: [example])).rules.first?.paths, paths)
    }

    func testCompiledPolicyRejectsUnapprovedRootsAndRootPrefixCollisions() throws {
        for path in [
            "/", "/Library/Logs/fixture-app", "/System/fixture-app",
            "~/Library/Developer/fixture-app", "~/Library/Application Support/fixture-app",
            "~/Library/CachesBackup/fixture-app", "~/Library/Logs.old/fixture-app",
            "/another-synthetic-home/Library/Caches/fixture-app"
        ] {
            var example = rule()
            example["paths"] = [path]
            XCTAssertThrowsError(try decode(document(rules: [example]))) { error in
                XCTAssertTrue(error is PathGuardError, "Expected compiled-policy refusal for \(path); got \(error)")
            }
        }
    }

    func testCompiledPolicyRejectsProtectedDescendantsAtEveryDepth() throws {
        let names = [
            ".git", "Original Media", "Auto-Save", "Adobe Premiere Pro Auto-Save",
            "CloudStorage", "Mobile Documents", "com~apple~CloudDocs",
            "Project.photoslibrary", "Project.DRP", "Project.dra", "Shoot.lrcat", "Shoot.cocatalog"
        ]
        for name in names {
            for root in ["~/Library/Caches", "~/Library/Logs/vendor/nested"] {
                var example = rule()
                example["paths"] = [root + "/" + name + "/data"]
                XCTAssertThrowsError(try decode(document(rules: [example]))) { error in
                    guard case PathGuardError.protectedPath = error else {
                        return XCTFail("Expected protected-path refusal for \(name); got \(error)")
                    }
                }
            }
        }
    }

    func testDisabledAndUnverifiedRulesMustStillPassCompiledPathPolicy() throws {
        for flags in [(false, false), (true, false), (true, true)] {
            for path in ["~/Library/Preferences/settings.plist", "~/Library/Caches/vendor/.git/objects", "/outside-synthetic-home/cache"] {
                var example = rule(verified: flags.0, enabled: flags.1)
                example["paths"] = [Self.fixturePath, path]
                XCTAssertThrowsError(try decode(document(rules: [example]))) { error in
                    XCTAssertTrue(error is PathGuardError, "Disabled state must not hide an unsafe declaration")
                }
            }
        }
    }

    func testCompiledPolicyRejectsTraversalGlobsAndUnknownExpansionSyntax() throws {
        for path in [
            "~/Library/Caches/vendor/../cache", "~/Library/Caches/../../Documents",
            "~/Library/Caches/*", "~/Library/Caches/vendor?", "~/Library/Caches/[ab]",
            "~/Library/Caches/{a,b}", "~/Library/Caches/vendor\\cache",
            "~someone/Library/Caches/cache", "$HOME/Library/Caches/cache", "relative/cache"
        ] {
            var example = rule()
            example["paths"] = [path]
            XCTAssertThrowsError(try decode(document(rules: [example]))) { error in
                guard case PathGuardError.invalidPath = error else {
                    return XCTFail("Expected invalid-path refusal for \(path); got \(error)")
                }
            }
        }
    }

    func testEveryPathPassesTheInjectedPolicy() throws {
        var example = rule()
        example["paths"] = [Self.fixturePath, Self.fixturePath + "/nested"]
        XCTAssertEqual(try decode(document(rules: [example])).rules.first?.paths.count, 2)
        example["paths"] = ["/Library/Logs/fixture", Self.fixturePath]
        XCTAssertThrowsError(try decode(document(rules: [example])))
    }

    func testRulesCannotProvideSafeRootsOrHomeDirectoryOverrides() throws {
        for field in ["safeRoots", "homeDirectory", "allowOutsideRoot"] {
            var example = rule()
            example[field] = ["/"]
            XCTAssertThrowsError(try decode(document(rules: [example])))
            var topLevel = document(rules: [rule()])
            topLevel[field] = ["/"]
            XCTAssertThrowsError(try decode(topLevel))
        }
    }

    func testUnknownKeysFailClosedAtEveryObjectLevel() throws {
        var unknownTop = document(rules: [rule()])
        unknownTop["futureOption"] = false
        XCTAssertThrowsError(try decode(unknownTop))
        var unknownRule = rule()
        unknownRule["futureOption"] = false
        XCTAssertThrowsError(try decode(document(rules: [unknownRule])))
        var unknownMatch = rule()
        unknownMatch["match"] = ["kind": "directoryContents", "maxDepth": 2, "followSymlinks": false]
        XCTAssertThrowsError(try decode(document(rules: [unknownMatch])))
        var unknownCondition = rule()
        unknownCondition["conditions"] = [["olderThanDays": 14, "includeAll": true]]
        XCTAssertThrowsError(try decode(document(rules: [unknownCondition])))
    }

    func testDuplicateJSONFieldsAreRejectedIncludingEscapedEquivalentKeys() throws {
        for json in [
            #"{"schemaVersion":1,"schemaVersion":2,"version":"1.0.0","rules":[]}"#,
            #"{"schemaVersion":1,"version":"1.0.0","rules":[],"r\u0075les":[]}"#,
            #"{"schemaVersion":1,"version":"1.0.0","rules":[{"enabled":false,"enabled":true}]}"#,
            #"{"schemaVersion":1,"version":"1.0.0","rules":[{"reason":"first","\u0072eason":"second"}]}"#,
            #"{"schemaVersion":1,"version":"1.0.0","rules":[{"futureOption":false,"futureOption":true}]}"#,
            #"{"schemaVersion":1,"version":"1.0.0","rules":[{"match":{"kind":"glob","kind":"directoryContents"}}]}"#
        ] {
            XCTAssertThrowsError(try RuleSet.decode(Data(json.utf8)) { _ in }) { error in
                guard case .duplicateField = error as? RuleValidationError else {
                    return XCTFail("Expected duplicate-field refusal; got \(error)")
                }
            }
        }
    }

    func testSameKeysInIndependentObjectsAndEscapedStringValuesAreAllowed() throws {
        var first = rule()
        first["reason"] = "Quotes \"reason\" and slash \\ remain ordinary text.\nNext line."
        let result = try decode(document(rules: [first, rule(id: "fixture.other.cache")]))
        XCTAssertEqual(result.rules.count, 2)
        XCTAssertEqual(result.rules.first?.reason, first["reason"] as? String)
    }

    func testDocumentStructureRejectsExcessiveNestingAndTrailingContent() throws {
        let deeplyNested = String(repeating: "[", count: 66) + "0" + String(repeating: "]", count: 66)
        for json in [deeplyNested, #"{"schemaVersion":1,"version":"1.0.0","rules":[]} {}"#,
                     #"{"schemaVersion":1,"version":"1.0.0","rules":[],}"#] {
            XCTAssertThrowsError(try RuleSet.decode(Data(json.utf8)) { _ in })
        }
    }

    func testUnsupportedMatchRiskAndModuleAreRejected() throws {
        for kind in ["glob", "file", "regex", "directory", "futureKind"] {
            var example = rule()
            example["match"] = ["kind": kind, "maxDepth": 2]
            XCTAssertThrowsError(try decode(document(rules: [example])))
        }
        for (field, value) in [("module", "futureModule"), ("risk", "safe"), ("risk", "Judgement")] {
            var example = rule()
            example[field] = value
            XCTAssertThrowsError(try decode(document(rules: [example])))
        }
    }

    func testDepthIsRequiredIntegralAndBounded() throws {
        for value: Any in [-1, 0, 33, 1_000_000, 1.5, "2", true, NSNull()] {
            var example = rule()
            example["match"] = ["kind": "directoryContents", "maxDepth": value]
            XCTAssertThrowsError(try decode(document(rules: [example])))
        }
        for depth in [1, 32] {
            var example = rule()
            example["match"] = ["kind": "directoryContents", "maxDepth": depth]
            XCTAssertNoThrow(try decode(document(rules: [example])))
        }
        var missingDepth = rule()
        missingDepth["match"] = ["kind": "directoryContents"]
        XCTAssertThrowsError(try decode(document(rules: [missingDepth])))
    }

    func testAgeConditionIsRequiredIntegralBoundedAndNotRepeated() throws {
        for value: Any in [-1, 0, 36_501, 1.5, "14", true, NSNull()] {
            var example = rule()
            example["conditions"] = [["olderThanDays": value]]
            XCTAssertThrowsError(try decode(document(rules: [example])))
        }
        for conditions: [[String: Any]] in [[], [["olderThanDays": 1]], [["olderThanDays": 36_500]]] {
            var example = rule()
            example["conditions"] = conditions
            XCTAssertNoThrow(try decode(document(rules: [example])))
        }
        for conditions: [[String: Any]] in [[[:]], [["olderThanDays": 14], ["olderThanDays": 30]]] {
            var example = rule()
            example["conditions"] = conditions
            XCTAssertThrowsError(try decode(document(rules: [example])))
        }
    }

    func testProducerAndPathListsRequireUniqueNonblankEntries() throws {
        for field in ["producers", "paths"] {
            for values in [[], [""], [" "], ["a", "a"], Array(repeating: "a", count: 65)] {
                var example = rule()
                example[field] = values
                XCTAssertThrowsError(try decode(document(rules: [example])))
            }
        }
    }

    func testCitationRequiresHTTPSAndRejectsCredentials() throws {
        for source in ["not a URL", "http://example.org/cache", "file:///tmp/cache", "https://", "https://user:secret@example.org/cache"] {
            var example = rule()
            example["citation"] = source
            XCTAssertThrowsError(try decode(document(rules: [example])))
        }
    }

    func testControlCharactersAndOversizedTextAreRejected() throws {
        for value in ["Reason\u{0000}after", "Reason\u{0008}after", String(repeating: "x", count: 4_097)] {
            var example = rule()
            example["reason"] = value
            XCTAssertThrowsError(try decode(document(rules: [example])))
        }
    }

    func testFlagNullsAndTypeCoercionAreRejected() throws {
        for field in ["verified", "enabled"] {
            for value: Any in [NSNull(), "true", 1] {
                var example = rule()
                example[field] = value
                XCTAssertThrowsError(try decode(document(rules: [example])))
            }
        }
    }

    func testUnsupportedOrMissingSchemaAndVersionAreRejected() throws {
        for value: Any in [0, 2, -1, "1", true, NSNull()] {
            var object = document(rules: [])
            object["schemaVersion"] = value
            XCTAssertThrowsError(try decode(object))
        }
        for version in ["", " ", "1", "1.0", "1.0.0.0", "1.0.0-beta", "01.0.0", "a.b.c"] {
            var object = document(rules: [])
            object["version"] = version
            XCTAssertThrowsError(try decode(object))
        }
        for field in ["schemaVersion", "version", "rules"] {
            var object = document(rules: [])
            object[field] = nil
            XCTAssertThrowsError(try decode(object))
        }
    }

    func testOversizedAndMalformedDocumentsAreRejected() throws {
        XCTAssertThrowsError(try RuleSet.decode(Data(repeating: 32, count: RuleSet.maximumDocumentBytes + 1)) { _ in }) { error in
            XCTAssertEqual(error as? RuleValidationError, .documentTooLarge)
        }
        for bytes in [Data(), Data("{not-json}".utf8), Data([0xFF, 0xFE]), Data("[]".utf8), Data("null".utf8)] {
            XCTAssertThrowsError(try RuleSet.decode(bytes) { _ in })
        }
        let tooMany = (0...RuleSet.maximumRuleCount).map { rule(id: "fixture.rule.\($0)") }
        XCTAssertThrowsError(try decode(document(rules: tooMany)))
    }

    func testRuleCodableRoundTripPreservesAllFields() throws {
        let loaded = try XCTUnwrap(decode(document(rules: [rule()])).rules.first)
        let roundTrip = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(loaded))
        XCTAssertEqual(loaded, roundTrip)
    }
}
