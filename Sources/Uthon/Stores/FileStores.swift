import AppKit

/// Apps and folders pinned to the Shortcuts grid.
final class ShortcutsStore: ObservableObject {
    static let shared = ShortcutsStore()
    private let key = "shortcuts"

    @Published private(set) var paths: [String] {
        didSet { Persist.save(paths, key: key) }
    }

    private init() {
        if let saved = Persist.load([String].self, key: key) {
            paths = saved
        } else {
            paths = Self.starterSet()
        }
    }

    private static func starterSet() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/System/Library/CoreServices/Finder.app",
            "/Applications/Safari.app",
            "/System/Applications/Notes.app",
            "/System/Applications/Calendar.app",
            "/System/Applications/Music.app",
            "/System/Applications/Photos.app",
            "/System/Applications/System Settings.app",
            home + "/Documents",
            home + "/Downloads",
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0) }
    }

    func add(_ urls: [URL]) {
        for url in urls where !paths.contains(url.path) {
            paths.append(url.path)
        }
    }

    func remove(_ path: String) {
        paths.removeAll { $0 == path }
    }

    func pickAndAdd() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose apps, folders or files to pin"
        DockController.shared.holdOpen = true
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        DockController.shared.holdOpen = false
        if response == .OK { add(panel.urls) }
    }
}

/// Files parked on the shelf for later.
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    private let key = "shelf"

    @Published private(set) var paths: [String] {
        didSet { Persist.save(paths, key: key) }
    }

    private init() {
        let saved = Persist.load([String].self, key: key) ?? []
        paths = saved.filter { FileManager.default.fileExists(atPath: $0) }
    }

    func add(_ urls: [URL]) {
        for url in urls where !paths.contains(url.path) {
            paths.insert(url.path, at: 0)
        }
    }

    func remove(_ path: String) {
        paths.removeAll { $0 == path }
    }

    func clear() {
        paths.removeAll()
    }
}

/// The newest items in ~/Downloads.
final class DownloadsStore: ObservableObject {
    static let shared = DownloadsStore()

    struct Item: Hashable, Identifiable {
        let url: URL
        let date: Date
        var id: URL { url }
    }

    @Published private(set) var recent: [Item] = []

    let folder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private var pendingCheck: DispatchWorkItem?

    /// Watch ~/Downloads so a finished download can pop up on the island.
    func startWatching() {
        guard source == nil else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        known = Set(currentNames())
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
        src.setEventHandler { [weak self] in self?.folderChanged() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func currentNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    private func folderChanged() {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.detectNewFiles() }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func detectNewFiles() {
        let names = Set(currentNames())
        let added = names.subtracting(known)
        known = names
        let partial: Set<String> = ["download", "crdownload", "part", "partial", "tmp", "opdownload"]
        if AppSettings.shared.peekDownloads,
           let name = added.sorted().first(where: { !$0.hasPrefix(".") && !partial.contains(($0 as NSString).pathExtension.lowercased()) }) {
            IslandController.shared.showPeek(.download(folder.appendingPathComponent(name)), duration: 6)
        }
        refresh()
    }

    func refresh() {
        let folder = self.folder
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey]
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            let items = urls.map { url -> Item in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let date = values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast
                return Item(url: url, date: date)
            }
            let newest = Array(items.sorted { $0.date > $1.date }.prefix(6))
            DispatchQueue.main.async { self?.recent = newest }
        }
    }
}
