import AppKit
import SwiftUI

/// Knows when any menu (right-click menu, menu bar menu) is open, so the island and
/// the dock never close underneath it. Closing a window while its menu is open made
/// the app crash when a menu item was then chosen.
final class MenuTracker {
    static let shared = MenuTracker()

    private(set) var openMenus = 0
    var isTracking: Bool { openMenus > 0 }

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        // queue: nil runs the handler immediately, while the menu is opening, so there is no gap.
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { [weak self] _ in
            self?.openMenus += 1
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.openMenus = max(0, self.openMenus - 1)
        }
    }
}

/// A button for right-click menus. Its action runs on the next turn of the run loop,
/// after the menu has fully closed, so changing the layout from a menu is always safe.
struct MenuButton: View {
    let title: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(L(title), role: role) {
            let work = action
            DispatchQueue.main.async { work() }
        }
    }
}

/// Hosts SwiftUI inside a plain container view instead of making the NSHostingView the
/// window's content view. As the content view, NSHostingView keeps recomputing the
/// window's min/max size during layout; with continuous animations (wiggling tiles in
/// edit mode) macOS 26 looped forever ("more Update Constraints in Window passes than
/// there are views in the window") and crashed. Inside a container it never touches
/// the window size.
enum HostingContainer {
    static func make<Content: View>(_ root: Content, size: NSSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizesSubviews = true
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        return container
    }
}
