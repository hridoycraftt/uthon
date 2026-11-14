import AppKit
import SwiftUI
import Combine
import ApplicationServices

/// Pieces the bottom dock can show, in this order.
enum BottomDockItem: String, CaseIterable, Identifiable {
    case apps, clock, music, weather, battery, system, network
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apps: return "Apps"
        case .clock: return "Clock"
        case .music: return "Music"
        case .weather: return "Weather"
        case .battery: return "Battery"
        case .system: return "CPU & memory"
        case .network: return "Internet speed"
        }
    }
    var symbol: String {
        switch self {
        case .apps: return "square.grid.2x2.fill"
        case .clock: return "clock.fill"
        case .music: return "music.note"
        case .weather: return "cloud.sun.fill"
        case .battery: return "battery.75percent"
        case .system: return "cpu"
        case .network: return "arrow.up.arrow.down"
        }
    }
    /// Width at size 1.0 (apps are counted per app).
    var baseWidth: CGFloat {
        switch self {
        case .apps: return 0
        case .clock: return 84
        case .music: return 190
        case .weather: return 78
        case .battery: return 66
        case .system: return 92
        case .network: return 92
        }
    }
}

enum BottomDockSide: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var title: String { self == .left ? "Left of the Dock" : "Right of the Dock" }
}

/// A second dock at the bottom of the screen, beside the macOS Dock.
///
/// macOS does not tell other apps where its Dock is. With Accessibility permission Uthon
/// reads the Dock's real frame and sits right next to it; without it, the bar sits in the
/// chosen bottom corner, as high as the Dock, at a distance the user can set.
final class BottomDockController: ObservableObject {
    static let shared = BottomDockController()

    static let appSize: CGFloat = 40
    /// The user's size setting (with "match the Dock" on, a fine-tune on top of the Dock's size).
    static var userScale: CGFloat { CGFloat(min(max(UserLibrary.shared.bottomDockScale, 0.7), 1.4)) }
    /// Size before squeezing: follows the macOS Dock's height when "match" is on.
    static var scale: CGFloat { shared.baseScale }

    /// Bar size for a Dock of this height: the bar is as tall as the Dock.
    /// Height of the bar at size 1 (an app icon is `appSize`, like a Dock icon of 40 pt).
    static let baseHeight: CGFloat = 52

    /// Bar size for the macOS Dock: exactly as tall as the Dock when its frame is known
    /// (Accessibility), otherwise app icons as big as the Dock's own icons (its icon size setting).
    static func matchedScale(dockHeight: CGFloat?, tileSize: CGFloat?, user: CGFloat, match: Bool) -> CGFloat {
        guard match else { return user }
        let base: CGFloat
        if let dockHeight, dockHeight > 10 { base = dockHeight / baseHeight }
        else if let tileSize, tileSize > 10 { base = tileSize / appSize }
        else { return user }
        return min(max(base, 0.5), 2.2) * user
    }

    /// The Dock's icon size setting (System Settings > Desktop & Dock > Size).
    static var dockTileSize: CGFloat? {
        (CFPreferencesCopyAppValue("tilesize" as CFString, "com.apple.dock" as CFString) as? NSNumber).map { CGFloat($0.doubleValue) }
    }

    private var panel: DockPanel?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private(set) var isShown = false
    private var outsideSince: Date?
    private var activeStores = false
    /// Where the macOS Dock was found last (Cocoa coordinates), if we may read it.
    private(set) var dockFrame: CGRect?
    /// Shrinks the bar when there is not enough room beside the Dock (1 = full size).
    @Published private(set) var fitScale: CGFloat = 1
    /// Even at the smallest size the bar does not fit beside the Dock.
    @Published private(set) var tooWide = false
    /// The Dock's size came from Accessibility (exact) rather than an estimate.
    @Published private(set) var exactDock = false
    /// The items that fit beside the Dock (the last ones drop off first when space is tight).
    @Published private(set) var visibleItems: [BottomDockItem] = []
    /// How many items were left out for lack of room.
    @Published private(set) var droppedCount = 0

    /// Follows the macOS Dock's size (or the user's size when matching is off).
    @Published private(set) var baseScale: CGFloat = 1

    var effectiveScale: CGFloat { baseScale * fitScale }

    func start() {
        guard panel == nil else { return }
        let p = DockPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        // Not .fullScreenAuxiliary: the bar stays out of full-screen apps, like the real Dock.
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovable = false
        p.becomesKeyOnlyIfNeeded = true
        p.contentView = HostingContainer.make(BottomDockView(), size: p.frame.size)
        panel = p

        let t = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let library = UserLibrary.shared
        Publishers.MergeMany(
            library.$bottomDockEnabled.map { _ in () }.eraseToAnyPublisher(),
            library.$bottomDockItems.map { _ in () }.eraseToAnyPublisher(),
            library.$bottomDockApps.map { _ in () }.eraseToAnyPublisher(),
            library.$bottomDockSide.map { _ in () }.eraseToAnyPublisher(),
            library.$bottomDockScale.map { _ in () }.eraseToAnyPublisher(),
            library.$bottomDockOffset.map { _ in () }.eraseToAnyPublisher(),
            library.$bottomDockAutoHide.map { _ in () }.eraseToAnyPublisher(),
            library.$bottomDockMatchDock.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
        .sink { [weak self] in self?.layout(force: true) }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.layout(force: true) }
            .store(in: &cancellables)
        layout(force: true)
    }

    // MARK: Size and place

    var contentWidth: CGFloat {
        Self.width(items: UserLibrary.shared.bottomDockItems, appCount: UserLibrary.shared.bottomDockAppURLs.count, scale: Self.scale)
    }

    static func width(items: [String], appCount: Int, scale: CGFloat) -> CGFloat {
        let parts = items.compactMap(BottomDockItem.init(rawValue:))
        var w: CGFloat = 0
        for part in parts {
            if part == .apps { w += CGFloat(max(appCount, 1)) * (appSize + 8) }
            else { w += part.baseWidth }
        }
        w += CGFloat(max(parts.count - 1, 0)) * 9   // dividers
        return (w + 20) * scale
    }

    static var height: CGFloat { baseHeight * scale }

    /// The screen with the macOS Dock (the primary one when unsure).
    static func dockScreen() -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.minY > $0.frame.minY + 1 } ?? NSScreen.screens.first
    }

    /// The Dock's frame from Accessibility, in Cocoa screen coordinates.
    static func readDockFrame() -> CGRect? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement], !items.isEmpty else { return nil }
        // The row of icons is the Dock's AXList (not always its first child).
        let list = items.first { element in
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            return (role as? String) == (kAXListRole as String)
        } ?? items[0]
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(list, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        // swiftlint:disable:next force_cast
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        guard size.width > 20, size.height > 20, let primary = NSScreen.screens.first else { return nil }
        // Accessibility uses top-left origin on the primary screen.
        return CGRect(x: point.x, y: primary.frame.height - point.y - size.height, width: size.width, height: size.height)
    }

    /// Where the bar goes, given the screen, the Dock (if known) and the settings.
    static func frame(screen: CGRect, visible: CGRect, dock: CGRect?, width: CGFloat, height: CGFloat,
                      side: BottomDockSide, offset: CGFloat) -> CGRect {
        let gap: CGFloat = 10
        let dockHeight = visible.minY - screen.minY
        var y = screen.minY + 6
        if let dock, dock.width > dock.height, abs(dock.minY - screen.minY) < 40 {
            y = dock.midY - height / 2
        } else if dockHeight > height {
            y = screen.minY + (dockHeight - height) / 2
        }
        var x: CGFloat
        if let dock, dock.width > dock.height, dock.minX >= screen.minX - 1, dock.maxX <= screen.maxX + 1 {
            x = side == .left ? dock.minX - gap - width - offset : dock.maxX + gap + offset
        } else {
            x = side == .left ? screen.minX + 12 + offset : screen.maxX - 12 - offset - width
        }
        x = min(max(x, screen.minX + 4), screen.maxX - width - 4)
        return CGRect(x: x.rounded(), y: max(y, screen.minY + 2).rounded(), width: width.rounded(), height: height.rounded())
    }

    private var lastFrame: CGRect = .zero
    private var lastDockCheck = Date.distantPast
    private var dockReadInFlight = false
    private static let dockQueue = DispatchQueue(label: "nook.bottomdock.ax", qos: .userInitiated)

    /// How much to shrink a bar of width `base` so it fits beside the Dock.
    static func fit(base: CGFloat, screen: CGRect, dock: CGRect?, side: BottomDockSide, offset: CGFloat) -> (scale: CGFloat, tooWide: Bool) {
        let room: CGFloat
        if let dock, dock.width > dock.height {
            room = side == .left ? dock.minX - screen.minX - 14 - offset : screen.maxX - dock.maxX - 14 - offset
        } else {
            room = screen.width - 24 - offset
        }
        guard base > room else { return (1, false) }
        let ratio = max(room, 0) / max(base, 1)
        return (max(ratio, 0.6), ratio < 0.6)
    }

    /// Which items to show and how big, so the bar never covers the macOS Dock: first it
    /// shrinks (down to 60%), then the last items drop off one by one.
    static func plan(items: [BottomDockItem], appCount: Int, scale: CGFloat, screen: CGRect, dock: CGRect?,
                     side: BottomDockSide, offset: CGFloat) -> (items: [BottomDockItem], scale: CGFloat, tooWide: Bool, dropped: Int) {
        var shown = items
        while !shown.isEmpty {
            let base = width(items: shown.map(\.rawValue), appCount: appCount, scale: scale)
            let f = fit(base: base, screen: screen, dock: dock, side: side, offset: offset)
            if !f.tooWide { return (shown, f.scale, false, items.count - shown.count) }
            shown.removeLast()
        }
        return ([], 1, !items.isEmpty, items.count)
    }

    /// Without Accessibility: the Dock's width worked out from its settings (icon size and
    /// the apps in it), centred on the screen. Good to a few points.
    static func estimatedDockFrame(on screen: NSScreen) -> CGRect? {
        let height = screen.visibleFrame.minY - screen.frame.minY
        guard height > 10 else { return nil }          // hidden, or on the side
        func pref(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) }
        let tile = CGFloat((pref("tilesize") as? NSNumber)?.doubleValue ?? 48)
        let persistent = (pref("persistent-apps") as? [[String: Any]]) ?? []
        let pinnedIDs = Set(persistent.compactMap { (($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String) })
        let others = (pref("persistent-others") as? [Any])?.count ?? 1
        let showRecents = (pref("show-recents") as? NSNumber)?.boolValue ?? true
        let recents = showRecents ? min((pref("recent-apps") as? [Any])?.count ?? 0, 3) : 0
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != "com.apple.finder"
                && !pinnedIDs.contains($0.bundleIdentifier ?? "")
        }.count
        let icons = CGFloat(1 + persistent.count + running + recents + others + 1)   // Finder ... Trash
        let separators: CGFloat = recents > 0 ? 2 : 1
        let width = icons * tile * 0.98 + separators * tile * 0.45 + tile * 0.4
        let f = screen.frame
        return CGRect(x: f.midX - width / 2, y: f.minY, width: min(width, f.width), height: height)
    }

    private func layout(force: Bool = false) {
        guard let panel else { return }
        let library = UserLibrary.shared
        guard library.bottomDockEnabled, !library.bottomDockItems.isEmpty, let screen = Self.dockScreen() else {
            hide()
            return
        }
        if force || dockFrame == nil {
            let exact = Self.readDockFrame()
            dockFrame = exact ?? Self.estimatedDockFrame(on: screen)
            if exactDock != (exact != nil) { exactDock = exact != nil }
            lastDockCheck = Date()
        } else if Date().timeIntervalSince(lastDockCheck) > 0.5, !dockReadInFlight {
            // Asking the Dock (Accessibility) talks to another app and can take a while when
            // it is busy, so it is done in the background; the bar follows when the answer comes.
            lastDockCheck = Date()
            dockReadInFlight = true
            Self.dockQueue.async { [weak self] in
                let exact = Self.readDockFrame()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.dockReadInFlight = false
                    let frame = exact ?? Self.dockScreen().flatMap { Self.estimatedDockFrame(on: $0) }
                    let changed = frame != self.dockFrame || self.exactDock != (exact != nil)
                    if self.exactDock != (exact != nil) { self.exactDock = exact != nil }
                    if changed {
                        self.dockFrame = frame
                        self.layout()
                    }
                }
            }
        }
        // Track the Dock's size: when it grows or shrinks, so does the bar.
        let atBottom = dockFrame.map { $0.width > $0.height } ?? false
        let wanted = Self.matchedScale(dockHeight: exactDock && atBottom ? dockFrame?.height : nil,
                                       tileSize: Self.dockTileSize, user: Self.userScale, match: library.bottomDockMatchDock)
        if abs(wanted - baseScale) > 0.01 { baseScale = wanted }
        let offset = CGFloat(library.bottomDockOffset)
        let plan = Self.plan(items: library.bottomDockItems.compactMap(BottomDockItem.init(rawValue:)),
                             appCount: library.bottomDockAppURLs.count, scale: Self.scale,
                             screen: screen.frame, dock: dockFrame, side: library.bottomDockSide, offset: offset)
        if plan.items != visibleItems { visibleItems = plan.items }
        if plan.dropped != droppedCount { droppedCount = plan.dropped }
        if abs(plan.scale - fitScale) > 0.005 { fitScale = plan.scale }
        if plan.tooWide != tooWide { tooWide = plan.tooWide }
        guard !plan.items.isEmpty else {
            hide()
            return
        }
        let width = Self.width(items: plan.items.map(\.rawValue), appCount: library.bottomDockAppURLs.count, scale: Self.scale)
        let target = Self.frame(screen: screen.frame, visible: screen.visibleFrame, dock: dockFrame,
                                width: width * plan.scale, height: Self.height * plan.scale,
                                side: library.bottomDockSide, offset: offset)
        if target != lastFrame || force {
            let animate = !force && isShown && lastFrame != .zero
            lastFrame = target
            if animate {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    panel.animator().setFrame(target, display: true)
                }
            } else {
                panel.setFrame(target, display: true)
            }
        }
        if !library.bottomDockAutoHide { show() }
    }

    // MARK: Show / hide

    private func show() {
        guard let panel, !isShown else { return }
        isShown = true
        setStores(true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel, isShown else { return }
        isShown = false
        setStores(false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isShown else { return }
            self.panel?.orderOut(nil)
        })
    }

    private func setStores(_ on: Bool) {
        guard on != activeStores else { return }
        activeStores = on
        NowPlayingStore.shared.setActive(on)
        SystemStatsStore.shared.setActive(on)
        if on { NetworkStore.shared.start() }
    }

    private func tick() {
        let library = UserLibrary.shared
        guard library.bottomDockEnabled else {
            if isShown { hide() }
            return
        }
        if Date().timeIntervalSince(lastDockCheck) > 0.5 { layout() }
        guard library.bottomDockAutoHide else { return }
        // Auto-hide: appear when the mouse touches the bottom edge below the bar.
        let mouse = NSEvent.mouseLocation
        if !isShown {
            let band = CGRect(x: lastFrame.minX - 20, y: lastFrame.minY - 10, width: lastFrame.width + 40, height: 14)
            if band.contains(mouse) || (Self.dockScreen().map { mouse.y <= $0.frame.minY + 2 && mouse.x >= lastFrame.minX && mouse.x <= lastFrame.maxX } ?? false) {
                show()
            }
            return
        }
        let inside = lastFrame.insetBy(dx: -30, dy: -30).contains(mouse)
        if inside || MenuTracker.shared.isTracking || NSEvent.pressedMouseButtons != 0 {
            outsideSince = nil
        } else if let since = outsideSince {
            if Date().timeIntervalSince(since) > 0.6 { outsideSince = nil; hide() }
        } else {
            outsideSince = Date()
        }
    }
}

// MARK: View

struct BottomDockView: View {
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var controller = BottomDockController.shared
    /// Screenshots: show these items at full size instead of what fits on this screen.
    var forcedItems: [BottomDockItem]?

    var body: some View {
        let scale = forcedItems == nil ? controller.effectiveScale : BottomDockController.userScale
        GeometryReader { geo in
            content
                .frame(width: geo.size.width / scale, height: geo.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .id(settings.lookKey)
        .environment(\.locale, Localization.locale)
        .nookGlass(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous))
        .overlay(NightDimOverlay().clipShape(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)))
    }

    private var items: [BottomDockItem] { forcedItems ?? controller.visibleItems }

    private var content: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                if index > 0 {
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 30).padding(.horizontal, 4)
                }
                view(for: item)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            MenuButton("Add Apps…") { library.pickBottomDockApps() }
            MenuButton("Bottom Dock Settings…") { SettingsWindowController.shared.show(tab: .bottomDock) }
            MenuButton("Hide Bottom Dock") { library.bottomDockEnabled = false }
        }
    }

    @ViewBuilder private func view(for item: BottomDockItem) -> some View {
        switch item {
        case .apps: BottomApps()
        case .clock: BottomClock().frame(width: item.baseWidth)
        case .music: BottomMusic().frame(width: item.baseWidth)
        case .weather: BottomWeather().frame(width: item.baseWidth)
        case .battery: BottomBattery().frame(width: item.baseWidth)
        case .system: BottomSystem().frame(width: item.baseWidth)
        case .network: BottomNetwork().frame(width: item.baseWidth)
        }
    }
}

private struct BottomApps: View {
    @ObservedObject private var library = UserLibrary.shared

    var body: some View {
        HStack(spacing: 8) {
            if library.bottomDockAppURLs.isEmpty {
                Button { library.pickBottomDockApps() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: BottomDockController.appSize, height: BottomDockController.appSize)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(L("Add Apps…"))
            }
            ForEach(library.bottomDockAppURLs, id: \.self) { url in
                BottomAppIcon(url: url)
            }
        }
    }
}

private struct BottomAppIcon: View {
    let url: URL
    @State private var hover = false

    private var running: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
    }

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            VStack(spacing: 2) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: BottomDockController.appSize, height: BottomDockController.appSize)
                    .scaleEffect(hover ? 1.12 : 1, anchor: .bottom)
                Circle().fill(Color.primary.opacity(running ? 0.6 : 0)).frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hover = h } }
        .help(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
        .contextMenu {
            MenuButton("Open") { NSWorkspace.shared.open(url) }
            MenuButton("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            MenuButton("Remove from Bottom Dock") { UserLibrary.shared.bottomDockApps.removeAll { $0 == url.path } }
        }
    }
}

private struct BottomClock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(spacing: 1) {
                Text(context.date.formatted(.dateTime.hour().minute().locale(Localization.locale)))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Localization.locale)))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}

private struct BottomMusic: View {
    @ObservedObject private var player = NowPlayingStore.shared

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let art = player.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").foregroundStyle(Color.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(player.track?.title ?? L("Not playing")).font(.system(size: 11, weight: .semibold))
                Text(player.track?.artist ?? "").font(.system(size: 10)).foregroundStyle(Color.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Button { player.track == nil ? player.openMusic() : player.command("playpause") } label: {
                Image(systemName: player.track?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            Button { player.command("next track") } label: {
                Image(systemName: "forward.fill").font(.system(size: 11)).frame(width: 18, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(player.track == nil)
        }
        .padding(.horizontal, 4)
    }
}

private struct BottomWeather: View {
    @ObservedObject private var weather = WeatherStore.shared

    var body: some View {
        if let w = weather.current {
            HStack(spacing: 5) {
                Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 18))
                Text("\(Int(w.temperature.rounded()))°").font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .help(w.city)
        } else {
            Image(systemName: "cloud.sun").foregroundStyle(Color.secondary)
        }
    }
}

private struct BottomBattery: View {
    @ObservedObject private var stats = SystemStatsStore.shared

    var body: some View {
        if let battery = stats.battery {
            VStack(spacing: 2) {
                Image(systemName: battery.charging ? "battery.100percent.bolt" : Self.symbol(battery.percent))
                    .font(.system(size: 16))
                    .foregroundStyle(battery.percent <= 20 && !battery.charging ? Color.red : Color.primary)
                Text("\(battery.percent)%").font(.system(size: 10, weight: .semibold)).monospacedDigit()
            }
        } else {
            VStack(spacing: 2) {
                Image(systemName: "powerplug.fill").font(.system(size: 15))
                Text(L("Power")).font(.system(size: 9)).foregroundStyle(Color.secondary)
            }
        }
    }

    static func symbol(_ percent: Int) -> String {
        switch percent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

private struct BottomSystem: View {
    @ObservedObject private var stats = SystemStatsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            bar("CPU", stats.cpu)
            bar("RAM", stats.memoryFraction)
        }
        .padding(.horizontal, 4)
    }

    private func bar(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.secondary).frame(width: 24, alignment: .leading)
            GeometryReader { geo in
                Capsule().fill(Color.primary.opacity(0.1))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.accent).frame(width: geo.size.width * min(max(value, 0), 1))
                    }
            }
            .frame(height: 5)
            Text("\(Int((value * 100).rounded()))%").font(.system(size: 9, weight: .semibold)).monospacedDigit().frame(width: 26, alignment: .trailing)
        }
    }
}

private struct BottomNetwork: View {
    @ObservedObject private var net = NetworkStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(NetworkStore.rate(net.downRate), systemImage: "arrow.down")
            Label(NetworkStore.rate(net.upRate), systemImage: "arrow.up")
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .onAppear { net.start() }
    }
}
