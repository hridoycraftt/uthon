import SwiftUI
import AppKit
import EventKit

/// Root of the island window: one shape that morphs between closed, peek and open.
struct IslandView: View {
    @ObservedObject private var model = IslandModel.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var player = NowPlayingStore.shared
    @ObservedObject private var care = CareReminders.shared
    @ObservedObject private var timers = TimerStore.shared
    @Environment(\.colorScheme) private var systemScheme

    private enum Mode: Equatable { case closed, peek, open }

    private var activity: IslandActivity? {
        if let kind = care.active { return .reminder(kind) }
        if settings.liveTimers, timers.timerActive { return .timer }
        if settings.liveTimers, timers.stopwatchRunning { return .stopwatch }
        if settings.liveMusic, player.track?.isPlaying == true { return .music }
        return nil
    }

    private var mode: Mode {
        if model.expanded { return .open }
        if model.peek != nil { return .peek }
        return .closed
    }

    private func size(for mode: Mode) -> CGSize {
        switch mode {
        case .open: return model.expandedSize
        case .peek: return model.peek.map { model.peekSize($0.kind) } ?? model.compactSize(activity: activity)
        case .closed: return model.compactSize(activity: activity)
        }
    }

    var body: some View {
        let mode = self.mode
        let size = size(for: mode)
        let shape = NotchShape(
            topRadius: mode == .open ? IslandModel.expandedFlare : IslandModel.compactFlare,
            bottomRadius: mode == .open ? 32 : min(mode == .peek ? 24 : 14, size.height * 0.45)
        )
        // With a notch the closed island stays black so it melts into the hardware.
        let glass = settings.islandStyle == .automatic && (mode != .closed || !model.hasNotch)
        let visible = mode != .closed || model.hasNotch || activity != nil

        ZStack(alignment: .top) {
            // The glass is one layer that is always there and only changes size, centred,
            // so the island always grows out of the middle (never from a corner).
            ZStack {
                LiquidGlass(shape: shape)
                    .opacity(glass ? 1 : 0)
                shape
                    .fill(Color.black)
                    .opacity(glass ? 0 : 1)
            }
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottom) {
                if model.debugMarkers {
                    Rectangle().fill(Color(red: 0, green: 1, blue: 0)).frame(width: 6, height: 10)
                }
            }
            .shadow(color: .black.opacity(mode == .closed ? 0 : 0.3), radius: 20, y: 10)

            // The content never moves: it stays centred at its final size, and the island
            // shape opens over it like a window, from the middle out (as on iPhone).
            // (Sizing the content to the animating island made it ride along the island's
            // left edge, so it slid in from the right while the glass grew from the middle.)
            content(mode)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // An animatable clip that grows from the middle together with the glass.
                .clipShape(CentredIslandShape(width: size.width, height: size.height,
                                              topRadius: shape.topRadius, bottomRadius: shape.bottomRadius))
                // Same spring as the glass, so the clip and the glass grow together.
                .animation(mode == .open ? IslandModel.openSpring : IslandModel.closeSpring, value: mode)
            NightDimOverlay()
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
        }
        .id(settings.lookKey)
        .environment(\.locale, Localization.locale)
        .scaleEffect(visible ? 1 : 0.92, anchor: .top)
        .opacity(visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, glass ? systemScheme : .dark)
        .animation(mode == .open ? IslandModel.openSpring : IslandModel.closeSpring, value: mode)
        .animation(IslandModel.spring, value: activity)
        .animation(IslandModel.peekSpring, value: model.peek?.id)
    }

    @ViewBuilder
    private func content(_ mode: Mode) -> some View {
        let scale = IslandModel.scale
        let base = model.baseExpandedSize
        ZStack(alignment: .top) {
            // The open island's content is always there, centred at its final spot; opening
            // and closing only fade it in and out. It is never inserted or removed, so it can
            // never slide in from a side (it used to, for the first few frames).
            ExpandedIsland()
                .frame(width: base.width, height: base.height)
                .overlay(alignment: .center) {
                    if model.debugMarkers {
                        Rectangle().fill(Color(red: 1, green: 0, blue: 0)).frame(width: 6, height: 40)
                    }
                }
                .scaleEffect(scale, anchor: .top)
                .frame(width: base.width * scale, height: base.height * scale, alignment: .top)
                .opacity(mode == .open ? 1 : 0)
                .blur(radius: mode == .open ? 0 : 8)
                .allowsHitTesting(mode == .open)
                .accessibilityHidden(mode != .open)
                // Fade in only once the glass has mostly opened, so nothing (the bright app icons
                // on the right especially) shows before the island shape is there.
                .animation(mode == .open ? .easeOut(duration: 0.22).delay(0.12) : .easeIn(duration: 0.1), value: mode)
            otherContent(mode)
        }
    }

    @ViewBuilder
    private func otherContent(_ mode: Mode) -> some View {
        let scale = IslandModel.scale
        switch mode {
        case .open:
            EmptyView()
        case .peek:
            if let peek = model.peek {
                let base = model.basePeekSize(peek.kind)
                PeekView(kind: peek.kind)
                    .frame(width: base.width, height: base.height)
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: base.width * scale, height: base.height * scale, alignment: .top)
                    .id(peek.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        case .closed:
            if let activity {
                let closed = size(for: .closed)
                CompactActivity(activity: activity)
                    .frame(width: closed.width, height: closed.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
    }
}

// MARK: - Closed island: live activity on the "ears"

private struct CompactActivity: View {
    let activity: IslandActivity
    @ObservedObject private var model = IslandModel.shared
    @ObservedObject private var player = NowPlayingStore.shared
    @ObservedObject private var timers = TimerStore.shared

    var body: some View {
        let h = model.notchSize.height
        let ear = model.earWidth(for: activity)
        HStack(spacing: 0) {
            left.frame(width: ear, height: h)
            Spacer(minLength: 0)
            right.frame(width: ear, height: h)
        }
        .padding(.horizontal, IslandModel.compactFlare + 2)
        .foregroundStyle(Color.white)
    }

    @ViewBuilder private var left: some View {
        switch activity {
        case .music:
            ArtworkView(image: player.artwork, bundleID: player.track?.bundleID ?? "", size: model.notchSize.height - 10)
        case .reminder(let kind):
            Image(systemName: kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                RingProgress(progress: timers.progress(at: context.date), lineWidth: 2.5, color: Theme.accent)
                    .frame(width: 15, height: 15)
            }
        case .stopwatch:
            Image(systemName: "stopwatch.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
    }

    @ViewBuilder private var right: some View {
        switch activity {
        case .music:
            EqualizerBars(playing: true)
                .frame(width: 16, height: 12)
        case .reminder:
            PulsingDot()
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(TimerStore.format(timers.remaining(at: context.date)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timers.timerPaused ? Color.secondary : Theme.accent)
                    .contentTransition(.numericText(countsDown: true))
            }
        case .stopwatch:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(TimerStore.format(timers.elapsed(at: context.date)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }
}

struct PulsingDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 8, height: 8)
            .scaleEffect(on ? 1.25 : 0.8)
            .opacity(on ? 1 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

struct RingProgress: View {
    var progress: Double
    var lineWidth: CGFloat = 4
    var color: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
        }
    }
}

// MARK: - Open island

struct ExpandedIsland: View {
    @ObservedObject private var model = IslandModel.shared
    @ObservedObject private var care = CareReminders.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            IslandHeader()
                .frame(height: model.headerHeight)
            Group {
                if let kind = care.active {
                    IslandReminder(kind: kind)
                } else {
                    tabContent
                        .id(model.tab)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal: .opacity
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, IslandModel.expandedFlare + 12)
            .padding(.top, 4)
            .padding(.bottom, 14)
            .animation(.easeOut(duration: 0.18), value: model.tab)
        }
        .overlay(alignment: .bottom) {
            if let undo = model.undo {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(Theme.accent)
                    Text(undo.message).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Button(L("Undo")) { model.performUndo() }
                        .buttonStyle(AccentButtonStyle())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .environment(\.colorScheme, .dark)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .foregroundStyle(Color.white)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let peek = model.peek, peek.kind.isSlim {
                InlineHUD(kind: peek.kind)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onDrop(of: FileDrop.types, isTargeted: $model.dropTargeted) { providers in
            FileDrop.load(providers) { urls in
                ShelfStore.shared.add(urls)
                model.tab = .shelf
            }
            return true
        }
        .onAppear {
            if !settings.visibleIslandTabs.contains(model.tab) { model.tab = .home }
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch model.tab {
        case .home: IslandHome()
        case .controls: IslandControls()
        case .search: IslandSearch()
        case .shelf: IslandShelf()
        case .timer: IslandTimerTab()
        case .clipboard: IslandClipboard()
        case .notes: IslandNotes()
        case .mirror: IslandMirror()
        case .assistant: IslandAssistant()
        }
    }
}

private struct IslandHeader: View {
    @ObservedObject private var model = IslandModel.shared
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var weather = WeatherStore.shared
    @ObservedObject private var batteries = DeviceBatteryStore.shared
    @ObservedObject private var library = UserLibrary.shared
    @Namespace private var tabNamespace

    private enum HijriStyle { case none, full, short }
    private var hijriOn: Bool { library.hijriInHeader }
    /// Worked out once per header update, not for every layout tried.
    @State private var hijriFull = Hijri.text()
    @State private var hijriShort = Hijri.shortText()
    private let minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// The right side, from roomiest to tightest. With the Hijri date on, it stays (in short
    /// form) until only the clock is left; batteries go first, then the weather.
    @ViewBuilder private func rightGroups(dockButton: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            if hijriOn {
                rightGroup(hijri: .full, weather: true, batteries: true, dockButton: dockButton)
                rightGroup(hijri: .short, weather: true, batteries: true, dockButton: dockButton)
                rightGroup(hijri: .short, weather: true, batteries: false, dockButton: dockButton)
                rightGroup(hijri: .short, weather: false, batteries: false, dockButton: dockButton)
                rightGroup(hijri: .short, weather: false, batteries: false, clock: false, dockButton: dockButton)
            } else {
                rightGroup(weather: true, batteries: true, dockButton: dockButton)
                rightGroup(weather: true, batteries: false, dockButton: dockButton)
                rightGroup(weather: false, batteries: false, dockButton: dockButton)
            }
            rightGroup(weather: false, batteries: false, clock: false, dockButton: dockButton)
            rightGroup(weather: false, batteries: false, clock: false, dockButton: false)
        }
        // A fresh layout whenever the setting flips: no items left half-moved.
        .id(hijriOn ? hijriFull + hijriShort : "off")
        .transaction { $0.animation = nil }
    }

    /// Room the notch takes in the header (in the island's own, unscaled layout).
    private var notchGap: CGFloat { model.hasNotch ? model.notchSize.width / IslandModel.scale + 24 : 16 }

    private var inset: CGFloat { IslandModel.expandedFlare + 12 }
    private var iconSize: CGFloat { CGFloat(settings.tabIconSize) }
    private func pillWidth(compact: Bool) -> CGFloat { iconSize + 6 + (compact ? 16 : 20) }
    private var labelWidth: CGFloat { CGFloat(L(model.tab.title).count) * max(12, iconSize * 0.85) * 0.62 + 6 }
    private func tabsWidth(_ count: Int, compact: Bool) -> CGFloat {
        CGFloat(count) * pillWidth(compact: compact) + CGFloat(max(count - 1, 0)) * (compact ? 2 : 4)
            + (compact ? 0 : labelWidth)
    }

    /// No notch: tabs left, everything else right; tabs drop their labels when short of room.
    private func compactTabs(width: CGFloat) -> Bool {
        let available = width - 2 * inset - 16 - 220
        return tabsWidth(settings.visibleIslandTabs.count, compact: false) > available
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if model.hasNotch {
                    notchRow(width: geo.size.width)
                } else {
                    row(compact: compactTabs(width: geo.size.width))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // The Hijri date turns over at midnight and follows the adjustment and language.
        .onReceive(minuteTick) { _ in refreshHijri() }
        .onChange(of: library.hijriAdjust) { _, _ in refreshHijri() }
        .onChange(of: library.hijriInHeader) { _, _ in refreshHijri() }
        .onChange(of: settings.lookKey) { _, _ in refreshHijri() }
    }

    private func refreshHijri() {
        let full = Hijri.text(), short = Hijri.shortText()
        if full != hijriFull { hijriFull = full }
        if short != hijriShort { hijriShort = short }
    }

    private func pill(_ tab: IslandTab, compact: Bool) -> some View {
        TabPill(tab: tab,
                badge: tab == .shelf && !shelf.paths.isEmpty ? shelf.paths.count : nil,
                selected: model.tab == tab,
                compact: compact,
                namespace: tabNamespace) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                model.tab = tab
                model.editing = false
                model.openFolder = nil
            }
        }
    }

    /// With a notch: the notch splits the row. Tabs fill the left side; any that do not fit
    /// continue right of the notch, then Edit, the clock and the buttons (the clock and the
    /// side-dock button give way first). Nothing ever sits under the notch.
    private func notchRow(width: CGFloat) -> some View {
        let tabs = settings.visibleIslandTabs
        let half = max(0, (width - 2 * inset - notchGap) / 2)
        let labelled = tabsWidth(tabs.count, compact: false) <= half
        let compact = !labelled
        let fitLeft = labelled ? tabs.count
            : max(1, Int((half + 2) / (pillWidth(compact: true) + 2)))
        let left = Array(tabs.prefix(fitLeft))
        let right = Array(tabs.dropFirst(fitLeft))
        return HStack(spacing: 0) {
            HStack(spacing: compact ? 2 : 4) {
                ForEach(left) { pill($0, compact: compact) }
            }
            .frame(width: half, alignment: .leading)
            Color.clear.frame(width: notchGap)
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(right) { pill($0, compact: true) }
                }
                .fixedSize()
                Spacer(minLength: 0)
                rightGroups(dockButton: true)
            }
            .frame(width: half, alignment: .trailing)
        }
        .padding(.horizontal, inset)
    }

    private func row(compact: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: compact ? 2 : 4) {
                ForEach(settings.visibleIslandTabs) { pill($0, compact: compact) }
            }
            Spacer(minLength: 16)
            // When space is short, drop the battery chips first, then the weather.
            // Nothing ever wraps onto two lines.
            rightGroups(dockButton: true)
                .layoutPriority(1)
        }
        .padding(.horizontal, inset)
    }

    private func rightGroup(hijri: HijriStyle = .none, weather showWeather: Bool, batteries showBatteries: Bool,
                            clock: Bool = true, dockButton: Bool = true) -> some View {
        HStack(spacing: 8) {
            if model.tab == .home || model.tab == .controls {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.editing.toggle() }
                } label: {
                    Text(L(model.editing ? "Done" : "Edit"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(model.editing ? Theme.accent : Color.primary.opacity(0.1)))
                        .foregroundStyle(model.editing ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .help(L(model.editing ? "Finish editing" : "Add, remove or reorder"))
            }
            if hijri != .none {
                HStack(spacing: 3) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 9)).foregroundStyle(Theme.accent)
                    Text(hijri == .full ? hijriFull : hijriShort)
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .fixedSize()
                .help(hijriFull)
            }
            if showWeather, let w = weather.current {
                HStack(spacing: 3) {
                    Image(systemName: w.symbol).symbolRenderingMode(.multicolor)
                    Text("\(Int(w.temperature.rounded()))°").lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                .fixedSize()
                .help(w.city)
            }
            if showBatteries {
                ForEach(batteries.devices.prefix(2)) { device in
                    HStack(spacing: 3) {
                        Image(systemName: device.symbol).font(.system(size: 10))
                        Text("\(device.percent)%").font(.system(size: 10, weight: .semibold)).monospacedDigit().lineLimit(1)
                    }
                    .fixedSize()
                    .foregroundStyle(device.percent <= 15 ? Color.red : Color.secondary)
                    .help("\(device.name): \(device.percent)%")
                }
            }
            if clock {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if settings.sideDockEnabled && dockButton {
                IconButton(symbol: settings.edge == .right ? "sidebar.right" : "sidebar.left", help: "Open the side dock", size: 14) {
                    IslandController.shared.collapse()
                    DockController.shared.show(sticky: true)
                }
            }
            IconButton(symbol: "gearshape", help: "Customize", size: 14) {
                SettingsWindowController.shared.show()
            }
        }
        .fixedSize()
    }
}

private struct TabPill: View {
    @ObservedObject private var settings = AppSettings.shared
    let tab: IslandTab
    let badge: Int?
    let selected: Bool
    /// Short on room: icons only (the name shows on hover).
    var compact = false
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            let icon = CGFloat(settings.tabIconSize)
            HStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(.system(size: icon, weight: .semibold))
                    .frame(width: icon + 6, height: icon + 6)
                if selected && !compact {
                    Text(L(tab.title))
                        .font(.system(size: max(12, icon * 0.85), weight: .semibold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Capsule().fill(Theme.accent))
                }
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, 4)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.primary.opacity(0.14))
                        .matchedGeometryEffect(id: "tab", in: namespace)
                } else if hover {
                    Capsule().fill(Color.primary.opacity(0.06))
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(L(tab.title))
    }
}

/// Volume / brightness bar shown at the bottom of the open island.
private struct InlineHUD: View {
    let kind: PeekKind

    var body: some View {
        HStack(spacing: 10) {
            PeekHUDContent(kind: kind)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: 280)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .environment(\.colorScheme, .dark)
    }
}

/// Content appears out of a soft blur (as on iPhone), instead of popping in.
private struct BlurFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: active ? 10 : 0)
            .opacity(active ? 0 : 1)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
    }
}

/// The island outline drawn centred in whatever space it is given, at an animatable size,
/// so content clipped by it is revealed from the middle outwards as the island grows.
struct CentredIslandShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(width, height), AnimatablePair(topRadius, bottomRadius)) }
        set {
            width = newValue.first.first
            height = newValue.first.second
            topRadius = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let box = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
        return NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: box)
    }
}
