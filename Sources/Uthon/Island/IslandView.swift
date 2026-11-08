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
            ZStack {
                LiquidGlass(shape: shape)
                    .opacity(glass ? 1 : 0)
                shape
                    .fill(Color.black)
                    .opacity(glass ? 0 : 1)
            }
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(mode == .closed ? 0 : 0.3), radius: 20, y: 10)

            content(mode)
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                .contentShape(shape)
        }
        .id(settings.lookKey)
        .environment(\.locale, Localization.locale)
        .scaleEffect(visible ? 1 : 0.6, anchor: .top)
        .opacity(visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, glass ? systemScheme : .dark)
        .animation(IslandModel.spring, value: mode)
        .animation(IslandModel.spring, value: activity)
        .animation(IslandModel.peekSpring, value: model.peek?.id)
    }

    @ViewBuilder
    private func content(_ mode: Mode) -> some View {
        let scale = IslandModel.scale
        switch mode {
        case .open:
            // Laid out at the base size, then scaled to the user's chosen island size.
            let base = model.baseExpandedSize
            ExpandedIsland()
                .frame(width: base.width, height: base.height)
                .scaleEffect(scale, anchor: .top)
                .frame(width: base.width * scale, height: base.height * scale, alignment: .top)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(IslandModel.spring.delay(0.05)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
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
                CompactActivity(activity: activity)
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
        }
    }
}

private struct IslandHeader: View {
    @ObservedObject private var model = IslandModel.shared
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var weather = WeatherStore.shared
    @ObservedObject private var batteries = DeviceBatteryStore.shared
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(settings.visibleIslandTabs) { tab in
                    TabPill(tab: tab,
                            badge: tab == .shelf && !shelf.paths.isEmpty ? shelf.paths.count : nil,
                            selected: model.tab == tab,
                            namespace: tabNamespace) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            model.tab = tab
                            model.editing = false
                            model.openFolder = nil
                        }
                    }
                }
            }
            Spacer(minLength: model.hasNotch ? model.notchSize.width + 24 : 16)
            HStack(spacing: 8) {
                if model.tab == .home || model.tab == .controls {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.editing.toggle() }
                    } label: {
                        Text(model.editing ? "Done" : "Edit")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(model.editing ? Theme.accent : Color.primary.opacity(0.1)))
                            .foregroundStyle(model.editing ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .help(model.editing ? "Finish editing" : "Add, remove or reorder")
                }
                if let w = weather.current {
                    HStack(spacing: 3) {
                        Image(systemName: w.symbol).symbolRenderingMode(.multicolor)
                        Text("\(Int(w.temperature.rounded()))°")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .help("\(w.city)")
                }
                ForEach(batteries.devices.prefix(2)) { device in
                    HStack(spacing: 2) {
                        Image(systemName: device.symbol).font(.system(size: 9))
                        Text("\(device.percent)%").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    }
                    .foregroundStyle(device.percent <= 15 ? Color.red : Color.secondary)
                    .help(device.name)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                if settings.sideDockEnabled {
                    IconButton(symbol: settings.edge == .right ? "sidebar.right" : "sidebar.left", help: "Open the side dock", size: 14) {
                        IslandController.shared.collapse()
                        DockController.shared.show(sticky: true)
                    }
                }
                IconButton(symbol: "gearshape", help: "Customize", size: 14) {
                    SettingsWindowController.shared.show()
                }
            }
        }
        .padding(.horizontal, IslandModel.expandedFlare + 12)
    }
}

private struct TabPill: View {
    @ObservedObject private var settings = AppSettings.shared
    let tab: IslandTab
    let badge: Int?
    let selected: Bool
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
                if selected {
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
            .padding(.horizontal, 10)
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
