import SwiftUI
import AppKit
import Combine

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
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon: Uthon lives in the menu bar, the notch and the screen edge.
        NSApp.setActivationPolicy(.accessory)

        AppSettings.shared.$appearance
            .sink { appearance in NSApp.appearance = appearance.nsAppearance }
            .store(in: &cancellables)

        if SnapshotTour.isActive {
            DockController.shared.start()
            IslandController.shared.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { SnapshotTour.run() }
            return
        }

        NowPlayingStore.shared.start()
        DockController.shared.start()
        IslandController.shared.start()
        CareReminders.shared.start()
        AudioController.shared.start()
        BrightnessController.shared.start()
        DeviceBatteryStore.shared.start()
        WeatherStore.shared.start()
        ClipboardStore.shared.start()
        ScreenshotWatcher.shared.start()
        DownloadsStore.shared.startWatching()
        MediaKeyTap.shared.update()

        AppSettings.shared.$hotkeyEnabled
            .sink { _ in DispatchQueue.main.async { HotKey.shared.update() } }
            .store(in: &cancellables)
        AppSettings.shared.$replaceSystemHUD
            .sink { _ in DispatchQueue.main.async { MediaKeyTap.shared.update() } }
            .store(in: &cancellables)

        // First launch: show the dock once so people know where it lives.
        let key = "didShowWelcome"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            if AppSettings.shared.sideDockEnabled { DockController.shared.show(sticky: true) }
        }
    }
}

struct MenuContent: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Toggle("Top island", isOn: $settings.islandEnabled)
        Toggle("Side dock", isOn: $settings.sideDockEnabled)
        if settings.sideDockEnabled {
            Button("Show side dock") { DockController.shared.show(sticky: true) }
            Toggle("Keep side dock visible", isOn: $settings.pinned)
            Picker("Side dock edge", selection: $settings.edge) {
                ForEach(DockEdge.allCases) { edge in
                    Text(edge.title).tag(edge)
                }
            }
        }
        Picker("Appearance", selection: $settings.appearance) {
            ForEach(AppAppearance.allCases) { appearance in
                Text(appearance.title).tag(appearance)
            }
        }
        Divider()
        Button("Open island") { IslandController.shared.expand(sticky: true) }
            .disabled(!settings.islandEnabled)
        Button("Customize…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")
        Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
