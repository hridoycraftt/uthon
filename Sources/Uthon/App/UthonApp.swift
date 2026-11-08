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
        MenuTracker.shared.start()

        AppSettings.shared.$appearance
            .sink { appearance in NSApp.appearance = appearance.nsAppearance }
            .store(in: &cancellables)

        if SelfTest.isActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { SelfTest.run() }
            return
        }

        if SnapshotTour.isActive {
            DockController.shared.start()
            IslandController.shared.start()
            WeatherStore.shared.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated { SnapshotTour.run() } }
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
        Updater.shared.start()
        WallpaperChanger.shared.start()
        if !AppSettings.shared.onboardingDone {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { OnboardingWindowController.shared.show() }
        }

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
    @ObservedObject private var library = UserLibrary.shared

    var body: some View {
        Toggle(L("Top island"), isOn: $settings.islandEnabled)
        Toggle(L("Side dock"), isOn: $settings.sideDockEnabled)
        if settings.sideDockEnabled {
            Button(L("Show side dock")) { DockController.shared.show(sticky: true) }
            Toggle(L("Keep side dock visible"), isOn: $settings.pinned)
            Picker(L("Side dock edge"), selection: $settings.edge) {
                ForEach(DockEdge.allCases) { edge in
                    Text(L(edge.title)).tag(edge)
                }
            }
        }
        Picker(L("Appearance"), selection: $settings.appearance) {
            ForEach(AppAppearance.allCases) { appearance in
                Text(L(appearance.title)).tag(appearance)
            }
        }
        Divider()
        Button(L("Open island")) { IslandController.shared.expand(sticky: true) }
            .disabled(!settings.islandEnabled)
        Menu(L("Layout")) {
            ForEach(Profiles.all) { profile in
                Button((library.activeProfile == profile.id ? "✓ " : "") + L(profile.name)) { Profiles.apply(profile) }
            }
            Divider()
            Button(L("Manage profiles…")) { SettingsWindowController.shared.show(tab: .profiles) }
        }
        Menu(L("Theme")) {
            ForEach(ThemeColor.allCases.filter { $0 != .custom }) { theme in
                Button((settings.themeColor == theme ? "✓ " : "") + L(theme.title)) { settings.themeColor = theme }
            }
        }
        if UserLibrary.shared.wallpaperSource != .off {
            Button(L("Next wallpaper")) { WallpaperChanger.shared.next() }
        }
        Button(L("Welcome guide")) { OnboardingWindowController.shared.show() }
        Button(L("Customize…")) { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")
        Button(L("Quit") + " \(AppInfo.name)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
