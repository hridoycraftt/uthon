import Foundation
import AppKit
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
        case .gradients: return "Nook gradients"
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
    /// Apps in the Home "Shortcuts" widget, in order (separate from the side dock's shortcuts).
    @Published var homeShortcuts: [String] { didSet { d.set(homeShortcuts, forKey: "homeShortcuts") } }
    @Published var activeProfile: UUID? { didSet { d.set(activeProfile?.uuidString, forKey: "activeProfile") } }

    // Daily Quran & Hadith
    @Published var verseEnabled: Bool { didSet { d.set(verseEnabled, forKey: "verseEnabled") } }
    @Published var verseSource: VerseSource { didSet { d.set(verseSource.rawValue, forKey: "verseSource") } }
    @Published var verseTranslation: VerseTranslation { didSet { d.set(verseTranslation.rawValue, forKey: "verseTranslation") } }
    @Published var verseShowArabic: Bool { didSet { d.set(verseShowArabic, forKey: "verseShowArabic") } }
    // Internet & Wi-Fi
    @Published var networkEnabled: Bool { didSet { d.set(networkEnabled, forKey: "networkEnabled") } }
    @Published var networkPeeks: Bool { didSet { d.set(networkPeeks, forKey: "networkPeeks") } }
    @Published var speedTestMB: Int { didSet { d.set(speedTestMB, forKey: "speedTestMB") } }
    // Notifications on the island
    @Published var notificationsEnabled: Bool { didSet { d.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    @Published var notificationHideContent: Bool { didSet { d.set(notificationHideContent, forKey: "notificationHideContent") } }
    /// How long a notification stays on the island, 0.5 to 10 seconds.
    @Published var notificationSeconds: Double { didSet { d.set(notificationSeconds, forKey: "notificationDuration") } }
    @Published var notificationQuietWhenFocused: Bool { didSet { d.set(notificationQuietWhenFocused, forKey: "notificationQuietWhenFocused") } }
    @Published var mutedNotificationApps: [String] { didSet { d.set(mutedNotificationApps, forKey: "mutedNotificationApps") } }
    // Night dimming
    @Published var dimEnabled: Bool { didSet { d.set(dimEnabled, forKey: "dimEnabled") } }
    @Published var dimStrength: Double { didSet { d.set(dimStrength, forKey: "dimStrength") } }
    @Published var dimSchedule: DimSchedule { didSet { d.set(dimSchedule.rawValue, forKey: "dimSchedule") } }
    @Published var dimTarget: DimTarget { didSet { d.set(dimTarget.rawValue, forKey: "dimTarget") } }
    @Published var dimStartHour: Int { didSet { d.set(dimStartHour, forKey: "dimStartHour") } }
    @Published var dimEndHour: Int { didSet { d.set(dimEndHour, forKey: "dimEndHour") } }
    // Bottom dock
    @Published var bottomDockEnabled: Bool { didSet { d.set(bottomDockEnabled, forKey: "bottomDockEnabled") } }
    @Published var bottomDockItems: [String] { didSet { d.set(bottomDockItems, forKey: "bottomDockItems") } }
    @Published var bottomDockApps: [String] { didSet { d.set(bottomDockApps, forKey: "bottomDockApps") } }
    @Published var bottomDockSide: BottomDockSide { didSet { d.set(bottomDockSide.rawValue, forKey: "bottomDockSide") } }
    @Published var bottomDockScale: Double { didSet { d.set(bottomDockScale, forKey: "bottomDockScale") } }
    @Published var bottomDockOffset: Double { didSet { d.set(bottomDockOffset, forKey: "bottomDockOffset") } }
    @Published var bottomDockAutoHide: Bool { didSet { d.set(bottomDockAutoHide, forKey: "bottomDockAutoHide") } }
    @Published var bottomDockMatchDock: Bool { didSet { d.set(bottomDockMatchDock, forKey: "bottomDockMatchDock") } }

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
        homeShortcuts = d.stringArray(forKey: "homeShortcuts") ?? [
            "/System/Library/CoreServices/Finder.app", "/Applications/Safari.app",
            "/System/Applications/Notes.app", "/System/Applications/Calendar.app",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        verseEnabled = d.object(forKey: "verseEnabled") as? Bool ?? true
        verseSource = VerseSource(rawValue: d.string(forKey: "verseSource") ?? "") ?? .both
        verseTranslation = VerseTranslation(rawValue: d.string(forKey: "verseTranslation") ?? "") ?? .bangla
        verseShowArabic = d.object(forKey: "verseShowArabic") as? Bool ?? true
        networkEnabled = d.object(forKey: "networkEnabled") as? Bool ?? true
        networkPeeks = d.object(forKey: "networkPeeks") as? Bool ?? true
        speedTestMB = d.object(forKey: "speedTestMB") as? Int ?? 25
        notificationsEnabled = d.object(forKey: "notificationsEnabled") as? Bool ?? false
        notificationHideContent = d.object(forKey: "notificationHideContent") as? Bool ?? false
        notificationSeconds = min(max(d.object(forKey: "notificationDuration") as? Double
            ?? (d.object(forKey: "notificationSeconds") as? Int).map(Double.init) ?? 4, 0.5), 10)
        notificationQuietWhenFocused = d.object(forKey: "notificationQuietWhenFocused") as? Bool ?? true
        mutedNotificationApps = d.stringArray(forKey: "mutedNotificationApps") ?? []
        dimEnabled = d.object(forKey: "dimEnabled") as? Bool ?? false
        dimStrength = d.object(forKey: "dimStrength") as? Double ?? 0.3
        dimSchedule = DimSchedule(rawValue: d.string(forKey: "dimSchedule") ?? "") ?? .sun
        dimTarget = DimTarget(rawValue: d.string(forKey: "dimTarget") ?? "") ?? .uthon
        dimStartHour = d.object(forKey: "dimStartHour") as? Int ?? 21
        dimEndHour = d.object(forKey: "dimEndHour") as? Int ?? 6
        bottomDockEnabled = d.object(forKey: "bottomDockEnabled") as? Bool ?? false
        bottomDockItems = d.stringArray(forKey: "bottomDockItems") ?? ["apps", "clock", "music", "weather"]
        bottomDockApps = d.stringArray(forKey: "bottomDockApps") ?? [
            "/System/Library/CoreServices/Finder.app", "/Applications/Safari.app", "/System/Applications/Notes.app",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        bottomDockSide = BottomDockSide(rawValue: d.string(forKey: "bottomDockSide") ?? "") ?? .right
        bottomDockScale = d.object(forKey: "bottomDockScale") as? Double ?? 1.0
        bottomDockOffset = d.object(forKey: "bottomDockOffset") as? Double ?? 0
        bottomDockAutoHide = d.object(forKey: "bottomDockAutoHide") as? Bool ?? false
        bottomDockMatchDock = d.object(forKey: "bottomDockMatchDock") as? Bool ?? true
    }
}

extension UserLibrary {
    var bottomDockAppURLs: [URL] {
        bottomDockApps.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    func pickBottomDockApps() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("Add")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !bottomDockApps.contains(url.path) {
            bottomDockApps.append(url.path)
        }
    }

    func moveBottomDockApp(_ path: String, by offset: Int) {
        guard let i = bottomDockApps.firstIndex(of: path) else { return }
        let j = min(max(i + offset, 0), bottomDockApps.count - 1)
        guard i != j else { return }
        bottomDockApps.swapAt(i, j)
    }

    func isBottomDockItemOn(_ item: BottomDockItem) -> Bool { bottomDockItems.contains(item.rawValue) }

    func setBottomDockItem(_ item: BottomDockItem, _ on: Bool) {
        if on {
            guard !bottomDockItems.contains(item.rawValue) else { return }
            // Keep the standard order.
            let order = BottomDockItem.allCases.map(\.rawValue)
            bottomDockItems = (bottomDockItems + [item.rawValue]).sorted {
                (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0)
            }
        } else {
            bottomDockItems.removeAll { $0 == item.rawValue }
        }
    }
}

extension UserLibrary {
    var homeShortcutURLs: [URL] {
        homeShortcuts.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    func addHomeShortcuts(_ urls: [URL]) {
        var list = homeShortcuts
        for url in urls where !list.contains(url.path) { list.append(url.path) }
        homeShortcuts = list
    }

    func removeHomeShortcut(_ url: URL) {
        homeShortcuts.removeAll { $0 == url.path }
    }

    func moveHomeShortcut(_ path: String, by offset: Int) {
        var list = homeShortcuts
        AppSettings.move(&list, path, by: offset)
        homeShortcuts = list
    }

    /// Choose apps (or folders/files) for the Shortcuts widget.
    func pickHomeShortcuts() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("Add")
        panel.message = L("Choose apps for the Shortcuts widget")
        IslandController.shared.holdOpen = true
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        IslandController.shared.holdOpen = false
        if response == .OK { addHomeShortcuts(panel.urls) }
    }
}
