import SwiftUI
import AppKit

@main
struct TaskManagerApp: App {
    @StateObject private var appState = AppState()
    @State private var didShowBetaNotice = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1100, minHeight: 680)
                .preferredColorScheme(.dark)
                .onAppear {
                    if !didShowBetaNotice {
                        didShowBetaNotice = true
                        DispatchQueue.main.async {
                            BetaNotice.show()
                        }
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Task Manager") {
                    BetaNotice.showAbout()
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Run new task…") {
                    appState.showRunDialog = true
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            CommandMenu("View") {
                Button("Processes") { appState.page = .processes }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Performance") { appState.page = .performance }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("App history") { appState.page = .appHistory }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Startup apps") { appState.page = .startup }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Users") { appState.page = .users }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("Details") { appState.page = .details }
                    .keyboardShortcut("6", modifiers: [.command])
                Button("Services") { appState.page = .services }
                    .keyboardShortcut("7", modifiers: [.command])
                Divider()
                Picker("Update speed", selection: $appState.updateSpeed) {
                    ForEach(UpdateSpeed.allCases) { speed in
                        Text(speed.rawValue).tag(speed)
                    }
                }
                .onChange(of: appState.updateSpeed) { _, _ in
                    appState.applyUpdateSpeed()
                }
                Toggle("Always on top", isOn: $appState.alwaysOnTop)
                    .onChange(of: appState.alwaysOnTop) { _, _ in
                        appState.applyAlwaysOnTop()
                    }
                Button("Refresh now") { appState.refreshNow() }
                    .keyboardShortcut("l", modifiers: [.command])
            }
            CommandMenu("Process") {
                Button("End task") { appState.endSelected(force: false) }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(appState.selectedPIDs.isEmpty)
                Button("End process tree") { appState.endTree(force: false) }
                    .disabled(appState.selectedProcess == nil)
                Button("Force quit") { appState.endSelected(force: true) }
                    .keyboardShortcut(.delete, modifiers: [.option])
                    .disabled(appState.selectedPIDs.isEmpty)
                Divider()
                Button("Open file location") { appState.openLocation() }
                    .disabled(appState.selectedProcess == nil)
                Button("Search online") { appState.searchOnline() }
                    .disabled(appState.selectedProcess == nil)
                Button("Properties") { appState.showProperties = true }
                    .keyboardShortcut("i", modifiers: [.command])
                    .disabled(appState.selectedProcess == nil)
            }
        }
    }
}

enum BetaNotice {
    static let body = """
    Task Manager is a beta project. It is not yet legally registered.

    Please do not share this file or the app with anyone.

    Developed by James Murphy.
    """

    static func show() {
        let alert = NSAlert()
        alert.messageText = "Beta software — please do not share"
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.addButton(withTitle: "I understand")
        alert.runModal()
    }

    static func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Task Manager — beta"
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
