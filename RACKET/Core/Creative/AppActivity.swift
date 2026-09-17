import Darwin
import Foundation

/// A synchronous observation of known producer executables, never a guarantee
/// that an application is closed. A producer may launch or exec after any check.
public enum ProducerActivity: Equatable, Sendable {
    case running([String])
    case notObservedRunning
    case unknown
}

/// Uses kernel process metadata and executable paths without reading application
/// bundles, preferences, or user file contents. Call again before each mutation;
/// observation and a filesystem operation cannot be made atomic with this API.
public struct AppActivity: Sendable {
    private let snapshot: @Sendable () throws -> [AppActivityProcess]
    private let identities: [ProducerExecutableIdentity]

    public init() {
        self.init(snapshot: { try AppActivityProcessSource().snapshot() }, identities: .compiled)
    }

    init(snapshot: @escaping @Sendable () throws -> [AppActivityProcess],
         identities: [ProducerExecutableIdentity] = .compiled) {
        self.snapshot = snapshot
        self.identities = identities
    }

    /// Unknown, empty, or partially supported producer lists fail closed. No
    /// cached observation, dispatch, suspension, or application state change occurs.
    public func check(producers: [String]) -> ProducerActivity {
        guard !producers.isEmpty, producers.count <= 64,
              Set(producers).count == producers.count else { return .unknown }
        var requested: [ProducerExecutableIdentity] = []
        for producer in producers {
            let entries = identities.filter { $0.producer == producer }
            guard !entries.isEmpty else { return .unknown }
            requested.append(contentsOf: entries)
        }
        do {
            // proc_pidpath can perform kernel path lookup. Nesting this strictly
            // synchronous scope also protects calls made outside RemovalEngine.
            return try withoutDatalessMaterialization {
                let processes = try snapshot()
                guard !processes.isEmpty, processes.count <= AppActivityProcessSource.maximumProcesses,
                      processes.allSatisfy({ AppActivityProcessSource.validPath($0.executablePath) }) else {
                    return .unknown
                }
                let observed = Set(requested.filter { identity in
                    processes.contains { identity.matches($0.executablePath) }
                }.map(\.producer)).sorted()
                return observed.isEmpty ? .notObservedRunning : .running(observed)
            }
        } catch { return .unknown }
    }
}

/// The seam contains executable identity only: no arguments, environment,
/// working directory, bundle contents, or user data are collected.
struct AppActivityProcess: Equatable, Sendable {
    let executablePath: String
}

/// Compiled identities are additional refusal criteria, not removal authority.
/// Basename matching survives application-folder renames; app-family matching
/// also catches helpers with a different executable name inside a known bundle.
struct ProducerExecutableIdentity: Sendable {
    let producer: String
    let executableNames: Set<String>
    var executableNamePrefixes: Set<String> = []
    var applicationNamePrefixes: Set<String> = []

    func matches(_ path: String) -> Bool {
        let components = path.split(separator: "/").map { String($0).lowercased() }
        guard let executable = components.last else { return false }
        if executableNames.contains(where: { $0.lowercased() == executable }) { return true }
        if executableNamePrefixes.contains(where: { Self.isFamily(executable, prefix: $0.lowercased()) }) { return true }
        return components.dropLast().contains { component in
            guard component.hasSuffix(".app") else { return false }
            let application = String(component.dropLast(4))
            return applicationNamePrefixes.contains { Self.isFamily(application, prefix: $0.lowercased()) }
        }
    }

    private static func isFamily(_ value: String, prefix: String) -> Bool {
        !prefix.isEmpty && (value == prefix || value.hasPrefix(prefix + " "))
    }
}

extension Array where Element == ProducerExecutableIdentity {
    /// Bundle identifiers and primary executable names were observed in the
    /// installed applications' Info.plist metadata on 2026-09-13; aerender was
    /// independently observed as an executable on 2026-09-17. The family
    /// prefixes deliberately add conservative refusals for versions and helpers.
    /// These are not a complete host catalogue: independently renamed helper
    /// executables outside a recognized bundle can escape name matching. Bridge
    /// has no independently verified identity here and therefore stays unknown.
    static let compiled: [ProducerExecutableIdentity] = [
        .init(producer: "com.adobe.Photoshop", executableNames: ["Adobe Photoshop 2026"],
              executableNamePrefixes: ["Adobe Photoshop"], applicationNamePrefixes: ["Adobe Photoshop"]),
        .init(producer: "com.adobe.AfterEffects.application",
              executableNames: ["After Effects", "After Effects Render Engine", "aerender"],
              executableNamePrefixes: ["After Effects"],
              applicationNamePrefixes: ["Adobe After Effects", "After Effects"]),
        .init(producer: "com.adobe.AfterEffectsRenderEngine", executableNames: ["After Effects Render Engine", "aerender"],
              executableNamePrefixes: ["After Effects Render Engine"],
              applicationNamePrefixes: ["Adobe After Effects", "After Effects"]),
        .init(producer: "com.adobe.LightroomClassicCC7", executableNames: ["Adobe Lightroom Classic"],
              executableNamePrefixes: ["Adobe Lightroom Classic"],
              applicationNamePrefixes: ["Adobe Lightroom Classic"]),
        .init(producer: "com.adobe.ame.application.26", executableNames: ["Adobe Media Encoder 2026"],
              executableNamePrefixes: ["Adobe Media Encoder"], applicationNamePrefixes: ["Adobe Media Encoder"]),
        .init(producer: "com.blackmagic-design.DaVinciResolve", executableNames: ["Resolve"],
              applicationNamePrefixes: ["DaVinci Resolve"])
    ]
}

struct AppActivityPIDList: Sendable {
    let byteCount: Int
    let pids: [pid_t]
}

struct AppActivityProcessInfo: Sendable {
    let pid: pid_t
    let effectiveUID: uid_t
    let realUID: uid_t
    let startedSeconds: UInt64
    let startedMicroseconds: UInt64
    let status: UInt32

    func isSameInstance(as other: Self) -> Bool {
        pid == other.pid && effectiveUID == other.effectiveUID && realUID == other.realUID &&
        startedSeconds == other.startedSeconds && startedMicroseconds == other.startedMicroseconds
    }
}

/// Typed syscall seams make incomplete buffers and process churn testable without
/// inspecting, launching, signalling, or changing any real application.
struct AppActivityProcessOperations: Sendable {
    var effectiveUID: @Sendable () -> uid_t
    var realUID: @Sendable () -> uid_t
    /// Zero capacity asks for a global process-count sizing hint, including
    /// kernel slack; it is not a filtered required size. Results are in bytes.
    var listPIDs: @Sendable (UInt32, uid_t, Int) throws -> AppActivityPIDList
    var processInfo: @Sendable (pid_t) throws -> AppActivityProcessInfo
    var executablePath: @Sendable (pid_t) throws -> String

    static let live = AppActivityProcessOperations(
        effectiveUID: { geteuid() }, realUID: { getuid() },
        listPIDs: { type, uid, capacity in
            if capacity == 0 {
                let size = proc_listpids(type, uid, nil, 0)
                guard size > 0 else { throw AppActivityObservationError.unavailable }
                return AppActivityPIDList(byteCount: Int(size), pids: [])
            }
            var pids = [pid_t](repeating: 0, count: capacity)
            let bytes = Int32(capacity * MemoryLayout<pid_t>.stride)
            let count = pids.withUnsafeMutableBytes { proc_listpids(type, uid, $0.baseAddress, bytes) }
            guard count > 0 else { throw AppActivityObservationError.unavailable }
            return AppActivityPIDList(byteCount: Int(count), pids: pids)
        },
        processInfo: { pid in
            var value = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            // arg=1 allows an explicit zombie status; ESRCH remains unknown.
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 1, &value, size) == size else {
                throw AppActivityObservationError.unavailable
            }
            return AppActivityProcessInfo(pid: pid_t(bitPattern: value.pbi_pid),
                                          effectiveUID: value.pbi_uid, realUID: value.pbi_ruid,
                                          startedSeconds: value.pbi_start_tvsec,
                                          startedMicroseconds: value.pbi_start_tvusec,
                                          status: value.pbi_status)
        },
        executablePath: { pid in
            // PROC_PIDPATHINFO_MAXSIZE is (4 * MAXPATHLEN), a C macro that Swift
            // cannot import. Use that SDK expression rather than a magic buffer size.
            let capacity = Int(MAXPATHLEN) * 4
            var bytes = [UInt8](repeating: 0, count: capacity)
            let count = bytes.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32(capacity)) }
            return try AppActivityProcessSource.decodeExecutablePath(bytes, reportedCount: Int(count))
        }
    )
}

struct AppActivityProcessSource: Sendable {
    static let maximumProcesses = 65_536
    var operations: AppActivityProcessOperations = .live

    /// The caller must enclose this synchronous method in the thread-local
    /// no-materialization scope. The public checker always establishes that scope.
    func snapshot() throws -> [AppActivityProcess] {
        let uid = operations.effectiveUID()
        guard uid != 0, operations.realUID() == uid else { throw AppActivityObservationError.unavailable }
        let initial = try currentUserPIDs(uid)
        var processes: [AppActivityProcess] = []
        for pid in initial.pids {
            let before = try info(pid, uid: uid)
            // A verified zombie cannot write caches. A missing process or failed
            // metadata lookup cannot be treated as an equivalent observation.
            if before.status == UInt32(SZOMB) {
                let after = try info(pid, uid: uid)
                guard before.isSameInstance(as: after), after.status == UInt32(SZOMB) else {
                    throw AppActivityObservationError.unavailable
                }
                continue
            }
            guard before.status != UInt32(SIDL) else { throw AppActivityObservationError.unavailable }
            let path = try operations.executablePath(pid)
            let after = try info(pid, uid: uid)
            let secondPath = try operations.executablePath(pid)
            guard before.isSameInstance(as: after), after.status != UInt32(SIDL),
                  after.status != UInt32(SZOMB), path == secondPath, Self.validPath(path) else {
                throw AppActivityObservationError.unavailable
            }
            processes.append(AppActivityProcess(executablePath: path))
        }
        guard try initial == currentUserPIDs(uid), operations.effectiveUID() == uid,
              operations.realUID() == uid else { throw AppActivityObservationError.unavailable }
        return processes
    }

    private func info(_ pid: pid_t, uid: uid_t) throws -> AppActivityProcessInfo {
        let value = try operations.processInfo(pid)
        guard value.pid == pid, value.effectiveUID == uid || value.realUID == uid,
              value.startedSeconds > 0, value.startedMicroseconds < 1_000_000,
              (UInt32(SIDL)...UInt32(SZOMB)).contains(value.status) else {
            throw AppActivityObservationError.unavailable
        }
        return value
    }

    private struct PIDObservation: Equatable {
        let pids: [pid_t]
        let globalSizingHint: Int
    }

    private func currentUserPIDs(_ uid: uid_t) throws -> PIDObservation {
        var result = Set<pid_t>()
        var globalSizingHint: Int?
        for filter in [UInt32(PROC_UID_ONLY), UInt32(PROC_RUID_ONLY)] {
            let stride = MemoryLayout<pid_t>.stride
            let size = try operations.listPIDs(filter, uid, 0)
            guard size.pids.isEmpty, size.byteCount > 0, size.byteCount % stride == 0,
                  size.byteCount / stride <= Self.maximumProcesses - 128,
                  globalSizingHint == nil || globalSizingHint == size.byteCount else {
                throw AppActivityObservationError.unavailable
            }
            globalSizingHint = size.byteCount
            // The size hint can become stale. Slack absorbs modest growth; a
            // completely filled buffer is refused because libproc can truncate it.
            // XNU also independently caps its internal allocation at nprocs+20,
            // which can be smaller than our buffer. Reject reaching the observed
            // hint and bracket the call with unchanged hints. Transient count
            // changes inside a syscall remain an observational limitation.
            // https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/proc_info.c
            let capacity = size.byteCount / stride + 128
            let list = try operations.listPIDs(filter, uid, capacity)
            guard list.byteCount > 0, list.byteCount % stride == 0,
                  list.byteCount < size.byteCount, list.byteCount < capacity * stride,
                  list.pids.count == capacity else {
                throw AppActivityObservationError.unavailable
            }
            let after = try operations.listPIDs(filter, uid, 0)
            guard after.pids.isEmpty, after.byteCount == size.byteCount else {
                throw AppActivityObservationError.unavailable
            }
            let pids = Array(list.pids.prefix(list.byteCount / stride))
            guard pids.allSatisfy({ $0 > 0 }), Set(pids).count == pids.count else {
                throw AppActivityObservationError.unavailable
            }
            result.formUnion(pids)
        }
        guard !result.isEmpty, result.count <= Self.maximumProcesses, let globalSizingHint else {
            throw AppActivityObservationError.unavailable
        }
        return PIDObservation(pids: result.sorted(), globalSizingHint: globalSizingHint)
    }

    /// Apple's libproc wrapper returns strlen(buffer), excluding the NUL byte.
    /// Requiring that exact boundary rejects truncation and malformed buffers.
    /// https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c
    static func decodeExecutablePath(_ bytes: [UInt8], reportedCount: Int) throws -> String {
        guard reportedCount > 0, reportedCount < bytes.count, bytes.count <= Int(MAXPATHLEN) * 4,
              bytes[reportedCount] == 0, !bytes.prefix(reportedCount).contains(0),
              let path = String(bytes: bytes.prefix(reportedCount), encoding: .utf8), validPath(path) else {
            throw AppActivityObservationError.unavailable
        }
        return path
    }

    static func validPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.utf8.count < Int(MAXPATHLEN) * 4,
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.count >= 2 && components.dropFirst().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

private enum AppActivityObservationError: Error { case unavailable }
