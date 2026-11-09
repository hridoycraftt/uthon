import SwiftUI

/// Built-in layout presets and the user's saved profiles.
enum Profiles {
    static let presets: [LayoutProfile] = [
        LayoutProfile(
            name: "Study", symbol: "book.fill",
            homePages: [["calendar", "todo", "notes", "countdown", "controls"], ["worldClock", "bookmarks", "system"]],
            controls: ["focusTimer", "keepAwake", "appearance", "sound", "screenshot", "sleepDisplay"],
            tabs: ["home", "timer", "notes", "search", "clipboard"], hiddenTabs: ["mirror", "shelf"],
            theme: ThemeColor.lavender.rawValue, builtIn: true),
        LayoutProfile(
            name: "Office", symbol: "briefcase.fill",
            homePages: [["calendar", "weather", "todo", "system", "batteries"], ["bookmarks", "worldClock", "shortcuts", "notes"]],
            controls: ["keepAwake", "screenshot", "sleepDisplay", "sound", "colorPicker", "activityMonitor", "screenRecording", "focusTimer"],
            tabs: ["home", "controls", "search", "clipboard", "shelf", "timer", "notes", "mirror"], hiddenTabs: [],
            theme: ThemeColor.ocean.rawValue, builtIn: true),
        LayoutProfile(
            name: "Music", symbol: "music.note",
            homePages: [["music", "weather", "shortcuts", "controls"]],
            controls: ["sound", "appearance", "keepAwake", "screenshot", "sleepDisplay", "emptyTrash"],
            tabs: ["home", "controls", "search", "shelf"], hiddenTabs: ["clipboard", "notes", "mirror", "timer"],
            theme: ThemeColor.rose.rawValue, builtIn: true),
        LayoutProfile(
            name: "Family", symbol: "house.fill",
            homePages: [["music", "calendar", "countdown", "prayer"], ["weather", "worldClock", "bookmarks", "todo", "notes"]],
            controls: ["keepAwake", "appearance", "sound", "screenshot", "sleepDisplay", "emptyTrash"],
            tabs: ["home", "controls", "search", "shelf", "timer", "clipboard", "notes", "mirror"], hiddenTabs: [],
            theme: ThemeColor.terracotta.rawValue, builtIn: true),
    ]

    static var all: [LayoutProfile] { presets + UserLibrary.shared.profiles }

    static func apply(_ profile: LayoutProfile) {
        let settings = AppSettings.shared
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            settings.homePages = profile.homePages.isEmpty ? [HomeWidget.defaults.map(\.rawValue)] : profile.homePages
            settings.enabledControls = Set(profile.controls)
            settings.controlOrder = profile.controls + ControlKind.allCases.map(\.rawValue).filter { !profile.controls.contains($0) }
            settings.islandTabOrder = profile.tabs + IslandTab.allCases.map(\.rawValue).filter { !profile.tabs.contains($0) }
            settings.hiddenIslandTabs = Set(profile.hiddenTabs)
            if let theme = ThemeColor(rawValue: profile.theme) { settings.themeColor = theme }
            IslandModel.shared.homePage = 0
        }
        UserLibrary.shared.activeProfile = profile.id
    }

    static func current(named name: String, symbol: String = "person.crop.circle.fill") -> LayoutProfile {
        let settings = AppSettings.shared
        return LayoutProfile(name: name, symbol: symbol, homePages: settings.homePages,
                             controls: settings.controls.map(\.rawValue),
                             tabs: settings.orderedIslandTabs.map(\.rawValue),
                             hiddenTabs: Array(settings.hiddenIslandTabs),
                             theme: settings.themeColor.rawValue)
    }

    @discardableResult
    static func saveCurrent(as name: String) -> LayoutProfile {
        let profile = current(named: name.isEmpty ? "My layout" : name)
        UserLibrary.shared.profiles.append(profile)
        UserLibrary.shared.activeProfile = profile.id
        return profile
    }

    /// Overwrite a saved profile with the current layout.
    static func update(_ profile: LayoutProfile) {
        guard let index = UserLibrary.shared.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = current(named: profile.name, symbol: profile.symbol)
        updated.id = profile.id
        UserLibrary.shared.profiles[index] = updated
    }

    static func delete(_ profile: LayoutProfile) {
        UserLibrary.shared.profiles.removeAll { $0.id == profile.id }
        if UserLibrary.shared.activeProfile == profile.id { UserLibrary.shared.activeProfile = nil }
    }
}

// MARK: - First-run guide

final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView())
            let w = NSWindow(contentViewController: hosting)
            w.title = L("Welcome to Nook")
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        AppSettings.shared.onboardingDone = true
    }
}

private struct OnboardingView: View {
    @State private var step = 0

    private let steps: [(symbol: String, title: String, text: String)] = [
        ("sparkles", "Welcome to Nook",
         "Your family's cosy little nook on the Mac: music, calendar, weather, files and handy controls, always one move away."),
        ("capsule.tophalf.filled", "The island at the top",
         "Move the mouse to the top centre of the screen (or press ⌃⌥Space) to open the island. Songs, timers and alerts appear there on their own."),
        ("square.grid.2x2.fill", "Make it yours",
         "Press Edit on the island: tiles wiggle. Tap − to remove, + Add Widget to add, drag to reorder. Right-click any tile to change its size or color."),
        ("sidebar.right", "The side dock",
         "Move the mouse to the right edge of the screen for the side dock with more widgets. You can switch it to the left or turn it off."),
        ("paintpalette.fill", "Themes, pages and profiles",
         "Pick a color theme, add up to 3 Home pages, and switch between layouts like Study, Office, Music or Family from the menu bar."),
    ]

    var body: some View {
        let item = steps[step]
        VStack(spacing: 18) {
            Image(systemName: item.symbol)
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(height: 70)
                .id(step)
                .transition(.scale.combined(with: .opacity))
            Text(L(item.title))
                .font(.system(size: 22, weight: .bold))
            Text(L(item.text))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Theme.accent : Color.secondary.opacity(0.3))
                        .frame(width: i == step ? 18 : 7, height: 7)
                }
            }
            HStack {
                if step > 0 {
                    Button(L("Back")) { withAnimation { step -= 1 } }
                }
                Spacer()
                if step < steps.count - 1 {
                    Button(L("Next")) { withAnimation { step += 1 } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(L("Start using Nook")) {
                        OnboardingWindowController.shared.close()
                        IslandController.shared.expand(sticky: true)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(32)
        .frame(width: 480, height: 400)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
    }
}
