import Foundation

/// Human-readable matching data, never authority to access or remove a path.
public struct Rule: Codable, Equatable, Sendable {
    public enum Module: String, Codable, Sendable {
        case creative
        case developer
        case system
        case uninstaller
    }

    public enum Risk: String, Codable, Sendable, CaseIterable {
        case regenerable
        case recreatable
        case stale
        case judgement
    }

    public struct Match: Codable, Equatable, Sendable {
        /// Additional matching modes need their own review and schema support.
        public enum Kind: String, Codable, Sendable {
            case directoryContents
        }

        public let kind: Kind
        public let maxDepth: Int

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case kind, maxDepth
        }

        public init(from decoder: any Decoder) throws {
            try rejectUnknownRuleFields(decoder, allowed: CodingKeys.allCases)
            let values = try decoder.container(keyedBy: CodingKeys.self)
            kind = try values.decode(Kind.self, forKey: .kind)
            maxDepth = try values.decode(Int.self, forKey: .maxDepth)
            guard (1...32).contains(maxDepth) else {
                throw RuleValidationError.invalidField("match.maxDepth", "Must be between 1 and 32.")
            }
        }
    }

    public struct Condition: Codable, Equatable, Sendable {
        public let olderThanDays: Int

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case olderThanDays
        }

        public init(from decoder: any Decoder) throws {
            try rejectUnknownRuleFields(decoder, allowed: CodingKeys.allCases)
            let values = try decoder.container(keyedBy: CodingKeys.self)
            olderThanDays = try values.decode(Int.self, forKey: .olderThanDays)
            guard (1...36_500).contains(olderThanDays) else {
                throw RuleValidationError.invalidField("conditions.olderThanDays", "Must be between 1 and 36,500.")
            }
        }
    }

    public let id: String
    public let module: Module
    public let title: String
    public let producers: [String]
    public let paths: [String]
    public let match: Match
    public let conditions: [Condition]
    public let risk: Risk
    public let reason: String
    public let regenerationCost: String
    public let citation: String
    public let verified: Bool
    public let enabled: Bool
    public let skipExcludedFromBackup: Bool

    /// Eligibility only; this is not user approval or a removal capability.
    /// Judgement data is ineligible even when its rule is verified and enabled.
    public var isPreselectable: Bool {
        enabled && verified && risk != .judgement
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, module, title, producers, paths, match, conditions, risk
        case reason, regenerationCost, citation, verified, enabled, skipExcludedFromBackup
    }

    public init(from decoder: any Decoder) throws {
        try rejectUnknownRuleFields(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        module = try values.decode(Module.self, forKey: .module)
        title = try values.decode(String.self, forKey: .title)
        producers = try values.decode([String].self, forKey: .producers)
        paths = try values.decode([String].self, forKey: .paths)
        match = try values.decode(Match.self, forKey: .match)
        conditions = try values.decode([Condition].self, forKey: .conditions)
        risk = try values.decode(Risk.self, forKey: .risk)
        reason = try values.decode(String.self, forKey: .reason)
        regenerationCost = try values.decode(String.self, forKey: .regenerationCost)
        citation = try values.decode(String.self, forKey: .citation)
        // Missing flags default to the most conservative state. Explicit nulls
        // and non-boolean flags are malformed, rather than another spelling of false.
        verified = values.contains(.verified) ? try values.decode(Bool.self, forKey: .verified) : false
        enabled = values.contains(.enabled) ? try values.decode(Bool.self, forKey: .enabled) : false
        skipExcludedFromBackup = values.contains(.skipExcludedFromBackup)
            ? try values.decode(Bool.self, forKey: .skipExcludedFromBackup) : false

        try requireRuleText(id, field: "id", maximumBytes: 256)
        let identifierCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard id.unicodeScalars.allSatisfy(identifierCharacters.contains) else {
            throw RuleValidationError.invalidField("id", "Use only ASCII letters, numbers, dots, underscores, and hyphens.")
        }
        try requireRuleText(title, field: "title", maximumBytes: 512)
        try requireRuleText(reason, field: "reason")
        try requireRuleText(regenerationCost, field: "regenerationCost")
        try requireRuleText(citation, field: "citation", maximumBytes: 2_048)
        guard let source = URLComponents(string: citation),
              source.scheme == "https", let host = source.host, !host.isEmpty,
              source.user == nil, source.password == nil else {
            throw RuleValidationError.invalidField("citation", "Provide an HTTPS source URL without credentials.")
        }

        try Self.validateStrings(producers, field: "producers", maximumCount: 64, maximumBytes: 256)
        try Self.validateStrings(paths, field: "paths", maximumCount: 64, maximumBytes: 4_096)
        guard conditions.count <= 1 else {
            throw RuleValidationError.invalidField("conditions", "This schema supports at most one olderThanDays condition.")
        }
        guard !enabled || verified else {
            throw RuleValidationError.invalidField("enabled", "An unverified rule cannot be enabled.")
        }
    }

    private static func validateStrings(
        _ values: [String], field: String, maximumCount: Int, maximumBytes: Int
    ) throws {
        guard !values.isEmpty, values.count <= maximumCount else {
            throw RuleValidationError.invalidField(field, "Must contain between 1 and \(maximumCount) entries.")
        }
        guard Set(values).count == values.count else {
            throw RuleValidationError.invalidField(field, "Duplicate entries are not supported.")
        }
        for value in values {
            try requireRuleText(value, field: field, maximumBytes: maximumBytes)
        }
    }
}

public enum RuleValidationError: Error, Equatable, Sendable {
    case unknownField(String)
    case duplicateField(String)
    case invalidField(String, String)
    case unsupportedSchema(Int)
    case duplicateID(String)
    case documentTooLarge
    case missingBundledDocument
}

extension RuleValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknownField(let name):
            "Unknown rule field: \(name)."
        case .duplicateField(let name):
            "Duplicate JSON rule field: \(name)."
        case .invalidField(let name, let detail):
            "Invalid rule field \(name): \(detail)"
        case .unsupportedSchema(let version):
            "Unsupported rule schema version: \(version)."
        case .duplicateID(let id):
            "Duplicate rule identifier: \(id)."
        case .documentTooLarge:
            "The rule document exceeds the 1 MiB limit."
        case .missingBundledDocument:
            "The bundled rule document is missing."
        }
    }
}

private struct AnyRuleKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

func rejectUnknownRuleFields<Key: CodingKey>(
    _ decoder: any Decoder, allowed: [Key]
) throws {
    let values = try decoder.container(keyedBy: AnyRuleKey.self)
    let names = Set(allowed.map(\.stringValue))
    if let unknown = values.allKeys.map(\.stringValue).filter({ !names.contains($0) }).sorted().first {
        let location = (decoder.codingPath.map(\.stringValue) + [unknown]).joined(separator: ".")
        throw RuleValidationError.unknownField(location)
    }
}

func requireRuleText(_ text: String, field: String, maximumBytes: Int = 4_096) throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          text.utf8.count <= maximumBytes,
          !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" }) else {
        throw RuleValidationError.invalidField(field, "Must contain nonblank text within \(maximumBytes) UTF-8 bytes, without control characters.")
    }
}
