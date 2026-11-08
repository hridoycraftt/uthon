import AppKit
import SwiftUI
import Combine
import QuartzCore

/// A borderless panel that can take keyboard focus (for the to-do field)
/// without activating the app or stealing focus from the app you are using.
final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the side dock window: where it sits, when it slides in and when it hides.
final class DockController {
    static let shared = DockController()

    let width: CGFloat = 300
    private let margin: CGFloat = 10
    private let revealDelay: TimeInterval = 0.15
    private let hideDelay: TimeInterval = 0.5

    private var panel: DockPanel?
    private var timer: Timer?
    private var screen: NSScreen?
    private var edgeSince: Date?
    private var outsideSince: Date?
    private var cancellables = Set<AnyCancellable>()

    private(set) var isShown = false
    /// Stay open until the mouse has visited the dock once (used by "Show" in the menu).
    private var sticky = false
    /// Set while a modal (file picker) is open, so the dock does not slide away.
    var holdOpen = false

    func start() {
        let p = DockPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovable = false
        p.becomesKeyOnlyIfNeeded = true
        p.contentView = NSHostingView(rootView: DockRootView())
        panel = p

        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        AppSettings.shared.$edge
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.reposition() } }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        if AppSettings.shared.pinned { show() }
    }

    // MARK: Show / hide

    func show(on target: NSScreen? = nil, sticky: Bool = false) {
        guard let panel else { return }
        if sticky { self.sticky = true }
        guard let scr = target ?? screenUnderMouse() ?? screen ?? NSScreen.main else { return }
        screen = scr

        if isShown {
            panel.setFrame(frame(on: scr, shown: true), display: true)
            return
        }
        isShown = true
        outsideSince = nil
        dockDidShow()

        panel.setFrame(frame(on: scr, shown: false), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let target = frame(on: scr, shown: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, isShown, let scr = screen else { return }
        isShown = false
        sticky = false
        dockDidHide()
        let target = frame(on: scr, shown: false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isShown else { return }
            self.panel?.orderOut(nil)
        })
    }

    func toggle() {
        isShown ? hide() : show(sticky: true)
    }

    // MARK: Geometry

    private func frame(on screen: NSScreen, shown: Bool) -> NSRect {
        let visible = screen.visibleFrame
        let slide: CGFloat = shown ? 0 : 28
        let height = visible.height - margin * 2
        let x: CGFloat
        switch AppSettings.shared.edge {
        case .right: x = visible.maxX - width - margin + slide
        case .left: x = visible.minX + margin - slide
        }
        return NSRect(x: x, y: visible.minY + margin, width: width, height: height)
    }

    private func reposition() {
        guard let panel, isShown, let scr = screen else { return }
        if !NSScreen.screens.contains(scr) { screen = NSScreen.main }
        if let s = screen { panel.setFrame(frame(on: s, shown: true), display: true) }
    }

    private func screenUnderMouse() -> NSScreen? {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { s in
            let f = s.frame
            return m.x >= f.minX && m.x <= f.maxX && m.y >= f.minY && m.y <= f.maxY
        }
    }

    // MARK: Mouse tracking

    private func tick() {
        guard let panel else { return }
        let settings = AppSettings.shared
        let mouse = NSEvent.mouseLocation

        if settings.pinned {
            if !isShown { show() }
            return
        }

        if !isShown {
            guard let scr = screenUnderMouse() else { edgeSince = nil; return }
            let f = scr.frame
            let atEdge: Bool
            switch settings.edge {
            case .right: atEdge = mouse.x >= f.maxX - 2
            case .left: atEdge = mouse.x <= f.minX + 1
            }
            let inBand = mouse.y > scr.visibleFrame.minY && mouse.y < scr.visibleFrame.maxY
            if atEdge && inBand {
                if let since = edgeSince {
                    if Date().timeIntervalSince(since) >= revealDelay {
                        edgeSince = nil
                        show(on: scr)
                    }
                } else {
                    edgeSince = Date()
                }
            } else {
                edgeSince = nil
            }
            return
        }

        // Shown: hide again once the mouse has left for a moment.
        let zone = panel.frame.insetBy(dx: -40, dy: -40)
        let inside = zone.contains(mouse)
        if inside { sticky = false }
        let busy = holdOpen
            || sticky
            || NSEvent.pressedMouseButtons != 0
            || CareReminders.shared.active != nil

        if inside || busy {
            outsideSince = nil
        } else if let since = outsideSince {
            if Date().timeIntervalSince(since) >= hideDelay {
                outsideSince = nil
                hide()
            }
        } else {
            outsideSince = Date()
        }
    }

    // Widgets only poll while the dock is on screen, to save battery.
    private func dockDidShow() {
        NowPlayingStore.shared.setActive(true)
        SystemStatsStore.shared.setActive(true)
        DownloadsStore.shared.refresh()
        CalendarStore.shared.refresh()
    }

    private func dockDidHide() {
        NowPlayingStore.shared.setActive(false)
        SystemStatsStore.shared.setActive(false)
    }
}
