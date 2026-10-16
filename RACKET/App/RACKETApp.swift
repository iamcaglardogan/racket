import SwiftUI
import RacketCore

@main
struct RACKETApp: App {
    @StateObject private var model = AppModel()

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--version") {
            print("RACKET \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")")
            exit(0)
        }
        if arguments.contains("--verify-installation") {
            do {
                // Bundle-only diagnostics: no scan, journal, user preference
                // writes, network request, or application window is started.
                let rules = try RuleSet.bundled()
                let result: [String: Any] = ["status": "pass", "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
                    "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                    "ruleSetVersion": rules.version, "enabledRules": rules.enabledRules.map(\.id),
                    "telemetry": false, "minimumMacOS": "14.0"]
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                FileHandle.standardOutput.write(data); print("")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("RACKET installation verification failed: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }

    var body: some Scene {
        WindowGroup("RACKET", id: "main") {
            MainWindow()
                .environmentObject(model)
                .preferredColorScheme(model.appearance == "light" ? .light : model.appearance == "dark" ? .dark : nil)
                .frame(minWidth: 980, minHeight: 680)
                .task { model.start() }
        }
        .defaultSize(width: 1140, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan verified categories") { model.scan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.busy || model.runtime == nil)
            }
            CommandGroup(after: .textEditing) {
                Button("Find in Results") { model.requestSearchFocus() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(!model.canFocusSearch)
            }
        }

        Settings {
            SettingsPage().environmentObject(model).frame(width: 650, height: 620)
                .padding(24)
        }

        MenuBarExtra("RACKET", systemImage: "sparkles", isInserted: Binding(
            get: { model.menuBarEnabled },
            set: { if model.menuBarEnabled != $0 { model.menuBarEnabled = $0 } }
        )) {
            RacketMenu().environmentObject(model)
        }
    }
}
