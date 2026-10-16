import SwiftUI
import RacketCore

enum RacketStyle {
    static let accent = Color(red: 0.443, green: 0.200, blue: 0.267)
    static let corner: CGFloat = 16
}

struct MainWindow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { viewport in
            navigationContent
                .frame(width: viewport.size.width, height: viewport.size.height)
        }
        .tint(scheme == .dark ? Color(red: 0.808, green: 0.537, blue: 0.604) : RacketStyle.accent)
        .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }
        .sheet(isPresented: $model.showOnboarding) { OnboardingView().environmentObject(model) }
        .sheet(isPresented: $model.confirmCleanup) { CleanupConfirmation().environmentObject(model) }
        .sheet(isPresented: $model.confirmApplication) { ApplicationConfirmation().environmentObject(model) }
    }

    private var navigationContent: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.title2).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RACKET").font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text("Space for your next idea.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 16).padding(.top, 24)
                VStack(spacing: 3) {
                    ForEach(Array(AppPage.allCases.enumerated()), id: \.element.id) { index, page in
                        Button {
                            if model.page != page { model.page = page }
                        } label: {
                            Label(page.title, systemImage: page.symbol)
                                .font(.callout.weight(model.page == page ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 13)
                                .foregroundStyle(model.page == page ? Color.white : Color.primary)
                                .background(model.page == page ? RacketStyle.accent : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                            .accessibilityValue(model.page == page ? "Selected" : "")
                    }
                }.padding(.horizontal, 12)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Local. Private. Yours.", systemImage: "lock.shield")
                    Text("No accounts. No telemetry.")
                }.font(.caption).foregroundStyle(.secondary).padding(16)
            }
            .navigationSplitViewColumnWidth(min: 215, ideal: 235, max: 280)
        } detail: {
            // Native macOS Lists have a large intrinsic height. A flexible
            // detail viewport keeps that estimate from enlarging the split.
            GeometryReader { detailViewport in
                VStack(spacing: 0) {
                    if model.verificationMode {
                        Label("Verification workspace · Sample files · Real user data is untouched", systemImage: "testtube.2")
                            .font(.caption).frame(maxWidth: .infinity).padding(8).background(.yellow.opacity(0.13))
                    }
                    if model.busy {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text(model.operation).font(.callout)
                            if let progress = model.scanProgress {
                                Text("\(progress.completedPaths) / \(progress.totalPaths) paths").foregroundStyle(.secondary).monospacedDigit()
                            }
                            Spacer()
                            Button("Cancel") { model.cancel() }.controlSize(.small)
                        }.padding(12).background(.quaternary.opacity(0.5))
                    }
                    if let error = model.errorMessage {
                        MessageBar(text: error, symbol: "exclamationmark.circle", isError: true) { model.errorMessage = nil }
                    }
                    if let notice = model.notice {
                        MessageBar(text: notice, symbol: "info.circle", isError: false) { model.notice = nil }
                    }
                    pageContent
                }
                .frame(width: detailViewport.size.width, height: detailViewport.size.height, alignment: .top)
                .background(scheme == .light ? Color(red: 0.961, green: 0.953, blue: 0.933) : Color(nsColor: .windowBackgroundColor))
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if model.page == .cleanup || model.page == .applications {
                        TextField("Search names and paths", text: $model.search)
                            .textFieldStyle(.roundedBorder).frame(width: 240).focused($searchFocused)
                            .accessibilityLabel("Search names and paths")
                    }
                }
                ToolbarItem {
                    Button { model.scan() } label: { Label("Scan", systemImage: "arrow.clockwise") }
                        .disabled(model.busy || model.runtime == nil)
                }
            }
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch model.page ?? .overview {
        case .overview: OverviewPage()
        case .cleanup: CleanupPage()
        case .creative: CreativePage()
        case .storage: StoragePage()
        case .applications: ApplicationsPage()
        case .recovery: RecoveryPage()
        case .settings: SettingsPage().padding(32)
        }
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: RacketStyle.corner))
            .overlay(RoundedRectangle(cornerRadius: RacketStyle.corner).stroke(.primary.opacity(0.055), lineWidth: 1))
    }
}

struct MessageBar: View {
    let text: String
    let symbol: String
    let isError: Bool
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(isError ? .red : .secondary)
            Text(text).textSelection(.enabled).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
        }.padding(14).background(isError ? Color.red.opacity(0.07) : Color.accentColor.opacity(0.06))
    }
}

struct EmptyPanel: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 38, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 450)
        }.frame(maxWidth: .infinity).padding(.vertical, 42)
    }
}

struct OverviewPage: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "Make room. Keep what matters.", subtitle: "Understand your storage, review every choice, and keep a way back.")
                Surface {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            Label("Your Mac's storage", systemImage: "internaldrive").font(.headline)
                            Spacer()
                            Button("Refresh") { Task { await model.refreshVolume() } }.buttonStyle(.borderless)
                        }
                        if let volume = model.volume {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(formattedBytes(volume.freeBytes)).font(.system(size: 42, weight: .medium, design: .rounded)).monospacedDigit()
                                Text("free of \(formattedBytes(volume.totalBytes))").foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(volume.usedBytes), total: max(1, Double(volume.totalBytes)))
                                .accessibilityLabel("Storage used").accessibilityValue(formattedBytes(volume.usedBytes))
                            HStack {
                                Label("\(formattedBytes(volume.usedBytes)) used", systemImage: "circle.fill")
                                Spacer()
                                Text("\(formattedBytes(volume.availableBytes)) available to your user")
                            }.font(.caption).foregroundStyle(.secondary)
                            Text("Filesystem free space is shown here. Finder may include purgeable storage that macOS manages. Scanned allocation is not a promise of space reclaimed.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else { Text("Reading storage capacity…").foregroundStyle(.secondary) }
                    }
                }
                HStack(alignment: .top, spacing: 18) {
                    Surface {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "sparkles").font(.title2).foregroundStyle(.tint)
                            Text("A considered cleanup").font(.title3.weight(.semibold))
                            Text("Scan \(model.enabledRules.count) verified \(model.enabledRules.count == 1 ? "category" : "categories"). Nothing is selected or removed automatically.")
                                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Review a scan") { model.scan() }.buttonStyle(.borderedProminent).disabled(model.busy || model.runtime == nil)
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "folder.badge.gearshape").font(.title2).foregroundStyle(.tint)
                            Text("Follow the space").font(.title3.weight(.semibold))
                            Text("Choose a folder and see its allocated storage. Explore larger folders and reveal files in Finder.")
                                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Choose a folder") { model.chooseFolder() }.buttonStyle(.bordered).disabled(model.busy)
                        }
                    }
                }
                HStack(spacing: 24) {
                    Label(model.lastScanDate.map { "Last scan \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No scan yet", systemImage: "clock")
                    Spacer()
                    Button("View recovery history") { model.page = .recovery }.buttonStyle(.borderless)
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(32)
        }
    }
}

struct RacketMenu: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if let volume = model.volume { Text("\(formattedBytes(volume.freeBytes)) filesystem free") }
        if model.busy { Text(model.operation) }
        Button("Open RACKET") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Scan verified categories") { openWindow(id: "main"); model.scan() }.disabled(model.busy || model.runtime == nil)
        Divider()
        Button("Recovery") { model.page = .recovery; openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Settings") { model.page = .settings; openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Text("Scheduled scans never remove files")
        Button("Quit RACKET") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "sparkles").font(.system(size: 42, weight: .light)).foregroundStyle(.tint)
            PageHeading(title: "A little more room.", subtitle: "RACKET helps you understand what's on your Mac and make deliberate cleanup choices.")
            Label("Scan only categories with a documented cleanup boundary.", systemImage: "checkmark.shield")
            Label("Choose files yourself and review the exact selection.", systemImage: "checklist")
            Label("Move to Trash, with a recorded path back through Recovery.", systemImage: "arrow.uturn.backward")
            Text("Recovery requires the recorded files to remain available. Emptying Trash can make removal permanent. RACKET never empties Trash automatically.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Everything stays on this Mac.").foregroundStyle(.secondary)
                Spacer()
                Button("Get started") { model.finishOnboarding() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(36).frame(width: 580)
    }
}
