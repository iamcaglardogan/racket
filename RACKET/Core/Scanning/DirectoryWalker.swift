import Darwin
import Foundation

/// Synchronous so the per-thread no-materialization policy covers every call,
/// including ancestor lookup. A Swift task must never suspend inside this scope.
public struct DirectoryWalker: Sendable {
    private let policy: SafeRoots
    private let entryLimit: Int
    private let calculator: SizeCalculator

    public init() throws {
        self.init(policy: try .currentUser())
    }

    init(policy: SafeRoots, entryLimit: Int = 20_000, calculator: SizeCalculator = SizeCalculator()) {
        self.policy = policy
        self.entryLimit = min(max(entryLimit, 1), 100_000)
        self.calculator = calculator
    }

    public func walk(path: String, maxDepth: Int, skipExcludedFromBackup: Bool = false) throws -> DirectoryWalk {
        try Task.checkCancellation()
        do {
            guard (1...32).contains(maxDepth) else { throw PathGuardError.invalidPath }
            let resolved = try policy.validateScanRoot(path)
            return try withoutDatalessMaterialization {
                let origin = try openOrigin(resolved, skipExcludedFromBackup: skipExcludedFromBackup)
                var state = WalkState()
                try visit(origin, depth: 0, maxDepth: maxDepth, skipExcludedFromBackup: skipExcludedFromBackup, state: &state)
                return DirectoryWalk(
                    files: state.files.sorted { $0.resolvedPath.utf8.lexicographicallyPrecedes($1.resolvedPath.utf8) },
                    issues: state.issues,
                    visitedEntryCount: state.visited
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return DirectoryWalk(files: [], issues: [issue(path: path, error: error)], visitedEntryCount: 0)
        }
    }

    private func openOrigin(_ path: String, skipExcludedFromBackup: Bool) throws -> OpenScanDirectory {
        let root = try policy.root(containing: path)
        var current = try ScanDescriptor.root()
        var anchors: [ScanAnchor] = []
        var currentPath = ""
        var rootDevice: Int32?
        var originMetadata: ScanMetadata?
        for component in path.split(separator: "/") {
            try Task.checkCancellation()
            currentPath += "/" + component
            current = try current.child(String(component))
            try current.requirePath(currentPath)
            let metadata = try calculator.inspect(
                descriptor: current.value, path: currentPath, includeSize: false,
                skipExcludedFromBackup: skipExcludedFromBackup && SafeRoots.isWithin(currentPath, root: path)
            )
            guard metadata.kind == .directory else { throw PathGuardError.notDirectory }
            if SafeRoots.sameBytes(currentPath, root) {
                rootDevice = metadata.identity.device
            }
            if let rootDevice {
                guard metadata.identity.device == rootDevice else { throw PathGuardError.mountBoundary }
                try current.refuseMountPoint(currentPath)
            }
            anchors.append(ScanAnchor(descriptor: current, path: currentPath))
            originMetadata = metadata
        }
        guard let originMetadata, let rootDevice else { throw PathGuardError.invalidPath }
        try verify(anchors)
        return OpenScanDirectory(descriptor: current, path: path, metadata: originMetadata, anchors: anchors, rootDevice: rootDevice)
    }

    private func visit(
        _ directory: OpenScanDirectory, depth: Int, maxDepth: Int,
        skipExcludedFromBackup: Bool, state: inout WalkState
    ) throws {
        try Task.checkCancellation()
        guard !state.limitReached else { return }
        do {
            try verify(directory.anchors)
            let readable = try directory.descriptor.readableDirectory()
            try readable.requirePath(directory.path)
            let opened = try calculator.inspect(descriptor: readable.value, path: directory.path, includeSize: false)
            guard opened.fingerprint == directory.metadata.fingerprint else { throw PathGuardError.changed }
            while !state.limitReached {
                try Task.checkCancellation()
                try verify(directory.anchors)
                let batch = try BulkDirectoryReader.next(descriptor: readable.value)
                if batch.isEmpty { break }
                for entry in batch {
                    try Task.checkCancellation()
                    guard state.visited < UInt64(entryLimit) else {
                        state.issues.append(WalkIssue(path: directory.path, reason: .entryLimit))
                        state.limitReached = true
                        break
                    }
                    state.visited += 1
                    let childPath = directory.path + "/" + entry.name
                    do {
                        _ = try policy.validateCandidate(childPath)
                        if entry.error != 0 { throw scanSystemError(entry.error) }
                        guard let flags = entry.flags else { throw ScanMetadataError.unsupportedMetadata }
                        if flags & UInt32(SF_DATALESS) != 0 { throw ScanMetadataError.dataless }
                        try verify(directory.anchors)
                        let child = try directory.descriptor.child(entry.name)
                        let gated = try calculator.inspect(
                            descriptor: child.value, path: childPath, includeSize: false,
                            skipExcludedFromBackup: skipExcludedFromBackup
                        )
                        guard gated.identity.device == directory.rootDevice else { throw PathGuardError.mountBoundary }
                        try child.refuseMountPoint(childPath)
                        try verify(directory.anchors)
                        if gated.kind == .directory { try child.requirePath(childPath) }
                        let metadata = try calculator.inspect(
                            descriptor: child.value, path: childPath, includeSize: true,
                            skipExcludedFromBackup: skipExcludedFromBackup
                        )
                        guard metadata.fingerprint == gated.fingerprint else { throw PathGuardError.changed }
                        // Reopen relative to the retained parent after pathname-based
                        // Foundation metadata. Replacement or symlink substitution
                        // invalidates this observation; it is never removal authority.
                        // A regular inode may have multiple hard-link names, so its
                        // F_GETPATH reverse lookup is not a unique name binding.
                        // Bind leaves through the verified parent + openat name,
                        // then compare a fresh no-follow open's full fingerprint.
                        let fresh = try directory.descriptor.child(entry.name)
                        let rechecked = try calculator.inspect(descriptor: fresh.value, path: childPath, includeSize: false)
                        try verify(directory.anchors)
                        if rechecked.kind == .directory { try fresh.requirePath(childPath) }
                        guard rechecked.fingerprint == metadata.fingerprint else { throw PathGuardError.changed }
                        if metadata.kind == .regularFile {
                            state.files.append(ScannedFile(
                                resolvedPath: childPath, allocatedSize: metadata.allocatedSize,
                                modifiedAt: metadata.modifiedAt, identity: metadata.identity,
                                observation: metadata.fingerprint
                            ))
                        } else if depth + 1 < maxDepth {
                            let next = OpenScanDirectory(
                                descriptor: child, path: childPath, metadata: metadata,
                                anchors: directory.anchors + [ScanAnchor(descriptor: child, path: childPath)],
                                rootDevice: directory.rootDevice
                            )
                            try visit(next, depth: depth + 1, maxDepth: maxDepth, skipExcludedFromBackup: skipExcludedFromBackup, state: &state)
                        } else {
                            state.issues.append(WalkIssue(path: childPath, reason: .depthLimit))
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        state.issues.append(issue(path: childPath, error: error))
                    }
                }
            }
            try verify(directory.anchors)
            let final = try calculator.inspect(descriptor: readable.value, path: directory.path, includeSize: false)
            guard final.fingerprint == opened.fingerprint else { throw PathGuardError.changed }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A changing directory is not a consistent scan. Discard observations
            // below it while retaining a visible refusal in the report.
            state.files = state.files.filter { !SafeRoots.isWithin($0.resolvedPath, root: directory.path) }
            state.issues.append(issue(path: directory.path, error: error))
        }
    }

    private func verify(_ anchors: [ScanAnchor]) throws {
        for anchor in anchors { try anchor.descriptor.requirePath(anchor.path) }
    }

    private func issue(path: String, error: any Error) -> WalkIssue {
        let reason: ScanIssueReason
        switch error {
        case let refusal as PathGuardError: reason = .pathRefused(refusal)
        case ScanMetadataError.dataless: reason = .dataless
        case ScanMetadataError.excludedFromBackup: reason = .excludedFromBackup
        case ScanMetadataError.unsupportedFileType: reason = .pathRefused(.unsupportedFileType)
        case ScanMetadataError.changed: reason = .pathRefused(.changed)
        case ScanMetadataError.system(let code): reason = .metadataUnavailable(code)
        default: reason = .unsupportedMetadata
        }
        return WalkIssue(path: path, reason: reason)
    }
}

private struct WalkState {
    var files: [ScannedFile] = []
    var issues: [WalkIssue] = []
    var visited: UInt64 = 0
    var limitReached = false
}

private struct OpenScanDirectory {
    let descriptor: ScanDescriptor
    let path: String
    let metadata: ScanMetadata
    let anchors: [ScanAnchor]
    let rootDevice: Int32
}

private struct ScanAnchor {
    let descriptor: ScanDescriptor
    let path: String
}

private final class ScanDescriptor {
    let value: Int32
    private init(_ value: Int32) throws {
        guard value >= 0 else { throw scanSystemError(errno) }
        self.value = value
    }
    deinit { _ = Darwin.close(value) }

    static func root() throws -> ScanDescriptor {
        try ScanDescriptor(Darwin.open("/", O_EVTONLY | O_NOFOLLOW | O_DIRECTORY | O_CLOEXEC))
    }

    func child(_ name: String) throws -> ScanDescriptor {
        try ScanDescriptor(name.withCString { Darwin.openat(value, $0, O_EVTONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) })
    }

    func readableDirectory() throws -> ScanDescriptor {
        try ScanDescriptor(Darwin.openat(value, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
    }

    func requirePath(_ expected: String) throws {
        var bytes = [CChar](repeating: 0, count: Int(PATH_MAX))
        let result = bytes.withUnsafeMutableBufferPointer { Darwin.fcntl(value, F_GETPATH, $0.baseAddress!) }
        guard result == 0 else { throw scanSystemError(errno) }
        let utf8 = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let resolved = String(bytes: utf8, encoding: .utf8), SafeRoots.sameBytes(resolved, expected) else {
            throw PathGuardError.changed
        }
    }

    func refuseMountPoint(_ path: String) throws {
        var filesystem = statfs()
        guard Darwin.fstatfs(value, &filesystem) == 0 else { throw scanSystemError(errno) }
        let mount = withUnsafeBytes(of: filesystem.f_mntonname) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) }
        guard let mount else { throw ScanMetadataError.unsupportedMetadata }
        guard !SafeRoots.sameBytes(mount, path) else { throw PathGuardError.mountBoundary }
    }
}
