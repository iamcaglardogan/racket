import Darwin
import Foundation

/// Read-only observations. These values can never be passed to RemovalEngine as
/// cleanup authority, and shared APFS extents are not reclaimable-space promises.
public struct StorageExplorerEntry: Identifiable, Sendable {
    public enum Kind: String, Sendable { case file, directory, package }

    public let id: Data
    /// Original filesystem bytes are retained independently of Swift String's
    /// canonical-equivalence comparison and Foundation URL transformations.
    public let rawPath: String
    public let url: URL
    public let name: String
    public let kind: Kind
    public let allocatedBytes: UInt64
    public let issueCount: Int
    public var isComplete: Bool { issueCount == 0 }

    init(rawPath: String, name: String, kind: Kind, allocatedBytes: UInt64, issueCount: Int) {
        self.id = Data(rawPath.utf8)
        self.rawPath = rawPath
        self.url = storageURL(rawPath)
        self.name = name
        self.kind = kind
        self.allocatedBytes = allocatedBytes
        self.issueCount = issueCount
    }
}

public struct StorageExplorerIssue: Sendable {
    public enum Reason: Equatable, Sendable {
        case dataless
        case symbolicLink
        case package
        case unsupportedFileType
        case metadataUnavailable(Int32)
        case unsupportedMetadata
        case invalidPath
        case notDirectory
        case changed
        case mountBoundary
        case duplicateHardLink
        case entryLimit
        case depthLimit
        case timeLimit
        case sizeOverflow
    }

    public let url: URL
    public let reason: Reason
}

public struct StorageExplorerOptions: Sendable {
    public let maxEntries: Int
    public let maxDepth: Int
    public let maxDurationSeconds: Int

    public init(maxEntries: Int = 100_000, maxDepth: Int = 24, maxDurationSeconds: Int = 30) {
        self.maxEntries = min(max(maxEntries, 1), 100_000)
        self.maxDepth = min(max(maxDepth, 1), 32)
        self.maxDurationSeconds = min(max(maxDurationSeconds, 1), 120)
    }
}

public struct StorageExplorerReport: Sendable {
    public let rootURL: URL
    public var rawRootPath: String { rootURL.path }
    public let entries: [StorageExplorerEntry]
    public let issues: [StorageExplorerIssue]
    public let visitedEntryCount: UInt64
    public let allocatedBytes: UInt64
    /// Every skip or limit makes the report partial, including packages and links.
    public var isComplete: Bool { issues.isEmpty }
}

/// A bounded explorer for a caller-selected folder. It has no removal methods.
/// Metadata and enumeration run off the main actor without materializing cloud
/// placeholders. Call explore again for a chosen directory to drill down.
public struct StorageExplorer: Sendable {
    private let calculator: SizeCalculator
    private let packageCheck: @Sendable (String) throws -> Bool

    public init() {
        calculator = SizeCalculator()
        packageCheck = storageIsPackage
    }

    init(calculator: SizeCalculator, packageCheck: @escaping @Sendable (String) throws -> Bool = storageIsPackage) {
        self.calculator = calculator
        self.packageCheck = packageCheck
    }

    public func explore(at url: URL, options: StorageExplorerOptions = .init()) async throws -> StorageExplorerReport {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try exploreSynchronously(at: url, options: options)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    private func exploreSynchronously(at url: URL, options: StorageExplorerOptions) throws -> StorageExplorerReport {
        let path: String
        do { path = try storagePath(url) }
        catch { return report(root: url, entries: [], state: StorageWalkState(options: options), error: error) }
        do {
            return try withoutDatalessMaterialization {
                var state = StorageWalkState(options: options)
                let origin: StorageOpenDirectory
                do { origin = try StorageOpenDirectory.open(path: path, calculator: calculator, packageCheck: packageCheck) }
                catch is CancellationError { throw CancellationError() }
                catch { return report(root: url, entries: [], state: state, error: error) }
                let entries = try visit(origin, depth: 0, state: &state)
                let ordered = entries.sorted {
                    if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
                    return $0.name.utf8.lexicographicallyPrecedes($1.name.utf8)
                }
                let total = sum(ordered, root: url, state: &state)
                return StorageExplorerReport(rootURL: storageURL(path, isDirectory: true), entries: ordered,
                    issues: state.issues, visitedEntryCount: state.visited, allocatedBytes: total)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { return report(root: url, entries: [], state: StorageWalkState(options: options), error: error) }
    }

    private func visit(_ directory: StorageOpenDirectory, depth: Int, state: inout StorageWalkState) throws -> [StorageExplorerEntry] {
        try Task.checkCancellation()
        var entries: [StorageExplorerEntry] = []
        do {
            try directory.verify()
            let readable = try directory.descriptor.readableDirectory()
            try readable.requirePath(directory.path)
            let opened = try calculator.inspect(descriptor: readable.value, path: directory.path, includeSize: false)
            guard opened.fingerprint == directory.metadata.fingerprint else { throw StorageReadError.changed }
            while !state.stopped {
                try Task.checkCancellation()
                guard !state.expired(at: directory.path) else { break }
                try directory.verify()
                let batch = try BulkDirectoryReader.next(descriptor: readable.value)
                if batch.isEmpty { break }
                for entry in batch.sorted(by: { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }) {
                    try Task.checkCancellation()
                    guard !state.expired(at: directory.path) else { break }
                    guard state.visited < UInt64(state.options.maxEntries) else {
                        state.add(directory.path, .entryLimit)
                        state.stopped = true
                        break
                    }
                    state.visited += 1
                    let childPath = directory.path == "/" ? "/" + entry.name : directory.path + "/" + entry.name
                    let firstIssue = state.issues.count
                    do {
                        if entry.error != 0 { throw scanSystemError(entry.error) }
                        guard let flags = entry.flags else { throw ScanMetadataError.unsupportedMetadata }
                        // A bulk batch requests only names/flags. No explicit stat,
                        // size or content access is allowed before this gate.
                        if flags & UInt32(SF_DATALESS) != 0 { throw ScanMetadataError.dataless }
                        try directory.verify()
                        let child = try directory.descriptor.child(entry.name)
                        let gated = try calculator.inspect(descriptor: child.value, path: childPath, includeSize: false)
                        guard gated.identity.device == directory.metadata.identity.device else { throw StorageReadError.mountBoundary }
                        try child.refuseMountPoint(childPath)
                        try directory.verify()
                        var bytes: UInt64 = 0
                        let kind: StorageExplorerEntry.Kind
                        if gated.kind == .directory {
                            try child.requirePath(childPath)
                            if try packageCheck(childPath) {
                                kind = .package
                                state.add(childPath, .package)
                            } else {
                                kind = .directory
                                if depth + 1 < state.options.maxDepth {
                                    let next = StorageOpenDirectory(descriptor: child, path: childPath, metadata: gated,
                                        anchors: directory.anchors + [StorageAnchor(descriptor: child, path: childPath)])
                                    bytes = sum(try visit(next, depth: depth + 1, state: &state), root: storageURL(childPath), state: &state)
                                } else { state.add(childPath, .depthLimit) }
                            }
                        } else {
                            kind = .file
                            let sized = try calculator.inspect(descriptor: child.value, path: childPath, includeSize: true)
                            guard sized.fingerprint == gated.fingerprint else { throw StorageReadError.changed }
                            if state.identities.insert(sized.identity).inserted { bytes = sized.allocatedSize }
                            else { state.add(childPath, .duplicateHardLink) }
                        }
                        let fresh = try directory.descriptor.child(entry.name)
                        let rechecked = try calculator.inspect(descriptor: fresh.value, path: childPath, includeSize: false)
                        try directory.verify()
                        if rechecked.kind == .directory { try fresh.requirePath(childPath) }
                        guard rechecked.fingerprint == gated.fingerprint else { throw StorageReadError.changed }
                        entries.append(StorageExplorerEntry(rawPath: childPath, name: entry.name, kind: kind,
                            allocatedBytes: bytes, issueCount: state.issues.count - firstIssue))
                    } catch is CancellationError { throw CancellationError() }
                    catch { state.add(childPath, storageIssueReason(error)) }
                }
            }
            try directory.verify()
            let final = try calculator.inspect(descriptor: readable.value, path: directory.path, includeSize: false)
            guard final.fingerprint == opened.fingerprint else { throw StorageReadError.changed }
            return entries
        } catch is CancellationError { throw CancellationError() }
        catch {
            // A renamed/replaced directory invalidates observations under it.
            state.add(directory.path, storageIssueReason(error))
            return []
        }
    }

    private func sum(_ entries: [StorageExplorerEntry], root: URL, state: inout StorageWalkState) -> UInt64 {
        var total: UInt64 = 0
        for entry in entries {
            let addition = total.addingReportingOverflow(entry.allocatedBytes)
            guard !addition.overflow else {
                state.add(root.path, .sizeOverflow)
                return total
            }
            total = addition.partialValue
        }
        return total
    }

    private func report(root: URL, entries: [StorageExplorerEntry], state: StorageWalkState, error: any Error) -> StorageExplorerReport {
        StorageExplorerReport(rootURL: root, entries: entries,
            issues: state.issues + [StorageExplorerIssue(url: root, reason: storageIssueReason(error))],
            visitedEntryCount: state.visited, allocatedBytes: 0)
    }
}

private struct StorageWalkState {
    let options: StorageExplorerOptions
    let deadline: ContinuousClock.Instant
    var issues: [StorageExplorerIssue] = []
    var visited: UInt64 = 0
    var stopped = false
    var identities: Set<ScanFileIdentity> = []

    init(options: StorageExplorerOptions) {
        self.options = options
        deadline = ContinuousClock.now.advanced(by: .seconds(options.maxDurationSeconds))
    }

    mutating func add(_ path: String, _ reason: StorageExplorerIssue.Reason) {
        issues.append(StorageExplorerIssue(url: storageURL(path), reason: reason))
    }

    mutating func expired(at path: String) -> Bool {
        guard !stopped else { return true }
        if ContinuousClock.now >= deadline {
            add(path, .timeLimit)
            stopped = true
            return true
        }
        return false
    }
}

enum StorageReadError: Error { case changed, mountBoundary, package }

struct StorageAnchor {
    let descriptor: StorageDescriptor
    let path: String
}

struct StorageOpenDirectory {
    let descriptor: StorageDescriptor
    let path: String
    let metadata: ScanMetadata
    let anchors: [StorageAnchor]

    static func open(path: String, calculator: SizeCalculator,
        packageCheck: @Sendable (String) throws -> Bool = storageIsPackage) throws -> StorageOpenDirectory {
        var current = try StorageDescriptor.root()
        var currentPath = "/"
        var metadata = try calculator.inspect(descriptor: current.value, path: currentPath, includeSize: false)
        var anchors = [StorageAnchor(descriptor: current, path: currentPath)]
        for component in path.split(separator: "/") {
            try Task.checkCancellation()
            currentPath = currentPath == "/" ? "/" + component : currentPath + "/" + component
            current = try current.child(String(component))
            // inspect gates flags and cloud residency before its internal fstat.
            metadata = try calculator.inspect(descriptor: current.value, path: currentPath, includeSize: false)
            guard metadata.kind == .directory else { throw PathGuardError.notDirectory }
            try current.requirePath(currentPath)
            if try packageCheck(currentPath) { throw StorageReadError.package }
            anchors.append(StorageAnchor(descriptor: current, path: currentPath))
        }
        let result = StorageOpenDirectory(descriptor: current, path: path, metadata: metadata, anchors: anchors)
        try result.verify()
        return result
    }

    func verify() throws { for anchor in anchors { try anchor.descriptor.requirePath(anchor.path) } }
}

final class StorageDescriptor {
    let value: Int32
    private init(_ value: Int32) throws {
        guard value >= 0 else { throw scanSystemError(errno) }
        self.value = value
    }
    deinit { _ = Darwin.close(value) }

    static func root() throws -> StorageDescriptor {
        try StorageDescriptor(Darwin.open("/", O_EVTONLY | O_NOFOLLOW | O_DIRECTORY | O_CLOEXEC))
    }

    func child(_ name: String) throws -> StorageDescriptor {
        try StorageDescriptor(name.withCString { Darwin.openat(value, $0, O_EVTONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) })
    }

    func readableDirectory() throws -> StorageDescriptor {
        try StorageDescriptor(Darwin.openat(value, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
    }

    func requirePath(_ expected: String) throws {
        var bytes = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard bytes.withUnsafeMutableBufferPointer({ Darwin.fcntl(value, F_GETPATH, $0.baseAddress!) }) == 0 else {
            throw scanSystemError(errno)
        }
        let utf8 = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let path = String(bytes: utf8, encoding: .utf8), SafeRoots.sameBytes(path, expected) else { throw StorageReadError.changed }
    }

    func refuseMountPoint(_ path: String) throws {
        var value = statfs()
        guard Darwin.fstatfs(self.value, &value) == 0 else { throw scanSystemError(errno) }
        let mount = withUnsafeBytes(of: value.f_mntonname) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) }
        guard let mount else { throw ScanMetadataError.unsupportedMetadata }
        if SafeRoots.sameBytes(mount, path) { throw StorageReadError.mountBoundary }
    }
}

func storageURL(_ path: String, isDirectory: Bool = false) -> URL {
    // The String-path initializer, and even a percent-encoded URL(string:), may
    // normalize the filesystem representation. This initializer retains the
    // original UTF-8 bytes for both URL.path and Foundation metadata operations.
    path.withCString { URL(fileURLWithFileSystemRepresentation: $0, isDirectory: isDirectory, relativeTo: nil) }
}

func storagePath(_ url: URL) throws -> String {
    guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else { throw PathGuardError.invalidPath }
    return try SafeRoots.normalizeAbsolute(url.path)
}

func storageIsPackage(_ path: String) throws -> Bool {
    var url = storageURL(path, isDirectory: true)
    url.removeAllCachedResourceValues()
    guard let result = try url.resourceValues(forKeys: [.isPackageKey]).isPackage else { throw ScanMetadataError.unsupportedMetadata }
    return result
}

func storageIssueReason(_ error: any Error) -> StorageExplorerIssue.Reason {
    switch error {
    case ScanMetadataError.dataless, PathGuardError.dataless: .dataless
    case PathGuardError.symbolicLink: .symbolicLink
    case StorageReadError.package: .package
    case ScanMetadataError.unsupportedFileType, PathGuardError.unsupportedFileType: .unsupportedFileType
    case ScanMetadataError.system(let code): .metadataUnavailable(code)
    case PathGuardError.missing: .metadataUnavailable(ENOENT)
    case PathGuardError.inaccessible: .metadataUnavailable(EACCES)
    case PathGuardError.invalidPath: .invalidPath
    case PathGuardError.notDirectory: .notDirectory
    case ScanMetadataError.changed, PathGuardError.changed, StorageReadError.changed: .changed
    case PathGuardError.mountBoundary, StorageReadError.mountBoundary: .mountBoundary
    default: .unsupportedMetadata
    }
}
