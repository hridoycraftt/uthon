import SwiftUI

enum IslandTab: String, CaseIterable, Identifiable {
    case home, controls, search, shelf, timer, clipboard, notes, mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .controls: return "Controls"
        case .search: return "Search"
        case .shelf: return "Shelf"
        case .timer: return "Timer"
        case .clipboard: return "Clipboard"
        case .notes: return "Notes"
        case .mirror: return "Mirror"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .controls: return "switch.2"
        case .search: return "magnifyingglass"
        case .shelf: return "tray.fill"
        case .timer: return "timer"
        case .clipboard: return "doc.on.clipboard.fill"
        case .notes: return "note.text"
        case .mirror: return "person.crop.square.fill"
        }
    }
}

/// Ongoing things the closed island shows on its "ears".
enum IslandActivity: Equatable {
    case reminder(CareReminders.Kind)
    case timer
    case stopwatch
    case music
}

/// Short pop-ups ("peeks") that drop out of the island for a moment.
enum PeekKind: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case capsLock(Bool)
    case charging(percent: Int)
    case headphones(name: String, symbol: String, levels: HeadphoneLevels?)
    case track
    case download(URL)
    case meeting(title: String, start: Date, link: URL?)
    case lowBattery(name: String, percent: Int)
    case timerDone
    case screenshot(URL)

    /// Peeks of the same category replace each other in place (e.g. volume steps).
    var category: Int {
        switch self {
        case .volume: return 0
        case .brightness: return 1
        case .capsLock: return 2
        case .charging: return 3
        case .headphones: return 4
        case .track: return 5
        case .download: return 6
        case .meeting: return 7
        case .lowBattery: return 8
        case .timerDone: return 9
        case .screenshot: return 10
        }
    }

    /// Small one-line pill (vs. a bigger card).
    var isSlim: Bool {
        switch self {
        case .volume, .brightness, .capsLock, .charging: return true
        default: return false
        }
    }
}

struct Peek: Equatable {
    var id = UUID()
    var kind: PeekKind
}

final class IslandModel: ObservableObject {
    static let shared = IslandModel()

    @Published var expanded = false
    @Published var tab: IslandTab = .home
    @Published var hasNotch = false
    @Published var notchSize = CGSize(width: 190, height: 32)
    @Published var dropTargeted = false
    @Published var peek: Peek?
    /// Control Center style editing of the Home and Controls rows.
    @Published var editing = false

    static let compactFlare: CGFloat = 6
    static let expandedFlare: CGFloat = 14
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)
    static let peekSpring = Animation.spring(response: 0.36, dampingFraction: 0.76)

    /// Layout size of the open island before the user's size setting is applied.
    var baseExpandedSize: CGSize {
        CGSize(width: max(740, notchSize.width + 520), height: max(notchSize.height, 40) + 176)
    }

    static var scale: CGFloat { CGFloat(min(max(AppSettings.shared.islandScale, 0.8), 1.5)) }

    var expandedSize: CGSize {
        CGSize(width: baseExpandedSize.width * Self.scale, height: baseExpandedSize.height * Self.scale)
    }

    /// Height of the tab bar row (at least the notch height so it never sits under the notch).
    var headerHeight: CGFloat { max(notchSize.height, 40) }

    func earWidth(for activity: IslandActivity) -> CGFloat {
        switch activity {
        case .timer, .stopwatch: return 60
        default: return notchSize.height + 8
        }
    }

    /// Closed size. With a notch the middle is the notch itself; without one it is a small gap.
    func compactSize(activity: IslandActivity?) -> CGSize {
        let middle = hasNotch ? notchSize.width : 28
        let base = middle + Self.compactFlare * 2
        guard let activity else { return CGSize(width: base, height: notchSize.height) }
        return CGSize(width: base + earWidth(for: activity) * 2, height: notchSize.height)
    }

    func basePeekSize(_ kind: PeekKind) -> CGSize {
        let top = hasNotch ? notchSize.height / Self.scale : 0
        if kind.isSlim {
            return CGSize(width: max(notchSize.width + 150, 320), height: top + 46)
        }
        return CGSize(width: max(notchSize.width + 240, 440), height: top + 78)
    }

    func peekSize(_ kind: PeekKind) -> CGSize {
        let base = basePeekSize(kind)
        return CGSize(width: base.width * Self.scale, height: base.height * Self.scale)
    }

    /// What the closed island should show right now (highest priority first).
    static func currentActivity() -> IslandActivity? {
        if let kind = CareReminders.shared.active { return .reminder(kind) }
        let settings = AppSettings.shared
        if settings.liveTimers, TimerStore.shared.timerActive { return .timer }
        if settings.liveTimers, TimerStore.shared.stopwatchRunning { return .stopwatch }
        if settings.liveMusic, NowPlayingStore.shared.track?.isPlaying == true { return .music }
        return nil
    }
}
