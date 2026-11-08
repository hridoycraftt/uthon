import Foundation
import Combine

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
    }

    private let defaults = UserDefaults.standard

    @Published var edge: DockEdge { didSet { defaults.set(edge.rawValue, forKey: Keys.edge) } }
    @Published var pinned: Bool { didSet { defaults.set(pinned, forKey: Keys.pinned) } }
    @Published var hiddenWidgets: Set<String> { didSet { defaults.set(Array(hiddenWidgets), forKey: Keys.hidden) } }
    @Published var waterEnabled: Bool { didSet { defaults.set(waterEnabled, forKey: Keys.waterOn) } }
    @Published var waterMinutes: Int { didSet { defaults.set(waterMinutes, forKey: Keys.waterMin) } }
    @Published var postureEnabled: Bool { didSet { defaults.set(postureEnabled, forKey: Keys.postureOn) } }
    @Published var postureMinutes: Int { didSet { defaults.set(postureMinutes, forKey: Keys.postureMin) } }

    private init() {
        edge = DockEdge(rawValue: defaults.string(forKey: Keys.edge) ?? "") ?? .right
        pinned = defaults.bool(forKey: Keys.pinned)
        hiddenWidgets = Set(defaults.stringArray(forKey: Keys.hidden) ?? [])
        waterEnabled = defaults.object(forKey: Keys.waterOn) as? Bool ?? true
        waterMinutes = defaults.object(forKey: Keys.waterMin) as? Int ?? 45
        postureEnabled = defaults.object(forKey: Keys.postureOn) as? Bool ?? true
        postureMinutes = defaults.object(forKey: Keys.postureMin) as? Int ?? 30
    }

    var visibleWidgets: [WidgetKind] {
        WidgetKind.allCases.filter { !hiddenWidgets.contains($0.rawValue) }
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
