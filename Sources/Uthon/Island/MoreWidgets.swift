import SwiftUI
import AppKit

// MARK: Bookmarks

struct BookmarksTile: View {
    @ObservedObject private var library = UserLibrary.shared

    var body: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Bookmarks")
                if library.bookmarks.isEmpty {
                    Spacer(minLength: 0)
                    Button(L("Add bookmarks")) { SettingsWindowController.shared.show(tab: .widgets) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                        ForEach(library.bookmarks.prefix(9)) { bookmark in
                            BookmarkButton(bookmark: bookmark)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct BookmarkButton: View {
    let bookmark: Bookmark
    @State private var hover = false

    var body: some View {
        Button {
            if let link = bookmark.link { NSWorkspace.shared.open(link) }
            IslandController.shared.collapse()
        } label: {
            VStack(spacing: 3) {
                Text(String(bookmark.title.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Self.color(for: bookmark.title)))
                    .scaleEffect(hover ? 1.08 : 1)
                Text(bookmark.title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hover = h } }
        .help(bookmark.url)
    }

    static func color(for text: String) -> Color {
        let palette = ThemeColor.widgetChoices.map(\.color)
        let sum = text.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

// MARK: World clock

struct WorldClockTile: View {
    @ObservedObject private var library = UserLibrary.shared

    var body: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("World Clock")
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(library.worldClocks.prefix(4), id: \.self) { identifier in
                            if let zone = TimeZone(identifier: identifier) {
                                ClockRow(zone: zone, now: context.date)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ClockRow: View {
    let zone: TimeZone
    let now: Date

    var body: some View {
        var cal = Calendar.current
        cal.timeZone = zone
        let hour = cal.component(.hour, from: now)
        let isDay = (6..<18).contains(hour)
        return HStack(spacing: 6) {
            Image(systemName: isDay ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 9))
                .foregroundStyle(isDay ? Color.orange : Color.indigo)
            Text(WorldClockTile.cityName(zone))
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(Self.time(now, zone))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }

    static func time(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

extension WorldClockTile {
    static func cityName(_ zone: TimeZone) -> String {
        zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
    }
}

// MARK: Prayer times

struct PrayerTile: View {
    @ObservedObject private var weather = WeatherStore.shared
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Prayer Times")
                if let place = weather.place {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        content(place: place, now: context.date)
                    }
                } else {
                    Spacer(minLength: 0)
                    Text(L("Set your city in Settings to see prayer times"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                    Button(L("Set your city")) { SettingsWindowController.shared.show(tab: .general) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func content(place: WeatherStore.Place, now: Date) -> some View {
        let times = PrayerTimes.compute(for: now, latitude: place.latitude, longitude: place.longitude,
                                        timeZone: place.timeZone, method: library.prayerMethod, hanafi: library.prayerHanafi)
        let tomorrow = PrayerTimes.compute(for: now.addingTimeInterval(86400), latitude: place.latitude, longitude: place.longitude,
                                           timeZone: place.timeZone, method: library.prayerMethod, hanafi: library.prayerHanafi)
        if let times {
            let next = times.next(after: now) ?? tomorrow.map { (name: "Fajr", time: $0.fajr) }
            if let next {
                Text(L(next.name))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text(Self.clock(next.time, place.timeZone))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(Self.countdown(to: next.time, from: now))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            if settings.slots(of: HomeItem(.prayer)) > 1 {
                HStack(spacing: 8) {
                    ForEach(times.prayers, id: \.name) { prayer in
                        VStack(spacing: 1) {
                            Text(L(prayer.name)).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.secondary)
                            Text(Self.clock(prayer.time, place.timeZone)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        }
                    }
                }
            } else {
                Text(place.city).font(.system(size: 10)).foregroundStyle(Color.secondary).lineLimit(1)
            }
        }
    }

    static func clock(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    static func countdown(to date: Date, from now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes >= 60 { return L("in") + " \(minutes / 60)h \(minutes % 60)m" }
        return L("in") + " \(minutes) min"
    }
}

// MARK: Special days

struct CountdownTile: View {
    @ObservedObject private var library = UserLibrary.shared

    var body: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Special Days")
                let upcoming = library.specialDays.sorted { $0.daysLeft() < $1.daysLeft() }
                if upcoming.isEmpty {
                    Spacer(minLength: 0)
                    Image(systemName: "gift.fill").font(.system(size: 20)).foregroundStyle(Theme.accent)
                    Button(L("Add birthdays and special days")) { SettingsWindowController.shared.show(tab: .widgets) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                } else if let first = upcoming.first {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(first.daysLeft() == 0 ? "🎉" : "\(first.daysLeft())")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                        Text(first.daysLeft() == 0 ? L("Today!") : L("days"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                    }
                    Text(first.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    ForEach(upcoming.dropFirst().prefix(2)) { day in
                        HStack {
                            Text(L(day.name)).font(.system(size: 10)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(day.daysLeft())d").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        }
                        .foregroundStyle(Color.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: App folders

struct FolderTile: View {
    let folder: AppFolder
    @State private var hover = false

    var body: some View {
        Button {
            withAnimation(IslandModel.spring) { IslandModel.shared.openFolder = folder.id }
        } label: {
            WidgetTile {
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    LazyVGrid(columns: [GridItem(.fixed(24), spacing: 4), GridItem(.fixed(24), spacing: 4)], spacing: 4) {
                        ForEach(folder.urls.prefix(4), id: \.self) { url in
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.08)))
                    .scaleEffect(hover ? 1.05 : 1)
                    Text(folder.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hover = h } }
    }
}

/// An open folder: all its apps, shown in place of the Home widgets.
struct FolderGrid: View {
    let folder: AppFolder
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(IslandModel.spring) { IslandModel.shared.openFolder = nil }
                } label: {
                    Label(L("Back"), systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                Text(folder.name).font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(folder.urls.count) " + L("apps")).font(.system(size: 11)).foregroundStyle(Color.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(folder.urls, id: \.self) { url in
                        Button {
                            NSWorkspace.shared.open(url)
                            IslandController.shared.collapse()
                        } label: {
                            VStack(spacing: 5) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 52, height: 52)
                                Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .frame(width: 76)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(12)
        .glassChip(radius: 20)
    }
}
