import AppKit
import Combine
import Foundation
import RacketCore
import ServiceManagement
import UserNotifications

enum AppPage: String, CaseIterable, Identifiable {
    case overview, cleanup, creative, storage, applications, recovery, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .cleanup: "Cleanup"
        case .creative: "Creative caches"
        case .storage: "Storage explorer"
        case .applications: "Applications"
        case .recovery: "Recovery"
        case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .cleanup: "sparkles"
        case .creative: "film.stack"
        case .storage: "internaldrive"
        case .applications: "square.stack.3d.up"
        case .recovery: "arrow.uturn.backward"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct FindingRow: Identifiable {
    let finding: Finding
    var id: Data { Data(finding.resolvedPath.utf8) }
}

struct RecoverySession: Identifiable {
    let session: ManifestSession
    var id: UUID { session.id }
    var latestEvents: [ManifestEvent] {
        var items: [UUID: ManifestEvent] = [:]
        for event in session.events { items[event.item.id] = event }
        return items.values.sorted { $0.item.originalPath.utf8.lexicographicallyPrecedes($1.item.originalPath.utf8) }
    }
    var recoverableCount: Int {
        latestEvents.filter { [.trashed, .staged, .prepared, .recoveryRequired, .restorePrepared, .restoreFailed].contains($0.action) }.count
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var page: AppPage? = .overview
    @Published private(set) var runtime: AppRuntime?
    @Published private(set) var volume: StorageVolumeSnapshot?
    @Published private(set) var report: ScanReport?
    @Published private(set) var scanProgress: ScanProgress?
    @Published private(set) var busy = false
    @Published private(set) var operation = ""
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var search = ""
    @Published var moduleFilter = "all"
    @Published var selected = Set<Data>()
    @Published var confirmCleanup = false
    @Published private(set) var lastRemoval: RemovalReport?
    @Published private(set) var lastUndo: UndoReport?
    @Published private(set) var sessions: [RecoverySession] = []
    @Published private(set) var historyIssues: [String] = []
    @Published private(set) var storageReport: StorageExplorerReport?
    @Published private(set) var applicationReport: ApplicationInventoryReport?
    @Published private(set) var reviewedApplication: ApplicationRemovalSelection?
    @Published var confirmApplication = false
    @Published var showOnboarding: Bool
    @Published var menuBarEnabled: Bool { didSet { defaults.set(menuBarEnabled, forKey: "menuBarEnabled") } }
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    @Published var scheduledScans: Bool { didSet { defaults.set(scheduledScans, forKey: "scheduledScans"); resetSchedule() } }
    @Published var scheduleHours: Int { didSet { defaults.set(scheduleHours, forKey: "scheduleHours"); resetSchedule() } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var nextScanDate: Date?
    @Published private(set) var exclusions: [String]
    @Published private(set) var launchAtLogin = false

    let verificationMode: Bool
    private let defaults: UserDefaults
    private var currentTask: Task<Void, Never>?
    private var timer: AnyCancellable?
    private var inventory: ApplicationInventory?
    private var started = false

    init() {
        #if DEBUG
        verificationMode = ProcessInfo.processInfo.arguments.contains("--verification-fixtures")
            || ProcessInfo.processInfo.environment["RACKET_TEST_WORKSPACE"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        verificationMode = false
        #endif
        defaults = verificationMode ? UserDefaults(suiteName: "RACKET-Verification-\(UUID().uuidString)")! : .standard
        menuBarEnabled = defaults.object(forKey: "menuBarEnabled") as? Bool ?? true
        appearance = defaults.string(forKey: "appearance") ?? "system"
        scheduledScans = defaults.bool(forKey: "scheduledScans")
        scheduleHours = defaults.object(forKey: "scheduleHours") as? Int ?? 24
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        exclusions = defaults.stringArray(forKey: "exclusions") ?? []
        lastScanDate = defaults.object(forKey: "lastScanDate") as? Date
        nextScanDate = defaults.object(forKey: "nextScanDate") as? Date
        showOnboarding = !defaults.bool(forKey: "onboardingCompleted") && !verificationMode
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var rows: [FindingRow] {
        (report?.findings ?? []).filter { finding in
            !isExcluded(finding.resolvedPath)
            && (moduleFilter == "all" || finding.module.rawValue == moduleFilter)
            && (search.isEmpty || finding.resolvedPath.localizedCaseInsensitiveContains(search)
                || finding.reason.localizedCaseInsensitiveContains(search))
        }.sorted { $0.allocatedSize > $1.allocatedSize }.map(FindingRow.init)
    }
    var selectedFindings: [Finding] {
        (report?.findings ?? []).filter { selected.contains(Data($0.resolvedPath.utf8)) && !isExcluded($0.resolvedPath) }
    }
    var selectedBytes: UInt64 { selectedFindings.reduce(0) { $0 + $1.allocatedSize } }
    var enabledRules: [Rule] { runtime?.rules.enabledRules ?? [] }
    var excludedFindingCount: Int { (report?.findings ?? []).filter { isExcluded($0.resolvedPath) }.count }
    var incompleteCount: Int { report?.issues.filter { $0.disposition == .incomplete }.count ?? 0 }

    func start() {
        guard !started else { return }
        started = true
        busy = true; operation = "Preparing RACKET"
        currentTask = Task {
            do {
                let verify = verificationMode
                let loaded = try await Task.detached(priority: .userInitiated) {
                    #if DEBUG
                    if verify { return try AppRuntime.verification() }
                    #endif
                    return try AppRuntime.production()
                }.value
                runtime = loaded
                await refreshVolume()
                await refreshHistory()
                resetSchedule(preserve: true)
                #if DEBUG
                if let root = loaded.verificationRoot { inventory = try ApplicationInventory.verification(root: root) }
                else { inventory = try ApplicationInventory() }
                #else
                inventory = try ApplicationInventory()
                #endif
            } catch { errorMessage = error.localizedDescription }
            busy = false; operation = ""
        }
        timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor in self?.checkSchedule() }
        }
    }

    func finishOnboarding() {
        defaults.set(true, forKey: "onboardingCompleted")
        showOnboarding = false
    }

    func scan(scheduled: Bool = false) {
        guard !busy, let runtime else { return }
        selected.removeAll(); report = nil; lastRemoval = nil; scanProgress = nil
        busy = true; operation = scheduled ? "Scheduled scan" : "Scanning verified categories"
        errorMessage = nil; notice = nil
        if !scheduled { page = .cleanup }
        currentTask = Task {
            do {
                let result = try await runtime.scanner.scan(ruleSet: runtime.rules) { [weak self] progress in
                    await MainActor.run { self?.scanProgress = progress }
                }
                try Task.checkCancellation()
                report = result
                lastScanDate = Date(); defaults.set(lastScanDate, forKey: "lastScanDate")
                if scheduled { await notifyScan(result) }
                await refreshVolume()
            } catch is CancellationError { notice = "Scan cancelled. Start a new scan when you're ready." }
            catch { errorMessage = error.localizedDescription }
            busy = false; operation = ""; scanProgress = nil
        }
    }

    func cancel() { currentTask?.cancel() }

    func setSelected(_ finding: Finding, enabled: Bool) {
        let key = Data(finding.resolvedPath.utf8)
        if enabled { selected.insert(key) } else { selected.remove(key) }
    }

    func selectVisible() { for row in rows { selected.insert(row.id) } }
    func clearSelection() { selected.removeAll() }

    func cleanSelected() {
        guard !busy, let runtime, !selectedFindings.isEmpty else { return }
        let reviewed = selectedFindings
        confirmCleanup = false; busy = true; operation = "Moving reviewed files to Trash"
        errorMessage = nil; notice = nil
        currentTask = Task {
            do {
                var moved = Set<Data>()
                var allResults: [RemovalResult] = []
                for offset in stride(from: 0, to: reviewed.count, by: 256) {
                    try Task.checkCancellation()
                    let batch = Array(reviewed[offset..<min(offset + 256, reviewed.count)])
                    let result = try await runtime.remover.moveToTrash(reviewedFindings: batch,
                        ruleSet: runtime.rules, appVersion: appVersion)
                    lastRemoval = result; allResults += result.results
                    for item in result.results where item.outcome == .trashed { moved.insert(Data(item.originalPath.utf8)) }
                    if result.journalFailure != nil || result.cancelled { break }
                }
                selected.subtract(moved)
                let count = allResults.filter { $0.outcome == .trashed }.count
                notice = "\(count) of \(reviewed.count) reviewed files moved to Trash. See Recovery for every result and undo."
                if let failure = lastRemoval?.journalFailure { errorMessage = failure }
                await refreshHistory(); await refreshVolume()
                // Removed observations must not remain selectable. Keep refusals
                // visible in history, and require a fresh scan for more cleanup.
                report = nil; selected.removeAll()
                page = .recovery
            } catch is CancellationError {
                notice = "Cleanup stopped. Completed operations are recorded in Recovery."
                report = nil; selected.removeAll(); await refreshHistory(); page = .recovery
            } catch {
                errorMessage = error.localizedDescription
                report = nil; selected.removeAll()
                await refreshHistory(); page = .recovery
            }
            busy = false; operation = ""
        }
    }

    func refreshHistory() async {
        guard let runtime else { return }
        let store = runtime.manifest
        let result = await Task.detached(priority: .utility) { () -> ([ManifestSession], [String]) in
            do {
                var sessions: [ManifestSession] = []; var errors: [String] = []
                for id in try store.sessionIDs() {
                    do { sessions.append(try store.read(id)) }
                    catch { errors.append("Session \(id.uuidString): \(error.localizedDescription)") }
                }
                return (sessions.sorted { $0.createdAt > $1.createdAt }, errors)
            } catch { return ([], [error.localizedDescription]) }
        }.value
        sessions = result.0.map(RecoverySession.init); historyIssues = result.1
    }

    func restore(_ session: RecoverySession) {
        guard !busy, let runtime else { return }
        busy = true; operation = "Restoring recorded files"; lastUndo = nil
        currentTask = Task {
            do {
                let result: UndoReport
                if session.session.ruleSetVersion == ApplicationRemovalSelection.manifestVersion {
                    result = try await runtime.remover.restoreApplication(sessionID: session.id)
                } else { result = try await runtime.undo.restore(sessionID: session.id) }
                lastUndo = result
                let restored = result.results.filter { $0.outcome == .restored || $0.outcome == .alreadyRestored }.count
                notice = "\(restored) of \(result.results.count) items restored. Existing files are never overwritten."
                if let failure = result.journalFailure { errorMessage = failure }
                await refreshHistory(); await refreshVolume()
            } catch { errorMessage = error.localizedDescription }
            busy = false; operation = ""
        }
    }

    func refreshVolume() async {
        do { volume = try await StorageVolumeSnapshot.read(at: runtime?.verificationRoot ?? FileManager.default.homeDirectoryForCurrentUser) }
        catch { notice = "Volume capacity is unavailable: \(error.localizedDescription)" }
    }

    func chooseFolder() {
        guard !busy else { return }
        if let root = runtime?.verificationRoot { explore(root); return }
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to measure"; panel.canChooseDirectories = true
        panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = "Measure folder"
        if panel.runModal() == .OK, let url = panel.url { explore(url) }
    }

    func explore(_ url: URL) {
        guard !busy else { return }
        busy = true; operation = "Measuring folder storage"; page = .storage
        currentTask = Task {
            do { storageReport = try await StorageExplorer().explore(at: url) }
            catch is CancellationError { notice = "Folder measurement cancelled." }
            catch { errorMessage = error.localizedDescription }
            busy = false; operation = ""
        }
    }

    func loadApplications() {
        guard !busy, let inventory else { return }
        busy = true; operation = "Reading installed applications"
        currentTask = Task {
            do { applicationReport = try await inventory.scan() }
            catch is CancellationError { notice = "Application scan cancelled." }
            catch { errorMessage = error.localizedDescription }
            busy = false; operation = ""
        }
    }

    func reviewApplication(_ app: InstalledApplication) {
        guard !busy, let inventory else { return }
        busy = true; operation = "Verifying application contents"
        currentTask = Task {
            do { reviewedApplication = try await inventory.reviewRemoval(of: app); confirmApplication = true }
            catch { errorMessage = error.localizedDescription }
            busy = false; operation = ""
        }
    }

    func removeReviewedApplication() {
        guard !busy, let runtime, let reviewedApplication else { return }
        confirmApplication = false; busy = true; operation = "Moving reviewed application to Trash"
        currentTask = Task {
            do {
                let result = try await runtime.remover.moveApplicationToTrash(reviewedApplication: reviewedApplication,
                                                                           appVersion: appVersion)
                lastRemoval = result
                notice = result.results.first?.outcome == .trashed ? "Application moved to Trash. Undo is available in Recovery." : "Application was not removed. See Recovery for the result."
                if let failure = result.journalFailure { errorMessage = failure }
                await refreshHistory(); await refreshVolume(); page = .recovery
                applicationReport = nil; self.reviewedApplication = nil
            } catch { errorMessage = error.localizedDescription }
            busy = false; operation = ""
        }
    }

    func exclude(_ path: String) {
        guard !busy else { return }
        if !exclusions.contains(where: { Data($0.utf8) == Data(path.utf8) }) { exclusions.append(path) }
        defaults.set(exclusions, forKey: "exclusions")
        selected.remove(Data(path.utf8))
    }
    func removeExclusion(_ path: String) {
        guard !busy else { return }
        exclusions.removeAll { Data($0.utf8) == Data(path.utf8) }
        defaults.set(exclusions, forKey: "exclusions")
    }
    private func isExcluded(_ path: String) -> Bool {
        exclusions.contains { Data(path.utf8) == Data($0.utf8) || path.utf8.starts(with: ($0 + "/").utf8) }
    }

    func reveal(_ path: String) {
        let url = path.withCString { URL(fileURLWithFileSystemRepresentation: $0, isDirectory: false, relativeTo: nil) }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    func openPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { notice = "Approve RACKET in System Settings → Login Items."; SMAppService.openSystemSettingsLoginItems() }
        } catch { errorMessage = error.localizedDescription }
    }
    func enableNotifications() {
        Task {
            do { notificationsEnabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            catch { errorMessage = error.localizedDescription }
        }
    }
    private func resetSchedule(preserve: Bool = false) {
        guard scheduledScans else { nextScanDate = nil; defaults.removeObject(forKey: "nextScanDate"); return }
        if !preserve || nextScanDate == nil { nextScanDate = Date().addingTimeInterval(Double(scheduleHours) * 3_600) }
        defaults.set(nextScanDate, forKey: "nextScanDate")
    }
    private func checkSchedule() {
        guard scheduledScans, !busy, !verificationMode, selected.isEmpty,
              !confirmCleanup, !confirmApplication,
              let nextScanDate, Date() >= nextScanDate else { return }
        resetSchedule(); scan(scheduled: true)
    }
    private func notifyScan(_ report: ScanReport) async {
        guard notificationsEnabled, !verificationMode, report.findings.contains(where: { !isExcluded($0.resolvedPath) }) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your RACKET scan is ready"
        content.body = "Review the files in RACKET. Nothing has been removed."
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
        catch { notice = "Scan completed. macOS couldn't deliver the notification." }
    }

    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
}

func formattedBytes(_ bytes: UInt64) -> String {
    if bytes > UInt64(Int64.max) { return String(format: "%.1f EB", Double(bytes) / 1_000_000_000_000_000_000) }
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}
