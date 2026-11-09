import SwiftUI

/// Lays the dock out at its normal size, then scales it to the user's chosen dock size.
struct DockRootView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        GeometryReader { geo in
            let scale = DockController.scale
            DockContentView()
                .frame(width: geo.size.width / scale, height: geo.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .id(settings.lookKey)
        .environment(\.locale, Localization.locale)
        // The glass stays outside the scaled content so the blur keeps its real size.
        .nookGlass(RoundedRectangle(cornerRadius: Theme.panelRadius * DockController.scale, style: .continuous))
        .overlay(NightDimOverlay().clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius * DockController.scale, style: .continuous)))
    }
}

struct DockContentView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var care = CareReminders.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    if let kind = care.active {
                        ReminderBanner(kind: kind)
                    }
                    ForEach(settings.visibleWidgets) { kind in
                        WidgetHost(kind: kind)
                    }
                    if settings.visibleWidgets.isEmpty {
                        Text(L("All widgets are hidden. Turn them on in Settings."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .animation(.easeOut(duration: 0.2), value: care.active)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(AppInfo.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Circle()
                .fill(Theme.accent)
                .frame(width: 5, height: 5)
            Spacer()
            IconButton(symbol: settings.pinned ? "pin.fill" : "pin",
                       help: settings.pinned ? "Unpin (auto-hide)" : "Pin (keep visible)") {
                settings.pinned.toggle()
            }
            IconButton(symbol: "slider.horizontal.3", help: "Settings") {
                SettingsWindowController.shared.show()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

struct WidgetHost: View {
    let kind: WidgetKind

    var body: some View {
        switch kind {
        case .clock: ClockWidget()
        case .nowPlaying: NowPlayingWidget()
        case .stats: SystemStatsWidget()
        case .shortcuts: ShortcutsWidget()
        case .shelf: FileShelfWidget()
        case .downloads: DownloadsWidget()
        case .todo: TodoWidget()
        case .care: CareWidget()
        }
    }
}
