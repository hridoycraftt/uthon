import Foundation
import SwiftUI

struct Bookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var url: String

    var link: URL? {
        let text = url.trimmingCharacters(in: .whitespaces)
        if let u = URL(string: text), u.scheme != nil { return u }
        return URL(string: "https://" + text)
    }
}

struct SpecialDay: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var date: Date
    var yearly = true
    var symbol = "gift.fill"

    /// The next time this day comes around (today counts).
    func next(after now: Date = Date()) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard yearly else { return cal.startOfDay(for: date) }
        var comps = cal.dateComponents([.month, .day], from: date)
        comps.year = cal.component(.year, from: now)
        if let thisYear = cal.date(from: comps), thisYear >= today { return thisYear }
        comps.year = (comps.year ?? 0) + 1
        return cal.date(from: comps) ?? date
    }

    func daysLeft(from now: Date = Date()) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: next(after: now)).day ?? 0
    }
}

enum PrayerMethod: String, CaseIterable, Identifiable, Codable {
    case karachi, mwl, isna, egypt, makkah
    var id: String { rawValue }

    var title: String {
        switch self {
        case .karachi: return "Karachi (Bangladesh, Pakistan, India)"
        case .mwl: return "Muslim World League"
        case .isna: return "ISNA (North America)"
        case .egypt: return "Egypt"
        case .makkah: return "Umm al-Qura (Makkah)"
        }
    }

    /// Sun angles below the horizon for Fajr and Isha (Makkah uses 90 min after Maghrib for Isha).
    var angles: (fajr: Double, isha: Double) {
        switch self {
        case .karachi: return (18, 18)
        case .mwl: return (18, 17)
        case .isna: return (15, 15)
        case .egypt: return (19.5, 17.5)
        case .makkah: return (18.5, 0)
        }
    }
}

/// A saved layout: Home pages, controls, tabs and theme. Built-in presets plus your own.
struct LayoutProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var homePages: [[String]]
    var controls: [String]
    var tabs: [String]
    var hiddenTabs: [String]
    var theme: String
    var builtIn = false
}

enum WallpaperSource: String, CaseIterable, Identifiable {
    case off, gradients, folder
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .gradients: return "Uthon gradients"
        case .folder: return "My folder"
        }
    }
}

/// User content and options for the newer features. Saved in UserDefaults.
final class UserLibrary: ObservableObject {
    static let shared = UserLibrary()
    private let d = UserDefaults.standard

    @Published var bookmarks: [Bookmark] { didSet { Persist.save(bookmarks, key: "bookmarks") } }
    @Published var worldClocks: [String] { didSet { d.set(worldClocks, forKey: "worldClocks") } }
    @Published var specialDays: [SpecialDay] { didSet { Persist.save(specialDays, key: "specialDays") } }
    @Published var specialDayAlerts: Bool { didSet { d.set(specialDayAlerts, forKey: "specialDayAlerts") } }
    @Published var prayerMethod: PrayerMethod { didSet { d.set(prayerMethod.rawValue, forKey: "prayerMethod") } }
    @Published var prayerHanafi: Bool { didSet { d.set(prayerHanafi, forKey: "prayerHanafi") } }
    @Published var prayerAlerts: Bool { didSet { d.set(prayerAlerts, forKey: "prayerAlerts") } }
    @Published var clipboardImages: Bool { didSet { d.set(clipboardImages, forKey: "clipboardImages") } }
    @Published var clipboardLimit: Int { didSet { d.set(clipboardLimit, forKey: "clipboardLimit") } }
    @Published var pinnedClips: [String] { didSet { d.set(pinnedClips, forKey: "pinnedClips") } }
    @Published var autoCheckUpdates: Bool { didSet { d.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }
    @Published var wallpaperSource: WallpaperSource { didSet { d.set(wallpaperSource.rawValue, forKey: "wallpaperSource") } }
    @Published var wallpaperFolder: String { didSet { d.set(wallpaperFolder, forKey: "wallpaperFolder") } }
    @Published var wallpaperDaily: Bool { didSet { d.set(wallpaperDaily, forKey: "wallpaperDaily") } }
    @Published var profiles: [LayoutProfile] { didSet { Persist.save(profiles, key: "profiles") } }
    @Published var activeProfile: UUID? { didSet { d.set(activeProfile?.uuidString, forKey: "activeProfile") } }

    private init() {
        bookmarks = Persist.load([Bookmark].self, key: "bookmarks") ?? [
            Bookmark(title: "YouTube", url: "https://youtube.com"),
            Bookmark(title: "Gmail", url: "https://mail.google.com"),
            Bookmark(title: "Prothom Alo", url: "https://prothomalo.com"),
            Bookmark(title: "Wikipedia", url: "https://wikipedia.org"),
        ]
        worldClocks = d.stringArray(forKey: "worldClocks") ?? ["Asia/Dhaka", "Europe/London", "America/New_York"]
        specialDays = Persist.load([SpecialDay].self, key: "specialDays") ?? []
        specialDayAlerts = d.object(forKey: "specialDayAlerts") as? Bool ?? true
        prayerMethod = PrayerMethod(rawValue: d.string(forKey: "prayerMethod") ?? "") ?? .karachi
        prayerHanafi = d.object(forKey: "prayerHanafi") as? Bool ?? true
        prayerAlerts = d.object(forKey: "prayerAlerts") as? Bool ?? false
        clipboardImages = d.object(forKey: "clipboardImages") as? Bool ?? true
        clipboardLimit = d.object(forKey: "clipboardLimit") as? Int ?? 25
        pinnedClips = d.stringArray(forKey: "pinnedClips") ?? []
        autoCheckUpdates = d.object(forKey: "autoCheckUpdates") as? Bool ?? true
        wallpaperSource = WallpaperSource(rawValue: d.string(forKey: "wallpaperSource") ?? "") ?? .off
        wallpaperFolder = d.string(forKey: "wallpaperFolder") ?? ""
        wallpaperDaily = d.object(forKey: "wallpaperDaily") as? Bool ?? true
        profiles = Persist.load([LayoutProfile].self, key: "profiles") ?? []
        activeProfile = d.string(forKey: "activeProfile").flatMap(UUID.init(uuidString:))
    }
}
