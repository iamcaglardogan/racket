import Darwin
import Foundation

// A CI-only executable compiled with Core sources, outside Package.swift and
// the app/Xcode targets. It never invokes a Trash API directly or injects a
// transport: the public current-user entry points exercise the shipping code.
@main
private struct LiveTrashFixture {
    static func main() async {
        do {
            let context = try FixtureContext(arguments: CommandLine.arguments)
            try context.verifyIdentityAndHome()
            _ = umask(0o077)
            try await run(context)
        } catch {
            let message = "Live Trash fixture FAILED: \(error). Fixture and account are preserved.\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
    }

    private static func run(_ context: FixtureContext) async throws {
        let manager = FileManager.default
        let home = context.home
        let trash = home + "/.Trash"
        let scanRoot = home + "/Library/Caches/RACKET-LiveTrash"
        let source = scanRoot + "/ordinary-fixture.cache"
        let contents = Data("RACKET disposable-account Foundation Trash and Undo fixture.\n".utf8)

        // Identity/home verification above precedes every fixture-data write.
        // The setup script has created only the private, empty Home directory.
        for suffix in ["/.Trash", "/Library", "/Library/Caches", "/Library/Caches/RACKET-LiveTrash"] {
            let path = home + suffix
            try manager.createDirectory(atPath: path, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            try context.verifyPrivateDirectory(path)
        }
        try context.verifyIdentityAndHome()
        try require(manager.changeCurrentDirectoryPath(home), "Cannot use the synthetic home as working directory")

        // Discovery is a precondition, not an API promise that pins the later
        // destination. The disposable VM/account remain the isolation boundary.
        let discovered = try manager.url(for: .trashDirectory, in: .userDomainMask,
                                         appropriateFor: URL(fileURLWithPath: scanRoot, isDirectory: true), create: false)
        try require(discovered.path == trash, "Foundation did not discover the synthetic user's Trash")
        try context.verifyPrivateDirectory(discovered.path)
        try contents.write(to: URL(fileURLWithPath: source), options: .withoutOverwriting)
        let initial = try context.verifyOrdinaryFile(source)

        let policy = try SafeRoots.currentUser()
        let ruleJSON = """
        {"schemaVersion":1,"version":"1.0.0","rules":[{
          "id":"fixture.live-trash","module":"creative","title":"CI ordinary file",
          "producers":["io.github.iamcaglardogan.racket.fixture"],
          "paths":["~/Library/Caches/RACKET-LiveTrash"],
          "match":{"kind":"directoryContents","maxDepth":1},"conditions":[],
          "risk":"judgement","reason":"Explicitly selected disposable CI fixture.",
          "regenerationCost":"Created by this integration test.",
          "citation":"https://example.invalid/racket-live-trash-fixture",
          "enabled":true,"verified":true
        }]}
        """
        let rules = try RuleSet.decode(Data(ruleJSON.utf8), validatePath: policy.validateRulePath)
        let scanner = try ScanEngine()
        let scan = try await scanner.scan(ruleSet: rules)
        try require(scan.issues.isEmpty, "The synthetic scan reported issues: \(scan.issues)")
        try require(scan.findings.count == 1 && scan.findings.first?.resolvedPath == source,
                    "The scanner did not return exactly the selected fixture")

        try context.verifyIdentityAndHome()
        let selectedTrash = try manager.url(for: .trashDirectory, in: .userDomainMask,
                                            appropriateFor: URL(fileURLWithPath: source), create: false)
        try require(selectedTrash.path == trash, "Trash discovery changed before removal")
        try context.verifyPrivateDirectory(trash)
        let manifest = try ManifestStore()
        let removal = try RemovalEngine(manifest: manifest)
        let removed = try await removal.moveToTrash(reviewedFindings: scan.findings, ruleSet: rules,
                                                    appVersion: "test-live-trash")
        try require(!removed.cancelled && removed.journalFailure == nil, "Removal did not finish durably: \(removed)")
        try require(removed.results.count == 1 && removed.results.first?.outcome == .trashed,
                    "Foundation Trash did not succeed: \(removed.results)")
        guard let destination = removed.results.first?.recoveryPath else {
            throw FixtureFailure("Successful removal omitted its destination")
        }
        // Check the string boundary before accessing any returned filesystem URL.
        try require(destination.hasPrefix(trash + "/") &&
                    URL(fileURLWithPath: destination).deletingLastPathComponent().path == trash,
                    "Foundation returned a destination outside the synthetic Trash")
        let trashed = try context.verifyOrdinaryFile(destination)
        try require(trashed.st_dev == initial.st_dev && trashed.st_ino == initial.st_ino,
                    "The returned Trash item is not the original fixture")
        try requireMissing(source)
        let trashedBytes = try Data(contentsOf: URL(fileURLWithPath: destination))
        try require(trashedBytes == contents, "Trash changed fixture contents")

        // Reopen the public persistent store to verify the on-disk key and
        // authenticated journal, not just an in-memory record from removal.
        let reopenedManifest = try ManifestStore()
        let trashedSession = try reopenedManifest.read(removed.sessionID)
        try require(trashedSession.events.map(\.action) == [.prepared, .staged, .trashed],
                    "Unexpected authenticated removal history")
        try require(trashedSession.events.last?.trashPath == destination &&
                    trashedSession.events.last?.item.originalPath == source,
                    "Journal paths do not identify the fixture")
        try context.verifyIdentityAndHome()
        let undo = try UndoService(manifest: reopenedManifest)
        let restored = try await undo.restore(sessionID: removed.sessionID)
        try require(!restored.cancelled && restored.journalFailure == nil &&
                    restored.results.count == 1 && restored.results.first?.outcome == .restored,
                    "Undo did not finish durably: \(restored)")
        let restoredMetadata = try context.verifyOrdinaryFile(source)
        try require(restoredMetadata.st_dev == initial.st_dev && restoredMetadata.st_ino == initial.st_ino,
                    "Undo did not restore the original fixture identity")
        let restoredBytes = try Data(contentsOf: URL(fileURLWithPath: source))
        try require(restoredBytes == contents, "Undo changed fixture contents")
        try requireMissing(destination)
        let finalSession = try ManifestStore().read(removed.sessionID)
        try require(finalSession.appVersion == "test-live-trash" && finalSession.ruleSetVersion == rules.version,
                    "Unexpected persisted session versions")
        try require(finalSession.events.map(\.action) == [.prepared, .staged, .trashed, .restorePrepared, .restored],
                    "Unexpected authenticated removal/undo history")
        print("Live Foundation Trash and Undo passed: one original inode, identical bytes, five authenticated journal actions.")
        print("Preserved synthetic home: \(home)")
    }
}

private struct FixtureContext: Sendable {
    let home: String
    let root: String
    let uid: uid_t
    let gid: gid_t
    let account: String

    init(arguments: [String]) throws {
        guard arguments.count == 5, let uid = UInt32(arguments[2]), let gid = UInt32(arguments[3]),
              (45_000...60_000).contains(uid), uid == gid else {
            throw FixtureFailure("Expected a reserved synthetic home, UID, GID and account")
        }
        home = arguments[1]
        root = URL(fileURLWithPath: home).deletingLastPathComponent().path
        let prefix = "/Users/RACKET-LiveTrash-"
        guard root.hasPrefix(prefix), home == root + "/Home",
              let uuid = UUID(uuidString: String(root.dropFirst(prefix.count))),
              root == prefix + uuid.uuidString else {
            throw FixtureFailure("Home is not an exact UUID fixture path")
        }
        let token = uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        account = "_racket_trash_" + token.prefix(16)
        guard arguments[4] == account else { throw FixtureFailure("Unexpected synthetic account name") }
        self.uid = uid
        self.gid = gid
    }

    func verifyIdentityAndHome() throws {
        try require(getuid() == uid && geteuid() == uid && getgid() == gid && getegid() == gid,
                    "The process is not running as the reserved non-root account/group")
        guard let record = getpwuid(uid) else { throw FixtureFailure("Synthetic passwd record is missing") }
        try require(String(cString: record.pointee.pw_name) == account &&
                    String(cString: record.pointee.pw_dir) == home && record.pointee.pw_gid == gid &&
                    String(cString: record.pointee.pw_shell) == "/usr/bin/false",
                    "The passwd record does not match the synthetic fixture")
        let groupCount = getgroups(0, nil)
        try require(groupCount >= 0 && groupCount <= 128, "Cannot inspect supplementary groups")
        var groups = [gid_t](repeating: 0, count: Int(groupCount))
        let received = groups.withUnsafeMutableBufferPointer { getgroups(groupCount, $0.baseAddress) }
        try require(received == groupCount && !groups.contains(0) && !groups.contains(20) && !groups.contains(80),
                    "The fixture inherited root, staff or admin group membership")
        let foundationName = NSUserName()
        let foundationHome = NSHomeDirectory()
        let currentHome = FileManager.default.homeDirectoryForCurrentUser.path
        let namedHome = FileManager.default.homeDirectory(forUser: account)?.path
        try require(foundationName == account, "Unexpected Foundation user: \(foundationName)")
        try require(foundationHome == home, "Unexpected NSHomeDirectory: \(foundationHome)")
        try require(currentHome == home, "Unexpected current-user home: \(currentHome)")
        try require(namedHome == home, "Unexpected named-user home: \(namedHome ?? "nil")")
        try verifyPrivateDirectory(root)
        try verifyPrivateDirectory(home)
    }

    func verifyPrivateDirectory(_ path: String) throws {
        try require(path == root || path.hasPrefix(root + "/"), "Directory escaped the fixture")
        try verifyCanonicalChain(path)
        var metadata = stat()
        try require(lstat(path, &metadata) == 0 && metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) &&
                    metadata.st_uid == uid && metadata.st_gid == gid && metadata.st_mode & 0o7777 == 0o700,
                    "Fixture directory is not private and owned by the synthetic account: \(path)")
    }

    func verifyOrdinaryFile(_ path: String) throws -> stat {
        try require(path.hasPrefix(home + "/"), "File escaped the synthetic home")
        try verifyCanonicalChain(path)
        var metadata = stat()
        try require(lstat(path, &metadata) == 0 && metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) &&
                    metadata.st_uid == uid && metadata.st_gid == gid && metadata.st_nlink == 1,
                    "Fixture is not an ordinary single-link file owned by the synthetic account")
        return metadata
    }

    private func verifyCanonicalChain(_ path: String) throws {
        try require(URL(fileURLWithPath: path).resolvingSymlinksInPath().path == path,
                    "Fixture path is not canonical")
        var current = ""
        for component in path.split(separator: "/") {
            try require(component != "." && component != "..", "Dot path component")
            current += "/" + component
            var metadata = stat()
            try require(lstat(current, &metadata) == 0 && metadata.st_mode & mode_t(S_IFMT) != mode_t(S_IFLNK),
                        "Fixture path contains a missing or symbolic-link component")
        }
    }
}

private struct FixtureFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw FixtureFailure(message) }
}

private func requireMissing(_ path: String) throws {
    var metadata = stat()
    let result = lstat(path, &metadata)
    try require(result == -1 && errno == ENOENT, "Expected the fixture path to be absent: \(path)")
}
