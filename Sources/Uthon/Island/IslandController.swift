import AppKit
import SwiftUI
import Combine
import EventKit

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
    private var slowTimer: Timer?
    private var outsideSince: Date?
    private var peekDeadline: Date?
    private var peekHovered = false
    private var stickyOpen = false
    private var lastCapsLock: Bool?
    private var scrollMonitor: Any?
    private var scrollAccumulator: CGFloat = 0
    private var lastSwipe = Date.distantPast
    private var notifiedMeetings: Set<String> = []
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
        // We size this window ourselves. Letting SwiftUI resize it too made the two fight
        // in an endless layout loop: macOS 26 crashed ("more Update Constraints passes than
        // views") and macOS 15 stopped redrawing.
        let host = NSHostingView(rootView: IslandView())
        host.sizingOptions = []
        p.contentView = host
        panel = p

        let t = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let slow = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.slowTick() }
        RunLoop.main.add(slow, forMode: .common)
        slowTimer = slow

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScroll(event) ? nil : event
        }

        lastCapsLock = NSEvent.modifierFlags.contains(.capsLock)

        NotificationCenter.default.addObserver(forName: NowPlayingStore.trackChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self, AppSettings.shared.peekTrack, !self.model.expanded else { return }
            self.showPeek(.track, duration: 3.5)
        }

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
            model.peek = nil
            panel.orderOut(nil)
        }
        MediaKeyTap.shared.update()
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

        // The window never changes size while in use: it is made big enough for the largest
        // island (biggest size setting, widget gallery open) once. Resizing it while the
        // island animated (e.g. opening + Add Widget while tiles wiggle) sent macOS 26 into
        // an endless layout loop and crashed. Clicks outside the island still pass through
        // (see tick: the window only takes the mouse while it is over the island).
        let base = model.baseExpandedSize
        let galleryExtra: CGFloat = model.pickerOpen ? 0 : 210
        let maxScale: CGFloat = 1.5
        let width = base.width * maxScale + 80
        let height = (base.height + galleryExtra) * maxScale + 40
        let frame = NSRect(x: s.frame.midX - width / 2, y: s.frame.maxY - height, width: width, height: height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    private func rect(for size: CGSize, on s: NSScreen) -> NSRect {
        NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height, width: size.width, height: size.height)
    }

    private static func contains(_ r: NSRect, _ p: NSPoint) -> Bool {
        p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY
    }

    // MARK: Open / close

    func expand(tab: IslandTab? = nil, sticky: Bool = false) {
        guard AppSettings.shared.islandEnabled, let panel else { return }
        if let tab { model.tab = tab }
        if sticky { stickyOpen = true }
        guard !model.expanded else { return }
        if screen == nil { layout() }
        panel.ignoresMouseEvents = false
        outsideSince = nil
        withAnimation(IslandModel.spring) {
            model.expanded = true
            if let peek = model.peek, peek.kind.isSlim == false, peek.kind != .timerDone {
                model.peek = nil
            }
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        NowPlayingStore.shared.setActive(true)
        CalendarStore.shared.refresh()
    }

    func collapse() {
        guard model.expanded else { return }
        // Never close under an open menu: the menu's items belong to this window.
        if MenuTracker.shared.isTracking {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.collapse() }
            return
        }
        stickyOpen = false
        withAnimation(IslandModel.spring) {
            model.expanded = false
            model.dropTargeted = false
            model.editing = false
            model.pickerOpen = false
            model.openFolder = nil
        }
        panel?.ignoresMouseEvents = true
        if panel?.isKeyWindow == true { panel?.resignKey() }
        NowPlayingStore.shared.setActive(false)
    }

    func toggleFromShortcut() {
        if AppSettings.shared.islandEnabled {
            model.expanded ? collapse() : expand(sticky: true)
        } else if AppSettings.shared.sideDockEnabled {
            DockController.shared.toggle()
        }
    }

    // MARK: Peeks

    func showPeek(_ kind: PeekKind, duration: TimeInterval = 2.2) {
        guard AppSettings.shared.islandEnabled, screen != nil else { return }
        if let current = model.peek, current.kind.category == kind.category {
            model.peek?.kind = kind   // update in place: no new pop animation
        } else {
            withAnimation(IslandModel.peekSpring) { model.peek = Peek(kind: kind) }
        }
        peekDeadline = Date().addingTimeInterval(duration)
    }

    /// Replace the content of the current peek if it is of the same category.
    func updatePeek(_ kind: PeekKind) {
        guard let current = model.peek, current.kind.category == kind.category else { return }
        withAnimation(.easeOut(duration: 0.25)) { model.peek?.kind = kind }
        peekDeadline = Date().addingTimeInterval(3)
    }

    func dismissPeek() {
        withAnimation(IslandModel.peekSpring) { model.peek = nil }
        peekDeadline = nil
        peekHovered = false
    }

    // MARK: Tracking

    private func tick() {
        guard AppSettings.shared.islandEnabled, let s = screen, let panel else { return }
        let mouse = NSEvent.mouseLocation
        let pressed = NSEvent.pressedMouseButtons != 0

        checkCapsLock()

        if model.peek != nil, let deadline = peekDeadline, Date() > deadline, !peekHovered {
            dismissPeek()
        }

        if model.expanded {
            let zone = rect(for: model.expandedSize, on: s).insetBy(dx: -18, dy: -18)
            let inside = Self.contains(zone, mouse)
            // Take the mouse only over the island itself; elsewhere clicks go to the app below.
            let overIsland = Self.contains(rect(for: model.expandedSize, on: s).insetBy(dx: -4, dy: -4), mouse)
            let wantsMouse = overIsland || pressed || MenuTracker.shared.isTracking
            if panel.ignoresMouseEvents == wantsMouse { panel.ignoresMouseEvents = !wantsMouse }
            if inside { stickyOpen = false }
            let typing = panel.isKeyWindow
            let busy = holdOpen || stickyOpen || pressed || typing || MenuTracker.shared.isTracking
                || CareReminders.shared.active != nil || TimerStore.shared.alarmRinging
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
            return
        }

        if let peek = model.peek {
            let inside = Self.contains(rect(for: model.peekSize(peek.kind), on: s).insetBy(dx: -6, dy: -6), mouse)
            peekHovered = inside
            panel.ignoresMouseEvents = !inside
            if inside { return }
        } else {
            peekHovered = false
            panel.ignoresMouseEvents = true
        }

        let activity = IslandModel.currentActivity()
        let compact = model.compactSize(activity: activity)
        // An idle island without a notch is invisible: only a thin strip at the very top opens it.
        let invisible = !model.hasNotch && activity == nil
        let hot = CGSize(width: max(compact.width, 220), height: invisible ? 4 : compact.height)
        if Self.contains(rect(for: hot, on: s), mouse) {
            let draggingFiles = pressed && (NSPasteboard(name: .drag).types ?? []).contains(.fileURL)
            expand(tab: draggingFiles ? .shelf : nil)
        }
    }

    private func checkCapsLock() {
        let on = NSEvent.modifierFlags.contains(.capsLock)
        defer { lastCapsLock = on }
        guard let last = lastCapsLock, last != on, AppSettings.shared.peekCapsLock else { return }
        showPeek(.capsLock(on), duration: 1.6)
    }

    /// Every 30 seconds: meeting reminders and the media key tap (after permission is granted).
    private var notifiedPrayers: Set<String> = []
    private var announcedDay: String?

    private func slowTick() {
        MediaKeyTap.shared.update()
        checkPrayer()
        checkSpecialDays()
        guard AppSettings.shared.peekMeetings, AppSettings.shared.islandEnabled else { return }
        let calendar = CalendarStore.shared
        calendar.refresh()
        let now = Date()
        for event in calendar.events where !event.isAllDay {
            let start: Date = event.startDate
            let lead = start.timeIntervalSince(now)
            let key = "\(event.eventIdentifier ?? "")-\(start.timeIntervalSince1970)"
            if lead > 0, lead <= 5 * 60, !notifiedMeetings.contains(key) {
                notifiedMeetings.insert(key)
                showPeek(.meeting(title: event.title ?? "Meeting", start: start, link: event.meetingLink), duration: 15)
                NSSound(named: "Tink")?.play()
                break
            }
        }
    }

    private func checkPrayer() {
        let library = UserLibrary.shared
        guard library.prayerAlerts, AppSettings.shared.islandEnabled, let place = WeatherStore.shared.place,
              let times = PrayerTimes.compute(for: Date(), latitude: place.latitude, longitude: place.longitude,
                                              timeZone: place.timeZone, method: library.prayerMethod,
                                              hanafi: library.prayerHanafi) else { return }
        let now = Date()
        for prayer in times.prayers {
            let since = now.timeIntervalSince(prayer.time)
            let key = "\(prayer.name)-\(Int(prayer.time.timeIntervalSince1970))"
            if since >= 0, since < 120, !notifiedPrayers.contains(key) {
                notifiedPrayers.insert(key)
                showPeek(.prayer(name: prayer.name, time: prayer.time), duration: 20)
                NSSound(named: "Glass")?.play()
            }
        }
    }

    private func checkSpecialDays() {
        let library = UserLibrary.shared
        guard library.specialDayAlerts, AppSettings.shared.islandEnabled else { return }
        let today = Calendar.current.startOfDay(for: Date()).description
        guard announcedDay != today else { return }
        if let day = library.specialDays.first(where: { $0.daysLeft() == 0 }) {
            announcedDay = today
            showPeek(.specialDay(name: day.name, symbol: day.symbol), duration: 15)
        }
    }

    // MARK: Scroll gestures

    /// Over the open Home tab or a peek: scroll up/down = volume, swipe sideways = next/previous song.
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let s = screen else { return false }
        let size: CGSize
        if model.expanded {
            guard model.tab == .home else { return false }
            size = model.expandedSize
        } else if let peek = model.peek {
            size = model.peekSize(peek.kind)
        } else {
            return false
        }
        guard Self.contains(rect(for: size, on: s), NSEvent.mouseLocation) else { return false }

        var dx = event.scrollingDeltaX
        var dy = event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas {
            dx *= 8
            dy *= 8
        }
        if event.isDirectionInvertedFromDevice {
            dx = -dx
            dy = -dy
        }

        if abs(dx) > abs(dy) * 1.5 {
            guard abs(dx) > 14, Date().timeIntervalSince(lastSwipe) > 0.7 else { return true }
            let settings = AppSettings.shared
            if model.expanded, settings.homeSwipe == .pages, settings.pageCount > 1 {
                lastSwipe = Date()
                let next = model.homePage + (dx < 0 ? 1 : -1)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    model.homePage = min(settings.pageCount - 1, max(0, next))
                }
            } else if NowPlayingStore.shared.track != nil {
                lastSwipe = Date()
                NowPlayingStore.shared.command(dx < 0 ? "next track" : "previous track")
            }
            return true
        }

        scrollAccumulator += dy
        let step: CGFloat = 10
        while abs(scrollAccumulator) >= step {
            let up = scrollAccumulator > 0
            AudioController.shared.nudge(up ? 1.0 / 32.0 : -1.0 / 32.0)
            scrollAccumulator += up ? -step : step
        }
        return true
    }
}
