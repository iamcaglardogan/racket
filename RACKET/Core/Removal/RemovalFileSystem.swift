import Darwin
import Foundation

enum RemovalSafetyError: Error, Equatable, Sendable {
    case invalidSelection, changed, unsupported, ownership, multipleLinks
    case conflict, missing, unsafeRecoveryLocation, invalidHistory
    case system(Int32)
}

extension ManifestIdentity {
    init(_ value: ScanMetadataFingerprint) {
        self.init(device: value.identity.device, inode: value.identity.inode,
                  generation: value.generation, owner: value.owner, group: value.group,
                  mode: value.mode, flags: value.flags, links: value.links,
                  bornSeconds: value.bornSeconds, bornNanoseconds: value.bornNanoseconds,
                  modifiedSeconds: value.modifiedSeconds, modifiedNanoseconds: value.modifiedNanoseconds)
    }
}

/// Retains metadata descriptors, never file contents. All callers must enclose
/// this synchronous transaction in withoutDatalessMaterialization.
final class RemovalDescriptor {
    let value: Int32
    init(_ value: Int32) throws {
        guard value >= 0 else { throw removalSystemError(errno) }
        self.value = value
    }
    deinit { _ = Darwin.close(value) }

    func child(_ name: String) throws -> RemovalDescriptor {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            throw RemovalSafetyError.unsupported
        }
        return try RemovalDescriptor(name.withCString {
            Darwin.openat(value, $0, O_EVTONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        })
    }

    func requirePath(_ expected: String) throws {
        var bytes = [CChar](repeating: 0, count: Int(PATH_MAX))
        let result = bytes.withUnsafeMutableBufferPointer { Darwin.fcntl(value, F_GETPATH, $0.baseAddress!) }
        guard result == 0 else { throw removalSystemError(errno) }
        let actual = String(bytes: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
        guard let actual, SafeRoots.sameBytes(actual, expected) else { throw RemovalSafetyError.changed }
    }

    func requireLocalVolume() throws -> Int32 {
        var filesystem = statfs()
        guard Darwin.fstatfs(value, &filesystem) == 0 else { throw removalSystemError(errno) }
        guard filesystem.f_flags & UInt32(MNT_LOCAL) != 0 else { throw RemovalSafetyError.unsupported }
        return filesystem.f_fsid.val.0
    }

    func requirePrivateDirectory(_ metadata: ScanMetadata) throws {
        guard metadata.kind == .directory, metadata.fingerprint.owner == geteuid(), geteuid() != 0,
              metadata.fingerprint.mode & 0o7777 == 0o700 else { throw RemovalSafetyError.ownership }
        try requireNoACLGrants()
    }

    func requireTrustedDirectory(_ metadata: ScanMetadata, path: String) throws {
        let value = metadata.fingerprint
        guard metadata.kind == .directory, value.owner == 0 || value.owner == geteuid() else {
            throw RemovalSafetyError.ownership
        }
        let temporaryRoot = path == "/private/tmp" && value.owner == 0 && value.mode & UInt16(S_ISVTX) != 0
        guard value.mode & 0o022 == 0 || temporaryRoot else { throw RemovalSafetyError.ownership }
        try requireNoACLGrants()
    }

    func requireNoACLGrants() throws {
        guard let acl = acl_get_fd_np(value, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT { return }
            throw removalSystemError(errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw removalSystemError(errno) }
        var entry: acl_entry_t?
        var position = ACL_FIRST_ENTRY
        while acl_get_entry(acl, Int32(position.rawValue), &entry) == 0 {
            guard let entry else { throw RemovalSafetyError.ownership }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0 else { throw removalSystemError(errno) }
            guard tag != ACL_EXTENDED_ALLOW else { throw RemovalSafetyError.ownership }
            position = ACL_NEXT_ENTRY
        }
        // Darwin reports the end of a valid ACL as -1/EINVAL.
        guard errno == EINVAL else { throw removalSystemError(errno) }
    }
}

struct RemovalAnchor {
    let descriptor: RemovalDescriptor
    let path: String
    let identity: ManifestIdentity
}

struct RemovalLocation {
    let path: String
    let name: String
    let parent: RemovalDescriptor
    let descriptor: RemovalDescriptor
    let metadata: ScanMetadata
    let anchors: [RemovalAnchor]
}

struct RemovalFileSystem: Sendable {
    let policy: SafeRoots
    let calculator: SizeCalculator

    init(policy: SafeRoots, calculator: SizeCalculator = SizeCalculator()) {
        self.policy = policy
        self.calculator = calculator
    }

    /// No symlink component or network volume is accepted, including ancestors.
    /// Directory identities exclude mtime/ctime because our own entries change them.
    func open(_ path: String, includeSize: Bool = false, skipBackup: Bool = false) throws -> RemovalLocation {
        guard SafeRoots.sameBytes(try SafeRoots.normalizeAbsolute(path), path), path != "/" else {
            throw PathGuardError.invalidPath
        }
        var current = try RemovalDescriptor(Darwin.open("/", O_EVTONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        var anchors: [RemovalAnchor] = []
        let components = path.split(separator: "/").map(String.init)
        var prefix = ""
        for (index, name) in components.enumerated() {
            prefix += "/" + name
            let child = try current.child(name)
            let last = index == components.count - 1
            let metadata = try calculator.inspect(descriptor: child.value, path: prefix,
                                                  includeSize: last && includeSize,
                                                  skipExcludedFromBackup: last && skipBackup)
            // F_GETPATH cannot bind a multiply linked inode to a unique name.
            // These files are unsupported here; classify them before that lookup.
            if metadata.kind == .regularFile, metadata.fingerprint.links != 1 {
                throw RemovalSafetyError.multipleLinks
            }
            _ = try child.requireLocalVolume()
            try child.requirePath(prefix)
            if metadata.kind == .directory { try child.requireTrustedDirectory(metadata, path: prefix) }
            if last {
                let result = RemovalLocation(path: path, name: name, parent: current, descriptor: child,
                                             metadata: metadata, anchors: anchors)
                try verify(result.anchors)
                return result
            }
            guard metadata.kind == .directory else { throw PathGuardError.notDirectory }
            anchors.append(RemovalAnchor(descriptor: child, path: prefix, identity: ManifestIdentity(metadata.fingerprint)))
            current = child
        }
        throw PathGuardError.invalidPath
    }

    func verify(_ anchors: [RemovalAnchor]) throws {
        for anchor in anchors {
            try anchor.descriptor.requirePath(anchor.path)
            let fresh = try calculator.inspect(descriptor: anchor.descriptor.value, path: anchor.path, includeSize: false)
            let before = anchor.identity
            let after = ManifestIdentity(fresh.fingerprint)
            try anchor.descriptor.requireTrustedDirectory(fresh, path: anchor.path)
            guard fresh.kind == .directory, before.device == after.device, before.inode == after.inode,
                  before.generation == after.generation, before.bornSeconds == after.bornSeconds,
                  before.bornNanoseconds == after.bornNanoseconds, before.mode == after.mode,
                  before.owner == after.owner, before.group == after.group, before.flags == after.flags else {
                throw RemovalSafetyError.changed
            }
        }
    }

    func requireOrdinaryOwnedFile(_ location: RemovalLocation, expected: ManifestIdentity? = nil) throws {
        guard location.metadata.kind == .regularFile else { throw RemovalSafetyError.unsupported }
        let metadata = location.metadata.fingerprint
        guard geteuid() != 0, metadata.owner == geteuid(), metadata.mode & 0o022 == 0 else {
            throw RemovalSafetyError.ownership
        }
        try location.descriptor.requireNoACLGrants()
        guard metadata.links == 1 else { throw RemovalSafetyError.multipleLinks }
        if let expected, ManifestIdentity(metadata) != expected { throw RemovalSafetyError.changed }
    }

    func stagingPath(for item: ManifestItem, sessionID: UUID) throws -> String {
        let original = try policy.validateCandidate(item.originalPath)
        return try policy.root(containing: original) + "/.racket-staging/" + sessionID.uuidString + "/" + item.id.uuidString
    }

    /// The reservation is excluded from rules and findings. It remains inside
    /// the same compiled root; no new user-data root is granted removal authority.
    func makeStagingParent(for item: ManifestItem, sessionID: UUID) throws -> RemovalLocation {
        let original = try policy.validateCandidate(item.originalPath)
        let root = try policy.root(containing: original)
        var directory = try open(root)
        guard directory.metadata.kind == .directory else { throw PathGuardError.notDirectory }
        for name in [".racket-staging", sessionID.uuidString] {
            try verify(directory.anchors)
            try directory.descriptor.requirePath(directory.path)
            let result = name.withCString { Darwin.mkdirat(directory.descriptor.value, $0, 0o700) }
            if result != 0 && errno != EEXIST { throw removalSystemError(errno) }
            let next = try open(directory.path + "/" + name)
            guard next.metadata.identity.device == directory.metadata.identity.device else { throw PathGuardError.mountBoundary }
            try next.descriptor.requirePrivateDirectory(next.metadata)
            directory = next
        }
        return directory
    }

    func verifiedStage(_ path: String, item: ManifestItem, sessionID: UUID) throws -> RemovalLocation {
        guard SafeRoots.sameBytes(path, try stagingPath(for: item, sessionID: sessionID)) else {
            throw RemovalSafetyError.unsafeRecoveryLocation
        }
        let result = try open(path)
        try requireOrdinaryOwnedFile(result, expected: item.identity)
        for anchor in result.anchors where anchor.path.contains("/.racket-staging") {
            let metadata = try calculator.inspect(descriptor: anchor.descriptor.value, path: anchor.path, includeSize: false)
            try anchor.descriptor.requirePrivateDirectory(metadata)
        }
        guard result.metadata.identity.device == item.identity.device else { throw PathGuardError.mountBoundary }
        return result
    }

    func originalParent(for item: ManifestItem) throws -> RemovalLocation {
        let original = try policy.validateCandidate(item.originalPath)
        let parent = try open((original as NSString).deletingLastPathComponent)
        guard parent.metadata.kind == .directory, parent.metadata.identity.device == item.identity.device else {
            throw PathGuardError.mountBoundary
        }
        return parent
    }

    /// Atomic no-overwrite namespace move. No cross-volume copy/delete fallback.
    func move(_ source: RemovalLocation, into parent: RemovalLocation, name: String,
              beforeRename: () throws -> Void = {}) throws {
        try verify(source.anchors)
        try source.descriptor.requirePath(source.path)
        try verify(parent.anchors)
        try parent.descriptor.requirePath(parent.path)
        guard source.metadata.identity.device == parent.metadata.identity.device,
              parent.metadata.kind == .directory else { throw PathGuardError.mountBoundary }
        try beforeRename()
        let result = source.name.withCString { sourceName in
            name.withCString { destinationName in
                renameatx_np(source.parent.value, sourceName, parent.descriptor.value, destinationName,
                             UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY))
            }
        }
        guard result == 0 else { throw removalSystemError(errno) }
    }

    func restoreStage(_ path: String, item: ManifestItem, sessionID: UUID, expectedParents: [RemovalAnchor]? = nil) throws {
        let stage = try verifiedStage(path, item: item, sessionID: sessionID)
        let parent = try originalParent(for: item)
        if let expectedParents { try verify(expectedParents) }
        try move(stage, into: parent, name: (item.originalPath as NSString).lastPathComponent)
        let restored = try open(item.originalPath)
        try requireOrdinaryOwnedFile(restored, expected: item.identity)
    }
}

func removalSystemError(_ number: Int32) -> any Error {
    switch number {
    case EEXIST: RemovalSafetyError.conflict
    case ENOENT: RemovalSafetyError.missing
    case ELOOP: PathGuardError.symbolicLink
    case ENOTDIR: PathGuardError.notDirectory
    case EDEADLK: ScanMetadataError.dataless
    case EXDEV: PathGuardError.mountBoundary
    default: RemovalSafetyError.system(number)
    }
}

func removalExplanation(_ error: any Error) -> String {
    switch error {
    case RemovalSafetyError.conflict: "The original location is occupied. Keep both items and choose a different destination manually."
    case RemovalSafetyError.missing, PathGuardError.missing: "The recorded item is missing. It may have been moved or Trash may have been emptied."
    case RemovalSafetyError.ownership: "The item does not have the required current-user ownership or private permissions."
    case RemovalSafetyError.multipleLinks: "The item has multiple hard links. This removal phase supports one-link files only."
    case ScanMetadataError.dataless, PathGuardError.dataless: "The item is an offline placeholder. Leave it to its cloud provider."
    case ScanMetadataError.excludedFromBackup: "The rule excludes this item because it is excluded from backup."
    case let error as PathGuardError: error.localizedDescription
    default: "The item or its recovery record could not be verified. Preserve its recorded locations and review it again."
    }
}
