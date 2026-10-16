import SwiftUI
import RacketCore

struct CleanupPage: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: "Review before you remove.", subtitle: "Only verified categories are scanned. Each file keeps its path, explanation, and recovery record.")
            HStack {
                Picker("Category", selection: $model.moduleFilter) {
                    Text("All categories").tag("all")
                    Text("Developer").tag("developer")
                    Text("System").tag("system")
                    Text("Creative").tag("creative")
                }.pickerStyle(.menu).frame(width: 210)
                Spacer()
                if model.report != nil {
                    Button("Select visible") { model.selectVisible() }.disabled(model.busy || model.rows.isEmpty)
                    Button("Clear selection") { model.clearSelection() }.disabled(model.busy || model.selected.isEmpty)
                }
            }
            if let report = model.report {
                HStack {
                    Text("\(model.rows.count) visible files · \(formattedBytes(report.reportedAllocatedBytes)) observed allocation")
                    Spacer()
                    if model.incompleteCount > 0 { Label("Partial coverage", systemImage: "info.circle") }
                }.font(.caption).foregroundStyle(.secondary)
                if model.rows.isEmpty {
                    EmptyPanel(symbol: "checkmark.circle", title: "Nothing to review here", detail: "No files matched the current category and filters. This does not mean your Mac is free of all caches.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.rows) { row in FindingItem(row: row) }
                        }
                    }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                }
                DisclosureGroup("Scan details · \(report.visitedEntryCount) entries · \(report.issues.count) skips or issues") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(report.issues.prefix(500).enumerated()), id: \.offset) { _, issue in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(issueDescription(issue.reason)).font(.caption.weight(.medium))
                                    Text(issue.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if report.issues.count > 500 { Text("Showing the first 500 issues. Narrow categories and scan again for a smaller report.").font(.caption) }
                        }.padding(8)
                    }.frame(maxHeight: 170)
                }.font(.caption)
                if model.excludedFindingCount > 0 { Text("\(model.excludedFindingCount) findings are hidden by your exclusions.").font(.caption).foregroundStyle(.secondary) }
            } else {
                Spacer()
                EmptyPanel(symbol: "sparkles", title: model.busy ? "Looking carefully…" : "Start with a scan", detail: "Scan results are a review list. Files are never selected or removed by a scan.")
                HStack { Spacer(); Button("Scan verified categories") { model.scan() }.buttonStyle(.borderedProminent).disabled(model.busy || model.runtime == nil); Spacer() }
                Spacer()
            }
            Spacer(minLength: 0)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(model.selectedFindings.count) selected · \(formattedBytes(model.selectedBytes))").font(.headline).monospacedDigit()
                    Text("Selection may include files hidden by search or category filters. The review shows every selected path.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review selected files") { model.confirmCleanup = true }.buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.selectedFindings.isEmpty)
            }
        }.padding(32)
    }
}

struct FindingItem: View {
    @EnvironmentObject private var model: AppModel
    let row: FindingRow
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Toggle(isOn: Binding(get: { model.selected.contains(row.id) }, set: { model.setSelected(row.finding, enabled: $0) })) {
                Text("Select \((row.finding.resolvedPath as NSString).lastPathComponent)")
            }.labelsHidden().toggleStyle(.checkbox).disabled(model.busy)
                .accessibilityLabel("Select \((row.finding.resolvedPath as NSString).lastPathComponent), \(formattedBytes(row.finding.allocatedSize))")
            VStack(alignment: .leading, spacing: 5) {
                Text((row.finding.resolvedPath as NSString).lastPathComponent).font(.callout.weight(.medium))
                Text(row.finding.resolvedPath).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                Text(row.finding.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Recovery cost and source") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.finding.regenerationCost)
                        Text("Modified \(row.finding.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                        if let rule = model.runtime?.rules.rules.first(where: { $0.id == row.finding.ruleID }), let url = URL(string: rule.citation) {
                            Link("Read the rule's source", destination: url)
                        }
                    }.font(.caption).padding(.top, 4)
                }.font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(formattedBytes(row.finding.allocatedSize)).font(.callout).monospacedDigit().frame(width: 85, alignment: .trailing)
            Menu {
                Button("Reveal in Finder") { model.reveal(row.finding.resolvedPath) }
                Button("Always exclude this file") { model.exclude(row.finding.resolvedPath) }.disabled(model.busy)
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24)
                .accessibilityLabel("Actions for \((row.finding.resolvedPath as NSString).lastPathComponent)")
        }.padding(16)
        Divider().padding(.leading, 46)
    }
}

struct CleanupConfirmation: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Review your selection", systemImage: "trash").font(.title2.weight(.semibold))
            Text("Move \(model.selectedFindings.count) files (\(formattedBytes(model.selectedBytes)) allocated) to Trash?")
            Text("The files will be rechecked before each move. Trash continues to occupy storage. Recovery is available while the recorded files remain in Trash; emptying it can make removal permanent.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.selectedFindings.map(FindingRow.init)) { row in
                        HStack(alignment: .top) {
                            Text(row.finding.resolvedPath).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            Text(formattedBytes(row.finding.allocatedSize)).font(.caption).monospacedDigit()
                        }
                    }
                }.padding(12)
            }.frame(height: 260).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("Cancel") { model.confirmCleanup = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Move reviewed files to Trash", role: .destructive) { model.cleanSelected() }.buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 660)
    }
}

struct CreativePage: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "Creative work deserves care.", subtitle: "Originals, projects, and autosaves stay protected. A cache name alone never makes a file safe to remove.")
                ForEach(model.runtime?.rules.rules.filter { $0.module == .creative } ?? [], id: \.id) { rule in
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(rule.title).font(.title3.weight(.semibold)); Spacer(); Label(rule.enabled ? "Available" : "Verification pending", systemImage: rule.enabled ? "checkmark.circle" : "pause.circle").font(.caption) }
                            Text(rule.reason).foregroundStyle(.secondary)
                            ForEach(rule.paths, id: \.self) { Text($0).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                            Text(rule.regenerationCost).font(.caption).foregroundStyle(.secondary)
                            if let source = URL(string: rule.citation) { Link("Vendor documentation", destination: source).font(.caption) }
                            if !rule.enabled { Text("This category is not scanned or removed. Its content boundary, producer coverage, and recovery behavior need vendor-specific verification.").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DaVinci Resolve · After Effects · Photoshop").font(.headline)
                        Text("Locations can vary by project and application settings. Automatic project attribution and these broader cache categories are not available in this build.").foregroundStyle(.secondary)
                        Text("Use Storage Explorer to inspect a folder you choose, then reveal it in Finder. Exploration does not authorize cleanup.").font(.callout).foregroundStyle(.secondary)
                        Button("Explore a folder") { model.chooseFolder() }.disabled(model.busy)
                    }
                }
            }.padding(32)
        }
    }
}

func issueDescription(_ reason: ScanIssueReason) -> String {
    switch reason {
    case .dataless: "Cloud-only file skipped"
    case .pathRefused(let error): "Path skipped or refused: \(error.localizedDescription)"
    case .metadataUnavailable: "Metadata unavailable; coverage is incomplete"
    case .unsupportedMetadata: "Unsupported metadata; coverage is incomplete"
    case .depthLimit: "Folder depth limit reached"
    case .entryLimit: "Entry limit reached"
    case .excludedFromBackup: "Backup-excluded item skipped"
    case .notOldEnough: "Newer than this category's age boundary"
    case .duplicate: "Previously counted file or hard link"
    case .sizeOverflow: "Size could not be represented safely"
    case .producerRunning: "A producing application or tool is running"
    case .producerActivityUnknown: "Application activity is unknown; this category was refused"
    }
}
