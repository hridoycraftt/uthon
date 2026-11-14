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
    @State private var headerHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { headerHeight = g.size.height; report() }
                        .onChange(of: g.size.height) { _, h in headerHeight = h; report() }
                })
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    if let kind = care.active {
                        ReminderBanner(kind: kind)
                    }
                    ForEach(settings.visibleWidgets) { kind in
                        WidgetHost(kind: kind)
                    }
                    if settings.visibleWidgets.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .animation(.easeOut(duration: 0.2), value: care.active)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { listHeight = g.size.height; report() }
                        .onChange(of: g.size.height) { _, h in listHeight = h; report() }
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }

    /// Tells the window how tall the dock wants to be (it fits its widgets).
    private func report() {
        DockController.shared.setContentHeight(headerHeight + listHeight)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.dashed")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.secondary)
            Text(L("No widgets yet"))
                .font(.system(size: 13, weight: .semibold))
            Button(L("Choose widgets…")) { SettingsWindowController.shared.show(tab: .dock) }
                .buttonStyle(AccentButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// Today's date on the left (as in Notification Center), the controls on the right.
    private var header: some View {
        HStack(spacing: 4) {
            TimelineView(.everyMinute) { context in
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Localization.locale)))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            IconButton(symbol: settings.pinned ? "pin.fill" : "pin",
                       help: settings.pinned ? "Unpin (auto-hide)" : "Pin (keep visible)", size: 12) {
                settings.pinned.toggle()
            }
            IconButton(symbol: "gearshape", help: "Settings", size: 12) {
                SettingsWindowController.shared.show(tab: .dock)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
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
