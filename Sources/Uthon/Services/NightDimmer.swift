import AppKit
import SwiftUI
import Combine

enum DimSchedule: String, CaseIterable, Identifiable {
    /// From sunset to sunrise in the user's city (falls back to 19:00–06:00).
    case sun
    /// Whenever macOS is in Dark Mode.
    case darkMode
    /// The user's own hours.
    case custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sun: return "Sunset to sunrise (my city)"
        case .darkMode: return "When macOS is in Dark Mode"
        case .custom: return "Custom hours"
        }
    }
}

enum DimTarget: String, CaseIterable, Identifiable {
    case uthon, screen
    var id: String { rawValue }
    var title: String { self == .uthon ? "Nook only (island and docks)" : "Every screen" }
}

/// Makes the screen (or only Uthon) a little darker at night. Works the same on a built-in
/// display, an iMac or an external monitor: it lays a soft, click-through dark layer over
/// each screen, fading in over half an hour around sunset and out around sunrise.
final class NightDimmer: ObservableObject {
    static let shared = NightDimmer()

    /// 0 (no dimming) ... 0.6, already faded for the time of day.
    @Published private(set) var level: Double = 0

    private var windows: [NSWindow] = []
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// Lets the user turn it off until the next morning from the menu.
    private var pausedUntil: Date?

    func start() {
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.rebuildWindows() }
            .store(in: &cancellables)
        let library = UserLibrary.shared
        Publishers.MergeMany(
            library.$dimEnabled.map { _ in () }.eraseToAnyPublisher(),
            library.$dimStrength.map { _ in () }.eraseToAnyPublisher(),
            library.$dimSchedule.map { _ in () }.eraseToAnyPublisher(),
            library.$dimTarget.map { _ in () }.eraseToAnyPublisher(),
            library.$dimStartHour.map { _ in () }.eraseToAnyPublisher(),
            library.$dimEndHour.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$systemAppearanceTick.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        .sink { [weak self] in self?.update() }
        .store(in: &cancellables)
        update()
    }

    var isPaused: Bool { pausedUntil.map { $0 > Date() } ?? false }

    /// Shows the chosen strength for a few seconds, whatever the time, so it can be judged.
    private var previewUntil: Date?
    @Published private(set) var previewing = false

    func preview(seconds: TimeInterval = 4) {
        previewUntil = Date().addingTimeInterval(seconds)
        previewing = true
        update()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.1) { [weak self] in
            self?.previewUntil = nil
            self?.previewing = false
            self?.update()
        }
    }

    /// "Not tonight": stays off until 6 in the morning.
    func pauseForTonight() {
        let cal = Calendar.current
        var next = cal.date(bySettingHour: 6, minute: 0, second: 0, of: Date()) ?? Date()
        if next <= Date() { next = cal.date(byAdding: .day, value: 1, to: next) ?? next }
        pausedUntil = next
        update()
    }

    func resume() {
        pausedUntil = nil
        update()
    }

    func update(now: Date = Date()) {
        let library = UserLibrary.shared
        var value = 0.0
        if library.dimEnabled, !isPaused {
            value = Self.factor(now: now, schedule: library.dimSchedule, darkMode: Self.systemIsDark,
                                window: nightWindow(now: now)) * library.dimStrength
        }
        if let until = previewUntil, until > now { value = library.dimStrength }
        value = min(max(value, 0), 0.6)
        if abs(value - level) > 0.001 { level = value }
        applyScreenLayer(library.dimTarget == .screen ? value : 0)
    }

    static var systemIsDark: Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Tonight's dark period for the chosen schedule: (start, end).
    func nightWindow(now: Date) -> (start: Date, end: Date) {
        let library = UserLibrary.shared
        if library.dimSchedule == .sun, let place = WeatherStore.shared.place,
           let sun = Self.sunTimes(for: now, latitude: place.latitude, longitude: place.longitude, timeZone: place.timeZone) {
            return Self.window(now: now, start: sun.sunset, end: sun.sunrise)
        }
        let start = library.dimSchedule == .custom ? library.dimStartHour : 19
        let end = library.dimSchedule == .custom ? library.dimEndHour : 6
        let cal = Calendar.current
        let s = cal.date(bySettingHour: start, minute: 0, second: 0, of: now) ?? now
        let e = cal.date(bySettingHour: end, minute: 0, second: 0, of: now) ?? now
        return Self.window(now: now, start: s, end: e)
    }

    /// Given today's start (evening) and end (morning) clock times, the night that `now` is in or next to.
    static func window(now: Date, start: Date, end: Date) -> (start: Date, end: Date) {
        let day: TimeInterval = 86400
        var s = start, e = end
        if e <= s { e += day }                       // the night crosses midnight
        // Early morning: we are still in (or fading out of) last night.
        if now < e - day + 30 * 60 { s -= day; e -= day }
        return (s, e)
    }

    /// 0...1: how far into the night we are, with a 30-minute fade at both ends.
    static func factor(now: Date, schedule: DimSchedule, darkMode: Bool, window: (start: Date, end: Date)) -> Double {
        if schedule == .darkMode { return darkMode ? 1 : 0 }
        let fade: TimeInterval = 30 * 60
        let (s, e) = window
        guard now > s - fade, now < e + fade else { return 0 }
        if now < s + fade { return max(0, min(1, (now.timeIntervalSince(s) + fade) / (2 * fade))) }
        if now > e - fade { return max(0, min(1, (e.timeIntervalSince(now) + fade) / (2 * fade))) }
        return 1
    }

    /// Sunrise and sunset for a date and place (NOAA approximation, ±2 minutes).
    static func sunTimes(for date: Date, latitude: Double, longitude: Double, timeZone: TimeZone) -> (sunrise: Date, sunset: Date)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        guard let dayOfYear = cal.ordinality(of: .day, in: .year, for: date) else { return nil }
        let gamma = 2 * Double.pi / 365 * Double(dayOfYear - 1)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                               - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let lat = latitude * .pi / 180
        let zenith = 90.833 * Double.pi / 180
        let cosHA = cos(zenith) / (cos(lat) * cos(decl)) - tan(lat) * tan(decl)
        guard cosHA > -1, cosHA < 1 else { return nil }   // polar day or night
        let ha = acos(cosHA) * 180 / .pi
        let offsetMinutes = Double(timeZone.secondsFromGMT(for: date)) / 60
        let sunriseMin = 720 - 4 * (longitude + ha) - eqTime + offsetMinutes
        let sunsetMin = 720 - 4 * (longitude - ha) - eqTime + offsetMinutes
        let midnight = cal.startOfDay(for: date)
        return (midnight.addingTimeInterval(sunriseMin * 60), midnight.addingTimeInterval(sunsetMin * 60))
    }

    // MARK: Screen layer

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        update()
    }

    private func applyScreenLayer(_ alpha: Double) {
        if alpha <= 0.001 {
            windows.forEach { $0.orderOut(nil) }
            return
        }
        if windows.count != NSScreen.screens.count {
            windows.forEach { $0.orderOut(nil) }
            windows = NSScreen.screens.map(Self.makeWindow)
        }
        for (window, screen) in zip(windows, NSScreen.screens) {
            window.setFrame(screen.frame, display: false)
            window.alphaValue = alpha
            window.orderFrontRegardless()
        }
    }

    private static func makeWindow(for screen: NSScreen) -> NSWindow {
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.backgroundColor = .black
        w.isOpaque = false
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        w.sharingType = .none
        return w
    }
}

/// Darkens Uthon's own windows at night (when the target is "Nook only").
struct NightDimOverlay: View {
    @ObservedObject private var dimmer = NightDimmer.shared
    @ObservedObject private var library = UserLibrary.shared

    var body: some View {
        Color.black
            .opacity(library.dimTarget == .uthon ? dimmer.level : 0)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.6), value: dimmer.level)
    }
}
