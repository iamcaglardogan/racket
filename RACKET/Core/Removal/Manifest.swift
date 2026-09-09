import CryptoKit
import Darwin
import Foundation

public struct ManifestIdentity: Codable, Equatable, Sendable {
    public let device: Int32
    public let inode: UInt64
    public let generation: UInt32
    public let owner: UInt32
    public let group: UInt32
    public let mode: UInt16
    public let flags: UInt32
    public let links: UInt16
    public let bornSeconds: Int
    public let bornNanoseconds: Int
    public let modifiedSeconds: Int
    public let modifiedNanoseconds: Int
}

public struct ManifestItem: Codable, Equatable, Sendable {
    public let id: UUID
    public let originalPath: String
    public let ruleID: String
    public let allocatedSize: UInt64
    public let identity: ManifestIdentity
}

public enum ManifestAction: String, Codable, Sendable {
    case prepared, staged, trashed, failed, refused, recoveryRequired
    case restorePrepared, restored, restoreFailed
}

public struct ManifestEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let action: ManifestAction
    public let item: ManifestItem
    public let stagingPath: String?
    public let trashPath: String?
    public let detail: String?
}

public struct ManifestSession: Sendable {
    public let id: UUID
    public let appVersion: String
    public let ruleSetVersion: String
    public let createdAt: Date
    public let events: [ManifestEvent]
}

public enum ManifestError: Error, Equatable, Sendable {
    case system(Int32)
    case unsafePath
    case unsafeMetadata
    case changed
    case invalidKey
    case invalidHeader
    case corruptJournal
    case limitExceeded
    case busy
}

/// Authenticated, durable NDJSON records, serialized across store instances by
/// advisory file locks. The engine, rather than this journal, validates event
/// transitions. No recovery operation silently discards a malformed tail.
///
/// The local key detects accidental damage and modifications by actors without
/// key access. It cannot defend against a malicious process running as the same
/// user, or detect truncation to a complete, previously authenticated prefix.
public final class ManifestStore: @unchecked Sendable {
    private let directory: String
    private let directoryIdentity: ManifestDirectoryIdentity
    private let key: Data
    private let operations: ScanMetadataOperations
    private let synchronize: @Sendable (Int32) throws -> Void
    private let lock = NSLock()

    static let maximumJournalBytes = 32 * 1_024 * 1_024
    static let maximumRecordBytes = 128 * 1_024
    static let maximumEvents = 10_000
    static let maximumVersionBytes = 256

    public convenience init() throws {
        try self.init(
            directory: FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/RACKET/Manifests",
            key: nil, operations: .live, synchronize: Self.sync
        )
    }

    /// Test-only storage always uses an isolated synthetic directory. Supplying
    /// a key does not write it to disk; the production initializer persists one.
    convenience init(
        directory: String, authenticationKey: Data,
        operations: ScanMetadataOperations = .live,
        synchronize: @escaping @Sendable (Int32) throws -> Void = ManifestStore.sync
    ) throws {
        try self.init(directory: directory, key: authenticationKey, operations: operations, synchronize: synchronize)
    }

    /// Exercises production key persistence without accessing a real home.
    convenience init(persistentDirectory: String) throws {
        try self.init(directory: persistentDirectory, key: nil, operations: .live, synchronize: Self.sync)
    }

    private init(
        directory: String, key: Data?, operations: ScanMetadataOperations,
        synchronize: @escaping @Sendable (Int32) throws -> Void
    ) throws {
        self.directory = directory
        self.operations = operations
        self.synchronize = synchronize
        let result = try withoutDatalessMaterialization {
            let descriptor = try Self.openDirectory(directory, create: true, operations: operations, synchronize: synchronize)
            defer { Darwin.close(descriptor) }
            let metadata = try Self.metadata(descriptor, path: directory, operations: operations)
            let authenticationKey: Data
            if let key {
                guard key.count == 32 else { throw ManifestError.invalidKey }
                authenticationKey = key
            } else {
                authenticationKey = try Self.loadKey(directory: descriptor, path: directory, operations: operations, synchronize: synchronize)
            }
            return (ManifestDirectoryIdentity(metadata), authenticationKey)
        }
        directoryIdentity = result.0
        self.key = result.1
    }

    public func createSession(appVersion: String, ruleSetVersion: String, now: Date = Date()) throws -> UUID {
        guard Self.validHeader(appVersion: appVersion, ruleSetVersion: ruleSetVersion, createdAt: now) else {
            throw ManifestError.invalidHeader
        }
        return try serialized {
            let descriptor = try self.openCurrentDirectory()
            defer { Darwin.close(descriptor) }
            let id = UUID()
            let name = self.fileName(id)
            let file = Darwin.openat(descriptor, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
            guard file >= 0 else { throw ManifestError.system(errno) }
            defer { Darwin.close(file) }
            try Self.fileLock(file, exclusive: true)
            defer { _ = flock(file, LOCK_UN) }
            try self.validateFile(file, parent: descriptor, name: name)
            let header = ManifestHeader(version: 1, id: id, appVersion: appVersion, ruleSetVersion: ruleSetVersion, createdAt: now)
            let line = try self.record(ManifestPayload(header: header, event: nil), sequence: 0, previous: Data(repeating: 0, count: 32))
            try Self.writeAll(line, to: file)
            try self.synchronize(file)
            try self.synchronize(descriptor)
            try self.validateFile(file, parent: descriptor, name: name)
            return id
        }
    }

    public func append(_ event: ManifestEvent, to sessionID: UUID) throws {
        try serialized {
            try self.withJournal(sessionID, writing: true) { file, parent, name in
                let parsed = try self.parse(Self.readAll(file, limit: Self.maximumJournalBytes), expected: sessionID)
                guard parsed.session.events.count < Self.maximumEvents else { throw ManifestError.limitExceeded }
                let line = try self.record(ManifestPayload(header: nil, event: event), sequence: UInt64(parsed.session.events.count + 1), previous: parsed.lastMAC)
                guard parsed.bytes.count <= Self.maximumJournalBytes - line.count else { throw ManifestError.limitExceeded }
                // O_APPEND keeps the record at the current end even after reads.
                // A failed write/sync leaves its evidence in place and throws.
                try Self.writeAll(line, to: file)
                try self.synchronize(file)
                try self.validateFile(file, parent: parent, name: name)
            }
        }
    }

    public func read(_ sessionID: UUID) throws -> ManifestSession {
        try serialized {
            try self.withJournal(sessionID, writing: false) { file, parent, name in
                let parsed = try self.parse(Self.readAll(file, limit: Self.maximumJournalBytes), expected: sessionID)
                try self.validateFile(file, parent: parent, name: name)
                return parsed.session
            }
        }
    }

    /// Exports the original authenticated NDJSON, only after full verification.
    public func export(_ sessionID: UUID) throws -> Data {
        try serialized {
            try self.withJournal(sessionID, writing: false) { file, parent, name in
                let parsed = try self.parse(Self.readAll(file, limit: Self.maximumJournalBytes), expected: sessionID)
                try self.validateFile(file, parent: parent, name: name)
                return parsed.bytes
            }
        }
    }

    /// Serializes entire removal/recovery operations without holding `lock`;
    /// the body may call append/read. A separate file avoids nested journal locks.
    func withExclusiveOperation<T>(_ body: () throws -> T) throws -> T {
        try withoutDatalessMaterialization {
            let parent = try openCurrentDirectory()
            defer { Darwin.close(parent) }
            let name = ".operation-lock"
            let file = try Self.openPrivateFile(parent: parent, path: directory, name: name, create: true, writable: true, operations: operations)
            defer { Darwin.close(file) }
            guard flock(file, LOCK_EX | LOCK_NB) == 0 else {
                if errno == EWOULDBLOCK { throw ManifestError.busy }
                throw ManifestError.system(errno)
            }
            defer { _ = flock(file, LOCK_UN) }
            try validateFile(file, parent: parent, name: name)
            let metadata = try Self.metadata(file, path: directory + "/" + name, operations: operations)
            guard metadata.st_size == 0 else { throw ManifestError.unsafeMetadata }
            try synchronize(file)
            try synchronize(parent)
            return try body()
        }
    }

    private func serialized<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try withoutDatalessMaterialization(body)
    }

    private func openCurrentDirectory() throws -> Int32 {
        let descriptor = try Self.openDirectory(directory, create: false, operations: operations, synchronize: synchronize)
        do {
            let current = try Self.metadata(descriptor, path: directory, operations: operations)
            guard ManifestDirectoryIdentity(current) == directoryIdentity else { throw ManifestError.changed }
            return descriptor
        } catch { Darwin.close(descriptor); throw error }
    }

    private func withJournal<T>(_ id: UUID, writing: Bool, _ body: (Int32, Int32, String) throws -> T) throws -> T {
        let parent = try openCurrentDirectory()
        defer { Darwin.close(parent) }
        let name = fileName(id)
        let file = try Self.openPrivateFile(parent: parent, path: directory, name: name, create: false, writable: writing, operations: operations)
        defer { Darwin.close(file) }
        try Self.fileLock(file, exclusive: writing)
        defer { _ = flock(file, LOCK_UN) }
        try validateFile(file, parent: parent, name: name)
        return try body(file, parent, name)
    }

    private func validateFile(_ file: Int32, parent: Int32, name: String) throws {
        let path = directory + "/" + name
        let original = try Self.metadata(file, path: path, operations: operations)
        try Self.requirePrivateFile(original, descriptor: file)
        let fresh = Darwin.openat(parent, name, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fresh >= 0 else { throw ManifestError.system(errno) }
        defer { Darwin.close(fresh) }
        let current = try Self.metadata(fresh, path: path, operations: operations)
        try Self.requirePrivateFile(current, descriptor: fresh)
        guard ManifestDirectoryIdentity(original) == ManifestDirectoryIdentity(current) else { throw ManifestError.changed }
        try Self.requireDescriptorPath(parent, expected: directory)
        guard ManifestDirectoryIdentity(try Self.metadata(parent, path: directory, operations: operations)) == directoryIdentity else {
            throw ManifestError.changed
        }
    }

    private func fileName(_ id: UUID) -> String { id.uuidString.lowercased() + ".jsonl" }

    private func record(_ payload: ManifestPayload, sequence: UInt64, previous: Data) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(payload)
        guard let text = String(data: bytes, encoding: .utf8) else { throw ManifestError.corruptJournal }
        let mac = Data(HMAC<SHA256>.authenticationCode(for: Self.authenticatedBytes(sequence: sequence, previous: previous, payload: bytes), using: SymmetricKey(data: key)))
        var line = try encoder.encode(ManifestRecord(sequence: sequence, previous: previous, payload: text, mac: mac))
        guard line.count < Self.maximumRecordBytes else { throw ManifestError.limitExceeded }
        line.append(10)
        return line
    }

    private func parse(_ bytes: Data, expected: UUID) throws -> ManifestParsed {
        guard !bytes.isEmpty, bytes.last == 10 else { throw ManifestError.corruptJournal }
        let lines = bytes.dropLast().split(separator: 10, omittingEmptySubsequences: false)
        guard lines.count <= Self.maximumEvents + 1 else { throw ManifestError.limitExceeded }
        var previous = Data(repeating: 0, count: 32)
        var header: ManifestHeader?
        var events: [ManifestEvent] = []
        let decoder = JSONDecoder()
        for (index, line) in lines.enumerated() {
            guard !line.isEmpty, line.count < Self.maximumRecordBytes else { throw ManifestError.corruptJournal }
            let record: ManifestRecord
            let payload: ManifestPayload
            do {
                record = try decoder.decode(ManifestRecord.self, from: Data(line))
                let payloadBytes = Data(record.payload.utf8)
                guard record.sequence == UInt64(index), record.previous == previous, record.mac.count == 32,
                      HMAC<SHA256>.isValidAuthenticationCode(record.mac, authenticating: Self.authenticatedBytes(sequence: record.sequence, previous: record.previous, payload: payloadBytes), using: SymmetricKey(data: key)) else {
                    throw ManifestError.corruptJournal
                }
                payload = try decoder.decode(ManifestPayload.self, from: payloadBytes)
            } catch { throw ManifestError.corruptJournal }
            if index == 0 {
                guard let value = payload.header, payload.event == nil, value.version == 1, value.id == expected,
                      Self.validHeader(appVersion: value.appVersion, ruleSetVersion: value.ruleSetVersion,
                                       createdAt: value.createdAt) else { throw ManifestError.corruptJournal }
                header = value
            } else {
                guard payload.header == nil, let event = payload.event,
                      event.timestamp.timeIntervalSinceReferenceDate.isFinite else { throw ManifestError.corruptJournal }
                events.append(event)
            }
            previous = record.mac
        }
        guard let header else { throw ManifestError.corruptJournal }
        return ManifestParsed(session: ManifestSession(id: header.id, appVersion: header.appVersion, ruleSetVersion: header.ruleSetVersion, createdAt: header.createdAt, events: events), lastMAC: previous, bytes: bytes)
    }

    private static func validHeader(appVersion: String, ruleSetVersion: String, createdAt: Date) -> Bool {
        createdAt.timeIntervalSinceReferenceDate.isFinite && [appVersion, ruleSetVersion].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= maximumVersionBytes
        }
    }

    private static func authenticatedBytes(sequence: UInt64, previous: Data, payload: Data) -> Data {
        // Domain separation prevents these MACs being reused by another format.
        var result = Data("RACKET.Manifest.v1\0".utf8)
        var bigEndian = sequence.bigEndian
        withUnsafeBytes(of: &bigEndian) { result.append(contentsOf: $0) }
        result.append(previous)
        result.append(payload)
        return result
    }

    private static func openDirectory(
        _ path: String, create: Bool, operations: ScanMetadataOperations,
        synchronize: @Sendable (Int32) throws -> Void
    ) throws -> Int32 {
        guard path.hasPrefix("/"), !path.contains("\0"), !path.hasSuffix("/") else { throw ManifestError.unsafePath }
        let components = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw ManifestError.unsafePath }
        var parent = Darwin.open("/", O_EVTONLY | O_NOFOLLOW | O_CLOEXEC | O_DIRECTORY)
        guard parent >= 0 else { throw ManifestError.system(errno) }
        do {
            var current = ""
            for (index, component) in components.enumerated() {
                current += "/" + component
                var child = Darwin.openat(parent, String(component), O_EVTONLY | O_NOFOLLOW | O_CLOEXEC | O_DIRECTORY)
                if child < 0, errno == ENOENT, create {
                    guard Darwin.mkdirat(parent, String(component), 0o700) == 0 || errno == EEXIST else { throw ManifestError.system(errno) }
                    try synchronize(parent)
                    child = Darwin.openat(parent, String(component), O_EVTONLY | O_NOFOLLOW | O_CLOEXEC | O_DIRECTORY)
                }
                guard child >= 0 else { throw ManifestError.system(errno) }
                Darwin.close(parent)
                parent = child
                let value = try metadata(child, path: current, operations: operations)
                guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw ManifestError.unsafeMetadata }
                if index == components.count - 1 {
                    guard value.st_uid == getuid(), value.st_mode & 0o7777 == 0o700 else { throw ManifestError.unsafeMetadata }
                } else {
                    guard value.st_uid == 0 || value.st_uid == getuid() else { throw ManifestError.unsafeMetadata }
                    let trustedTemporaryRoot = current == "/private/tmp" && value.st_uid == 0 && value.st_mode & mode_t(S_ISVTX) != 0
                    guard value.st_mode & 0o022 == 0 || trustedTemporaryRoot else { throw ManifestError.unsafeMetadata }
                }
                try requireNoAllowACL(child)
                try requireDescriptorPath(child, expected: current)
            }
            return parent
        } catch { Darwin.close(parent); throw error }
    }

    private static func openPrivateFile(parent: Int32, path: String, name: String, create: Bool, writable: Bool, operations: ScanMetadataOperations) throws -> Int32 {
        if create {
            let created = Darwin.openat(parent, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
            if created >= 0 {
                do {
                    try requirePrivateFile(metadata(created, path: path + "/" + name, operations: operations), descriptor: created)
                    return created
                } catch { Darwin.close(created); throw error }
            }
            guard errno == EEXIST else { throw ManifestError.system(errno) }
        }
        let probe = Darwin.openat(parent, name, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard probe >= 0 else { throw ManifestError.system(errno) }
        defer { Darwin.close(probe) }
        let initial = try metadata(probe, path: path + "/" + name, operations: operations)
        try requirePrivateFile(initial, descriptor: probe)
        let descriptor = Darwin.openat(parent, name, (writable ? O_RDWR | O_APPEND : O_RDONLY) | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw ManifestError.system(errno) }
        do {
            let opened = try metadata(descriptor, path: path + "/" + name, operations: operations)
            try requirePrivateFile(opened, descriptor: descriptor)
            guard ManifestDirectoryIdentity(opened) == ManifestDirectoryIdentity(initial) else { throw ManifestError.changed }
            return descriptor
        } catch { Darwin.close(descriptor); throw error }
    }

    private static func loadKey(directory: Int32, path: String, operations: ScanMetadataOperations, synchronize: @Sendable (Int32) throws -> Void) throws -> Data {
        let name = "authentication.key"
        let created = Darwin.openat(directory, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        let file: Int32
        if created >= 0 { file = created }
        else {
            guard errno == EEXIST else { throw ManifestError.system(errno) }
            file = try openPrivateFile(parent: directory, path: path, name: name, create: false, writable: false, operations: operations)
        }
        defer { Darwin.close(file) }
        try fileLock(file, exclusive: created >= 0)
        defer { _ = flock(file, LOCK_UN) }
        try requirePrivateFile(metadata(file, path: path + "/" + name, operations: operations), descriptor: file)
        if created >= 0 {
            let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            try writeAll(key, to: file)
            try synchronize(file)
            try synchronize(directory)
            return key
        }
        let key = try readAll(file, limit: 32)
        guard key.count == 32 else { throw ManifestError.invalidKey }
        return key
    }

    private static func metadata(_ descriptor: Int32, path: String, operations: ScanMetadataOperations) throws -> stat {
        let inspected = try SizeCalculator(operations: operations).inspect(descriptor: descriptor, path: path, includeSize: false)
        let flags = try operations.flags(descriptor)
        guard flags & UInt32(SF_DATALESS) == 0 else { throw ScanMetadataError.dataless }
        let value = try operations.metadata(descriptor)
        guard flags == value.st_flags, inspected.fingerprint == ScanMetadataFingerprint(value) else { throw ManifestError.changed }
        return value
    }

    private static func requirePrivateFile(_ value: stat, descriptor: Int32) throws {
        guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), value.st_uid == getuid(),
              value.st_mode & 0o7777 == 0o600, value.st_nlink == 1 else { throw ManifestError.unsafeMetadata }
        try requireNoAllowACL(descriptor)
    }

    private static func requireNoAllowACL(_ descriptor: Int32) throws {
        guard let acl = Darwin.acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            // On APFS, a live descriptor without an extended ACL returns ENOENT.
            // The caller already established a resident object through this fd.
            if errno == ENOENT { return }
            throw ManifestError.system(errno)
        }
        defer { Darwin.acl_free(UnsafeMutableRawPointer(acl)) }
        guard Darwin.acl_valid(acl) == 0 else { throw ManifestError.unsafeMetadata }
        var entry: acl_entry_t?
        var position = ACL_FIRST_ENTRY
        while Darwin.acl_get_entry(acl, Int32(position.rawValue), &entry) == 0 {
            guard let entry else { throw ManifestError.unsafeMetadata }
            var tag = ACL_UNDEFINED_TAG
            guard Darwin.acl_get_tag_type(entry, &tag) == 0 else { throw ManifestError.system(errno) }
            guard tag != ACL_EXTENDED_ALLOW else { throw ManifestError.unsafeMetadata }
            position = ACL_NEXT_ENTRY
        }
        guard errno == EINVAL else { throw ManifestError.system(errno) }
    }

    private static func requireDescriptorPath(_ descriptor: Int32, expected: String) throws {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard Darwin.fcntl(descriptor, F_GETPATH, &buffer) == 0 else { throw ManifestError.system(errno) }
        let actual = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        guard actual.utf8.elementsEqual(expected.utf8) else { throw ManifestError.changed }
    }

    private static func fileLock(_ descriptor: Int32, exclusive: Bool) throws {
        while flock(descriptor, exclusive ? LOCK_EX : LOCK_SH) != 0 {
            if errno != EINTR { throw ManifestError.system(errno) }
        }
    }

    private static func readAll(_ descriptor: Int32, limit: Int) throws -> Data {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) == 0 else { throw ManifestError.system(errno) }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(descriptor, &buffer, min(buffer.count, limit - result.count + 1))
            if count == 0 { return result }
            if count < 0 {
                if errno == EINTR { continue }
                throw ManifestError.system(errno)
            }
            guard count <= limit - result.count else { throw ManifestError.limitExceeded }
            result.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw ManifestError.system(errno)
                }
                guard count > 0 else { throw ManifestError.system(EIO) }
                offset += count
            }
        }
    }

    static func sync(_ descriptor: Int32) throws {
        guard Darwin.fsync(descriptor) == 0 else { throw ManifestError.system(errno) }
    }
}

private struct ManifestDirectoryIdentity: Equatable {
    let device: Int32
    let inode: UInt64
    let generation: UInt32
    let bornSeconds: Int
    let bornNanoseconds: Int
    init(_ value: stat) {
        device = value.st_dev
        inode = value.st_ino
        generation = value.st_gen
        bornSeconds = value.st_birthtimespec.tv_sec
        bornNanoseconds = value.st_birthtimespec.tv_nsec
    }
}

private struct ManifestHeader: Codable {
    let version: Int
    let id: UUID
    let appVersion: String
    let ruleSetVersion: String
    let createdAt: Date
}

private struct ManifestPayload: Codable {
    let header: ManifestHeader?
    let event: ManifestEvent?
}

private struct ManifestRecord: Codable {
    let sequence: UInt64
    let previous: Data
    /// Readable JSON text preserves the exact authenticated UTF-8 bytes. Parsing
    /// must verify this string before decoding it, never re-encode its fields.
    let payload: String
    let mac: Data
}

private struct ManifestParsed {
    let session: ManifestSession
    let lastMAC: Data
    let bytes: Data
}
