import Foundation

/// A complete, validated snapshot of the bundled declarative rules.
///
/// Construction always requires the compiled path policy, including for disabled
/// rules. Rules do not provide safe roots, a home directory, or path exceptions.
/// Loading a rule set validates its declarations, not a future filesystem item:
/// the scanner and removal boundary must still use PathGuard for each item.
public struct RuleSet: Equatable, Sendable {
    public static let supportedSchemaVersion = 1
    public static let maximumDocumentBytes = 1_048_576
    public static let maximumRuleCount = 1_000

    public let schemaVersion: Int
    public let version: String
    public let rules: [Rule]

    public var enabledRules: [Rule] { rules.filter(\.enabled) }

    private init(document: RuleDocument) {
        schemaVersion = document.schemaVersion
        version = document.version
        rules = document.rules
    }

    /// Explicit bytes are useful for CI and review fixtures. The production
    /// entry point is loadBundled; there is no path/URL or network rule loader.
    /// A validator refusal is propagated unchanged for a typed policy error.
    public static func decode(
        _ data: Data,
        validatePath: @Sendable (String) throws -> Void
    ) throws -> RuleSet {
        guard data.count <= maximumDocumentBytes else {
            throw RuleValidationError.documentTooLarge
        }
        // JSONDecoder alone accepts duplicate object keys, leaving a reviewer
        // unsure which value (especially enabled/verified) will take effect.
        var structure = UnambiguousRuleJSON(data: data)
        try structure.validate()
        let document = try JSONDecoder().decode(RuleDocument.self, from: data)
        var identifiers = Set<String>()
        for rule in document.rules {
            guard identifiers.insert(rule.id).inserted else {
                throw RuleValidationError.duplicateID(rule.id)
            }
            for path in rule.paths {
                try validatePath(path)
            }
        }
        return RuleSet(document: document)
    }

    /// Reads only the fixed resource shipped with RacketCore, never user input.
    public static func loadBundled(
        validatePath: @Sendable (String) throws -> Void
    ) throws -> RuleSet {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: RuleBundleMarker.self)
        #endif
        guard let resource = bundle.url(forResource: "core-v1", withExtension: "json") else {
            throw RuleValidationError.missingBundledDocument
        }
        return try decode(Data(contentsOf: resource), validatePath: validatePath)
    }
}

private final class RuleBundleMarker: NSObject {}

private struct RuleDocument: Decodable {
    let schemaVersion: Int
    let version: String
    let rules: [Rule]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, version, rules
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownRuleFields(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == RuleSet.supportedSchemaVersion else {
            throw RuleValidationError.unsupportedSchema(schemaVersion)
        }
        version = try values.decode(String.self, forKey: .version)
        try requireRuleText(version, field: "version", maximumBytes: 64)
        let segments = version.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3, segments.allSatisfy({ segment in
            !segment.isEmpty && segment.utf8.allSatisfy { (48...57).contains($0) }
                && (segment.count == 1 || segment.first != "0")
        }) else {
            throw RuleValidationError.invalidField("version", "Use a three-part numeric version, such as 1.0.0.")
        }
        rules = try values.decode([Rule].self, forKey: .rules)
        guard rules.count <= RuleSet.maximumRuleCount else {
            throw RuleValidationError.invalidField("rules", "At most 1,000 rules are supported.")
        }
    }
}

/// A bounded structure pass for duplicate keys. JSONDecoder still owns value
/// syntax, numeric types, Unicode decoding, and the actual schema afterward.
private struct UnambiguousRuleJSON {
    private let bytes: [UInt8]
    private var position = 0

    init(data: Data) { bytes = Array(data) }

    mutating func validate() throws {
        try consumeValue(depth: 0)
        skipWhitespace()
        guard position == bytes.count else { throw malformed() }
    }

    private mutating func consumeValue(depth: Int) throws {
        guard depth <= 64 else {
            throw RuleValidationError.invalidField("document", "JSON nesting exceeds 64 levels.")
        }
        skipWhitespace()
        guard position < bytes.count else { throw malformed() }
        switch bytes[position] {
        case 123: // {
            position += 1
            skipWhitespace()
            if consume(125) { return }
            var keys = Set<String>()
            while true {
                let keyBytes = try consumeString()
                let key = try JSONDecoder().decode(String.self, from: keyBytes)
                guard keys.insert(key).inserted else {
                    throw RuleValidationError.duplicateField(key)
                }
                skipWhitespace()
                guard consume(58) else { throw malformed() }
                try consumeValue(depth: depth + 1)
                skipWhitespace()
                if consume(125) { return }
                guard consume(44) else { throw malformed() }
                skipWhitespace()
            }
        case 91: // [
            position += 1
            skipWhitespace()
            if consume(93) { return }
            while true {
                try consumeValue(depth: depth + 1)
                skipWhitespace()
                if consume(93) { return }
                guard consume(44) else { throw malformed() }
            }
        case 34: // "
            _ = try consumeString()
        default:
            let start = position
            while position < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[position]) {
                position += 1
            }
            guard position > start else { throw malformed() }
        }
    }

    private mutating func consumeString() throws -> Data {
        let start = position
        guard consume(34) else { throw malformed() }
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            if byte == 34 { return Data(bytes[start..<position]) }
            if byte == 92 {
                guard position < bytes.count else { throw malformed() }
                position += 1
            }
        }
        throw malformed()
    }

    private mutating func skipWhitespace() {
        while position < bytes.count && [9, 10, 13, 32].contains(bytes[position]) {
            position += 1
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard position < bytes.count, bytes[position] == byte else { return false }
        position += 1
        return true
    }

    private func malformed() -> RuleValidationError {
        .invalidField("document", "Malformed JSON structure.")
    }
}
