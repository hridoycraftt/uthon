import SwiftUI
import AppKit

/// A short pop-up that drops out of the island (volume, AirPods, downloads...).
struct PeekView: View {
    let kind: PeekKind
    @ObservedObject private var model = IslandModel.shared

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.hasNotch ? model.notchSize.height / IslandModel.scale : 0)
            Group {
                if kind.isSlim {
                    HStack(spacing: 10) { PeekHUDContent(kind: kind) }
                } else {
                    card
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, IslandModel.compactFlare + 16)
            .padding(.bottom, kind.isSlim ? 2 : 6)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            switch kind {
            case .volume, .brightness, .track, .capsLock, .charging:
                IslandController.shared.dismissPeek()
                IslandController.shared.expand()
            default:
                break
            }
        }
    }

    @ViewBuilder private var card: some View {
        switch kind {
        case .headphones(let name, let symbol, let levels):
            HeadphonesPeek(name: name, symbol: symbol, levels: levels)
        case .track:
            TrackPeek()
        case .download(let url):
            FilePeek(url: url, title: "Downloaded", symbol: "arrow.down.circle.fill", thumbnail: false)
        case .screenshot(let url):
            FilePeek(url: url, title: "Screenshot", symbol: "camera.viewfinder", thumbnail: true)
        case .meeting(let title, let start, let link):
            MeetingPeek(title: title, start: start, link: link)
        case .lowBattery(let name, let percent):
            PeekRow(symbol: DeviceBatteryStore.symbol(for: name), tint: .red,
                    title: "\(name) battery low", subtitle: "\(percent)% left, charge it soon") {
                BatteryGlyph(percent: percent, charging: false)
            }
        case .timerDone:
            PeekRow(symbol: "timer", tint: Theme.accent, title: "Time's up!", subtitle: "Your timer has finished") {
                HStack(spacing: 8) {
                    Button(L("+1 min")) {
                        TimerStore.shared.stopAlarm()
                        TimerStore.shared.startTimer(minutes: 1)
                        IslandController.shared.dismissPeek()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    Button(L("Stop")) {
                        TimerStore.shared.stopAlarm()
                        IslandController.shared.dismissPeek()
                    }
                    .buttonStyle(AccentButtonStyle())
                }
            }
        case .update(let version):
            UpdatePeekRow(version: version)
        case .verse(let reference, let text, let isQuran):
            HStack(spacing: 12) {
                Image(systemName: isQuran ? "book.closed.fill" : "text.book.closed.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(text).font(.system(size: 12)).lineLimit(2).minimumScaleFactor(0.85)
                    Text(reference).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                IslandController.shared.dismissPeek()
                VerseReader.show()
            }
        case .prayer(let name, let time):
            PeekRow(symbol: "moon.stars.fill", tint: Theme.accent, title: L("Time for") + " " + L(name),
                    subtitle: time.formatted(date: .omitted, time: .shortened)) {
                Button(L("OK")) { IslandController.shared.dismissPeek() }
                    .buttonStyle(AccentButtonStyle())
            }
        case .specialDay(let name, let symbol):
            PeekRow(symbol: symbol, tint: Theme.accent, title: L("Today is") + " " + name + " 🎉",
                    subtitle: L("Don't forget to celebrate!")) {
                Button(L("OK")) { IslandController.shared.dismissPeek() }
                    .buttonStyle(AccentButtonStyle())
            }
        case .notification(let note):
            NotificationPeekView(note: note)
        default:
            EmptyView()
        }
    }
}

/// A notification from another app: its icon, who it is from and the message.
private struct NotificationPeekView: View {
    let note: NotificationPeek

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: note.bundleID) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                } else {
                    Image(systemName: "bell.badge.fill").font(.system(size: 18)).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(note.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(note.app).font(.system(size: 10)).foregroundStyle(Color.secondary).lineLimit(1)
                }
                Text(note.text).font(.system(size: 11)).foregroundStyle(Color.secondary).lineLimit(2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            IslandController.shared.dismissPeek()
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: note.bundleID) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

/// Icon + level bar used for volume, brightness, Caps Lock and charging.
struct PeekHUDContent: View {
    let kind: PeekKind

    var body: some View {
        switch kind {
        case .volume(let level, let muted):
            Image(systemName: Self.volumeSymbol(level: level, muted: muted))
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22)
                .contentTransition(.symbolEffect(.replace))
            LevelBar(level: muted ? 0 : level)
            Text(muted ? "Muted" : "\(Int((level * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
                .contentTransition(.numericText())
        case .brightness(let level):
            Image(systemName: level < 0.5 ? "sun.min.fill" : "sun.max.fill")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22)
                .contentTransition(.symbolEffect(.replace))
            LevelBar(level: level)
            Text("\(Int((level * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
                .contentTransition(.numericText())
        case .capsLock(let on):
            Image(systemName: on ? "capslock.fill" : "capslock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Theme.accent : Color.secondary)
            Text(on ? "Caps Lock on" : "Caps Lock off")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
        case .charging(let percent):
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.green)
                .symbolEffect(.pulse)
            Text(L("Charging"))
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            Text("\(percent)%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
            BatteryGlyph(percent: percent, charging: true)
        case .network(let online):
            Image(systemName: online ? "wifi" : "wifi.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(online ? Color.green : Color.orange)
            Text(L(online ? "Back online" : "Internet disconnected"))
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
        default:
            EmptyView()
        }
    }

    static func volumeSymbol(level: Float, muted: Bool) -> String {
        if muted || level < 0.01 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

struct LevelBar: View {
    let level: Float
    var color: Color = .primary

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: max(6, geo.size.width * CGFloat(max(0, min(1, level)))))
                    .shadow(color: Color.white.opacity(0.35), radius: 4)
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: level)
    }
}

/// A battery outline that fills up (and glows green while charging).
struct BatteryGlyph: View {
    let percent: Int
    let charging: Bool
    @State private var shown = false

    var body: some View {
        let fill = CGFloat(max(0, min(100, percent))) / 100
        let color: Color = charging ? .green : (percent <= 20 ? .red : Color.primary)
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(Color.primary.opacity(0.5), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: max(2, 22 * (shown ? fill : 0)))
                    .padding(2)
            }
            .frame(width: 28, height: 13)
            RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.5)).frame(width: 2, height: 5)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.15)) { shown = true }
        }
    }
}

/// Animated ring with a label, for AirPods L / R / case.
struct BatteryRing: View {
    let percent: Int
    let label: String
    @State private var shown = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: shown ? CGFloat(percent) / 100 : 0)
                    .stroke(percent <= 20 ? Color.red : Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(L(label)).font(.system(size: 9, weight: .bold))
            }
            .frame(width: 28, height: 28)
            Text("\(percent)%").font(.system(size: 9, weight: .semibold)).monospacedDigit()
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.1)) { shown = true }
        }
    }
}

private struct PeekRow<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(L(subtitle)).font(.system(size: 11)).foregroundStyle(Color.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            accessory()
        }
    }
}

private struct HeadphonesPeek: View {
    let name: String
    let symbol: String
    let levels: HeadphoneLevels?
    @State private var bounce = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .regular))
                .symbolEffect(.bounce, value: bounce)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(L("Connected")).font(.system(size: 11)).foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
            if let levels {
                HStack(spacing: 10) {
                    if let left = levels.left { BatteryRing(percent: left, label: "L") }
                    if let right = levels.right { BatteryRing(percent: right, label: "R") }
                    if let c = levels.caseLevel { BatteryRing(percent: c, label: "C") }
                    if let single = levels.single, levels.left == nil { BatteryRing(percent: single, label: "") }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .onAppear { bounce += 1 }
    }
}

private struct TrackPeek: View {
    @ObservedObject private var player = NowPlayingStore.shared

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(image: player.artwork, bundleID: player.track?.bundleID ?? "", size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.track?.title ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(player.track?.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            EqualizerBars(playing: player.track?.isPlaying == true)
                .frame(width: 18, height: 14)
        }
    }
}

private struct FilePeek: View {
    let url: URL
    let title: String
    let symbol: String
    let thumbnail: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if thumbnail, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .onDrag { NSItemProvider(object: url as NSURL) }
            VStack(alignment: .leading, spacing: 2) {
                Label(L(title), systemImage: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                IconButton(symbol: "tray.and.arrow.down", help: "Keep on the shelf") {
                    ShelfStore.shared.add([url])
                    IslandController.shared.dismissPeek()
                }
                IconButton(symbol: "folder", help: "Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    IslandController.shared.dismissPeek()
                }
                Button(L("Open")) {
                    NSWorkspace.shared.open(url)
                    IslandController.shared.dismissPeek()
                }
                .buttonStyle(AccentButtonStyle())
            }
        }
    }
}

private struct MeetingPeek: View {
    let title: String
    let start: Date
    let link: URL?

    var body: some View {
        PeekRow(symbol: "video.fill", tint: Theme.accent, title: title, subtitle: subtitle) {
            HStack(spacing: 8) {
                Button(L("Dismiss")) { IslandController.shared.dismissPeek() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
                if let link {
                    Button(L("Join")) {
                        NSWorkspace.shared.open(link)
                        IslandController.shared.dismissPeek()
                    }
                    .buttonStyle(AccentButtonStyle())
                }
            }
        }
    }

    private var subtitle: String {
        let minutes = max(0, Int(start.timeIntervalSinceNow / 60))
        let time = start.formatted(date: .omitted, time: .shortened)
        return minutes <= 0 ? "Starting now · \(time)" : "In \(minutes) min · \(time)"
    }
}

/// The update pop-up: made to be noticed (pulsing icon, clear one-click action).
private struct UpdatePeekRow: View {
    let version: String
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.accent))
                .overlay(Circle().stroke(Theme.accent.opacity(0.5), lineWidth: 2).scaleEffect(pulse ? 1.35 : 1).opacity(pulse ? 0 : 1))
                .symbolEffect(.bounce, value: pulse)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Nook") + " \(version) " + L("is ready") + " ✨").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(L("New features and fixes · one click")).font(.system(size: 11)).foregroundStyle(Color.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(L("Later")) { IslandController.shared.dismissPeek() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)
            Button(L("Update now")) {
                IslandController.shared.dismissPeek()
                Updater.shared.install()
            }
            .buttonStyle(AccentButtonStyle())
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
