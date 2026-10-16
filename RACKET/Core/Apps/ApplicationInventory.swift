import Darwin
import Foundation

public struct InstalledApplication: Identifiable, Equatable, Sendable {
    public var id: Data { Data(path.utf8) }
    public let path: String
    public let name: String
    public let bundleIdentifier: String
    public let version: String
    public let protectionReason: String?
    /// A preliminary eligibility check. Descendants and running processes are
    /// checked separately when preparing the explicit removal review.
    public var canUninstall: Bool { protectionReason == nil }
    public let allocatedSize: UInt64?
    let identity: ManifestIdentity
}

public struct ApplicationInventoryIssue: Equatable, Sendable {
    public let path: String
    public let detail: String
}

public struct ApplicationInventoryReport: Sendable {
    public let applications: [InstalledApplication]
    public let issues: [ApplicationInventoryIssue]
    public let limited: Bool
}

public struct ApplicationRelatedLocation: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case cache, log }
    public var id: Data { Data(path.utf8) }
    public let path: String
    public let kind: Kind
}

/// A review receipt cannot be manufactured by a caller outside Core. Its digest
/// binds every descendant name and metadata identity, not merely the .app name.
public struct ApplicationRemovalSelection: Sendable {
    public static let manifestVersion = "application-removal-v1"
    public let application: InstalledApplication
    public let allocatedSize: UInt64
    public let descendantCount: Int
    let digest: String
    let identity: ManifestIdentity
}

public enum ApplicationManagementError: Error, Equatable, Sendable, LocalizedError {
    case invalidApplication, protectedApplication, unsafeDescendant, runningApplication
    case activityUnknown, changed, scanLimit

    public var errorDescription: String? {
        switch self {
        case .invalidApplication: "The application bundle or its metadata could not be verified."
        case .protectedApplication: "This application is protected, owned by another user, or requires administrator privileges."
        case .unsafeDescendant: "The application contains linked, protected, shared, or unsupported items. Review it in Finder."
        case .runningApplication: "The application or a process inside its bundle is running. Quit it before trying again."
        case .activityUnknown: "Running application activity could not be verified. Try again after closing other applications."
        case .changed: "The application changed after it was reviewed. Refresh the application list and review it again."
        case .scanLimit: "The application exceeds the bounded inspection limit. Review it in Finder."
        }
    }
}

/// Read-only discovery of app metadata. No Launch Services registration, bundle
/// code loading, preference reads, or application launching occurs.
public actor ApplicationInventory {
    private let policy: ApplicationPolicy
    private let fileSystem: ApplicationFileSystem
    private let activity: ApplicationProcessActivity

    public init() throws {
        let policy = try ApplicationPolicy.currentUser()
        self.init(policy: policy)
    }

    init(policy: ApplicationPolicy, calculator: SizeCalculator = SizeCalculator(),
         activity: ApplicationProcessActivity = ApplicationProcessActivity()) {
        self.policy = policy
        fileSystem = ApplicationFileSystem(policy: policy, calculator: calculator)
        self.activity = activity
    }

    public func scan() throws -> ApplicationInventoryReport {
        try withoutDatalessMaterialization {
            var apps: [InstalledApplication] = []
            var issues: [ApplicationInventoryIssue] = []
            var seen = Set<Data>()
            var examined = 0
            var limited = false
            func visit(_ path: String, depth: Int) throws {
                try Task.checkCancellation()
                guard examined < 20_000, apps.count < 2_000 else { limited = true; return }
                examined += 1
                let location: RemovalLocation
                do { location = try fileSystem.open(path, trusted: false) }
                catch { issues.append(.init(path: path, detail: "This location could not be inspected safely.")); return }
                guard location.metadata.kind == .directory else { return }
                if path.lowercased().hasSuffix(".app") {
                    guard seen.insert(Data(path.utf8)).inserted else { return }
                    do { apps.append(try fileSystem.application(at: location)) }
                    catch { issues.append(.init(path: path, detail: "Application metadata was unavailable or invalid.")) }
                    return
                }
                guard depth < 3 else { limited = true; return }
                do {
                    for entry in try fileSystem.entries(location) {
                        guard !entry.name.hasPrefix("."), entry.flags.map({ $0 & UInt32(SF_DATALESS) == 0 }) == true,
                              entry.error == 0 else { continue }
                        try visit(path + "/" + entry.name, depth: depth + 1)
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { issues.append(.init(path: path, detail: "Some entries could not be inspected safely.")) }
            }
            for root in policy.inventoryRoots { try visit(root, depth: 0) }
            return ApplicationInventoryReport(applications: apps.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }, issues: issues, limited: limited)
        }
    }

    public func reviewRemoval(of application: InstalledApplication) throws -> ApplicationRemovalSelection {
        try withoutDatalessMaterialization {
            try Task.checkCancellation()
            try policy.validateRemovalPath(application.path)
            guard application.canUninstall else { throw ApplicationManagementError.protectedApplication }
            let opened = try fileSystem.open(application.path)
            let current = try fileSystem.application(at: opened)
            guard current.identity == application.identity, current.bundleIdentifier == application.bundleIdentifier,
                  current.name == application.name, current.version == application.version else {
                throw ApplicationManagementError.changed
            }
            guard current.canUninstall else { throw ApplicationManagementError.protectedApplication }
            try activity.requireClosed(paths: [application.path])
            let snapshot = try fileSystem.snapshot(opened)
            try activity.requireClosed(paths: [application.path])
            return ApplicationRemovalSelection(application: current, allocatedSize: snapshot.allocatedSize,
                                               descendantCount: snapshot.count - 1, digest: snapshot.digest,
                                               identity: snapshot.identity)
        }
    }

    /// Only exact bundle IDs under the already compiled Caches/Logs roots.
    /// These are review locations, never new cleanup rules or deletion authority.
    public func relatedCacheLocations(for application: InstalledApplication) throws -> [ApplicationRelatedLocation] {
        try withoutDatalessMaterialization {
            guard ApplicationPolicy.validBundleIdentifier(application.bundleIdentifier) else {
                throw ApplicationManagementError.invalidApplication
            }
            let safe = try SafeRoots(homeDirectory: policy.homeDirectory)
            var result: [ApplicationRelatedLocation] = []
            for (suffix, kind) in [("/Library/Caches/", ApplicationRelatedLocation.Kind.cache), ("/Library/Logs/", .log)] {
                let path = policy.homeDirectory + suffix + application.bundleIdentifier
                _ = try safe.validateCandidate(path)
                do {
                    let location = try fileSystem.open(path, trusted: false)
                    guard location.metadata.kind == .directory else { continue }
                    result.append(.init(path: path, kind: kind))
                } catch RemovalSafetyError.missing { continue }
                catch PathGuardError.missing { continue }
                catch { continue }
            }
            return result
        }
    }
}

struct ApplicationPolicy: Sendable {
    let homeDirectory: String
    let inventoryRoots: [String]
    let removalRoots: [String]

    static func currentUser() throws -> Self {
        let home = try SafeRoots.normalizeAbsolute(FileManager.default.homeDirectoryForCurrentUser.path)
        return forHome(home)
    }

    static func forHome(_ home: String) -> Self {
        Self(homeDirectory: home, inventoryRoots: ["/Applications", home + "/Applications", "/System/Applications",
                                                         "/System/Library/CoreServices/Applications"],
                    removalRoots: ["/Applications", home + "/Applications"])
    }

    func validateRemovalPath(_ path: String) throws {
        guard SafeRoots.sameBytes(try SafeRoots.normalizeAbsolute(path), path), path.lowercased().hasSuffix(".app"),
              let root = removalRoots.first(where: { SafeRoots.isWithin(path, root: $0) }),
              path != root else { throw ApplicationManagementError.protectedApplication }
        let relative = String(path.dropFirst(root.count + 1))
        let names = relative.split(separator: "/").map(String.init)
        guard (1...3).contains(names.count), names.dropLast().allSatisfy({ !$0.lowercased().hasSuffix(".app") }),
              names.allSatisfy({ !$0.hasPrefix(".") && !Self.protectedName($0) }) else {
            throw ApplicationManagementError.protectedApplication
        }
    }

    static func validBundleIdentifier(_ value: String) -> Bool {
        guard (3...255).contains(value.utf8.count), value.contains("."), !value.hasPrefix("."), !value.hasSuffix(".") else { return false }
        return value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")
            }
        }
    }

    static func protectedName(_ name: String) -> Bool {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let names: Set<String> = [".git", "original media", "auto-save", "adobe premiere pro auto-save", "cloudstorage",
                                  "mobile documents", "com~apple~clouddocs", ".racket-staging"]
        return names.contains(folded) || [".photoslibrary", ".drp", ".dra", ".lrcat", ".cocatalog"].contains(where: folded.hasSuffix)
    }
}

struct ApplicationProcessActivity: Sendable {
    var snapshot: @Sendable () throws -> [AppActivityProcess] = { try AppActivityProcessSource().stableSnapshot() }

    func requireClosed(paths: [String]) throws {
        let processes: [AppActivityProcess]
        do { processes = try snapshot() }
        catch { throw ApplicationManagementError.activityUnknown }
        guard !processes.isEmpty, processes.count <= AppActivityProcessSource.maximumProcesses,
              processes.allSatisfy({ AppActivityProcessSource.validPath($0.executablePath) }) else {
            throw ApplicationManagementError.activityUnknown
        }
        if processes.contains(where: { process in paths.contains { SafeRoots.isWithin(process.executablePath, root: $0) } }) {
            throw ApplicationManagementError.runningApplication
        }
    }
}

#if DEBUG
extension ApplicationInventory {
    /// Isolated app fixture for the explicitly selected UI verification mode.
    /// Production discovery never calls this factory.
    public static func verification(root: URL) throws -> ApplicationInventory {
        guard root.isFileURL, let representedPath = root.withUnsafeFileSystemRepresentation({ bytes in
            bytes.map { String(cString: $0) }
        }) else { throw ApplicationManagementError.invalidApplication }
        // Standardizing a file URL rewrites /private/tmp to its /tmp alias on
        // macOS. Keep the supplied filesystem representation and reject aliases.
        let path = representedPath.hasSuffix("/") ? String(representedPath.dropLast()) : representedPath
        let prefix = "/private/tmp/RACKET-UI-"
        guard SafeRoots.sameBytes(try SafeRoots.normalizeAbsolute(path), path), path.hasPrefix(prefix),
              (path as NSString).deletingLastPathComponent == "/private/tmp",
              let token = UUID(uuidString: String(path.dropFirst(prefix.count))), path == prefix + token.uuidString else {
            throw ApplicationManagementError.invalidApplication
        }
        let home = path + "/Home"
        let policy = ApplicationPolicy(homeDirectory: home, inventoryRoots: [home + "/Applications"],
                                       removalRoots: [home + "/Applications"])
        let fileSystem = ApplicationFileSystem(policy: policy)
        try withoutDatalessMaterialization {
            let verifiedRoot = try fileSystem.open(path)
            try verifiedRoot.descriptor.requirePrivateDirectory(verifiedRoot.metadata)
            var parent = try fileSystem.open(home)
            try parent.descriptor.requirePrivateDirectory(parent.metadata)
            for name in ["Applications", "Sample Tool.app", "Contents", "MacOS"] {
                try fileSystem.verify(parent.anchors)
                try parent.descriptor.requirePath(parent.path)
                if Darwin.mkdirat(parent.descriptor.value, name, 0o700) != 0, errno != EEXIST { throw removalSystemError(errno) }
                let next = try fileSystem.open(parent.path + "/" + name)
                try next.descriptor.requirePrivateDirectory(next.metadata)
                parent = next
            }
        }
        let contents = home + "/Applications/Sample Tool.app/Contents"
        let plist: [String: String] = ["CFBundlePackageType": "APPL", "CFBundleIdentifier": "org.example.racket-sample",
                                       "CFBundleName": "Sample Tool", "CFBundleExecutable": "Sample Tool",
                                       "CFBundleShortVersionString": "1.0"]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: removalFileURL(contents + "/Info.plist"), options: .withoutOverwriting)
        try Data("RACKET synthetic UI verification app\n".utf8).write(to: removalFileURL(contents + "/MacOS/Sample Tool"), options: .withoutOverwriting)
        return ApplicationInventory(policy: policy,
                                    activity: ApplicationProcessActivity(snapshot: { [AppActivityProcess(executablePath: "/synthetic/runner")] }))
    }
}
#endif
