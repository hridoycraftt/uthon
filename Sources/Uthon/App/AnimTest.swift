import AppKit
import SwiftUI

/// Animation check. Launch with `--anim-test <folder>`: the island opens and closes a few
/// times while the screen is recorded as a video. Coloured markers (only in this mode) show
/// the centre of the island's glass (green) and of its content (red), so every frame can be
/// measured: both must stay on the same spot, the screen's centre, from the first frame on.
enum AnimTest {
    static var isActive: Bool { CommandLine.arguments.contains("--anim-test") }

    static var folder: URL {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--anim-test"), i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1])
        }
        return URL(fileURLWithPath: NSTemporaryDirectory())
    }

    static func run() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        IslandModel.shared.debugMarkers = true
        let settings = AppSettings.shared
        settings.islandEnabled = true
        settings.hotkeyEnabled = false
        if CommandLine.arguments.contains("--dark") { settings.appearance = .dark } else { settings.appearance = .light }
        let screen = NSScreen.screens.first?.frame ?? .zero
        let suffix = CommandLine.arguments.contains("--dark") ? "dark" : "light"
        info("screen \(screen.width)x\(screen.height) scale \(NSScreen.screens.first?.backingScaleFactor ?? 0) island scale \(IslandModel.scale)")

        // Record the top of the screen for 9 seconds.
        let video = folder.appendingPathComponent("anim-\(suffix).mov")
        try? FileManager.default.removeItem(at: video)
        let recorder = Process()
        recorder.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        recorder.arguments = ["-v", "-V", "9", "-x", "-R", "0,0,\(Int(screen.width)),400", video.path]
        do { try recorder.run() } catch { info("recorder failed: \(error)") }

        let controller = IslandController.shared
        let steps: [(Double, () -> Void)] = [
            (2.0, { info("open 1"); controller.expand(tab: .home, sticky: true) }),
            (3.4, { info("close 1"); controller.collapse() }),
            (4.6, { info("open 2"); controller.expand(tab: .home, sticky: true) }),
            (6.0, { info("close 2"); controller.collapse() }),
            (7.0, { info("open 3"); controller.expand(tab: .home, sticky: true) }),
            (11.5, { info("done"); exit(0) }),
        ]
        for (delay, action) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
        }
    }

    private static func info(_ line: String) {
        let stamp = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        print("anim-test \(stamp) \(line)")
        let log = folder.appendingPathComponent("anim-log.txt")
        let text = "\(stamp) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: log) {
            handle.seekToEndOfFile()
            handle.write(text.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? text.write(to: log, atomically: false, encoding: .utf8)
        }
    }
}
