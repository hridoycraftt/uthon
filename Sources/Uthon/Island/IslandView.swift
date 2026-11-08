import SwiftUI
import AppKit
import EventKit

struct IslandView: View {
    @ObservedObject private var model = IslandModel.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var player = NowPlayingStore.shared
    @ObservedObject private var care = CareReminders.shared
    @Environment(\.colorScheme) private var systemScheme

    private var activity: IslandActivity? {
        if let kind = care.active { return .reminder(kind) }
        if player.track?.isPlaying == true { return .music }
        return nil
    }

    var body: some View {
        let expanded = model.expanded
        let glass = settings.islandStyle == .glass
        let size = expanded ? model.expandedSize : model.compactSize(hasActivity: activity != nil)
        let shape = NotchShape(
            topRadius: expanded ? IslandModel.expandedFlare : IslandModel.compactFlare,
            bottomRadius: expanded ? 32 : min(14, size.height * 0.42)
        )
        // Closed, the island is black so it melts into the notch.
        let visible = expanded || model.hasNotch || activity != nil

        ZStack(alignment: .top) {
            if glass {
                LiquidGlass(shape: NotchShape(topRadius: IslandModel.expandedFlare, bottomRadius: 32))
                    .frame(width: model.expandedSize.width, height: model.expandedSize.height)
                    .opacity(expanded ? 1 : 0)
            }
            shape
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(expanded && !glass ? 0.35 : 0), radius: 20, y: 10)
                .opacity(glass && expanded ? 0 : 1)

            content(expanded: expanded)
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                .contentShape(shape)
        }
        .opacity(visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, (!glass || !expanded) ? .dark : systemScheme)
        .animation(IslandModel.expandedSpring, value: expanded)
        .animation(IslandModel.expandedSpring, value: activity)
    }

    @ViewBuilder
    private func content(expanded: Bool) -> some View {
        if expanded {
            ExpandedIsland()
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
        } else if let activity {
            CompactActivity(activity: activity)
                .transition(.opacity)
        }
    }
}

// MARK: - Closed island (live activity on the "ears" either side of the notch)

private struct CompactActivity: View {
    let activity: IslandActivity
    @ObservedObject private var model = IslandModel.shared
    @ObservedObject private var player = NowPlayingStore.shared

    var body: some View {
        let h = model.notchSize.height
        HStack(spacing: 0) {
            left.frame(width: model.earWidth, height: h)
            Spacer(minLength: 0)
            right.frame(width: model.earWidth, height: h)
        }
        .padding(.horizontal, IslandModel.compactFlare + 2)
    }

    @ViewBuilder private var left: some View {
        switch activity {
        case .music:
            ArtworkView(image: player.artwork, bundleID: player.track?.bundleID ?? "", size: model.notchSize.height - 12)
        case .reminder(let kind):
            Image(systemName: kind.symbol)
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
        }
    }
}

private struct PulsingDot: View {
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

// MARK: - Open island

private struct ExpandedIsland: View {
    @ObservedObject private var model = IslandModel.shared
    @ObservedObject private var care = CareReminders.shared

    var body: some View {
        VStack(spacing: 0) {
            IslandHeader()
                .frame(height: model.notchSize.height)
            Group {
                if let kind = care.active {
                    IslandReminder(kind: kind)
                } else if model.tab == .home {
                    IslandHome()
                } else {
                    IslandShelf()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, IslandModel.expandedFlare + 12)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .onDrop(of: FileDrop.types, isTargeted: $model.dropTargeted) { providers in
            FileDrop.load(providers) { urls in
                ShelfStore.shared.add(urls)
                model.tab = .shelf
            }
            return true
        }
    }
}

private struct IslandHeader: View {
    @ObservedObject private var model = IslandModel.shared
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                TabPill(symbol: "house.fill", title: "Home", selected: model.tab == .home) { model.tab = .home }
                TabPill(symbol: "tray.fill",
                        title: shelf.paths.isEmpty ? "Shelf" : "Shelf · \(shelf.paths.count)",
                        selected: model.tab == .shelf) { model.tab = .shelf }
            }
            Spacer(minLength: model.notchSize.width + 24)
            HStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                if settings.sideDockEnabled {
                    IconButton(symbol: settings.edge == .right ? "sidebar.right" : "sidebar.left", help: "Open the side dock") {
                        IslandController.shared.collapse()
                        DockController.shared.show(sticky: true)
                    }
                }
                IconButton(symbol: "gearshape", help: "Settings") {
                    SettingsWindowController.shared.show()
                }
            }
        }
        .padding(.horizontal, IslandModel.expandedFlare + 14)
    }
}

private struct TabPill: View {
    let symbol: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(selected ? 0.14 : 0)))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Home tab

private struct IslandHome: View {
    var body: some View {
        HStack(spacing: 10) {
            IslandMusicTile()
                .frame(maxWidth: .infinity)
            IslandCalendarTile()
                .frame(width: 150)
            IslandShortcutsTile()
                .frame(width: 108)
        }
    }
}

private struct IslandMusicTile: View {
    @ObservedObject private var player = NowPlayingStore.shared

    var body: some View {
        Group {
            if let track = player.track {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 11) {
                        ArtworkView(image: player.artwork, bundleID: track.bundleID, size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text(track.artist.isEmpty ? track.player : track.artist)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        EqualizerBars(playing: track.isPlaying)
                            .frame(width: 16, height: 13)
                            .opacity(track.isPlaying ? 1 : 0.4)
                    }
                    if track.duration > 0 {
                        ProgressRow(track: track)
                    }
                    HStack(spacing: 28) {
                        Spacer()
                        control("backward.fill") { player.command("previous track") }
                        control(track.isPlaying ? "pause.fill" : "play.fill", size: 19) { player.command("playpause") }
                        control("forward.fill") { player.command("next track") }
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Color.secondary)
                    Text("Nothing playing")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                    Button("Open Music") { player.openMusic() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassChip(radius: 20)
    }

    private func control(_ symbol: String, size: CGFloat = 13, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
    }
}

private struct ProgressRow: View {
    let track: NowPlayingStore.Track

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = track.currentPosition(at: context.date)
            let fraction = track.duration > 0 ? min(max(position / track.duration, 0), 1) : 0
            HStack(spacing: 8) {
                Text(Self.time(position))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.14))
                        Capsule()
                            .fill(Color.primary.opacity(0.85))
                            .frame(width: max(3, geo.size.width * CGFloat(fraction)))
                    }
                }
                .frame(height: 4)
                Text(Self.time(track.duration))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct IslandCalendarTile: View {
    @ObservedObject private var calendar = CalendarStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Text(context.date.formatted(.dateTime.weekday(.wide)).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text(context.date, format: .dateTime.day())
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(context.date, format: .dateTime.month(.wide))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer(minLength: 0)
            switch calendar.access {
            case .granted:
                if let next = calendar.events.first {
                    Text(next.title ?? "Event")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(next.uthonTimeText)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                } else {
                    Text("No more events")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
            case .notDetermined:
                Button("Connect calendar") { calendar.requestAccess() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            case .denied:
                Text("Calendar off")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassChip(radius: 20)
    }
}

private struct IslandShortcutsTile: View {
    @ObservedObject private var store = ShortcutsStore.shared
    private let columns = [GridItem(.fixed(38), spacing: 8), GridItem(.fixed(38), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(store.paths.prefix(4)), id: \.self) { path in
                let url = URL(fileURLWithPath: path)
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 34, height: 34)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .help(FileManager.default.displayName(atPath: url.path))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassChip(radius: 20)
    }
}

// MARK: Shelf tab

private struct IslandShelf: View {
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var model = IslandModel.shared

    var body: some View {
        HStack(spacing: 10) {
            if shelf.paths.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .light))
                    Text("Drop files on the island to keep them here")
                        .font(.system(size: 11))
                }
                .foregroundStyle(model.dropTargeted ? Theme.accent : Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(model.dropTargeted ? Theme.accent : Color.secondary.opacity(0.4),
                                      style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.paths, id: \.self) { path in
                            ShelfTile(url: URL(fileURLWithPath: path)) { shelf.remove(path) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassChip(radius: 20)
                VStack(spacing: 8) {
                    ShelfAction(symbol: "paperplane.fill", title: "AirDrop") { airDrop() }
                    ShelfAction(symbol: "trash", title: "Clear") { shelf.clear() }
                }
                .frame(width: 86)
            }
        }
    }

    private func airDrop() {
        let urls = shelf.paths.map { URL(fileURLWithPath: $0) }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }
}

private struct ShelfTile: View {
    let url: URL
    let onRemove: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 70)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.10 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove from Shelf", action: onRemove)
        }
        .help("Double-click to open, or drag it out")
    }
}

private struct ShelfAction: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassChip(radius: 16)
    }
}

// MARK: Reminder

private struct IslandReminder: View {
    let kind: CareReminders.Kind

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: kind.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).font(.system(size: 15, weight: .semibold))
                Text(kind.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Button("Done") { CareReminders.shared.complete() }
                    .buttonStyle(AccentButtonStyle())
                Button("Later") { CareReminders.shared.snooze() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassChip(radius: 22)
    }
}

// MARK: Shared

struct ArtworkView: View {
    let image: NSImage?
    let bundleID: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .padding(size * 0.08)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .background(Color.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}
