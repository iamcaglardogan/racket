import Darwin
import Foundation
import XCTest
@testable import RacketCore

/// All inputs are in-memory fixtures. Paths are inert labels; no host file,
/// vendor configuration, installed application, or project is accessed.
final class CreativeCacheGroupingTests: XCTestCase {
    private let provenance = CreativeCacheAssociationProvenance(
        sourceID: "fixture.explicit-association", detail: "Synthetic supplied association, not vendor discovery."
    )

    private func rule(
        _ id: String = "fixture.project", module: String = "creative",
        producers: [String] = ["org.example.Editor"], risk: String = "regenerable",
        enabled: Bool = true, requiresClosedApplications: Bool = false
    ) -> [String: Any] {
        [
            "id": id, "title": "Synthetic cache", "module": module, "producers": producers,
            "paths": ["~/Library/Caches/Fixture"], "match": ["kind": "directoryContents", "maxDepth": 4],
            "conditions": [], "risk": risk, "reason": "Synthetic reason for " + id,
            "regenerationCost": "Synthetic regeneration for " + id,
            "citation": "https://example.invalid/fixture", "enabled": enabled, "verified": true,
            "requiresClosedApplications": requiresClosedApplications
        ]
    }

    private func ruleSet(_ values: [[String: Any]]) throws -> RuleSet {
        let bytes = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "version": "1.0.0", "rules": values])
        return try RuleSet.decode(bytes) { _ in }
    }

    private func finding(
        _ path: String = "/synthetic/Film/cache.bin", rule: Rule,
        bytes: UInt64 = 4_096, timestamp: Double = 1_700_000_000,
        observation: ScanMetadataFingerprint? = nil
    ) -> Finding {
        Finding(
            resolvedPath: path, allocatedSize: bytes, modifiedAt: Date(timeIntervalSince1970: timestamp),
            ruleID: rule.id, module: rule.module, risk: rule.risk, reason: rule.reason,
            regenerationCost: rule.regenerationCost, observation: observation,
            requiredClosedProducers: rule.requiresClosedApplications ? rule.producers.sorted() : []
        )
    }

    private func report(_ findings: [Finding], total: UInt64? = nil, version: String = "1.0.0") -> ScanReport {
        ScanReport(
            ruleSetVersion: version, findings: findings, issues: [],
            reportedAllocatedBytes: total ?? findings.reduce(0) { $0 &+ $1.allocatedSize },
            visitedEntryCount: UInt64(findings.count)
        )
    }

    private func mapping(
        _ rule: Rule, name: String = "Synthetic editor", scope: CreativeCacheRuleMapping.Scope = .projectCache
    ) -> CreativeCacheRuleMapping {
        CreativeCacheRuleMapping(ruleID: rule.id, producerIDs: rule.producers, producerName: name, scope: scope)
    }

    private func resolution(_ finding: Finding, id: String, title: String = "Film") -> CreativeCacheProjectResolution {
        CreativeCacheProjectResolution(
            resolvedPath: finding.resolvedPath, ruleID: finding.ruleID,
            outcome: .associated(CreativeCacheProject(id: id, title: title), provenance)
        )
    }

    func testMissingAndAmbiguousAssociationsStayUnknownDespiteProjectLikePaths() throws {
        let rules = try ruleSet([rule()])
        let first = finding("/synthetic/Film/ProjectA/ProjectA.aep.cache", rule: rules.rules[0])
        let second = finding("/synthetic/Film/ProjectB/ProjectB.aep.cache", rule: rules.rules[0])
        let ambiguous = CreativeCacheProjectResolution(
            resolvedPath: second.resolvedPath, ruleID: second.ruleID, outcome: .ambiguous(provenance)
        )
        let groups = try CreativeCacheGrouping.group(
            report: report([second, first]), ruleSet: rules,
            ruleMappings: [mapping(rules.rules[0])], projectResolutions: [ambiguous]
        )
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(group.attribution, .unknownProject)
        XCTAssertEqual(group.id.scope, .unknownProject)
        XCTAssertEqual(group.findings, [first, second])
        XCTAssertEqual(group.projectResolutions, [ambiguous])
    }

    func testApplicationWideMultiProducerCacheHasSeparateIdentityAndRefusesProjectAssociation() throws {
        let producers = ["org.example.Editor", "org.example.Compositor"]
        let rules = try ruleSet([rule("fixture.shared", producers: producers), rule(producers: producers)])
        let shared = finding("/synthetic/shared", rule: rules.rules[0])
        let unknown = finding("/synthetic/project", rule: rules.rules[1])
        let maps = [mapping(rules.rules[0], scope: .applicationWide), mapping(rules.rules[1])]
        let groups = try CreativeCacheGrouping.group(report: report([unknown, shared]), ruleSet: rules, ruleMappings: maps)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].attribution, .applicationWide)
        XCTAssertEqual(groups[1].attribution, .unknownProject)
        XCTAssertEqual(groups[0].id.producerIDs, producers.sorted())
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([shared]), ruleSet: rules, ruleMappings: maps,
            projectResolutions: [resolution(shared, id: "film-1")]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .applicationWideAssociation(shared.resolvedPath)) }
    }

    func testSameProjectTitleKeepsDifferentProjectAndProducerIdentities() throws {
        let rules = try ruleSet([
            rule("fixture.a", producers: ["org.example.A"]),
            rule("fixture.b", producers: ["org.example.B"])
        ])
        let first = finding("/synthetic/a", rule: rules.rules[0])
        let second = finding("/synthetic/b", rule: rules.rules[0])
        let third = finding("/synthetic/c", rule: rules.rules[1])
        let groups = try CreativeCacheGrouping.group(
            report: report([third, second, first]), ruleSet: rules,
            ruleMappings: rules.rules.map { mapping($0) },
            projectResolutions: [resolution(third, id: "project-1"), resolution(second, id: "project-2"), resolution(first, id: "project-1")]
        )
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(Set(groups.map(\.id)).count, 3)
        XCTAssertEqual(groups.map(\.findings), [[first], [second], [third]])
        XCTAssertTrue(groups.allSatisfy { group in
            guard case .project(let project) = group.attribution else { return false }
            return project.title == "Film"
        })
    }

    func testStructuredIdentityDoesNotCollideWhenIdentifiersContainSeparators() throws {
        let rules = try ruleSet([
            rule("fixture.a", producers: ["vendor|project"]),
            rule("fixture.b", producers: ["vendor"])
        ])
        let first = finding("/synthetic/a", rule: rules.rules[0])
        let second = finding("/synthetic/b", rule: rules.rules[1])
        let groups = try CreativeCacheGrouping.group(
            report: report([first, second]), ruleSet: rules, ruleMappings: rules.rules.map { mapping($0) },
            projectResolutions: [resolution(first, id: "one"), resolution(second, id: "project|one")]
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertNotEqual(groups[0].id, groups[1].id)
    }

    func testCanonicallyEquivalentOpaqueProjectIDsStayDistinctAcrossInputOrder() throws {
        let rules = try ruleSet([rule()])
        let first = finding("/synthetic/a", rule: rules.rules[0], bytes: 4_096)
        let second = finding("/synthetic/b", rule: rules.rules[0], bytes: 8_192)
        let composedID = "caf\u{00E9}"
        let decomposedID = "cafe\u{0301}"
        XCTAssertEqual(composedID, decomposedID)
        XCTAssertNotEqual(Data(composedID.utf8), Data(decomposedID.utf8))
        XCTAssertNotEqual(CreativeCacheProject(id: composedID, title: "Film"),
                          CreativeCacheProject(id: decomposedID, title: "Film"))
        let associations = [resolution(first, id: composedID), resolution(second, id: decomposedID)]
        let groups = try CreativeCacheGrouping.group(
            report: report([first, second]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
            projectResolutions: associations
        )
        let reversed = try CreativeCacheGrouping.group(
            report: report([second, first]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
            projectResolutions: associations.reversed()
        )
        XCTAssertEqual(groups, reversed)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.id)).count, 2)
        let expectedIDs = [Data(decomposedID.utf8), Data(composedID.utf8)]
        XCTAssertEqual(groups.compactMap { group -> Data? in
            guard case .project(let id) = group.id.scope else { return nil }
            return Data(id.utf8)
        }, expectedIDs)
        XCTAssertEqual(groups.compactMap { group -> Data? in
            guard case .project(let project) = group.attribution else { return nil }
            return Data(project.id.utf8)
        }, expectedIDs)
        XCTAssertEqual(groups.map(\.findings), [[second], [first]])
        XCTAssertEqual(groups.map(\.reportedAllocatedBytes), [8_192, 4_096])
        XCTAssertEqual(groups.map(\.projectResolutions), [[associations[1]], [associations[0]]])
    }

    func testCanonicallyEquivalentUnicodePathsRemainByteExactAndDistinct() throws {
        let rules = try ruleSet([rule()])
        let composed = finding("/synthetic/Caf\u{00E9}/cache.bin", rule: rules.rules[0], bytes: 4_096)
        let decomposed = finding("/synthetic/Cafe\u{0301}/cache.bin", rule: rules.rules[0], bytes: 8_192)
        // This is the trap: Swift String equality is not filesystem-path identity.
        XCTAssertEqual(composed.resolvedPath, decomposed.resolvedPath)
        XCTAssertNotEqual(Data(composed.resolvedPath.utf8), Data(decomposed.resolvedPath.utf8))
        let associations = [resolution(composed, id: "composed"), resolution(decomposed, id: "decomposed")]
        let groups = try CreativeCacheGrouping.group(
            report: report([composed, decomposed]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
            projectResolutions: associations.reversed()
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.id.scope), [.project("composed"), .project("decomposed")])
        XCTAssertEqual(groups.map(\.reportedAllocatedBytes), [4_096, 8_192])
        XCTAssertEqual(groups.flatMap(\.findings).map { Data($0.resolvedPath.utf8) },
                       [Data(composed.resolvedPath.utf8), Data(decomposed.resolvedPath.utf8)])
        XCTAssertEqual(groups.flatMap(\.projectResolutions).map { Data($0.resolvedPath.utf8) },
                       associations.map { Data($0.resolvedPath.utf8) })

        let unknown = try XCTUnwrap(CreativeCacheGrouping.group(
            report: report([composed, decomposed]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])]
        ).first)
        XCTAssertEqual(unknown.findingCount, 2)
        XCTAssertEqual(unknown.reportedAllocatedBytes, 12_288)
        XCTAssertEqual(unknown.findings.map { Data($0.resolvedPath.utf8) },
                       [Data(decomposed.resolvedPath.utf8), Data(composed.resolvedPath.utf8)])
    }

    func testCanonicallyEquivalentPathCannotResolveAnotherFinding() throws {
        let rules = try ruleSet([rule()])
        let composed = finding("/synthetic/Caf\u{00E9}/cache.bin", rule: rules.rules[0])
        let decomposed = finding("/synthetic/Cafe\u{0301}/cache.bin", rule: rules.rules[0])
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([composed]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
            projectResolutions: [resolution(decomposed, id: "incorrect-path")]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .invalidProjectResolution(decomposed.resolvedPath)) }
    }

    func testOriginalObservationAndExplicitProvenanceSurviveGrouping() throws {
        let rules = try ruleSet([rule()])
        var metadata = stat()
        metadata.st_dev = 12
        metadata.st_ino = 345
        metadata.st_gen = 6
        metadata.st_mode = UInt16(S_IFREG | 0o600)
        metadata.st_nlink = 1
        metadata.st_uid = 501
        metadata.st_gid = 20
        metadata.st_birthtimespec = timespec(tv_sec: 1_600_000_000, tv_nsec: 123)
        metadata.st_mtimespec = timespec(tv_sec: 1_700_000_000, tv_nsec: 456)
        metadata.st_ctimespec = timespec(tv_sec: 1_700_000_001, tv_nsec: 789)
        let observation = ScanMetadataFingerprint(metadata)
        let original = finding(rule: rules.rules[0], observation: observation)
        let association = resolution(original, id: "project.stable-123")
        let group = try XCTUnwrap(CreativeCacheGrouping.group(
            report: report([original]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
            projectResolutions: [association]
        ).first)
        XCTAssertEqual(group.findings, [original])
        XCTAssertEqual(group.findings[0].observation, observation)
        XCTAssertEqual(group.projectResolutions, [association])
        XCTAssertEqual(group.attribution, .project(CreativeCacheProject(id: "project.stable-123", title: "Film")))
        let synthetic = finding("/synthetic/unobserved", rule: rules.rules[0])
        let unobserved = try XCTUnwrap(CreativeCacheGrouping.group(
            report: report([synthetic]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])]
        ).first)
        XCTAssertNil(unobserved.findings[0].observation)
    }

    func testRequiredClosedProducerSetIsRetainedAndCannotBeStrippedOrChanged() throws {
        let producers = ["org.example.Editor", "org.example.Compositor"]
        let rules = try ruleSet([rule(producers: producers, requiresClosedApplications: true)])
        let original = finding(rule: rules.rules[0])
        let group = try XCTUnwrap(CreativeCacheGrouping.group(
            report: report([original]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])]
        ).first)
        XCTAssertEqual(group.findings[0].requiredClosedProducers, producers.sorted())
        for required in [[], [producers[0]], ["org.example.Other"]] {
            let changed = Finding(
                resolvedPath: original.resolvedPath, allocatedSize: original.allocatedSize,
                modifiedAt: original.modifiedAt, ruleID: original.ruleID, module: original.module,
                risk: original.risk, reason: original.reason, regenerationCost: original.regenerationCost,
                requiredClosedProducers: required
            )
            XCTAssertThrowsError(try CreativeCacheGrouping.group(
                report: report([changed]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])]
            )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .inconsistentFinding(changed.resolvedPath)) }
        }
        let changedRules = try ruleSet([rule(producers: producers, requiresClosedApplications: false)])
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([original]), ruleSet: changedRules, ruleMappings: [mapping(changedRules.rules[0])]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .inconsistentFinding(original.resolvedPath)) }
    }

    func testTotalsLastTouchedAndOrderAreDeterministicAcrossInputPermutations() throws {
        let rules = try ruleSet([rule()])
        let first = finding("/synthetic/a", rule: rules.rules[0], bytes: 0, timestamp: 10)
        let second = finding("/synthetic/b", rule: rules.rules[0], bytes: 8_192, timestamp: 30)
        let third = finding("/synthetic/c", rule: rules.rules[0], bytes: 4_096, timestamp: 20)
        let resolutions = [resolution(first, id: "same"), resolution(second, id: "same"), resolution(third, id: "same")]
        let one = try CreativeCacheGrouping.group(
            report: report([third, first, second]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
            projectResolutions: resolutions.reversed()
        )
        let two = try CreativeCacheGrouping.group(
            report: report([second, third, first]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
            projectResolutions: resolutions
        )
        XCTAssertEqual(one, two)
        XCTAssertEqual(one[0].reportedAllocatedBytes, 12_288)
        XCTAssertEqual(one[0].lastTouched, second.modifiedAt)
        XCTAssertEqual(one[0].findingCount, 3)
        XCTAssertEqual(one[0].findings, [first, second, third])
        XCTAssertTrue(one[0].isPreselectable)
    }

    func testMixedRisksAndJudgementAreNeverMadePreselectableByProjectLabel() throws {
        let rules = try ruleSet([rule("fixture.a"), rule("fixture.b", risk: "stale"), rule("fixture.c", risk: "judgement")])
        let values = rules.rules.enumerated().map { finding("/synthetic/\($0.offset)", rule: $0.element) }
        let groups = try CreativeCacheGrouping.group(
            report: report(values), ruleSet: rules, ruleMappings: rules.rules.map { mapping($0) },
            projectResolutions: values.map { resolution($0, id: $0.risk == .judgement ? "judgement" : "mixed") }
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { !$0.isPreselectable })
        XCTAssertEqual(groups.flatMap(\.findings).filter { $0.risk == .judgement }.count, 1)
    }

    func testUnrelatedModuleIsValidatedThenExcludedWithoutRequiringCreativeMapping() throws {
        let rules = try ruleSet([rule(), rule("fixture.developer", module: "developer")])
        let creative = finding("/synthetic/creative", rule: rules.rules[0], bytes: 4_096)
        let developer = finding("/synthetic/developer", rule: rules.rules[1], bytes: 8_192)
        let groups = try CreativeCacheGrouping.group(
            report: report([creative, developer]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])]
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].findings, [creative])
        XCTAssertEqual(groups[0].reportedAllocatedBytes, 4_096)
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([creative, developer, developer]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .duplicateFinding(developer.resolvedPath)) }
    }

    func testOverflowFailsEntireGroupingEvenAcrossDifferentGroups() throws {
        let rules = try ruleSet([rule()])
        let maximum = finding("/synthetic/a", rule: rules.rules[0], bytes: .max)
        let extra = finding("/synthetic/b", rule: rules.rules[0], bytes: 1)
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([maximum, extra], total: 0), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
            projectResolutions: [resolution(maximum, id: "a"), resolution(extra, id: "b")]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .sizeOverflow) }
        let group = try XCTUnwrap(CreativeCacheGrouping.group(
            report: report([maximum]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])]
        ).first)
        XCTAssertEqual(group.reportedAllocatedBytes, .max)
    }

    func testDuplicatePathsAndObservedFileIdentitiesAreRefused() throws {
        let rules = try ruleSet([rule()])
        var metadata = stat()
        metadata.st_dev = 1
        metadata.st_ino = 2
        let first = finding("/synthetic/a", rule: rules.rules[0], observation: ScanMetadataFingerprint(metadata))
        let alias = finding("/synthetic/b", rule: rules.rules[0], observation: ScanMetadataFingerprint(metadata))
        for values in [[first, first], [first, alias]] {
            XCTAssertThrowsError(try CreativeCacheGrouping.group(
                report: report(values), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])]
            )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .duplicateFinding(values[1].resolvedPath)) }
        }
    }

    func testMissingRulesMappingsAndIncorrectProducerMappingsAreRefused() throws {
        let rules = try ruleSet([rule(producers: ["org.example.A", "org.example.B"])])
        let value = finding(rule: rules.rules[0])
        let empty = try ruleSet([])
        XCTAssertThrowsError(try CreativeCacheGrouping.group(report: report([value]), ruleSet: empty, ruleMappings: [])) {
            XCTAssertEqual($0 as? CreativeCacheGroupingError, .missingRule(value.ruleID))
        }
        XCTAssertThrowsError(try CreativeCacheGrouping.group(report: report([value]), ruleSet: rules, ruleMappings: [])) {
            XCTAssertEqual($0 as? CreativeCacheGroupingError, .missingRuleMapping(value.ruleID))
        }
        let incomplete = CreativeCacheRuleMapping(
            ruleID: value.ruleID, producerIDs: ["org.example.A"], producerName: "Only A", scope: .applicationWide
        )
        XCTAssertThrowsError(try CreativeCacheGrouping.group(report: report([value]), ruleSet: rules, ruleMappings: [incomplete])) {
            XCTAssertEqual($0 as? CreativeCacheGroupingError, .invalidRuleMapping(value.ruleID))
        }
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([value]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0]), mapping(rules.rules[0])]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .invalidRuleMapping(value.ruleID)) }
    }

    func testProducerOrderDoesNotAffectIdentityButConflictingProducerNamesAreRefused() throws {
        let rules = try ruleSet([
            rule("fixture.a", producers: ["org.example.A", "org.example.B"]),
            rule("fixture.b", producers: ["org.example.B", "org.example.A"])
        ])
        let values = rules.rules.enumerated().map { finding("/synthetic/\($0.offset)", rule: $0.element) }
        let groups = try CreativeCacheGrouping.group(
            report: report(values), ruleSet: rules, ruleMappings: rules.rules.map { mapping($0) }
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].findingCount, 2)
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report(values), ruleSet: rules,
            ruleMappings: [mapping(rules.rules[0]), mapping(rules.rules[1], name: "Conflicting name")]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .inconsistentProducerMetadata("fixture.b")) }
    }

    func testConflictingProjectTitlesAndDuplicateOrUnmatchedResolutionsAreRefused() throws {
        let rules = try ruleSet([rule()])
        let first = finding("/synthetic/a", rule: rules.rules[0])
        let second = finding("/synthetic/b", rule: rules.rules[0])
        let firstResolution = resolution(first, id: "same")
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([first, second]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
            projectResolutions: [firstResolution, resolution(second, id: "same", title: "Conflicting title")]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .inconsistentProjectMetadata(second.resolvedPath)) }
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([first]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
            projectResolutions: [firstResolution, firstResolution]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .duplicateProjectResolution(first.resolvedPath)) }
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([first]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
            projectResolutions: [resolution(second, id: "same")]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .invalidProjectResolution(second.resolvedPath)) }
    }

    func testInvalidProjectMetadataAndProvenanceAreRefused() throws {
        let rules = try ruleSet([rule()])
        let value = finding(rule: rules.rules[0])
        let emptySource = CreativeCacheAssociationProvenance(sourceID: " ", detail: "Supplied evidence")
        let invalidDetail = CreativeCacheAssociationProvenance(sourceID: "fixture", detail: "NUL\u{0000}detail")
        let outcomes: [CreativeCacheProjectResolution.Outcome] = [
            .associated(CreativeCacheProject(id: "", title: "Film"), provenance),
            .associated(CreativeCacheProject(id: "stable", title: "\n"), provenance),
            .associated(CreativeCacheProject(id: "stable", title: "Film"), emptySource),
            .ambiguous(invalidDetail)
        ]
        for outcome in outcomes {
            let invalid = CreativeCacheProjectResolution(
                resolvedPath: value.resolvedPath, ruleID: value.ruleID, outcome: outcome
            )
            XCTAssertThrowsError(try CreativeCacheGrouping.group(
                report: report([value]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
                projectResolutions: [invalid]
            )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .invalidProjectResolution(value.resolvedPath)) }
        }
        let wrongRule = CreativeCacheProjectResolution(
            resolvedPath: value.resolvedPath, ruleID: "fixture.other-rule", outcome: .unknown
        )
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([value]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])],
            projectResolutions: [wrongRule]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .invalidProjectResolution(value.resolvedPath)) }
    }

    func testMismatchedRuleExplanationDisabledRuleInvalidDateAndStaleReportAreRefused() throws {
        let rules = try ruleSet([rule()])
        let value = finding(rule: rules.rules[0])
        let changed = Finding(
            resolvedPath: value.resolvedPath, allocatedSize: value.allocatedSize, modifiedAt: value.modifiedAt,
            ruleID: value.ruleID, module: value.module, risk: .judgement, reason: "Different explanation",
            regenerationCost: value.regenerationCost
        )
        for invalid in [changed] + [Double.nan, .infinity, -.infinity].map({ finding(rule: rules.rules[0], timestamp: $0) }) {
            XCTAssertThrowsError(try CreativeCacheGrouping.group(
                report: report([invalid]), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])]
            )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .inconsistentFinding(invalid.resolvedPath)) }
        }
        let disabled = try ruleSet([rule(enabled: false)])
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([value]), ruleSet: disabled, ruleMappings: [mapping(disabled.rules[0])]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .inconsistentFinding(value.resolvedPath)) }
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([value], version: "0.9.0"), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .ruleSetVersionMismatch) }
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report([value], total: 0), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .inconsistentReportTotal) }
    }

    func testEmptyReportAndBoundedInput() throws {
        let rules = try ruleSet([rule()])
        XCTAssertTrue(try CreativeCacheGrouping.group(report: report([]), ruleSet: rules, ruleMappings: []).isEmpty)
        let values = Array(repeating: finding(rule: rules.rules[0]), count: CreativeCacheGrouping.maximumFindingCount + 1)
        XCTAssertThrowsError(try CreativeCacheGrouping.group(
            report: report(values), ruleSet: rules, ruleMappings: [mapping(rules.rules[0])]
        )) { XCTAssertEqual($0 as? CreativeCacheGroupingError, .resourceLimitExceeded) }
    }
}
