import Darwin
import Foundation

public enum PathGuardError: Error, Equatable, Sendable {
    case invalidPath
    case outsideSafeRoots
    case protectedPath
    case safeRoot
    case symbolicLink
    case missing
    case notDirectory
    case unsupportedFileType
    case mountBoundary
    case dataless
    case changed
    case inaccessible(Int32)
}

extension PathGuardError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPath: "The path is malformed or uses unsupported syntax."
        case .outsideSafeRoots: "The path is outside the compiled safe roots."
        case .protectedPath: "The path identifies protected user or system data."
        case .safeRoot: "A safe root itself cannot be a removal candidate."
        case .symbolicLink: "The path contains a symbolic link. Inspect its original location."
        case .missing: "The item no longer exists. Refresh the findings."
        case .notDirectory: "A parent path is not a directory. Refresh the findings."
        case .unsupportedFileType: "The item is not an ordinary file or directory."
        case .mountBoundary: "The path reaches a volume boundary."
        case .dataless: "The item is an offline placeholder. Leave it to its cloud provider."
        case .changed: "The item or a parent changed after validation. Review it again."
        case .inaccessible: "The operating system refused path metadata access. Review the item's permissions."
        }
    }
}

/// An unforgeable observation, not a capability to remove anything.
/// It does not authorize unexamined descendants or close a future Trash race.
public struct ValidatedPath: Sendable {
    public let resolvedPath: String
    fileprivate let root: String
    fileprivate let chain: [FileIdentity]
    fileprivate let modification: ModificationIdentity
}

/// Read-only, component-by-component validation. The pure path policy lives in
/// SafeRoots; Darwin calls here open metadata descriptors, never file contents.
public struct PathGuard: Sendable {
    private let policy: SafeRoots

    public init() throws { policy = try .currentUser() }

    init(policy: SafeRoots) { self.policy = policy }

    public func validate(_ input: String) throws -> ValidatedPath {
        let candidate = try policy.validateCandidate(input)
        let root = try policy.root(containing: candidate)
        let components = candidate.split(separator: "/").map(String.init)
        let rootDepth = root.split(separator: "/").count
        var current = try MetadataDescriptor.openRoot()
        var rootDescriptor: MetadataDescriptor?
        var rootDevice: dev_t?
        var chain: [FileIdentity] = []
        var leaf: stat?

        for (index, component) in components.enumerated() {
            let last = index == components.count - 1
            let next = try current.openChild(component)
            // Read only flags before stat metadata. No logical/allocated size,
            // hashing, content read, or ubiquitous-file hydration is performed.
            try next.refuseDataless()
            let metadata = try next.metadata()
            let kind = metadata.st_mode & mode_t(S_IFMT)
            guard kind == mode_t(S_IFREG) || kind == mode_t(S_IFDIR) else {
                throw PathGuardError.unsupportedFileType
            }
            if !last && kind != mode_t(S_IFDIR) { throw PathGuardError.notDirectory }

            if index + 1 == rootDepth {
                rootDescriptor = next
                rootDevice = metadata.st_dev
                try next.refuseMountPoint(at: root)
            } else if index + 1 > rootDepth {
                guard metadata.st_dev == rootDevice else { throw PathGuardError.mountBoundary }
                try next.refuseMountPoint(at: "/" + components.prefix(index + 1).joined(separator: "/"))
            }
            chain.append(FileIdentity(metadata))
            leaf = metadata
            current = next
        }

        guard let rootDescriptor, let leaf else { throw PathGuardError.invalidPath }
        let resolvedRoot = try rootDescriptor.path()
        let resolved = try current.path()
        _ = try policy.validateCandidate(resolved)
        // If an opened ancestor was moved while walking, the descriptor reports
        // its new location. Refuse even a move to a different safe location.
        guard SafeRoots.sameBytes(resolvedRoot, root), SafeRoots.sameBytes(resolved, candidate) else {
            throw PathGuardError.changed
        }
        return ValidatedPath(resolvedPath: resolved, root: root, chain: chain, modification: ModificationIdentity(leaf))
    }

    /// Reopens the entire path. Parent replacement is significant even if the
    /// leaf inode is moved back. No caller can turn a receipt into removal here.
    public func revalidate(_ receipt: ValidatedPath) throws -> ValidatedPath {
        let fresh = try validate(receipt.resolvedPath)
        guard SafeRoots.sameBytes(fresh.root, receipt.root), fresh.chain == receipt.chain,
              fresh.modification == receipt.modification else {
            throw PathGuardError.changed
        }
        return fresh
    }
}

fileprivate struct FileIdentity: Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let generation: UInt32
    let kind: UInt16
    let owner: UInt32
    let group: UInt32
    let bornSeconds: Int
    let bornNanoseconds: Int

    init(_ metadata: stat) {
        device = metadata.st_dev
        inode = metadata.st_ino
        generation = metadata.st_gen
        kind = metadata.st_mode & mode_t(S_IFMT)
        owner = metadata.st_uid
        group = metadata.st_gid
        bornSeconds = metadata.st_birthtimespec.tv_sec
        bornNanoseconds = metadata.st_birthtimespec.tv_nsec
    }
}

fileprivate struct ModificationIdentity: Equatable, Sendable {
    let changedSeconds: Int
    let changedNanoseconds: Int
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let flags: UInt32
    let mode: UInt16
    let links: UInt16

    init(_ metadata: stat) {
        changedSeconds = metadata.st_ctimespec.tv_sec
        changedNanoseconds = metadata.st_ctimespec.tv_nsec
        modifiedSeconds = metadata.st_mtimespec.tv_sec
        modifiedNanoseconds = metadata.st_mtimespec.tv_nsec
        flags = metadata.st_flags
        mode = metadata.st_mode
        links = metadata.st_nlink
    }
}

/// Descriptor ownership is scoped to one synchronous validation call.
private final class MetadataDescriptor {
    let value: Int32

    private init(_ value: Int32) { self.value = value }
    deinit { _ = Darwin.close(value) }

    static func openRoot() throws -> MetadataDescriptor {
        let descriptor = Darwin.open("/", O_EVTONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw systemError() }
        return MetadataDescriptor(descriptor)
    }

    func openChild(_ name: String) throws -> MetadataDescriptor {
        // O_DIRECTORY makes Darwin report symlink ancestors as ENOTDIR rather
        // than ELOOP. Metadata-only opens preserve a distinct symlink refusal;
        // validate checks directory kind before descending into any child.
        let flags = O_EVTONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
        let descriptor = name.withCString { Darwin.openat(value, $0, flags) }
        guard descriptor >= 0 else { throw Self.systemError() }
        return MetadataDescriptor(descriptor)
    }

    func refuseDataless() throws {
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = attrgroup_t(ATTR_CMN_FLAGS)
        var flags = FlagsBuffer()
        guard Darwin.fgetattrlist(value, &attributes, &flags, MemoryLayout<FlagsBuffer>.size, 0) == 0 else {
            throw Self.systemError()
        }
        guard flags.length == MemoryLayout<FlagsBuffer>.size else { throw PathGuardError.invalidPath }
        guard flags.flags & UInt32(SF_DATALESS) == 0 else { throw PathGuardError.dataless }
    }

    func metadata() throws -> stat {
        var result = stat()
        guard Darwin.fstat(value, &result) == 0 else { throw Self.systemError() }
        // Recheck flags from this same descriptor in case they changed since
        // the flags-only query. No file sizes from this structure are consumed.
        guard result.st_flags & UInt32(SF_DATALESS) == 0 else { throw PathGuardError.dataless }
        return result
    }

    func path() throws -> String {
        var bytes = [CChar](repeating: 0, count: Int(PATH_MAX))
        let result = bytes.withUnsafeMutableBufferPointer { Darwin.fcntl(value, F_GETPATH, $0.baseAddress!) }
        guard result == 0 else { throw Self.systemError() }
        let utf8 = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let path = String(bytes: utf8, encoding: .utf8) else { throw PathGuardError.invalidPath }
        return path
    }

    func refuseMountPoint(at path: String) throws {
        var filesystem = statfs()
        guard Darwin.fstatfs(value, &filesystem) == 0 else { throw Self.systemError() }
        let mountPath = withUnsafeBytes(of: filesystem.f_mntonname) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
        }
        guard let mountPath else { throw PathGuardError.invalidPath }
        if SafeRoots.sameBytes(path, mountPath) { throw PathGuardError.mountBoundary }
    }

    private static func systemError() -> PathGuardError {
        switch errno {
        case ELOOP: .symbolicLink
        case ENOENT: .missing
        case ENOTDIR: .notDirectory
        case ENAMETOOLONG, EINVAL: .invalidPath
        default: .inaccessible(errno)
        }
    }
}

private struct FlagsBuffer {
    var length: UInt32 = 0
    var flags: UInt32 = 0
}
