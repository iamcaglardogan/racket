import Darwin
import Foundation

/// The same engines are used by the application and its isolated verification
/// mode. Production callers cannot supply a home directory or a Trash transport.
public struct AppRuntime: Sendable {
    public let rules: RuleSet
    public let scanner: ScanEngine
    public let manifest: ManifestStore
    public let remover: RemovalEngine
    public let undo: UndoService
    public let verificationRoot: URL?

    public static func production() throws -> AppRuntime {
        let policy = try SafeRoots.currentUser()
        let rules = try RuleSet.loadBundled(validatePath: policy.validateRulePath)
        let manifest = try ManifestStore()
        return try AppRuntime(rules: rules, scanner: ScanEngine(), manifest: manifest,
                              remover: RemovalEngine(manifest: manifest), undo: UndoService(manifest: manifest),
                              verificationRoot: nil)
    }

    #if DEBUG
    /// Only a Debug build can create this workspace. No real home, application
    /// cache, or real Trash is read or changed. Files are deliberately preserved.
    public static func verification() throws -> AppRuntime {
        let root = URL(fileURLWithPath: "/private/tmp/RACKET-UI-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("Home", isDirectory: true)
        let cache = home.appendingPathComponent("Library/Caches/RACKET-Verification", isDirectory: true)
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        let journal = root.appendingPathComponent("Manifests", isDirectory: true)
        for directory in [root, home, home.appendingPathComponent("Library"),
                          home.appendingPathComponent("Library/Caches"),
                          home.appendingPathComponent("Library/Logs"), cache, trash, journal] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        for (name, count) in [("Preview cache.bin", 262_144), ("Render index.bin", 131_072),
                              ("Thumbnail cache.bin", 65_536), ("Review notes.log", 8_192)] {
            let file = cache.appendingPathComponent(name)
            try Data(repeating: 0x52, count: count).write(to: file, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600,
                .modificationDate: Date(timeIntervalSinceNow: -30 * 86_400)], ofItemAtPath: file.path)
        }
        let document = Data("""
        {"schemaVersion":1,"version":"1.0.0","rules":[{
          "id":"racket.verification","module":"system","title":"Sample cache files",
          "producers":["io.github.iamcaglardogan.racket"],
          "paths":["~/Library/Caches/RACKET-Verification"],
          "match":{"kind":"directoryContents","maxDepth":2},"conditions":[],
          "risk":"regenerable","reason":"These sample files were generated in an isolated temporary workspace for verification.",
          "regenerationCost":"Create another verification workspace to generate new samples.",
          "citation":"https://github.com/iamcaglardogan/racket","verified":true,"enabled":true
        }]}
        """.utf8)
        let policy = try SafeRoots(homeDirectory: home.path)
        let rules = try RuleSet.decode(document, validatePath: policy.validateRulePath)
        let manifest = try ManifestStore(directory: journal.path, authenticationKey: Data(repeating: 0x52, count: 32))
        let transport = RemovalOperations(trash: { path in
            let destination = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(atPath: path, toPath: destination.path)
            return destination.path
        }, isInTrash: { path in SafeRoots.isWithin(path, root: trash.path) && path != trash.path })
        let walker = DirectoryWalker(policy: policy)
        let scanner = ScanEngine(policy: policy, concurrencyLimit: 2) { path, depth, skip in
            try walker.walk(path: path, maxDepth: depth, skipExcludedFromBackup: skip)
        }
        return AppRuntime(rules: rules, scanner: scanner, manifest: manifest,
                          remover: RemovalEngine(policy: policy, manifest: manifest, operations: transport,
                                                 applicationActivity: ApplicationProcessActivity(snapshot: { [AppActivityProcess(executablePath: "/synthetic/runner")] })),
                          undo: UndoService(policy: policy, manifest: manifest, operations: transport),
                          verificationRoot: root)
    }
    #endif
}
