import Foundation
import SwiftUI
import AppKit

/// Hijri date, Ramadan (sehri and iftar countdowns and reminders) and the prayer sound.
enum Hijri {
    /// The Islamic (Umm al-Qura) calendar, moved by the user's adjustment (moon sighting differs by country).
    static func components(for date: Date = Date(), adjust: Int = UserLibrary.shared.hijriAdjust) -> DateComponents {
        let cal = Calendar(identifier: .islamicUmmAlQura)
        let shifted = date.addingTimeInterval(Double(adjust) * 86400)
        return cal.dateComponents([.day, .month, .year], from: shifted)
    }

    static let monthsEnglish = ["Muharram", "Safar", "Rabi al-Awwal", "Rabi al-Thani", "Jumada al-Awwal", "Jumada al-Thani",
                                "Rajab", "Shaban", "Ramadan", "Shawwal", "Dhu al-Qadah", "Dhu al-Hijjah"]
    static let monthsBangla = ["মুহাররম", "সফর", "রবিউল আউয়াল", "রবিউস সানি", "জমাদিউল আউয়াল", "জমাদিউস সানি",
                               "রজব", "শাবান", "রমজান", "শাওয়াল", "জিলকদ", "জিলহজ"]

    /// "15 Ramadan 1448" / "১৫ রমজান ১৪৪৮"
    static func text(for date: Date = Date(), adjust: Int = UserLibrary.shared.hijriAdjust, bangla: Bool = Localization.isBangla) -> String {
        let c = components(for: date, adjust: adjust)
        guard let day = c.day, let month = c.month, let year = c.year, (1...12).contains(month) else { return "" }
        if bangla {
            return "\(digits(day)) \(monthsBangla[month - 1]) \(digits(year))"
        }
        return "\(day) \(monthsEnglish[month - 1]) \(year)"
    }

    static func digits(_ n: Int) -> String {
        let bn = Array("০১২৩৪৫৬৭৮৯")
        return String(String(n).map { $0.isNumber ? bn[Int(String($0))!] : $0 })
    }

    static func isRamadan(_ date: Date = Date(), adjust: Int = UserLibrary.shared.hijriAdjust) -> Bool {
        components(for: date, adjust: adjust).month == 9
    }

    /// Ramadan mode is on: always, never, or (auto) during the month of Ramadan.
    static var ramadanActive: Bool {
        switch UserLibrary.shared.ramadanMode {
        case "on": return true
        case "off": return false
        default: return isRamadan()
        }
    }
}

enum Ramadan {
    /// The next sehri end (Fajr) and iftar (Maghrib) after `now`, for the user's city.
    static func next(after now: Date = Date()) -> (sehriEnds: Date, iftar: Date)? {
        guard let place = WeatherStore.shared.place else { return nil }
        let library = UserLibrary.shared
        func times(_ day: Date) -> PrayerTimes.Times? {
            PrayerTimes.compute(for: day, latitude: place.latitude, longitude: place.longitude,
                                timeZone: place.timeZone, method: library.prayerMethod, hanafi: library.prayerHanafi)
        }
        guard let today = times(now), let tomorrow = times(now.addingTimeInterval(86400)) else { return nil }
        let sehri = today.fajr > now ? today.fajr : tomorrow.fajr
        let iftar = today.maghrib > now ? today.maghrib : tomorrow.maghrib
        return (sehri, iftar)
    }

    /// "2 h 15 m" / "২ ঘ ১৫ মি"
    static func countdown(to date: Date, from now: Date = Date()) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let h = minutes / 60, m = minutes % 60
        if Localization.isBangla {
            return h > 0 ? "\(Hijri.digits(h)) ঘ \(Hijri.digits(m)) মি" : "\(Hijri.digits(m)) মি"
        }
        return h > 0 ? "\(h) h \(m) m" : "\(m) m"
    }

    // MARK: Sound

    static let systemSounds = ["Glass", "Hero", "Ping", "Purr", "Submarine", "Funk", "Bottle", "Tink"]
    private static var player: NSSound?

    /// Plays the sound chosen in Settings: a macOS sound, the user's own file (e.g. an adhan), or nothing.
    static func playPrayerSound() {
        let choice = UserLibrary.shared.prayerSound
        guard choice != "off" else { return }
        player?.stop()
        if choice.hasPrefix("/") {
            player = NSSound(contentsOf: URL(fileURLWithPath: choice), byReference: true)
        } else {
            player = NSSound(named: choice)
        }
        player?.play()
    }

    static func stopSound() { player?.stop() }

    static func pickSoundFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { UserLibrary.shared.prayerSound = url.path }
    }
}

// MARK: Home widget

struct RamadanTile: View {
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var weather = WeatherStore.shared

    var body: some View {
        WidgetTile {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        SectionLabel(Hijri.ramadanActive ? "Ramadan" : "Hijri date")
                        Spacer(minLength: 2)
                        Image(systemName: "moon.stars.fill").font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                    Text(Hijri.text(for: context.date))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if Hijri.ramadanActive {
                        if let next = Ramadan.next(after: context.date) {
                            let iftarFirst = next.iftar < next.sehriEnds
                            let target = iftarFirst ? next.iftar : next.sehriEnds
                            Spacer(minLength: 0)
                            Text(L(iftarFirst ? "Iftar in" : "Sehri ends in"))
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(Color.secondary)
                            Text(Ramadan.countdown(to: target, from: context.date))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(L(iftarFirst ? "Iftar" : "Sehri") + " " + target.formatted(.dateTime.hour().minute().locale(Localization.locale)))
                                .font(.system(size: 10)).foregroundStyle(Color.secondary).lineLimit(1)
                        } else {
                            Spacer(minLength: 0)
                            Button(L("Set your city")) { SettingsWindowController.shared.show(tab: .general) }
                                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                        }
                    } else {
                        Spacer(minLength: 0)
                        Text(Hijri.text(for: context.date, bangla: !Localization.isBangla))
                            .font(.system(size: 10)).foregroundStyle(Color.secondary).lineLimit(1)
                    }
                }
            }
        }
        .contextMenu {
            MenuButton("Settings…") { SettingsWindowController.shared.show(tab: .ramadan) }
        }
    }
}
