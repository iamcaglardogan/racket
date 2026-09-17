import Foundation

/// Reviewed presentation metadata for a rule. Producer identifiers must match
/// the complete rule producer set; neither this mapping nor its label is authority.
public struct CreativeCacheRuleMapping: Equatable, Sendable {
    public enum Scope: String, Sendable {
        case applicationWide
        case projectCache
    }

    public let ruleID: String
    public let producerIDs: [String]
    public let producerName: String
    public let scope: Scope

    public init(ruleID: String, producerIDs: [String], producerName: String, scope: Scope) {
        self.ruleID = ruleID
        self.producerIDs = producerIDs
        self.producerName = producerName
        self.scope = scope
    }
}

public struct CreativeCacheProject: Equatable, Sendable {
    /// An opaque vendor identifier, stable within the complete producer set.
    /// Preserve exact UTF-8 bytes; a title is never an identifier.
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        // Titles retain ordinary String equality; opaque IDs do not normalize.
        lhs.id.utf8.elementsEqual(rhs.id.utf8) && lhs.title == rhs.title
    }
}

/// Caller-supplied evidence for display. The grouping core does not discover or
/// verify vendor metadata, read a project, or turn an association into permission.
public struct CreativeCacheAssociationProvenance: Equatable, Sendable {
    public let sourceID: String
    public let detail: String

    public init(sourceID: String, detail: String) {
        self.sourceID = sourceID
        self.detail = detail
    }
}

/// A result supplied by a caller for an exact existing finding. Omission means
/// unknown. Ambiguity remains unknown even if a path happens to resemble a title.
public struct CreativeCacheProjectResolution: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case unknown
        case ambiguous(CreativeCacheAssociationProvenance)
        case associated(CreativeCacheProject, CreativeCacheAssociationProvenance)
    }

    /// Matched by exact UTF-8 bytes, without Unicode or filesystem normalization.
    public let resolvedPath: String
    public let ruleID: String
    public let outcome: Outcome

    public init(resolvedPath: String, ruleID: String, outcome: Outcome) {
        self.resolvedPath = resolvedPath
        self.ruleID = ruleID
        self.outcome = outcome
    }
}

public struct CreativeCacheGroup: Equatable, Sendable {
    public struct ID: Hashable, Sendable {
        public enum Scope: Hashable, Sendable {
            case applicationWide
            case unknownProject
            case project(String)

            public static func == (lhs: Self, rhs: Self) -> Bool {
                switch (lhs, rhs) {
                case (.applicationWide, .applicationWide), (.unknownProject, .unknownProject): true
                case (.project(let left), .project(let right)): left.utf8.elementsEqual(right.utf8)
                default: false
                }
            }

            public func hash(into hasher: inout Hasher) {
                // Canonically equivalent opaque vendor IDs can identify distinct
                // projects. Match equality's exact bytes and separate scope cases.
                switch self {
                case .applicationWide:
                    hasher.combine(0)
                case .unknownProject:
                    hasher.combine(1)
                case .project(let id):
                    hasher.combine(2)
                    hasher.combine(Data(id.utf8))
                }
            }
        }

        public let producerIDs: [String]
        public let scope: Scope
    }

    public enum Attribution: Equatable, Sendable {
        case applicationWide
        case unknownProject
        case project(CreativeCacheProject)
    }

    public let id: ID
    public let producerName: String
    public let attribution: Attribution
    /// The exact input values, including any internal live-scan observation.
    public let findings: [Finding]
    /// Retains supplied provenance per finding, including ambiguous resolutions.
    public let projectResolutions: [CreativeCacheProjectResolution]
    /// Observed allocated bytes, never an estimate of physical space reclaimed.
    public let reportedAllocatedBytes: UInt64
    /// Latest file modification time, not verified project or application activity.
    public let lastTouched: Date

    public var findingCount: Int { findings.count }

    /// Eligibility only. Mixed risks require individual review; this property
    /// does not select findings or authorize removal, regardless of attribution.
    public var isPreselectable: Bool {
        guard let risk = findings.first?.risk else { return false }
        return findings.allSatisfy { $0.risk == risk && $0.isPreselectable }
    }
}

public enum CreativeCacheGroupingError: Error, Equatable, Sendable {
    case resourceLimitExceeded
    case ruleSetVersionMismatch
    case missingRule(String)
    case inconsistentFinding(String)
    case duplicateFinding(String)
    case sizeOverflow
    case inconsistentReportTotal
    case missingRuleMapping(String)
    case invalidRuleMapping(String)
    case inconsistentProducerMetadata(String)
    case invalidProjectResolution(String)
    case duplicateProjectResolution(String)
    case applicationWideAssociation(String)
    case inconsistentProjectMetadata(String)
}

/// Pure, bounded grouping of a completed report. No filesystem access, project
/// inference, configuration discovery, selection, or removal occurs here.
public enum CreativeCacheGrouping {
    public static let maximumFindingCount = 100_000

    public static func group(
        report: ScanReport,
        ruleSet: RuleSet,
        ruleMappings: [CreativeCacheRuleMapping],
        projectResolutions: [CreativeCacheProjectResolution] = []
    ) throws -> [CreativeCacheGroup] {
        guard report.findings.count <= maximumFindingCount,
              ruleMappings.count <= RuleSet.maximumRuleCount,
              projectResolutions.count <= maximumFindingCount else {
            throw CreativeCacheGroupingError.resourceLimitExceeded
        }
        guard report.ruleSetVersion == ruleSet.version else {
            throw CreativeCacheGroupingError.ruleSetVersionMismatch
        }
        let rules = Dictionary(uniqueKeysWithValues: ruleSet.rules.map { ($0.id, $0) })
        let findings = try validate(report: report, rules: rules)
        let mappings = try validate(mappings: ruleMappings, rules: rules)
        let resolutions = try validate(resolutions: projectResolutions, findings: findings, mappings: mappings)
        var groups: [CreativeCacheGroup.ID: GroupBuilder] = [:]

        for finding in report.findings.filter({ $0.module == .creative }).sorted(by: findingBefore) {
            guard let mapping = mappings[finding.ruleID] else {
                throw CreativeCacheGroupingError.missingRuleMapping(finding.ruleID)
            }
            let resolution = resolutions[Data(finding.resolvedPath.utf8)]
            let attribution: CreativeCacheGroup.Attribution
            let scope: CreativeCacheGroup.ID.Scope
            switch (mapping.scope, resolution?.outcome) {
            case (.applicationWide, _):
                attribution = .applicationWide
                scope = .applicationWide
            case (.projectCache, .associated(let project, _)):
                attribution = .project(project)
                scope = .project(project.id)
            default:
                attribution = .unknownProject
                scope = .unknownProject
            }
            let id = CreativeCacheGroup.ID(producerIDs: mapping.producerIDs.sorted(by: before), scope: scope)
            if let existingAttribution = groups[id]?.attribution, existingAttribution != attribution {
                throw CreativeCacheGroupingError.inconsistentProjectMetadata(finding.resolvedPath)
            }
            try groups[id, default: GroupBuilder(
                id: id, producerName: mapping.producerName, attribution: attribution
            )].append(finding, resolution: resolution)
        }
        return groups.values.map { $0.finish() }.sorted { idBefore($0.id, $1.id) }
    }

    private static func validate(report: ScanReport, rules: [String: Rule]) throws -> [Data: Finding] {
        var findings: [Data: Finding] = [:]
        var identities = Set<ScanFileIdentity>()
        var total: UInt64 = 0
        // Check the entire report before ignoring other modules. Malformed or
        // duplicated observations cannot silently distort the creative view.
        for finding in report.findings {
            guard let rule = rules[finding.ruleID] else {
                throw CreativeCacheGroupingError.missingRule(finding.ruleID)
            }
            guard rule.enabled, rule.verified, finding.module == rule.module,
                  finding.risk == rule.risk, finding.reason == rule.reason,
                  finding.regenerationCost == rule.regenerationCost,
                  finding.requiredClosedProducers == (rule.requiresClosedApplications ? rule.producers.sorted() : []),
                  finding.modifiedAt.timeIntervalSinceReferenceDate.isFinite,
                  finding.resolvedPath.hasPrefix("/"), validText(finding.resolvedPath, maximumBytes: 4_096) else {
                throw CreativeCacheGroupingError.inconsistentFinding(finding.resolvedPath)
            }
            // Swift String equality folds canonical Unicode equivalents. A path
            // association must instead match the exact observed path bytes.
            let path = Data(finding.resolvedPath.utf8)
            guard findings.updateValue(finding, forKey: path) == nil else {
                throw CreativeCacheGroupingError.duplicateFinding(finding.resolvedPath)
            }
            if let observation = finding.observation,
               !identities.insert(observation.identity).inserted {
                throw CreativeCacheGroupingError.duplicateFinding(finding.resolvedPath)
            }
            let (sum, overflow) = total.addingReportingOverflow(finding.allocatedSize)
            guard !overflow else { throw CreativeCacheGroupingError.sizeOverflow }
            total = sum
        }
        guard total == report.reportedAllocatedBytes else {
            throw CreativeCacheGroupingError.inconsistentReportTotal
        }
        return findings
    }

    private static func validate(
        mappings: [CreativeCacheRuleMapping], rules: [String: Rule]
    ) throws -> [String: CreativeCacheRuleMapping] {
        var result: [String: CreativeCacheRuleMapping] = [:]
        var producerNames: [[String]: String] = [:]
        for mapping in mappings {
            guard validText(mapping.ruleID, maximumBytes: 256),
                  (1...64).contains(mapping.producerIDs.count),
                  mapping.producerIDs.allSatisfy({ validText($0, maximumBytes: 256) }),
                  let rule = rules[mapping.ruleID], rule.module == .creative,
                  Set(mapping.producerIDs).count == mapping.producerIDs.count,
                  Set(mapping.producerIDs) == Set(rule.producers),
                  validText(mapping.producerName, maximumBytes: 512),
                  result.updateValue(mapping, forKey: mapping.ruleID) == nil else {
                throw CreativeCacheGroupingError.invalidRuleMapping(mapping.ruleID)
            }
            let ids = mapping.producerIDs.sorted(by: before)
            if let name = producerNames[ids], name != mapping.producerName {
                throw CreativeCacheGroupingError.inconsistentProducerMetadata(mapping.ruleID)
            }
            producerNames[ids] = mapping.producerName
        }
        return result
    }

    private static func validate(
        resolutions: [CreativeCacheProjectResolution], findings: [Data: Finding],
        mappings: [String: CreativeCacheRuleMapping]
    ) throws -> [Data: CreativeCacheProjectResolution] {
        var result: [Data: CreativeCacheProjectResolution] = [:]
        for resolution in resolutions {
            guard validText(resolution.resolvedPath, maximumBytes: 4_096),
                  validText(resolution.ruleID, maximumBytes: 256) else {
                throw CreativeCacheGroupingError.invalidProjectResolution(resolution.resolvedPath)
            }
            let path = Data(resolution.resolvedPath.utf8)
            guard let finding = findings[path], finding.ruleID == resolution.ruleID,
                  finding.module == .creative, let mapping = mappings[finding.ruleID] else {
                throw CreativeCacheGroupingError.invalidProjectResolution(resolution.resolvedPath)
            }
            guard mapping.scope == .projectCache else {
                throw CreativeCacheGroupingError.applicationWideAssociation(resolution.resolvedPath)
            }
            guard result.updateValue(resolution, forKey: path) == nil else {
                throw CreativeCacheGroupingError.duplicateProjectResolution(resolution.resolvedPath)
            }
            switch resolution.outcome {
            case .unknown:
                break
            case .ambiguous(let provenance):
                guard valid(provenance) else {
                    throw CreativeCacheGroupingError.invalidProjectResolution(resolution.resolvedPath)
                }
            case .associated(let project, let provenance):
                guard validText(project.id, maximumBytes: 256), validText(project.title, maximumBytes: 512),
                      valid(provenance) else {
                    throw CreativeCacheGroupingError.invalidProjectResolution(resolution.resolvedPath)
                }
            }
        }
        return result
    }

    private static func valid(_ provenance: CreativeCacheAssociationProvenance) -> Bool {
        validText(provenance.sourceID, maximumBytes: 256) && validText(provenance.detail, maximumBytes: 1_024)
    }

    private static func validText(_ text: String, maximumBytes: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= maximumBytes
            && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func before(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    private static func findingBefore(_ lhs: Finding, _ rhs: Finding) -> Bool {
        before(lhs.resolvedPath, rhs.resolvedPath)
    }

    private static func idBefore(_ lhs: CreativeCacheGroup.ID, _ rhs: CreativeCacheGroup.ID) -> Bool {
        if lhs.producerIDs != rhs.producerIDs {
            return lhs.producerIDs.lexicographicallyPrecedes(rhs.producerIDs, by: before)
        }
        func order(_ scope: CreativeCacheGroup.ID.Scope) -> (Int, String) {
            switch scope {
            case .applicationWide: (0, "")
            case .unknownProject: (1, "")
            case .project(let id): (2, id)
            }
        }
        let left = order(lhs.scope), right = order(rhs.scope)
        return left.0 == right.0 ? before(left.1, right.1) : left.0 < right.0
    }
}

private struct GroupBuilder {
    let id: CreativeCacheGroup.ID
    let producerName: String
    let attribution: CreativeCacheGroup.Attribution
    var findings: [Finding] = []
    var resolutions: [CreativeCacheProjectResolution] = []
    var bytes: UInt64 = 0
    var lastTouched = Date.distantPast

    mutating func append(_ finding: Finding, resolution: CreativeCacheProjectResolution?) throws {
        let (sum, overflow) = bytes.addingReportingOverflow(finding.allocatedSize)
        guard !overflow else { throw CreativeCacheGroupingError.sizeOverflow }
        bytes = sum
        // Keep the original finding. Reconstructing it would discard its internal
        // observation and break later removal-boundary revalidation.
        findings.append(finding)
        if let resolution { resolutions.append(resolution) }
        lastTouched = findings.count == 1 ? finding.modifiedAt : max(lastTouched, finding.modifiedAt)
    }

    func finish() -> CreativeCacheGroup {
        CreativeCacheGroup(
            id: id, producerName: producerName, attribution: attribution, findings: findings,
            projectResolutions: resolutions, reportedAllocatedBytes: bytes, lastTouched: lastTouched
        )
    }
}
