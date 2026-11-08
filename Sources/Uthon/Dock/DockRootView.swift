import SwiftUI

struct DockRootView: View {
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
                        Text("All widgets are hidden. Turn them on in Settings.")
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
        .background(LiquidGlass(shape: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)))
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
