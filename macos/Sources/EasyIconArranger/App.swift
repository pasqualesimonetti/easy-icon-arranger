import AppKit
import SwiftUI

@main
struct HomeManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()

    init() {
        UserDefaults.standard.register(defaults: [L10n.languageKey: L10n.system])
    }

    var body: some Scene {
        Window(L("app.title"), id: "main") {
            ContentView()
                .environment(store)
                .tint(Brand.blue)
                .preferredColorScheme(Brand.forcedScheme)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1440, height: 920)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button(L("tb.undo")) { store.undo() }
                    .keyboardShortcut("z")
                    .disabled(!store.canUndo)
            }
            CommandGroup(replacing: .saveItem) {
                Button(L("tb.save") + "...") { NotificationCenter.default.post(name: .appSave, object: nil) }
                    .keyboardShortcut("s")
                    .disabled(!store.dirty || !store.problems.isEmpty)
            }
            CommandGroup(after: .saveItem) {
                Button(L("tb.reload")) { NotificationCenter.default.post(name: .appReload, object: nil) }
                    .keyboardShortcut("r")
                Button(L("tb.backups") + "...") { NotificationCenter.default.post(name: .appBackups, object: nil) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Asks before quitting with unsaved changes; keeps the edits alive when the
/// window is closed with unsaved changes (reopen it from the Dock).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(store?.dirty ?? false)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store?.dirty == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L("dlg.quit.title")
        alert.informativeText = L("dlg.quit.body")
        alert.addButton(withTitle: L("dlg.cancel"))
        alert.addButton(withTitle: L("dlg.quit.confirm"))
        alert.alertStyle = .warning
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        Engine.shutdown()
    }
}
