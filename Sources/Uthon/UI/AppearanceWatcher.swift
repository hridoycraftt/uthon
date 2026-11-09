import AppKit

/// Glass and materials keep the colors they were created with, so when macOS switches
/// between light and dark (by hand, from the Controls tab, or automatically at sunset)
/// every Uthon surface is rebuilt with the new look.
final class AppearanceWatcher {
    static let shared = AppearanceWatcher()

    private var observation: NSKeyValueObservation?
    private var lastIsDark: Bool?

    func start() {
        lastIsDark = Self.systemIsDark
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            // The new appearance is applied a moment after the notification.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.changed() }
        }
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.changed() }
        }
    }

    static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Called when the system look may have changed; rebuilds only if it really did.
    func changed(force: Bool = false) {
        let dark = Self.systemIsDark
        guard force || dark != lastIsDark else { return }
        lastIsDark = dark
        AppSettings.shared.systemAppearanceTick += 1
        AppIcon.apply()
        QuickActions.shared.refresh()
    }
}

/// The app icon that matches the current appearance (dark icon in Dark Mode, light otherwise).
enum AppIcon {
    static var current: NSImage {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name = dark ? "AppIcon-Dark" : "AppIcon-Light"
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }

    /// Keep the Dock / app switcher icon in step with Light and Dark mode.
    static func apply() {
        guard Bundle.main.url(forResource: "AppIcon-Dark", withExtension: "png") != nil else { return }
        NSApp.applicationIconImage = current
    }
}
