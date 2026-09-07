import Foundation

/// Compiled authority, independent of rule JSON. New roots require code review.
public struct SafeRoots: Sendable {
    let homeDirectory: String
    let paths: [String]

    public static func currentUser() throws -> SafeRoots {
        try SafeRoots(homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    // Internal injection keeps tests out of the real home directory. Rule data
    // and callers outside Core cannot supply alternate roots or a home directory.
    init(homeDirectory: String) throws {
        let home = try Self.normalizeAbsolute(homeDirectory)
        guard home != "/" else { throw PathGuardError.invalidPath }
        self.homeDirectory = home
        paths = [home + "/Library/Caches", home + "/Library/Logs"]
    }

    /// Validates declarations only. Existing items still need PathGuard.
    /// A directoryContents rule may name a safe root; the root itself may never
    /// become a removal candidate. Globs are unsupported in this schema phase.
    public func validateRulePath(_ path: String) throws {
        guard !path.contains(where: { "*?[]{}\\".contains($0) }) else {
            throw PathGuardError.invalidPath
        }
        _ = try checked(path, allowRoot: true)
    }

    func validateCandidate(_ path: String) throws -> String {
        try checked(path, allowRoot: false)
    }

    /// A scan may enumerate a compiled root, but never emit that root as a finding.
    func validateScanRoot(_ path: String) throws -> String {
        try validateRulePath(path)
        return try checked(path, allowRoot: true)
    }

    func root(containing path: String) throws -> String {
        guard let root = paths.first(where: { Self.isWithin(path, root: $0) }) else {
            throw PathGuardError.outsideSafeRoots
        }
        return root
    }

    private func checked(_ input: String, allowRoot: Bool) throws -> String {
        let expanded = input.hasPrefix("~/") ? homeDirectory + String(input.dropFirst()) : input
        let path = try Self.normalizeAbsolute(expanded)
        guard !isProtected(path) else { throw PathGuardError.protectedPath }
        let root = try root(containing: path)
        if !allowRoot && Self.sameBytes(path, root) { throw PathGuardError.safeRoot }
        return path
    }

    static func sameBytes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    static func isWithin(_ path: String, root: String) -> Bool {
        sameBytes(path, root) || path.utf8.starts(with: (root + "/").utf8)
    }

    static func normalizeAbsolute(_ path: String) throws -> String {
        guard path.hasPrefix("/"), path.utf8.count <= 4_096,
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw PathGuardError.invalidPath
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains(".."), components.allSatisfy({ $0.utf8.count <= 255 }) else {
            throw PathGuardError.invalidPath
        }
        return "/" + components.filter { $0 != "." }.joined(separator: "/")
    }

    private func isProtected(_ path: String) -> Bool {
        // Denials are deliberately broader than byte-exact allow-list matching.
        // Case/normalization differences must never weaken protected names.
        func folded(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        let lowered = folded(path)
        let components = lowered.split(separator: "/").map(String.init)
        // These are user work, not caches. In particular Adobe autosaves and
        // Final Cut Original Media have no optional cleaning override.
        let protectedNames: Set<String> = [
            ".git", "original media", "auto-save", "adobe premiere pro auto-save",
            "cloudstorage", "mobile documents", "com~apple~clouddocs"
        ]
        let protectedExtensions = [".photoslibrary", ".drp", ".dra", ".lrcat", ".cocatalog"]
        if components.contains(where: { name in
            protectedNames.contains(name) || protectedExtensions.contains(where: name.hasSuffix)
        }) { return true }

        let systemRoots = ["/system", "/bin", "/sbin", "/private/var/db"]
        if systemRoots.contains(where: { Self.isWithin(lowered, root: $0) }) { return true }
        if Self.isWithin(lowered, root: "/usr"), !Self.isWithin(lowered, root: "/usr/local") { return true }

        let home = folded(homeDirectory)
        let homeRoots = [
            "/Library/Preferences", "/Library/Keychains", "/Library/Mail",
            "/Library/Messages", "/Library/Calendars", "/Library/AddressBook",
            "/Library/Application Support/AddressBook",
            "/Library/Application Support/Blackmagic Design"
        ]
        // Mail Downloads and narrow catalog exceptions remain outside the
        // allow-list until their dedicated modules have been reviewed.
        return homeRoots.contains { Self.isWithin(lowered, root: home + folded($0)) }
    }
}
