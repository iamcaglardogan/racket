import CryptoKit
import Darwin
import Foundation

struct ApplicationTreeSnapshot: Sendable {
    let identity: ManifestIdentity
    let digest: String
    let allocatedSize: UInt64
    let count: Int
}

/// App bundles have a separate, bounded directory capability. Nothing here
/// changes SafeRoots or the regular-file cleanup/undo capabilities.
struct ApplicationFileSystem: Sendable {
    let policy: ApplicationPolicy
    var calculator = SizeCalculator()
    static let maximumDescendants = 50_000
    static let maximumDepth = 64

    func open(_ path: String, trusted: Bool = true) throws -> RemovalLocation {
        guard SafeRoots.sameBytes(try SafeRoots.normalizeAbsolute(path), path), path != "/" else {
            throw ApplicationManagementError.invalidApplication
        }
        var current = try RemovalDescriptor(Darwin.open("/", O_EVTONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        var anchors: [RemovalAnchor] = []
        let components = path.split(separator: "/").map(String.init)
        var prefix = ""
        for (index, name) in components.enumerated() {
            prefix += "/" + name
            let child = try current.child(name)
            let metadata = try calculator.inspect(descriptor: child.value, path: prefix, includeSize: false)
            _ = try child.requireLocalVolume()
            try child.requirePath(prefix)
            if metadata.kind == .directory, trusted { try requireTrusted(child, metadata: metadata, path: prefix) }
            if index == components.count - 1 {
                let location = RemovalLocation(path: path, name: name, parent: current, descriptor: child,
                                               metadata: metadata, anchors: anchors)
                if trusted { try verify(anchors) }
                return location
            }
            guard metadata.kind == .directory else { throw ApplicationManagementError.invalidApplication }
            anchors.append(RemovalAnchor(descriptor: child, path: prefix, identity: ManifestIdentity(metadata.fingerprint)))
            current = child
        }
        throw ApplicationManagementError.invalidApplication
    }

    func requireTrusted(_ descriptor: RemovalDescriptor, metadata: ScanMetadata, path: String) throws {
        // /Applications is commonly root:admin 0775. Its known admin group is
        // accepted only at this exact system namespace, never for app contents.
        if path == "/Applications", metadata.kind == .directory, metadata.fingerprint.owner == 0,
           metadata.fingerprint.group == 80, metadata.fingerprint.mode & 0o002 == 0 {
            try descriptor.requireNoACLGrants()
            return
        }
        try descriptor.requireTrustedDirectory(metadata, path: path)
    }

    func verify(_ anchors: [RemovalAnchor]) throws {
        for anchor in anchors {
            try anchor.descriptor.requirePath(anchor.path)
            let fresh = try calculator.inspect(descriptor: anchor.descriptor.value, path: anchor.path, includeSize: false)
            try requireTrusted(anchor.descriptor, metadata: fresh, path: anchor.path)
            let after = ManifestIdentity(fresh.fingerprint)
            let before = anchor.identity
            guard before.device == after.device, before.inode == after.inode, before.generation == after.generation,
                  before.owner == after.owner, before.group == after.group, before.mode == after.mode,
                  before.flags == after.flags, before.bornSeconds == after.bornSeconds,
                  before.bornNanoseconds == after.bornNanoseconds else { throw ApplicationManagementError.changed }
        }
    }

    func entries(_ location: RemovalLocation) throws -> [BulkDirectoryEntry] {
        guard location.metadata.kind == .directory else { throw ApplicationManagementError.invalidApplication }
        let descriptor = try RemovalDescriptor(location.name.withCString {
            Darwin.openat(location.parent.value, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        })
        try descriptor.requirePath(location.path)
        let before = try calculator.inspect(descriptor: descriptor.value, path: location.path, includeSize: false)
        guard before.fingerprint == location.metadata.fingerprint else { throw ApplicationManagementError.changed }
        var result: [BulkDirectoryEntry] = []
        var names = Set<Data>()
        while true {
            try Task.checkCancellation()
            let batch = try BulkDirectoryReader.next(descriptor: descriptor.value)
            if batch.isEmpty { break }
            guard result.count <= Self.maximumDescendants - batch.count else { throw ApplicationManagementError.scanLimit }
            for entry in batch {
                guard names.insert(Data(entry.name.utf8)).inserted else { throw ApplicationManagementError.changed }
                result.append(entry)
            }
        }
        let after = try calculator.inspect(descriptor: descriptor.value, path: location.path, includeSize: false)
        guard before.fingerprint == after.fingerprint else { throw ApplicationManagementError.changed }
        try descriptor.requirePath(location.path)
        return result.sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
    }

    func application(at location: RemovalLocation) throws -> InstalledApplication {
        guard location.metadata.kind == .directory, location.path.lowercased().hasSuffix(".app") else {
            throw ApplicationManagementError.invalidApplication
        }
        let metadata = try readInfoPlist(location.path)
        guard metadata["CFBundlePackageType"] as? String == "APPL",
              let bundleID = metadata["CFBundleIdentifier"] as? String,
              ApplicationPolicy.validBundleIdentifier(bundleID),
              let executable = metadata["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), executable != ".", executable != "..",
              !executable.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ApplicationManagementError.invalidApplication
        }
        let identity = ManifestIdentity(location.metadata.fingerprint)
        let rawName = metadata["CFBundleDisplayName"] as? String ?? metadata["CFBundleName"] as? String
        let fallback = String(location.name.dropLast(4))
        let name = boundedText(rawName) ?? fallback
        let version = boundedText(metadata["CFBundleShortVersionString"] as? String)
            ?? boundedText(metadata["CFBundleVersion"] as? String) ?? "Unknown"
        let reason: String?
        if (try? policy.validateRemovalPath(location.path)) == nil {
            reason = "System location or unsupported application folder"
        } else if bundleID.lowercased().hasPrefix("com.apple.") {
            reason = "Apple system application"
        } else if bundleID == "io.github.iamcaglardogan.racket" {
            reason = "RACKET cannot remove itself"
        } else if identity.owner != geteuid() || geteuid() == 0 {
            reason = "Administrator privileges or another owner's permission required"
        } else if identity.mode & 0o022 != 0 {
            reason = "Application is writable by other users"
        } else {
            reason = nil
        }
        return InstalledApplication(path: location.path, name: name, bundleIdentifier: bundleID, version: version,
                                    protectionReason: reason, allocatedSize: nil, identity: identity)
    }

    private func boundedText(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf8.count <= 255,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return value
    }

    private func readInfoPlist(_ appPath: String) throws -> [String: Any] {
        let location = try open(appPath + "/Contents/Info.plist", trusted: false)
        guard location.metadata.kind == .regularFile, location.metadata.fingerprint.links == 1 else {
            throw ApplicationManagementError.invalidApplication
        }
        let descriptor = try RemovalDescriptor(location.name.withCString {
            Darwin.openat(location.parent.value, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        })
        try descriptor.requirePath(location.path)
        let before = try calculator.inspect(descriptor: descriptor.value, path: location.path, includeSize: false)
        guard before.fingerprint == location.metadata.fingerprint else { throw ApplicationManagementError.changed }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor.value, $0.baseAddress!, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw removalSystemError(errno) }
            if count == 0 { break }
            guard data.count <= 1_048_576 - count else { throw ApplicationManagementError.invalidApplication }
            data.append(contentsOf: buffer.prefix(count))
        }
        let after = try calculator.inspect(descriptor: descriptor.value, path: location.path, includeSize: false)
        guard before.fingerprint == after.fingerprint else { throw ApplicationManagementError.changed }
        try descriptor.requirePath(location.path)
        guard let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw ApplicationManagementError.invalidApplication
        }
        return value
    }

    func snapshot(_ root: RemovalLocation) throws -> ApplicationTreeSnapshot {
        guard root.metadata.kind == .directory else { throw ApplicationManagementError.invalidApplication }
        var digest = SHA256()
        var count = 0
        var allocated: UInt64 = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func visit(_ location: RemovalLocation, relative: String, depth: Int) throws {
            try Task.checkCancellation()
            guard depth <= Self.maximumDepth, count < Self.maximumDescendants else { throw ApplicationManagementError.scanLimit }
            count += 1
            let metadata = try calculator.inspect(descriptor: location.descriptor.value, path: location.path, includeSize: true)
            guard metadata.identity.device == root.metadata.identity.device else { throw PathGuardError.mountBoundary }
            let value = metadata.fingerprint
            guard geteuid() != 0, value.owner == geteuid(), value.mode & 0o022 == 0 else {
                throw ApplicationManagementError.unsafeDescendant
            }
            if metadata.kind == .regularFile, value.links != 1 { throw ApplicationManagementError.unsafeDescendant }
            try location.descriptor.requireNoACLGrants()
            try location.descriptor.requirePath(location.path)
            let addition = allocated.addingReportingOverflow(metadata.allocatedSize)
            guard !addition.overflow else { throw ApplicationManagementError.scanLimit }
            allocated = addition.partialValue
            let record = ApplicationSnapshotRecord(relativePath: relative, identity: ManifestIdentity(value), allocatedSize: metadata.allocatedSize,
                                                   changedSeconds: relative.isEmpty ? nil : value.changedSeconds,
                                                   changedNanoseconds: relative.isEmpty ? nil : value.changedNanoseconds)
            let bytes = try encoder.encode(record)
            digest.update(data: bytes)
            digest.update(data: Data([10]))
            if metadata.kind == .directory {
                let current = RemovalLocation(path: location.path, name: location.name, parent: location.parent,
                                              descriptor: location.descriptor, metadata: metadata, anchors: location.anchors)
                for entry in try entries(current) {
                    guard entry.error == 0, let flags = entry.flags, flags & UInt32(SF_DATALESS) == 0,
                          !ApplicationPolicy.protectedName(entry.name) else { throw ApplicationManagementError.unsafeDescendant }
                    let path = location.path + "/" + entry.name
                    // Opening with O_NOFOLLOW and the metadata gate refuses all
                    // symlinks, including framework aliases, without following them.
                    let child = try location.descriptor.child(entry.name)
                    let childMetadata = try calculator.inspect(descriptor: child.value, path: path, includeSize: false)
                    _ = try child.requireLocalVolume()
                    let childLocation = RemovalLocation(path: path, name: entry.name, parent: location.descriptor,
                                                        descriptor: child, metadata: childMetadata, anchors: [])
                    try visit(childLocation, relative: relative.isEmpty ? entry.name : relative + "/" + entry.name, depth: depth + 1)
                }
            }
            let after = try calculator.inspect(descriptor: location.descriptor.value, path: location.path, includeSize: false)
            guard after.fingerprint == metadata.fingerprint else { throw ApplicationManagementError.changed }
            try location.descriptor.requirePath(location.path)
        }
        try verify(root.anchors)
        try visit(root, relative: "", depth: 0)
        try verify(root.anchors)
        return ApplicationTreeSnapshot(identity: ManifestIdentity(root.metadata.fingerprint),
                                       digest: digest.finalize().map { String(format: "%02x", $0) }.joined(),
                                       allocatedSize: allocated, count: count)
    }

    func stagingPath(item: ManifestItem, sessionID: UUID) throws -> String {
        try policy.validateRemovalPath(item.originalPath)
        return (item.originalPath as NSString).deletingLastPathComponent + "/.racket-app-staging-" + String(geteuid())
            + "/" + sessionID.uuidString + "/" + item.id.uuidString + ".app"
    }

    func stagingParent(item: ManifestItem, sessionID: UUID) throws -> RemovalLocation {
        try policy.validateRemovalPath(item.originalPath)
        var parent = try open((item.originalPath as NSString).deletingLastPathComponent)
        for name in [".racket-app-staging-" + String(geteuid()), sessionID.uuidString] {
            try verify(parent.anchors)
            try parent.descriptor.requirePath(parent.path)
            if Darwin.mkdirat(parent.descriptor.value, name, 0o700) != 0, errno != EEXIST { throw removalSystemError(errno) }
            let child = try open(parent.path + "/" + name)
            try child.descriptor.requirePrivateDirectory(child.metadata)
            guard child.metadata.identity.device == item.identity.device else { throw PathGuardError.mountBoundary }
            parent = child
        }
        return parent
    }

    func move(_ source: RemovalLocation, into parent: RemovalLocation, name: String, beforeRename: () throws -> Void = {}) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              source.metadata.identity.device == parent.metadata.identity.device,
              parent.metadata.kind == .directory else { throw ApplicationManagementError.unsafeDescendant }
        try verify(source.anchors)
        try verify(parent.anchors)
        try source.descriptor.requirePath(source.path)
        try parent.descriptor.requirePath(parent.path)
        try beforeRename()
        let result = source.name.withCString { sourceName in
            name.withCString { destinationName in
                renameatx_np(source.parent.value, sourceName, parent.descriptor.value, destinationName,
                             UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY))
            }
        }
        guard result == 0 else { throw removalSystemError(errno) }
    }
}

private struct ApplicationSnapshotRecord: Codable {
    let relativePath: String
    let identity: ManifestIdentity
    let allocatedSize: UInt64
    let changedSeconds: Int?
    let changedNanoseconds: Int?
}
