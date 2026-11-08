import Foundation
import AppKit
import Combine

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// How the open island looks. "Automatic" uses the material that matches your macOS
/// (Liquid Glass on macOS 26, native frosted material on macOS 14/15).
enum IslandStyle: String, CaseIterable, Identifiable {
    case automatic, black
    var id: String { rawValue }
    var title: String { self == .automatic ? "Automatic" : "Black" }
}

/// Glass material. "Automatic" picks what macOS itself uses on this version.
enum GlassClarity: String, CaseIterable, Identifiable {
    case automatic, clear, frosted
    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .clear: return "Clear"
        case .frosted: return "Frosted"
        }
    }
}

/// Something the user can add, remove and reorder in an editable island row.
protocol CustomizableItem: RawRepresentable, CaseIterable, Identifiable, Hashable where RawValue == String {
    var title: String { get }
    var symbol: String { get }
    var slots: Int { get }
}

/// Widgets that can be placed on the island's Home tab.
enum HomeWidget: String, CaseIterable, Identifiable, CustomizableItem {
    case music, calendar, weather, shortcuts, system, batteries, todo, controls, notes

    var id: String { rawValue }

    /// Width in slots; the Home row holds 5 slots.
    var slots: Int { self == .music ? 2 : 1 }

    var title: String {
        switch self {
        case .music: return "Music"
        case .calendar: return "Calendar"
        case .weather: return "Weather"
        case .shortcuts: return "Shortcuts"
        case .system: return "System"
        case .batteries: return "Batteries"
        case .todo: return "To-do"
        case .controls: return "Quick Controls"
        case .notes: return "Note"
        }
    }

    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .weather: return "cloud.sun.fill"
        case .shortcuts: return "square.grid.2x2.fill"
        case .system: return "cpu"
        case .batteries: return "battery.75percent"
        case .todo: return "checklist"
        case .controls: return "switch.2"
        case .notes: return "note.text"
        }
    }

    static let maxSlots = 5
    static let defaults: [HomeWidget] = [.music, .calendar, .weather, .shortcuts]
}

enum DockEdge: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var title: String { self == .left ? "Left" : "Right" }
}

enum WidgetKind: String, CaseIterable, Identifiable {
    case clock, nowPlaying, stats, shortcuts, shelf, downloads, todo, care

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Today & Calendar"
        case .nowPlaying: return "Now Playing"
        case .stats: return "System"
        case .shortcuts: return "Shortcuts"
        case .shelf: return "File Shelf"
        case .downloads: return "Downloads"
        case .todo: return "To-do"
        case .care: return "Care Reminders"
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "calendar"
        case .nowPlaying: return "music.note"
        case .stats: return "cpu"
        case .shortcuts: return "square.grid.2x2"
        case .shelf: return "tray"
        case .downloads: return "arrow.down.circle"
        case .todo: return "checklist"
        case .care: return "heart"
        }
    }
}

/// All user preferences, saved in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let edge = "edge"
        static let pinned = "pinned"
        static let hidden = "hiddenWidgets"
        static let waterOn = "waterEnabled"
        static let waterMin = "waterMinutes"
        static let postureOn = "postureEnabled"
        static let postureMin = "postureMinutes"
        static let island = "islandEnabled"
        static let islandStyle = "islandLook"
        static let sideDock = "sideDockEnabled"
        static let appearance = "appearance"
        static let glassClarity = "glassMaterial"
        static let peekTrack = "peekTrack"
        static let hud = "hudEnabled"
        static let replaceHUD = "replaceSystemHUD"
        static let peekHeadphones = "peekHeadphones"
        static let peekCharging = "peekCharging"
        static let peekCaps = "peekCapsLock"
        static let peekDownloads = "peekDownloads"
        static let peekMeetings = "peekMeetings"
        static let clipboard = "clipboardEnabled"
        static let hotkey = "hotkeyEnabled"
        static let weatherCity = "weatherCity"
        static let fahrenheit = "weatherFahrenheit"
        static let tabOrder = "islandTabOrder"
        static let hiddenTabs = "hiddenIslandTabs"
        static let widgetOrder = "widgetOrder"
        static let liveMusic = "liveMusic"
        static let liveTimers = "liveTimers"
        static let peekScreenshots = "peekScreenshots"
        static let homeOrder = "homeWidgetOrder"
        static let homeEnabled = "homeWidgetsEnabled"
        static let islandScale = "islandScale"
        static let tabIconSize = "tabIconSize"
        static let dockScale = "dockScale"
        static let controlOrder = "controlOrder"
        static let controlsEnabled = "controlsEnabled"
    }

    private let defaults = UserDefaults.standard

    @Published var edge: DockEdge { didSet { defaults.set(edge.rawValue, forKey: Keys.edge) } }
    @Published var pinned: Bool { didSet { defaults.set(pinned, forKey: Keys.pinned) } }
    @Published var hiddenWidgets: Set<String> { didSet { defaults.set(Array(hiddenWidgets), forKey: Keys.hidden) } }
    @Published var waterEnabled: Bool { didSet { defaults.set(waterEnabled, forKey: Keys.waterOn) } }
    @Published var waterMinutes: Int { didSet { defaults.set(waterMinutes, forKey: Keys.waterMin) } }
    @Published var postureEnabled: Bool { didSet { defaults.set(postureEnabled, forKey: Keys.postureOn) } }
    @Published var postureMinutes: Int { didSet { defaults.set(postureMinutes, forKey: Keys.postureMin) } }
    @Published var islandEnabled: Bool { didSet { defaults.set(islandEnabled, forKey: Keys.island) } }
    @Published var islandStyle: IslandStyle { didSet { defaults.set(islandStyle.rawValue, forKey: Keys.islandStyle) } }
    @Published var sideDockEnabled: Bool { didSet { defaults.set(sideDockEnabled, forKey: Keys.sideDock) } }
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    @Published var glassClarity: GlassClarity { didSet { defaults.set(glassClarity.rawValue, forKey: Keys.glassClarity) } }
    @Published var peekTrack: Bool { didSet { defaults.set(peekTrack, forKey: Keys.peekTrack) } }
    @Published var hudEnabled: Bool { didSet { defaults.set(hudEnabled, forKey: Keys.hud) } }
    @Published var replaceSystemHUD: Bool { didSet { defaults.set(replaceSystemHUD, forKey: Keys.replaceHUD) } }
    @Published var peekHeadphones: Bool { didSet { defaults.set(peekHeadphones, forKey: Keys.peekHeadphones) } }
    @Published var peekCharging: Bool { didSet { defaults.set(peekCharging, forKey: Keys.peekCharging) } }
    @Published var peekCapsLock: Bool { didSet { defaults.set(peekCapsLock, forKey: Keys.peekCaps) } }
    @Published var peekDownloads: Bool { didSet { defaults.set(peekDownloads, forKey: Keys.peekDownloads) } }
    @Published var peekMeetings: Bool { didSet { defaults.set(peekMeetings, forKey: Keys.peekMeetings) } }
    @Published var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: Keys.clipboard) } }
    @Published var hotkeyEnabled: Bool { didSet { defaults.set(hotkeyEnabled, forKey: Keys.hotkey) } }
    @Published var weatherCity: String { didSet { defaults.set(weatherCity, forKey: Keys.weatherCity) } }
    @Published var weatherFahrenheit: Bool { didSet { defaults.set(weatherFahrenheit, forKey: Keys.fahrenheit) } }
    @Published var islandTabOrder: [String] { didSet { defaults.set(islandTabOrder, forKey: Keys.tabOrder) } }
    @Published var hiddenIslandTabs: Set<String> { didSet { defaults.set(Array(hiddenIslandTabs), forKey: Keys.hiddenTabs) } }
    @Published var widgetOrder: [String] { didSet { defaults.set(widgetOrder, forKey: Keys.widgetOrder) } }
    @Published var liveMusic: Bool { didSet { defaults.set(liveMusic, forKey: Keys.liveMusic) } }
    @Published var liveTimers: Bool { didSet { defaults.set(liveTimers, forKey: Keys.liveTimers) } }
    @Published var peekScreenshots: Bool { didSet { defaults.set(peekScreenshots, forKey: Keys.peekScreenshots) } }
    /// Overall size of the open island and its pop-ups (0.85 ... 1.4).
    @Published var islandScale: Double { didSet { defaults.set(islandScale, forKey: Keys.islandScale) } }
    /// Size of the tab icons at the top of the open island.
    @Published var tabIconSize: Double { didSet { defaults.set(tabIconSize, forKey: Keys.tabIconSize) } }
    /// Overall size of the side dock (0.85 ... 1.4).
    @Published var dockScale: Double { didSet { defaults.set(dockScale, forKey: Keys.dockScale) } }
    @Published var controlOrder: [String] { didSet { defaults.set(controlOrder, forKey: Keys.controlOrder) } }
    @Published var enabledControls: Set<String> { didSet { defaults.set(Array(enabledControls), forKey: Keys.controlsEnabled) } }
    @Published var homeWidgetOrder: [String] { didSet { defaults.set(homeWidgetOrder, forKey: Keys.homeOrder) } }
    @Published var enabledHomeWidgets: Set<String> { didSet { defaults.set(Array(enabledHomeWidgets), forKey: Keys.homeEnabled) } }

    private init() {
        edge = DockEdge(rawValue: defaults.string(forKey: Keys.edge) ?? "") ?? .right
        pinned = defaults.bool(forKey: Keys.pinned)
        hiddenWidgets = Set(defaults.stringArray(forKey: Keys.hidden) ?? [])
        waterEnabled = defaults.object(forKey: Keys.waterOn) as? Bool ?? true
        waterMinutes = defaults.object(forKey: Keys.waterMin) as? Int ?? 45
        postureEnabled = defaults.object(forKey: Keys.postureOn) as? Bool ?? true
        postureMinutes = defaults.object(forKey: Keys.postureMin) as? Int ?? 30
        islandEnabled = defaults.object(forKey: Keys.island) as? Bool ?? true
        islandStyle = IslandStyle(rawValue: defaults.string(forKey: Keys.islandStyle) ?? "") ?? .automatic
        sideDockEnabled = defaults.object(forKey: Keys.sideDock) as? Bool ?? true
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        glassClarity = GlassClarity(rawValue: defaults.string(forKey: Keys.glassClarity) ?? "") ?? .automatic
        peekTrack = defaults.object(forKey: Keys.peekTrack) as? Bool ?? true
        hudEnabled = defaults.object(forKey: Keys.hud) as? Bool ?? true
        replaceSystemHUD = defaults.object(forKey: Keys.replaceHUD) as? Bool ?? false
        peekHeadphones = defaults.object(forKey: Keys.peekHeadphones) as? Bool ?? true
        peekCharging = defaults.object(forKey: Keys.peekCharging) as? Bool ?? true
        peekCapsLock = defaults.object(forKey: Keys.peekCaps) as? Bool ?? true
        peekDownloads = defaults.object(forKey: Keys.peekDownloads) as? Bool ?? true
        peekMeetings = defaults.object(forKey: Keys.peekMeetings) as? Bool ?? true
        clipboardEnabled = defaults.object(forKey: Keys.clipboard) as? Bool ?? true
        hotkeyEnabled = defaults.object(forKey: Keys.hotkey) as? Bool ?? true
        weatherCity = defaults.string(forKey: Keys.weatherCity) ?? ""
        weatherFahrenheit = defaults.bool(forKey: Keys.fahrenheit)
        islandTabOrder = defaults.stringArray(forKey: Keys.tabOrder) ?? IslandTab.allCases.map(\.rawValue)
        hiddenIslandTabs = Set(defaults.stringArray(forKey: Keys.hiddenTabs) ?? [])
        widgetOrder = defaults.stringArray(forKey: Keys.widgetOrder) ?? WidgetKind.allCases.map(\.rawValue)
        liveMusic = defaults.object(forKey: Keys.liveMusic) as? Bool ?? true
        liveTimers = defaults.object(forKey: Keys.liveTimers) as? Bool ?? true
        peekScreenshots = defaults.object(forKey: Keys.peekScreenshots) as? Bool ?? true
        islandScale = defaults.object(forKey: Keys.islandScale) as? Double ?? 1.0
        tabIconSize = defaults.object(forKey: Keys.tabIconSize) as? Double ?? 15
        dockScale = defaults.object(forKey: Keys.dockScale) as? Double ?? 1.0
        controlOrder = defaults.stringArray(forKey: Keys.controlOrder) ?? ControlKind.allCases.map(\.rawValue)
        enabledControls = Set(defaults.stringArray(forKey: Keys.controlsEnabled) ?? ControlKind.defaults.map(\.rawValue))
        homeWidgetOrder = defaults.stringArray(forKey: Keys.homeOrder) ?? HomeWidget.allCases.map(\.rawValue)
        enabledHomeWidgets = Set(defaults.stringArray(forKey: Keys.homeEnabled) ?? HomeWidget.defaults.map(\.rawValue))
    }

    /// Widgets in the user's order (new widgets from updates go at the end).
    var orderedWidgets: [WidgetKind] {
        Self.ordered(WidgetKind.allCases, by: widgetOrder)
    }

    var visibleWidgets: [WidgetKind] {
        orderedWidgets.filter { !hiddenWidgets.contains($0.rawValue) }
    }

    var orderedIslandTabs: [IslandTab] {
        Self.ordered(IslandTab.allCases, by: islandTabOrder)
    }

    /// Home is always available so the island is never empty.
    var visibleIslandTabs: [IslandTab] {
        orderedIslandTabs.filter { $0 == .home || !hiddenIslandTabs.contains($0.rawValue) }
    }

    func setTabVisible(_ tab: IslandTab, _ visible: Bool) {
        if visible { hiddenIslandTabs.remove(tab.rawValue) } else { hiddenIslandTabs.insert(tab.rawValue) }
    }

    var orderedHomeWidgets: [HomeWidget] {
        Self.ordered(HomeWidget.allCases, by: homeWidgetOrder)
    }

    /// Enabled Home widgets in order, trimmed to what fits in 5 slots.
    var homeWidgets: [HomeWidget] {
        var used = 0
        var result: [HomeWidget] = []
        for widget in orderedHomeWidgets where enabledHomeWidgets.contains(widget.rawValue) {
            guard used + widget.slots <= HomeWidget.maxSlots else { continue }
            used += widget.slots
            result.append(widget)
        }
        return result
    }

    var homeSlotsUsed: Int { homeWidgets.reduce(0) { $0 + $1.slots } }

    func canEnable(_ widget: HomeWidget) -> Bool {
        enabledHomeWidgets.contains(widget.rawValue) || homeSlotsUsed + widget.slots <= HomeWidget.maxSlots
    }

    func setHomeWidget(_ widget: HomeWidget, _ on: Bool) {
        if on {
            guard canEnable(widget) else { return }
            enabledHomeWidgets.insert(widget.rawValue)
        } else {
            enabledHomeWidgets.remove(widget.rawValue)
        }
    }

    func moveHomeWidget(_ widget: HomeWidget, by offset: Int) {
        var order = orderedHomeWidgets.map(\.rawValue)
        Self.move(&order, widget.rawValue, by: offset)
        homeWidgetOrder = order
    }

    /// Drag-and-drop: put `item` where `target` is.
    func placeHomeWidget(_ item: HomeWidget, at target: HomeWidget) {
        var order = orderedHomeWidgets.map(\.rawValue)
        Self.place(&order, item.rawValue, at: target.rawValue)
        homeWidgetOrder = order
    }

    // MARK: Controls tab

    var orderedControls: [ControlKind] {
        Self.ordered(ControlKind.allCases, by: controlOrder)
    }

    var controls: [ControlKind] {
        Array(orderedControls.filter { enabledControls.contains($0.rawValue) }.prefix(ControlKind.maxSlots))
    }

    func canEnableControl(_ kind: ControlKind) -> Bool {
        enabledControls.contains(kind.rawValue) || controls.count < ControlKind.maxSlots
    }

    func setControl(_ kind: ControlKind, _ on: Bool) {
        if on {
            guard canEnableControl(kind) else { return }
            enabledControls.insert(kind.rawValue)
        } else {
            enabledControls.remove(kind.rawValue)
        }
    }

    func moveControl(_ kind: ControlKind, by offset: Int) {
        var order = orderedControls.map(\.rawValue)
        Self.move(&order, kind.rawValue, by: offset)
        controlOrder = order
    }

    func placeControl(_ item: ControlKind, at target: ControlKind) {
        var order = orderedControls.map(\.rawValue)
        Self.place(&order, item.rawValue, at: target.rawValue)
        controlOrder = order
    }

    func moveWidget(_ kind: WidgetKind, by offset: Int) {
        var order = orderedWidgets.map(\.rawValue)
        Self.move(&order, kind.rawValue, by: offset)
        widgetOrder = order
    }

    func moveTab(_ tab: IslandTab, by offset: Int) {
        var order = orderedIslandTabs.map(\.rawValue)
        Self.move(&order, tab.rawValue, by: offset)
        islandTabOrder = order
    }

    static func ordered<T: RawRepresentable>(_ all: [T], by order: [String]) -> [T] where T.RawValue == String {
        let known = order.compactMap { T(rawValue: $0) }
        let missing = all.filter { item in !known.contains { $0.rawValue == item.rawValue } }
        return known + missing
    }

    static func place(_ array: inout [String], _ item: String, at target: String) {
        guard item != target, let from = array.firstIndex(of: item), let to = array.firstIndex(of: target) else { return }
        array.remove(at: from)
        array.insert(item, at: to)
    }

    static func move(_ array: inout [String], _ item: String, by offset: Int) {
        guard let index = array.firstIndex(of: item) else { return }
        let target = max(0, min(array.count - 1, index + offset))
        guard target != index else { return }
        array.remove(at: index)
        array.insert(item, at: target)
    }

    func isVisible(_ kind: WidgetKind) -> Bool {
        !hiddenWidgets.contains(kind.rawValue)
    }

    func setVisible(_ kind: WidgetKind, _ visible: Bool) {
        if visible { hiddenWidgets.remove(kind.rawValue) } else { hiddenWidgets.insert(kind.rawValue) }
    }
}

/// Small helper to save Codable values in UserDefaults.
enum Persist {
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
