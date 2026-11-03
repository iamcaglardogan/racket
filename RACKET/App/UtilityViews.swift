import SwiftUI
import RacketCore

struct StoragePage: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeading(title: "See where the space goes.", subtitle: "Measure a folder you choose. Allocated sizes are observations; shared APFS storage can affect the total.")
            HStack {
                Button("Choose a folder") { model.chooseFolder() }.buttonStyle(.borderedProminent).disabled(model.busy)
                if let report = model.storageReport {
                    Button("Parent folder") { model.explore(report.rootURL.deletingLastPathComponent()) }.disabled(model.busy || report.rootURL.path == "/")
                    Button("Reveal folder") { model.reveal(report.rootURL.path) }
                }
                Spacer()
            }
            if let report = model.storageReport {
                VStack(alignment: .leading, spacing: 8) {
                    Text(report.rootURL.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Text("\(formattedBytes(report.allocatedBytes)) measured · \(report.visitedEntryCount) entries").monospacedDigit()
                        Spacer()
                        Label(report.isComplete ? "Complete observation" : "Partial observation", systemImage: report.isComplete ? "checkmark.circle" : "info.circle")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                if report.entries.isEmpty {
                    EmptyPanel(symbol: "folder", title: "No measurable entries", detail: "This folder is empty or its entries could not be measured safely. Check the observation details below.")
                } else {
                    List(report.entries) { entry in
                        HStack(spacing: 14) {
                            Image(systemName: entry.kind == .directory ? "folder" : entry.kind == .package ? "shippingbox" : "doc")
                                .font(.title3).foregroundStyle(.secondary).frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).font(.callout.weight(.medium))
                                if !entry.isComplete { Text("Partial · \(entry.issueCount) skipped or unavailable items").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(formattedBytes(entry.allocatedBytes)).monospacedDigit()
                            if entry.kind == .directory {
                                Button("Explore") { model.explore(entry.url) }.disabled(model.busy)
                            }
                            Button { model.reveal(entry.url.path) } label: { Image(systemName: "arrow.up.forward.square") }
                                .buttonStyle(.borderless).accessibilityLabel("Reveal \(entry.name) in Finder")
                        }.padding(.vertical, 6)
                    }.listStyle(.inset).frame(minHeight: 0, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                DisclosureGroup("Observation details · \(report.issues.count) skipped or unavailable items") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(report.issues.prefix(300).enumerated()), id: \.offset) { _, issue in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(storageIssueDescription(issue.reason)).font(.caption.weight(.medium))
                                    Text(issue.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                            if report.issues.count > 300 { Text("Showing the first 300 issues. Explore a smaller folder for more detail.").font(.caption) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }.frame(maxHeight: 150)
                }.font(.caption)
            } else {
                Spacer()
                EmptyPanel(symbol: "internaldrive", title: "Start with one folder", detail: "Explore without removing anything. Packages, links, cloud-only files, and inaccessible locations are reported as skipped.")
                Spacer()
            }
        }.padding(32)
    }
}

struct ApplicationsPage: View {
    @EnvironmentObject private var model: AppModel
    var apps: [InstalledApplication] {
        (model.applicationReport?.applications ?? []).filter {
            model.search.isEmpty || $0.name.localizedCaseInsensitiveContains(model.search)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(model.search)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeading(title: "Know your applications.", subtitle: "Review the exact application bundle before moving it to Trash. Your preferences and documents stay in place.")
            HStack {
                Button(model.applicationReport == nil ? "Read installed applications" : "Refresh applications") { model.loadApplications() }
                    .buttonStyle(.borderedProminent).disabled(model.busy || model.runtime == nil)
                Spacer()
                if model.applicationReport != nil { Text("\(apps.count) visible applications").font(.caption).foregroundStyle(.secondary) }
            }
            if let report = model.applicationReport {
                List(apps) { app in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "app").font(.title).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(app.name).font(.headline)
                            Text("\(app.version) · \(app.bundleIdentifier)").font(.caption).foregroundStyle(.secondary)
                            Text(app.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if let reason = app.protectionReason { Label(reason, systemImage: "lock").font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button("Reveal") { model.reveal(app.path) }
                        Button("Review removal") { model.reviewApplication(app) }.disabled(model.busy || !app.canUninstall)
                    }.padding(.vertical, 9)
                }.listStyle(.inset).frame(minHeight: 0, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if !report.issues.isEmpty || report.limited {
                    DisclosureGroup("Discovery details · \(report.issues.count) issues\(report.limited ? " · Limit reached" : "")") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                                    Text("\(issue.path) — \(issue.detail)").font(.caption).textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 130)
                    }.font(.caption)
                }
                Text("System apps, administrator-owned bundles, running apps, and bundles with unsupported or linked contents are protected. Use Finder when RACKET cannot verify a removal.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Spacer()
                EmptyPanel(symbol: "square.stack.3d.up", title: "A clear view of your apps", detail: "Discovery reads application metadata. It never launches applications or reads their documents.")
                Spacer()
            }
        }.padding(32)
    }
}

struct ApplicationConfirmation: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Review application removal", systemImage: "app.badge.checkmark").font(.title2.weight(.semibold))
            if let review = model.reviewedApplication {
                Text(review.application.name).font(.title3.weight(.medium))
                Text(review.application.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text("\(formattedBytes(review.allocatedSize)) allocated · \(review.descendantCount) verified descendants")
                Text("Only this application bundle will move to Trash. Preferences, licences, related caches, and user documents are retained. Contents and process activity are checked again before removal.").foregroundStyle(.secondary)
                Text("Use Recovery to restore while the recorded bundle remains available in Trash. Emptying Trash can make removal permanent.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { model.confirmApplication = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Move application to Trash", role: .destructive) { model.removeReviewedApplication() }.buttonStyle(.borderedProminent)
            }
        }.padding(30).frame(width: 620)
    }
}

struct RecoveryPage: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(title: "Keep a way back.", subtitle: "Authenticated records connect each move with its recovery location. Restore never overwrites an existing item.")
                HStack { Button("Refresh history") { Task { await model.refreshHistory() } }.disabled(model.busy); Spacer(); Text("\(model.sessions.count) sessions").font(.caption).foregroundStyle(.secondary) }
                if let undo = model.lastUndo {
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Latest restore results").font(.headline)
                            ForEach(undo.results, id: \.itemID) { result in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(undoOutcome(result.outcome)).font(.caption.weight(.semibold))
                                    Text(result.originalPath).font(.caption).textSelection(.enabled)
                                    if let detail = result.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                                    if let location = result.recoveryPath { Text("Recorded location: \(location)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                                }
                            }
                        }
                    }
                }
                if model.sessions.isEmpty { EmptyPanel(symbol: "arrow.uturn.backward", title: "No cleanup sessions yet", detail: "After a reviewed cleanup, its results and recovery actions appear here.") }
                ForEach(model.sessions) { session in
                    Surface {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.session.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                    Text("\(session.latestEvents.count) items · \(session.recoverableCount) available for recovery review").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Restore session") { model.restore(session) }.disabled(model.busy || session.recoverableCount == 0)
                            }
                            DisclosureGroup("View every result") {
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(session.latestEvents, id: \.item.id) { event in
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack { Text(historyAction(event.action)).font(.caption.weight(.semibold)); Spacer(); Text(formattedBytes(event.item.allocatedSize)).font(.caption).monospacedDigit() }
                                            Text(event.item.originalPath).font(.caption).textSelection(.enabled)
                                            if let detail = event.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                                            if let path = event.trashPath ?? event.stagingPath {
                                                HStack {
                                                    Text("Recorded location: \(path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                                    Button("Reveal") { model.reveal(path) }.controlSize(.small)
                                                }
                                            }
                                        }
                                        Divider()
                                    }
                                }.padding(.top, 12)
                            }.font(.callout)
                        }
                    }
                }
                ForEach(Array(model.historyIssues.enumerated()), id: \.offset) { _, issue in
                    Label(issue, systemImage: "exclamationmark.circle").font(.caption).textSelection(.enabled)
                }
                Text("Recovery may be unavailable if a file changed, was removed from Trash, or its original parent no longer exists. Preserve any location marked as requiring recovery.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(32)
        }
    }
}

struct SettingsPage: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeading(title: "At your pace.", subtitle: "Private by default, with explicit choices for background scans.")
            Form {
                Section("Appearance and access") {
                    Picker("Appearance", selection: $model.appearance) {
                        Text("Follow macOS").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    Toggle("Show RACKET in the menu bar", isOn: $model.menuBarEnabled)
                    Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { enabled in model.setLogin(enabled) }))
                        .disabled(model.verificationMode)
                }
                Section("Scheduled scans") {
                    Toggle("Scan verified categories on a schedule", isOn: $model.scheduledScans)
                    Picker("Interval", selection: $model.scheduleHours) {
                        Text("Daily").tag(24); Text("Every three days").tag(72); Text("Weekly").tag(168)
                    }.disabled(!model.scheduledScans)
                    if let next = model.nextScanDate { Text("Next scan: \(next.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                    Text("Scans run while RACKET is open, including in the menu bar. Missed scans run after the app next opens. Scheduled scans never select or remove files.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Toggle("Notify when a scheduled scan has files to review", isOn: $model.notificationsEnabled)
                            .disabled(!model.notificationsEnabled)
                        if !model.notificationsEnabled { Button("Enable notifications") { model.enableNotifications() }.disabled(model.verificationMode) }
                    }
                }
                Section("Permissions") {
                    Text("macOS may restrict some folders. Skipped and inaccessible paths are shown in each scan. Grant broader access only for locations you intend to review.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Full Disk Access settings") { model.openPrivacy() }.disabled(model.verificationMode)
                }
                Section("Exclusions") {
                    if model.exclusions.isEmpty { Text("No excluded paths.").foregroundStyle(.secondary) }
                    ForEach(model.exclusions, id: \.self) { path in
                        HStack { Text(path).font(.caption).textSelection(.enabled); Spacer(); Button("Remove") { model.removeExclusion(path) }.disabled(model.busy) }
                    }
                    Text("Exclude a result from its actions menu. Exclusions also hide findings from scheduled scans.").font(.caption).foregroundStyle(.secondary)
                }
                Section("About RACKET") {
                    LabeledContent("Version", value: model.appVersion)
                    Text("Free and open source · MIT licence · macOS 14+").font(.caption)
                    Text("No telemetry, crash uploads, accounts, or app network requests. Source links open your browser only when you choose them.").font(.caption).foregroundStyle(.secondary)
                    Link("Source and documentation", destination: URL(string: "https://github.com/iamcaglardogan/racket")!)
                }
            }.formStyle(.grouped)
        }
    }
}

func storageIssueDescription(_ reason: StorageExplorerIssue.Reason) -> String {
    switch reason {
    case .dataless: "Cloud-only item skipped"
    case .symbolicLink: "Symbolic link skipped"
    case .package: "Package contents skipped"
    case .unsupportedFileType: "Special file skipped"
    case .metadataUnavailable: "Metadata unavailable"
    case .unsupportedMetadata: "Unsupported metadata"
    case .invalidPath: "Invalid path refused"
    case .notDirectory: "This location is not an ordinary folder"
    case .changed: "Location changed during observation"
    case .mountBoundary: "Mounted volume skipped"
    case .duplicateHardLink: "Previously counted hard link skipped"
    case .entryLimit: "Entry limit reached"
    case .depthLimit: "Folder depth limit reached"
    case .timeLimit: "Measurement time limit reached"
    case .sizeOverflow: "Size could not be represented safely"
    }
}

func historyAction(_ action: ManifestAction) -> String {
    switch action {
    case .prepared: "Prepared · recovery review needed"
    case .staged: "Staged · recovery review needed"
    case .trashed: "Moved to Trash"
    case .refused: "Refused safely"
    case .failed: "Move failed"
    case .recoveryRequired: "Recovery review needed"
    case .restorePrepared: "Restore prepared · review needed"
    case .restored: "Restored"
    case .restoreFailed: "Restore failed · review result"
    }
}

func undoOutcome(_ outcome: UndoOutcome) -> String {
    switch outcome {
    case .restored: "Restored"
    case .alreadyRestored: "Already restored"
    case .conflict: "Original path is occupied · Nothing overwritten"
    case .missing: "Recorded recovery item is missing"
    case .refused: "Restore refused safely"
    case .recoveryRequired: "Manual recovery review needed"
    }
}
