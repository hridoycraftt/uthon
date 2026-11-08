import AppKit

/// Reads the current song from Music or Spotify via AppleScript.
/// (macOS asks once for permission to control these apps.)
final class NowPlayingStore: ObservableObject {
    static let shared = NowPlayingStore()

    struct Track: Equatable {
        var player: String
        var title: String
        var artist: String
        var isPlaying: Bool
    }

    @Published private(set) var track: Track?

    private static let players: [(name: String, bundleID: String)] = [
        ("Spotify", "com.spotify.client"),
        ("Music", "com.apple.Music"),
    ]
    private var timer: Timer?

    func setActive(_ active: Bool) {
        timer?.invalidate()
        timer = nil
        guard active else { return }
        refresh()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func runningPlayer() -> String? {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        return Self.players.first { ids.contains($0.bundleID) }?.name
    }

    func refresh() {
        guard let player = runningPlayer() else {
            if track != nil { track = nil }
            return
        }
        let source = """
        tell application "\(player)"
            if player state is stopped then return ""
            if player state is playing then
                set s to "1"
            else
                set s to "0"
            end if
            return s & linefeed & (name of current track) & linefeed & (artist of current track)
        end tell
        """
        guard let result = run(source), !result.isEmpty else {
            if track != nil { track = nil }
            return
        }
        let parts = result.components(separatedBy: "\n")
        guard parts.count >= 3 else { return }
        let new = Track(player: player, title: parts[1], artist: parts[2], isPlaying: parts[0] == "1")
        if new != track { track = new }
    }

    /// "playpause", "next track" or "previous track"
    func command(_ command: String) {
        guard let player = track?.player ?? runningPlayer() else { return }
        _ = run("tell application \"\(player)\" to \(command)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refresh() }
    }

    func openMusic() {
        let url = URL(fileURLWithPath: "/System/Applications/Music.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return output.stringValue
    }
}
