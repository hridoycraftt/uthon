import AppKit
import IOKit.pwr_mgt

/// One-tap system controls for the Controls tab.
final class QuickActions: ObservableObject {
    static let shared = QuickActions()

    @Published private(set) var keepAwake = false
    @Published private(set) var darkMode = false
    private var assertion: IOPMAssertionID = 0

    private init() {
        darkMode = Self.systemIsDark()
    }

    static func systemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    func refresh() {
        let dark = Self.systemIsDark()
        if darkMode != dark { darkMode = dark }
    }

    /// Stop the Mac and display from sleeping (like `caffeinate`).
    func toggleKeepAwake() {
        if keepAwake {
            IOPMAssertionRelease(assertion)
            keepAwake = false
        } else {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Nook: Keep awake" as CFString,
                &assertion
            )
            keepAwake = result == kIOReturnSuccess
        }
    }

    /// Switches the whole system between light and dark (macOS asks once to allow controlling System Events).
    func toggleDarkMode() {
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
            AppearanceWatcher.shared.changed()
        }
    }

    func sleepDisplay() {
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    func screenshot() {
        IslandController.shared.collapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.run("/usr/sbin/screencapture", ["-i", "-U"])
        }
    }

    func emptyTrash() {
        let source = "tell application \"Finder\" to empty trash"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func run(_ tool: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try? process.run()
    }
}

/// Finds apps by name (instant, cached) and offers a web search fallback.
final class AppSearch {
    static let shared = AppSearch()

    struct Result: Identifiable, Hashable {
        let url: URL
        let name: String
        var id: URL { url }
    }

    private var apps: [Result] = []
    private var loadedAt = Date.distantPast

    /// Every app on this Mac, sorted by name.
    var allApps: [Result] {
        if Date().timeIntervalSince(loadedAt) > 600 { reload() }
        return apps
    }

    func search(_ query: String) -> [Result] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        if Date().timeIntervalSince(loadedAt) > 600 { reload() }
        let starts = apps.filter { $0.name.lowercased().hasPrefix(q) }
        let contains = apps.filter { !$0.name.lowercased().hasPrefix(q) && $0.name.lowercased().contains(q) }
        return Array((starts + contains).prefix(6))
    }

    private func reload() {
        loadedAt = Date()
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var found: [Result] = []
        for folder in folders {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            for item in items where item.hasSuffix(".app") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(item)
                found.append(Result(url: url, name: String(item.dropLast(4))))
            }
        }
        found.append(Result(url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), name: "Finder"))
        var seen = Set<String>()
        apps = found.filter { seen.insert($0.name).inserted }.sorted { $0.name < $1.name }
    }

    static func webSearchURL(_ query: String) -> URL? {
        var comps = URLComponents(string: "https://www.google.com/search")
        comps?.queryItems = [URLQueryItem(name: "q", value: query)]
        return comps?.url
    }

    /// Opens Spotlight-style file search in Finder.
    static func searchFiles(_ query: String) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let url = URL(string: "x-apple.finder:search?\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Notices new screenshots (via Spotlight metadata) so the island can offer them.
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()

    private let query = NSMetadataQuery()
    private var startedAt = Date()
    private var seen: Set<String> = []

    func start() {
        startedAt = Date()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture = 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] _ in
            self?.checkNew()
        }
        query.start()
    }

    private func checkNew() {
        guard AppSettings.shared.peekScreenshots else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        var newest: (URL, Date)?
        for case let item as NSMetadataItem in query.results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let date = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date,
                  date > startedAt, !seen.contains(path) else { continue }
            if newest == nil || date > newest!.1 { newest = (URL(fileURLWithPath: path), date) }
        }
        guard let (url, _) = newest else { return }
        seen.insert(url.path)
        IslandController.shared.showPeek(.screenshot(url), duration: 8)
    }
}

/// Controls that can be placed on the Controls tab (customizable like Control Center).
enum ControlKind: String, CaseIterable, Identifiable, CustomizableItem {
    case keepAwake, appearance, sound, screenshot, sleepDisplay, emptyTrash
    case focusTimer, hideDesktopIcons, hiddenFiles, missionControl, colorPicker
    case calculator, activityMonitor, screenRecording

    var id: String { rawValue }
    var slots: Int { 1 }

    static let maxSlots = 8
    static let defaults: [ControlKind] = [.keepAwake, .appearance, .sound, .screenshot, .sleepDisplay, .emptyTrash]

    var title: String {
        switch self {
        case .keepAwake: return "Keep Awake"
        case .appearance: return "Appearance"
        case .sound: return "Sound"
        case .screenshot: return "Screenshot"
        case .sleepDisplay: return "Sleep Display"
        case .emptyTrash: return "Empty Trash"
        case .focusTimer: return "Focus 25 min"
        case .hideDesktopIcons: return "Desktop Icons"
        case .hiddenFiles: return "Hidden Files"
        case .missionControl: return "Mission Control"
        case .colorPicker: return "Color Picker"
        case .calculator: return "Calculator"
        case .activityMonitor: return "Activity Monitor"
        case .screenRecording: return "Record Screen"
        }
    }

    var symbol: String {
        switch self {
        case .keepAwake: return "cup.and.saucer.fill"
        case .appearance: return "circle.lefthalf.filled"
        case .sound: return "speaker.wave.2.fill"
        case .screenshot: return "camera.viewfinder"
        case .sleepDisplay: return "moon.zzz.fill"
        case .emptyTrash: return "trash.fill"
        case .focusTimer: return "brain.head.profile"
        case .hideDesktopIcons: return "menubar.dock.rectangle"
        case .hiddenFiles: return "eye.fill"
        case .missionControl: return "rectangle.3.group.fill"
        case .colorPicker: return "eyedropper.halffull"
        case .calculator: return "plusminus.circle.fill"
        case .activityMonitor: return "waveform.path.ecg"
        case .screenRecording: return "record.circle"
        }
    }
}

extension QuickActions {
    struct ControlState {
        var symbol: String
        var subtitle: String
        var active: Bool
    }

    func state(of kind: ControlKind) -> ControlState {
        switch kind {
        case .keepAwake:
            return ControlState(symbol: keepAwake ? "cup.and.saucer.fill" : "cup.and.saucer",
                                subtitle: keepAwake ? "On" : "Off", active: keepAwake)
        case .appearance:
            return ControlState(symbol: darkMode ? "moon.fill" : "sun.max.fill",
                                subtitle: darkMode ? "Dark" : "Light", active: darkMode)
        case .sound:
            let muted = AudioController.shared.isMuted
            return ControlState(symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                subtitle: muted ? "Muted" : "On", active: muted)
        case .screenshot:
            return ControlState(symbol: kind.symbol, subtitle: "Select area", active: false)
        case .sleepDisplay:
            return ControlState(symbol: kind.symbol, subtitle: "Turn off screen", active: false)
        case .emptyTrash:
            return ControlState(symbol: kind.symbol, subtitle: "Finder", active: false)
        case .focusTimer:
            let running = TimerStore.shared.timerActive
            return ControlState(symbol: kind.symbol, subtitle: running ? "Running" : "Start", active: running)
        case .hideDesktopIcons:
            let hidden = desktopIconsHidden
            return ControlState(symbol: kind.symbol, subtitle: hidden ? "Hidden" : "Shown", active: hidden)
        case .hiddenFiles:
            let shown = hiddenFilesShown
            return ControlState(symbol: shown ? "eye.fill" : "eye.slash.fill", subtitle: shown ? "Shown" : "Hidden", active: shown)
        case .missionControl, .colorPicker, .calculator, .activityMonitor:
            return ControlState(symbol: kind.symbol, subtitle: "Open", active: false)
        case .screenRecording:
            return ControlState(symbol: kind.symbol, subtitle: "Screenshot app", active: false)
        }
    }

    func perform(_ kind: ControlKind) {
        switch kind {
        case .keepAwake: toggleKeepAwake()
        case .appearance: toggleDarkMode()
        case .sound:
            AudioController.shared.toggleMute()
            objectWillChange.send()
        case .screenshot: screenshot()
        case .sleepDisplay: sleepDisplay()
        case .emptyTrash: emptyTrash()
        case .focusTimer:
            if TimerStore.shared.timerActive {
                TimerStore.shared.cancelTimer()
            } else {
                TimerStore.shared.startTimer(minutes: 25)
            }
            objectWillChange.send()
        case .hideDesktopIcons:
            setFinder("CreateDesktop", value: desktopIconsHidden)   // hidden -> show again
        case .hiddenFiles:
            setFinder("AppleShowAllFiles", value: !hiddenFilesShown)
        case .missionControl: open("/System/Applications/Mission Control.app")
        case .colorPicker: open("/System/Applications/Utilities/Digital Color Meter.app")
        case .calculator: open("/System/Applications/Calculator.app")
        case .activityMonitor: open("/System/Applications/Utilities/Activity Monitor.app")
        case .screenRecording:
            IslandController.shared.collapse()
            open("/System/Applications/Utilities/Screenshot.app")
        }
    }

    var desktopIconsHidden: Bool {
        let value = UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool
        return value == false
    }

    var hiddenFilesShown: Bool {
        UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "AppleShowAllFiles") ?? false
    }

    /// Writes a Finder preference and restarts Finder so it takes effect.
    private func setFinder(_ key: String, value: Bool) {
        let write = Process()
        write.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        write.arguments = ["write", "com.apple.finder", key, "-bool", value ? "true" : "false"]
        try? write.run()
        write.waitUntilExit()
        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        restart.arguments = ["Finder"]
        try? restart.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.objectWillChange.send() }
    }
}
