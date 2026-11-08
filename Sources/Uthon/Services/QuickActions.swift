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
        darkMode = Self.systemIsDark()
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
                "Uthon: Keep awake" as CFString,
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
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
