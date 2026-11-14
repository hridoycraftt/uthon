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
        // macOS resets display colours after sleep: put the dimming back.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in self?.gamma.forget(); self?.update() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.gamma.restore() }
            .store(in: &cancellables)
        let library = UserLibrary.shared
        Publishers.MergeMany(
            library.$dimEnabled.map { _ in () }.eraseToAnyPublisher(),
            library.$dimStrength.map { _ in () }.eraseToAnyPublisher(),
            library.$dimSchedule.map { _ in () }.eraseToAnyPublisher(),
            library.$dimTarget.map { _ in () }.eraseToAnyPublisher(),
            library.$dimWarmth.map { _ in () }.eraseToAnyPublisher(),
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
            // A newer preview (e.g. the slider is still moving) keeps it on.
            if let until = self?.previewUntil, until > Date() { return }
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
        let screen = library.dimTarget == .screen ? value : 0
        // Like lowering the backlight: the display's own colours are scaled down (blacks stay
        // black, text stays crisp) and warmed a little. Only if that is refused, a dark layer.
        if gamma.apply(level: screen, warmth: library.dimWarmth) {
            applyScreenLayer(0)
        } else {
            applyScreenLayer(screen)
        }
    }

    let gamma = GammaDimmer()

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
            windows.forEach { $0.orderOut(nil); $0.alphaValue = 0 }
            return
        }
        if windows.count != NSScreen.screens.count {
            windows.forEach { $0.orderOut(nil) }
            windows = NSScreen.screens.map(Self.makeWindow)
        }
        for (window, screen) in zip(windows, NSScreen.screens) {
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 1.0
                window.animator().alphaValue = alpha
            }
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
        w.alphaValue = 0
        return w
    }
}

/// Darkens Uthon's own windows at night (when the target is "Nook only").
struct NightDimOverlay: View {
    @ObservedObject private var dimmer = NightDimmer.shared
    @ObservedObject private var library = UserLibrary.shared

    var body: some View {
        // A deep, slightly warm shade rather than flat black: the glass gets darker without
        // turning grey.
        Color(red: 0.06, green: 0.04, blue: 0.02)
            .opacity(library.dimTarget == .uthon ? dimmer.level * (0.8 + 0.2 * library.dimWarmth) : 0)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 1.0), value: dimmer.level)
    }
}

/// Dims every display the way lowering the brightness does, by scaling the display's colour
/// tables (the same mechanism Night Shift-style apps use). It needs no permission, works on
/// built-in and external displays, does not cover the screen with a window, and macOS puts
/// the colours back by itself if Nook quits.
final class GammaDimmer {
    private var originals: [CGDirectDisplayID: (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue])] = [:]
    private(set) var shown: Double = 0
    private var shownWarmth: Double = 0
    private var ramp: Timer?
    private var active = false

    /// Forget the saved tables (after sleep or a display change macOS may have reset them).
    func forget() { originals = [:] }

    private static func displays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func original(_ id: CGDirectDisplayID) -> (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue])? {
        if let saved = originals[id] { return saved }
        let capacity = CGDisplayGammaTableCapacity(id)
        guard capacity > 1 else { return nil }
        var r = [CGGammaValue](repeating: 0, count: Int(capacity))
        var g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &r, &g, &b, &count) == .success, count > 1 else { return nil }
        let table = (Array(r.prefix(Int(count))), Array(g.prefix(Int(count))), Array(b.prefix(Int(count))))
        originals[id] = table
        return table
    }

    /// The factors for red, green and blue at a dimming level and warmth (0...1).
    static func factors(level: Double, warmth: Double) -> (r: Double, g: Double, b: Double) {
        let l = min(max(level, 0), 0.8), w = min(max(warmth, 0), 1) * min(1, level / 0.3)
        let k = 1 - l
        return (k, k * (1 - 0.10 * w), k * (1 - 0.30 * w))
    }

    private func set(level: Double, warmth: Double) -> Bool {
        let f = Self.factors(level: level, warmth: warmth)
        var ok = true
        for id in Self.displays() {
            guard let t = original(id) else { ok = false; continue }
            var r = t.r.map { CGGammaValue(Double($0) * f.r) }
            var g = t.g.map { CGGammaValue(Double($0) * f.g) }
            var b = t.b.map { CGGammaValue(Double($0) * f.b) }
            if CGSetDisplayTransferByTable(id, UInt32(r.count), &r, &g, &b) != .success { ok = false }
        }
        return ok
    }

    /// Glides to the level over about a second. Returns false if the displays refused.
    @discardableResult
    func apply(level: Double, warmth: Double) -> Bool {
        if level <= 0.001 {
            ramp?.invalidate()
            if active { glide(to: 0, warmth: warmth) }
            return true
        }
        // Check once that the displays accept it.
        if !active {
            originals = [:]
            CGDisplayRestoreColorSyncSettings()
            guard set(level: shown, warmth: warmth) else { return false }
            active = true
        }
        glide(to: level, warmth: warmth)
        return true
    }

    private func glide(to target: Double, warmth: Double) {
        ramp?.invalidate()
        let from = shown, fromWarmth = shownWarmth
        if abs(target - from) < 0.002 && abs(warmth - fromWarmth) < 0.002 {
            _ = set(level: target, warmth: warmth)   // re-apply (macOS may have reset it)
            return
        }
        let steps = 30
        var step = 0
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            step += 1
            let x = Double(step) / Double(steps)
            let eased = x * x * (3 - 2 * x)
            self.shown = from + (target - from) * eased
            self.shownWarmth = fromWarmth + (warmth - fromWarmth) * eased
            _ = self.set(level: self.shown, warmth: self.shownWarmth)
            if step >= steps {
                timer.invalidate()
                if target <= 0.001 { self.restore() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        ramp = t
    }

    /// Puts the displays' own colours back.
    func restore() {
        ramp?.invalidate()
        guard active else { return }
        CGDisplayRestoreColorSyncSettings()
        active = false
        shown = 0
        shownWarmth = 0
        originals = [:]
    }
}
