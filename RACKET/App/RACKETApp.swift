import SwiftUI
import RacketCore

@main
struct RACKETApp: App {
    @StateObject private var model = AppModel()

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
