import AppKit
import SwiftUI
import Combine

enum IslandActivity: Equatable {
    case music
    case reminder(CareReminders.Kind)
}

/// Shared state for the island view.
final class IslandModel: ObservableObject {
    static let shared = IslandModel()

    enum Tab { case home, shelf }

    @Published var expanded = false
    @Published var tab: Tab = .home
    @Published var hasNotch = false
    @Published var notchSize = CGSize(width: 190, height: 32)
    @Published var dropTargeted = false

    static let compactFlare: CGFloat = 6
    static let expandedFlare: CGFloat = 14
    static let expandedSpring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    var earWidth: CGFloat { notchSize.height + 8 }

    var expandedSize: CGSize {
        CGSize(width: max(640, notchSize.width + 440), height: notchSize.height + 168)
    }

    func compactSize(hasActivity: Bool) -> CGSize {
        let base = notchSize.width + Self.compactFlare * 2
        return CGSize(width: hasActivity ? base + earWidth * 2 : base, height: notchSize.height)
    }

    /// What the closed island shows on its "ears", if anything.
    static func currentActivity() -> IslandActivity? {
        if let kind = CareReminders.shared.active { return .reminder(kind) }
        if NowPlayingStore.shared.track?.isPlaying == true { return .music }
        return nil
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the island window at the top centre of the screen (on the notch if the Mac has one).
/// Closed, it ignores the mouse so the menu bar works normally; hovering opens it.
final class IslandController {
    static let shared = IslandController()

    private let model = IslandModel.shared
    private var panel: IslandPanel?
    private var screen: NSScreen?
    private var timer: Timer?
    private var outsideSince: Date?
    private var cancellables = Set<AnyCancellable>()
    var holdOpen = false

    func start() {
        let p = IslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isMovable = false
        p.becomesKeyOnlyIfNeeded = true
        p.ignoresMouseEvents = true
        p.contentView = NSHostingView(rootView: IslandView())
        panel = p

        let t = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        AppSettings.shared.$islandEnabled
            .sink { [weak self] enabled in DispatchQueue.main.async { self?.apply(enabled: enabled) } }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &cancellables)
    }

    private func apply(enabled: Bool) {
        guard let panel else { return }
        if enabled {
            layout()
            panel.orderFrontRegardless()
        } else {
            collapse()
            panel.orderOut(nil)
        }
    }

    // MARK: Geometry

    /// The screen with a notch, otherwise the main (menu bar) screen.
    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    private func layout() {
        guard let panel, let s = targetScreen() else { return }
        screen = s
        let hasNotch = s.safeAreaInsets.top > 0
        var notch = CGSize(width: 190, height: max(24, s.frame.maxY - s.visibleFrame.maxY))
        if hasNotch, let left = s.auxiliaryTopLeftArea, let right = s.auxiliaryTopRightArea {
            notch = CGSize(width: s.frame.width - left.width - right.width, height: s.safeAreaInsets.top)
        }
        if model.hasNotch != hasNotch { model.hasNotch = hasNotch }
        if model.notchSize != notch { model.notchSize = notch }

        let expanded = model.expandedSize
        let width = expanded.width + 80
        let height = expanded.height + 40
        panel.setFrame(NSRect(x: s.frame.midX - width / 2, y: s.frame.maxY - height, width: width, height: height),
                       display: true)
    }

    /// Island rectangle in screen coordinates for a given size (top-centred).
    private func rect(for size: CGSize, on s: NSScreen) -> NSRect {
        NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height, width: size.width, height: size.height)
    }

    private static func contains(_ r: NSRect, _ p: NSPoint) -> Bool {
        p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY
    }

    // MARK: Open / close

    func expand(tab: IslandModel.Tab? = nil) {
        guard AppSettings.shared.islandEnabled, let panel else { return }
        if let tab { model.tab = tab }
        guard !model.expanded else { return }
        if screen == nil { layout() }
        panel.ignoresMouseEvents = false
        outsideSince = nil
        withAnimation(IslandModel.expandedSpring) { model.expanded = true }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        NowPlayingStore.shared.setActive(true)
        CalendarStore.shared.refresh()
    }

    func collapse() {
        guard model.expanded else { return }
        withAnimation(IslandModel.expandedSpring) {
            model.expanded = false
            model.dropTargeted = false
        }
        panel?.ignoresMouseEvents = true
        NowPlayingStore.shared.setActive(false)
    }

    // MARK: Mouse tracking

    private func tick() {
        guard AppSettings.shared.islandEnabled, let s = screen else { return }
        let mouse = NSEvent.mouseLocation
        let pressed = NSEvent.pressedMouseButtons != 0

        if !model.expanded {
            let compact = model.compactSize(hasActivity: IslandModel.currentActivity() != nil)
            // Without a notch an idle island is invisible, so use a hot strip at the top edge.
            let hotSize = CGSize(width: max(compact.width, 220), height: max(compact.height, 6))
            if Self.contains(rect(for: hotSize, on: s), mouse) {
                let draggingFiles = pressed && (NSPasteboard(name: .drag).types ?? []).contains(.fileURL)
                expand(tab: draggingFiles ? .shelf : nil)
            }
            return
        }

        let zone = rect(for: model.expandedSize, on: s).insetBy(dx: -18, dy: -18)
        let inside = Self.contains(zone, mouse)
        let busy = holdOpen || pressed || CareReminders.shared.active != nil
        if inside || busy {
            outsideSince = nil
        } else if let since = outsideSince {
            if Date().timeIntervalSince(since) >= 0.25 {
                outsideSince = nil
                collapse()
            }
        } else {
            outsideSince = Date()
        }
    }
}
