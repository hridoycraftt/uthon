import SwiftUI

/// Ready-made Home layouts (just the Home pages; theme and tabs stay as they are).
struct HomePreset: Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let summary: String
    let pages: [[HomeWidget]]

    static let all: [HomePreset] = [
        HomePreset(id: "essentials", name: "Essentials", symbol: "star.fill",
                   summary: "Music, today, weather and your apps",
                   pages: [[.music, .calendar, .weather, .shortcuts]]),
        HomePreset(id: "work", name: "Work", symbol: "briefcase.fill",
                   summary: "Calendar, to-dos, system and quick links",
                   pages: [[.calendar, .todo, .weather, .system, .controls], [.bookmarks, .worldClock, .notes, .batteries]]),
        HomePreset(id: "music", name: "Music", symbol: "music.note",
                   summary: "Big player with quick controls",
                   pages: [[.music, .weather, .controls, .shortcuts]]),
        HomePreset(id: "study", name: "Study", symbol: "book.fill",
                   summary: "To-dos, notes, calendar and countdowns",
                   pages: [[.todo, .notes, .calendar, .countdown, .controls]]),
        HomePreset(id: "family", name: "Family", symbol: "house.fill",
                   summary: "Music, family days, prayer and clocks",
                   pages: [[.music, .calendar, .countdown, .prayer], [.weather, .worldClock, .bookmarks, .todo, .notes]]),
        HomePreset(id: "day", name: "Prayer & Day", symbol: "moon.stars.fill",
                   summary: "Prayer times, calendar, weather and clocks",
                   pages: [[.prayer, .calendar, .weather, .worldClock, .countdown]]),
        HomePreset(id: "monitor", name: "Mac Monitor", symbol: "gauge.with.dots.needle.67percent",
                   summary: "CPU, memory, batteries and controls",
                   pages: [[.system, .batteries, .controls, .weather, .calendar]]),
        HomePreset(id: "minimal", name: "Minimal", symbol: "circle.dashed",
                   summary: "Just the date and the weather",
                   pages: [[.calendar, .weather]]),
    ]

    var rawPages: [[String]] { pages.map { $0.map(\.rawValue) } }

    var isActive: Bool { AppSettings.shared.homePages == rawPages }

    /// Apply this layout to Home (can be undone from the island).
    func apply() {
        let settings = AppSettings.shared
        IslandModel.shared.registerUndo(L("Applied") + " " + L(name))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            for page in pages { for widget in page { settings.widgetSizes[widget.rawValue] = nil } }
            settings.homePages = rawPages
            IslandModel.shared.homePage = 0
        }
    }
}

/// A preset card: name, description and the widget icons it contains.
struct PresetCard: View {
    let preset: HomePreset
    @ObservedObject private var settings = AppSettings.shared
    @State private var hover = false

    var body: some View {
        let active = preset.isActive
        Button {
            preset.apply()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: preset.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.accent))
                    Text(L(preset.name))
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if active {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    }
                }
                Text(L(preset.summary))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                ForEach(Array(preset.pages.enumerated()), id: \.offset) { _, page in
                    HStack(spacing: 4) {
                        ForEach(page) { widget in
                            Image(systemName: widget.symbol)
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: widget == .music ? 34 : 18, height: 16)
                                .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Theme.accent.opacity(0.18)))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(active ? 0.12 : (hover ? 0.08 : 0.04)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(active ? Theme.accent.opacity(0.8) : Color.clear, lineWidth: 1.2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(L("Use this layout (you can undo)"))
    }
}
