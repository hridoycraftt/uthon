import SwiftUI
import AppKit

enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Uthon"
    }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

@main
struct UthonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(AppInfo.name, systemImage: "sidebar.right") {
            MenuContent()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon: Uthon lives in the menu bar and on the screen edge.
        NSApp.setActivationPolicy(.accessory)
        DockController.shared.start()
        CareReminders.shared.start()

        // First launch: show the dock once so people know where it lives.
        let key = "didShowWelcome"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            DockController.shared.show(sticky: true)
        }
    }
}

struct MenuContent: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button("Show \(AppInfo.name)") { DockController.shared.show(sticky: true) }
        Toggle("Keep visible", isOn: $settings.pinned)
        Picker("Screen edge", selection: $settings.edge) {
            ForEach(DockEdge.allCases) { edge in
                Text(edge.title).tag(edge)
            }
        }
        Divider()
        Button("Settings…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")
        Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
