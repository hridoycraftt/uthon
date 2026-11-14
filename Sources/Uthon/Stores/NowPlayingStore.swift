import AppKit

/// Current song from Music or Spotify.
/// Both apps broadcast a notification whenever playback changes, so the island
/// updates instantly; AppleScript is used to read details and send commands
/// (macOS asks once for permission to control these apps).
final class NowPlayingStore: ObservableObject {
    static let shared = NowPlayingStore()
    static let trackChanged = Notification.Name("UthonTrackChanged")

    struct Track: Equatable {
        var player: String
        var bundleID: String
        var title: String
        var artist: String
        var album: String
        var isPlaying: Bool
        var position: Double
        var duration: Double
        var fetchedAt: Date

        var key: String { "\(player)|\(title)|\(artist)|\(album)" }

        func currentPosition(at date: Date) -> Double {
            guard isPlaying else { return position }
            let pos = position + date.timeIntervalSince(fetchedAt)
            return duration > 0 ? min(duration, pos) : pos
        }
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?

    private static let players: [(name: String, bundleID: String)] = [
        ("Spotify", "com.spotify.client"),
        ("Music", "com.apple.Music"),
    ]
    private var artworkKey: String?
    private var timer: Timer?
    private var activeCount = 0
    private var started = false

    /// Listen for playback changes. Called once at launch.
    func start() {
        guard !started else { return }
        started = true
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        if runningPlayer() != nil { refresh() }
    }

    /// While the dock or island is open, also poll every few seconds (keeps progress accurate).
    func setActive(_ active: Bool) {
        activeCount = max(0, activeCount + (active ? 1 : -1))
        if activeCount > 0 {
            if timer == nil {
                refresh()
                let t = Timer(timeInterval: 4, repeats: true) { [weak self] _ in self?.refresh() }
                RunLoop.main.add(t, forMode: .common)
                timer = t
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func runningPlayer() -> (name: String, bundleID: String)? {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        return Self.players.first { ids.contains($0.bundleID) }
    }

    /// AppleScript talks to another app and can take a while (or hang if that app is busy),
    /// so it always runs on this queue, never on the main thread.
    private static let scriptQueue = DispatchQueue(label: "nook.nowplaying.script", qos: .utility)
    private var refreshing = false
    private var refreshAgain = false

    func refresh() {
        guard let player = runningPlayer() else {
            clear()
            return
        }
        if refreshing { refreshAgain = true; return }
        refreshing = true
        let source = Self.stateScript(player.name)
        Self.scriptQueue.async { [weak self] in
            let result = Self.run(source)?.stringValue
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                self.apply(result, player: player)
                if self.refreshAgain {
                    self.refreshAgain = false
                    self.refresh()
                }
            }
        }
    }

    private static func stateScript(_ name: String) -> String {
        """
        tell application "\(name)"
            if player state is stopped then return ""
            set s to "0"
            if player state is playing then set s to "1"
            set n to ""
            set a to ""
            set al to ""
            set p to 0
            set d to 0
            try
                set n to name of current track
            end try
            try
                set a to artist of current track
            end try
            try
                set al to album of current track
            end try
            try
                set p to player position
            end try
            try
                set d to duration of current track
            end try
            return s & linefeed & n & linefeed & a & linefeed & al & linefeed & (p as text) & linefeed & (d as text)
        end tell
        """
    }

    private func apply(_ result: String?, player: (name: String, bundleID: String)) {
        guard let result, !result.isEmpty else {
            clear()
            return
        }
        let parts = result.components(separatedBy: "\n")
        guard parts.count >= 6 else { return }
        var duration = Self.number(parts[5])
        if player.name == "Spotify" { duration /= 1000 }   // Spotify reports milliseconds
        let new = Track(
            player: player.name,
            bundleID: player.bundleID,
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            isPlaying: parts[0] == "1",
            position: Self.number(parts[4]),
            duration: duration,
            fetchedAt: Date()
        )
        // Same song, same state and the position where we expected it: nothing to redraw.
        if let old = track, old.key == new.key, old.isPlaying == new.isPlaying, old.duration == new.duration,
           abs(old.currentPosition(at: new.fetchedAt) - new.position) < 1.5 {
            return
        }
        let isNewSong = new.key != track?.key && track != nil && new.isPlaying
        track = new
        if new.key != artworkKey {
            artworkKey = new.key
            loadArtwork(for: new)
        }
        if isNewSong {
            // Give the artwork a moment to load before the island shows it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NotificationCenter.default.post(name: Self.trackChanged, object: nil)
            }
        }
    }

    private func clear() {
        if track != nil { track = nil }
        if artwork != nil { artwork = nil }
        artworkKey = nil
    }

    private func loadArtwork(for track: Track) {
        if artwork != nil { artwork = nil }
        let key = track.key
        if track.player == "Music" {
            let source = """
            tell application "Music"
                try
                    return data of artwork 1 of current track
                end try
                return ""
            end tell
            """
            Self.scriptQueue.async { [weak self] in
                guard let data = Self.run(source)?.data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { if self?.artworkKey == key { self?.artwork = image } }
            }
        } else if track.player == "Spotify" {
            Self.scriptQueue.async { [weak self] in
                guard let urlString = Self.run("tell application \"Spotify\" to return artwork url of current track")?.stringValue,
                      let url = URL(string: urlString) else { return }
                URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        if self?.artworkKey == key { self?.artwork = image }
                    }
                }.resume()
            }
        }
    }

    static let musicPlayers: [String: String] = ["com.spotify.client": "Spotify", "com.apple.Music": "Music"]

    /// The player name ("Spotify", "Music") for an app bundle, if it is a supported music app.
    static func playerName(for appURL: URL) -> String? {
        guard let id = Bundle(url: appURL)?.bundleIdentifier else { return nil }
        return musicPlayers[id]
    }

    /// Send a command to one specific player (launches it if needed).
    func command(_ command: String, player: String) {
        Self.scriptQueue.async { _ = Self.run("tell application \"\(player)\" to \(command)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    /// "playpause", "next track" or "previous track"
    func command(_ command: String) {
        guard let player = track?.player ?? runningPlayer()?.name else { return }
        Self.scriptQueue.async { _ = Self.run("tell application \"\(player)\" to \(command)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refresh() }
    }

    /// Used only by the screenshot tour.
    func debugSet(_ track: Track?, artwork: NSImage? = nil) {
        self.track = track
        self.artwork = artwork
        artworkKey = track?.key
    }

    func openMusic() {
        let url = URL(fileURLWithPath: "/System/Applications/Music.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        return error == nil ? output : nil
    }

    /// AppleScript prints numbers with the user's locale (e.g. "12,5").
    static func number(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}
