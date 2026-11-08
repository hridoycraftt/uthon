import SwiftUI
import AppKit

// MARK: - Small types used by settings

/// A named group of apps shown as one tile on Home.
struct AppFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var paths: [String]

    var urls: [URL] { paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) } }
}

/// Color themes. "custom" uses the color the user picked.
enum ThemeColor: String, CaseIterable, Identifiable {
    case terracotta, ocean, forest, lavender, rose, sunset, graphite, mint, gold, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terracotta: return "Terracotta"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .lavender: return "Lavender"
        case .rose: return "Rose"
        case .sunset: return "Sunset"
        case .graphite: return "Graphite"
        case .mint: return "Mint"
        case .gold: return "Gold"
        case .custom: return "Custom"
        }
    }

    var color: Color {
        switch self {
        case .terracotta: return Color(red: 0.89, green: 0.48, blue: 0.36)
        case .ocean: return Color(red: 0.20, green: 0.52, blue: 0.95)
        case .forest: return Color(red: 0.22, green: 0.66, blue: 0.42)
        case .lavender: return Color(red: 0.58, green: 0.45, blue: 0.92)
        case .rose: return Color(red: 0.93, green: 0.36, blue: 0.55)
        case .sunset: return Color(red: 0.98, green: 0.55, blue: 0.16)
        case .graphite: return Color(red: 0.45, green: 0.47, blue: 0.52)
        case .mint: return Color(red: 0.20, green: 0.74, blue: 0.70)
        case .gold: return Color(red: 0.86, green: 0.66, blue: 0.18)
        case .custom: return Color(hex: AppSettings.shared.customAccentHex) ?? Color(red: 0.89, green: 0.48, blue: 0.36)
        }
    }

    /// Presets usable as per-widget colors (custom excluded).
    static var widgetChoices: [ThemeColor] { allCases.filter { $0 != .custom } }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, bangla
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .bangla: return "বাংলা"
        }
    }
}

/// What a sideways swipe on Home does.
enum HomeSwipe: String, CaseIterable, Identifiable {
    case pages, songs
    var id: String { rawValue }
    var title: String { self == .pages ? "Change page" : "Change song" }
}

extension Color {
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .orange
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

// MARK: - Home layout (pages, sizes, colors)

extension AppSettings {
    /// A key that changes whenever the look changes, used to refresh every view at once.
    var lookKey: String { "\(themeColor.rawValue)-\(customAccentHex)-\(language.rawValue)-\(tintGlass)" }

    var pageCount: Int { max(1, homePages.count) }

    func page(_ index: Int) -> [String] {
        homePages.indices.contains(index) ? homePages[index] : []
    }

    func slots(of item: HomeItem) -> Int {
        let chosen = widgetSizes[item.rawValue] ?? item.defaultSlots
        return min(3, max(item.minSlots, chosen))
    }

    /// Items on a page, in order, trimmed to what fits in 5 slots.
    func homeItems(page index: Int) -> [HomeItem] {
        var used = 0
        var result: [HomeItem] = []
        for raw in page(index) {
            guard let item = HomeItem(rawValue: raw) else { continue }
            let width = slots(of: item)
            guard used + width <= HomeWidget.maxSlots else { continue }
            used += width
            result.append(item)
        }
        return result
    }

    func slotsUsed(page index: Int) -> Int {
        homeItems(page: index).reduce(0) { $0 + slots(of: $1) }
    }

    func isOnHome(_ item: HomeItem) -> Bool {
        homePages.contains { $0.contains(item.rawValue) }
    }

    func pageOf(_ item: HomeItem) -> Int? {
        homePages.firstIndex { $0.contains(item.rawValue) }
    }

    func canAdd(_ item: HomeItem, page index: Int) -> Bool {
        !isOnHome(item) && slotsUsed(page: index) + slots(of: item) <= HomeWidget.maxSlots
    }

    @discardableResult
    func addToHome(_ item: HomeItem, page index: Int) -> Bool {
        guard canAdd(item, page: index) else { return false }
        var pages = homePages
        while pages.count <= index { pages.append([]) }
        pages[index].append(item.rawValue)
        homePages = pages
        return true
    }

    func removeFromHome(_ item: HomeItem) {
        homePages = homePages.map { $0.filter { $0 != item.rawValue } }
    }

    /// Drag-and-drop: put `item` where `target` is (same page).
    func placeHomeItem(_ item: HomeItem, at target: HomeItem) {
        homePages = homePages.map { page in
            var p = page
            AppSettings.place(&p, item.rawValue, at: target.rawValue)
            return p
        }
    }

    func moveHomeItem(_ item: HomeItem, by offset: Int) {
        homePages = homePages.map { page in
            var p = page
            AppSettings.move(&p, item.rawValue, by: offset)
            return p
        }
    }

    /// Change a widget's size if it still fits on its page.
    @discardableResult
    func setSize(_ item: HomeItem, slots newSize: Int) -> Bool {
        let size = min(3, max(item.minSlots, newSize))
        if let index = pageOf(item) {
            let others = homeItems(page: index).filter { $0 != item }.reduce(0) { $0 + slots(of: $1) }
            guard others + size <= HomeWidget.maxSlots else { return false }
        }
        widgetSizes[item.rawValue] = size
        return true
    }

    func setPageCount(_ count: Int) {
        let n = min(HomeWidget.maxPages, max(1, count))
        var pages = homePages
        while pages.count < n { pages.append([]) }
        if pages.count > n {
            // Move what we can from removed pages onto the remaining ones.
            let extra = pages[n...].flatMap { $0 }
            pages = Array(pages[..<n])
            homePages = pages
            for raw in extra {
                guard let item = HomeItem(rawValue: raw) else { continue }
                for index in 0..<n where addToHome(item, page: index) { break }
            }
            return
        }
        homePages = pages
    }

    func color(of item: HomeItem) -> ThemeColor? {
        widgetColors[item.rawValue].flatMap(ThemeColor.init(rawValue:))
    }

    func setColor(_ color: ThemeColor?, for item: HomeItem) {
        widgetColors[item.rawValue] = color?.rawValue
    }

    @discardableResult
    func addHomeApp(_ url: URL, page index: Int) -> Bool {
        addToHome(HomeItem(app: url), page: index)
    }

    @discardableResult
    func createFolder(name: String, apps: [URL], page index: Int) -> AppFolder {
        let folder = AppFolder(name: name.isEmpty ? "Folder" : name, paths: apps.map(\.path))
        appFolders.append(folder)
        addToHome(HomeItem(folder: folder), page: index)
        return folder
    }

    func deleteFolder(_ folder: AppFolder) {
        removeFromHome(HomeItem(folder: folder))
        appFolders.removeAll { $0.id == folder.id }
    }
}
