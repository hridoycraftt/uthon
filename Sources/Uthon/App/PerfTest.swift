import AppKit
import QuartzCore

/// Performance check. Launch with `--perf-test <folder>`: the whole app runs as usual while
/// the island idles, opens, closes and switches tabs (with and without the live wallpaper).
/// For each phase it records how much CPU Nook used, how smoothly the main thread kept up
/// with the display (late frames = visible stutter) and a `sample` profile of where the time
/// went. Run by the "Visual QA" CI workflow.
enum PerfTest {
    static var isActive: Bool { CommandLine.arguments.contains("--perf-test") }

    static var folder: URL {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--perf-test"), i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1])
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nook-perf")
    }

    private struct Phase {
        let name: String
        let seconds: Double
        let setup: () -> Void
        /// Called every `every` seconds during the phase (to keep the island busy).
        var every: Double = 0
        var tick: ((Int) -> Void)?
    }

    private static var report: [String] = []
    private static var frameTimes: [CFTimeInterval] = []
    private static var link: CADisplayLink?
    private static var linkTarget = LinkTarget()

    private final class LinkTarget: NSObject {
        @objc func frame(_ link: CADisplayLink) { PerfTest.frameTimes.append(link.timestamp) }
    }

    static func run() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for w in NSApp.windows where w.title.contains("Welcome") || w.identifier?.rawValue == "onboarding" { w.orderOut(nil) }
        let settings = AppSettings.shared
        let library = UserLibrary.shared
        settings.islandEnabled = true
        settings.hotkeyEnabled = false
        library.liveEnabled = false
        let island = IslandController.shared
        let tabs = settings.visibleIslandTabs

        let phases: [Phase] = [
            Phase(name: "idle-closed", seconds: 6, setup: { island.collapse() }),
            Phase(name: "open-home", seconds: 6, setup: { island.expand(tab: .home, sticky: true) }),
            Phase(name: "open-close", seconds: 7, setup: { island.collapse() }, every: 0.7, tick: { i in
                if i % 2 == 0 { island.expand(tab: .home, sticky: true) } else { island.collapse() }
            }),
            Phase(name: "tab-switch", seconds: 7, setup: { island.expand(tab: .home, sticky: true) }, every: 0.6, tick: { i in
                IslandModel.shared.tab = tabs[i % max(tabs.count, 1)]
            }),
            Phase(name: "wallpaper-idle", seconds: 6, setup: {
                island.collapse()
                library.livePauseCovered = false
                library.livePauseOnBattery = false
                library.liveStyle = LiveStyle.aurora.rawValue
                library.liveMode = LiveMode.live.rawValue
                library.liveEnabled = true
                LiveWallpaper.shared.start()
            }),
            Phase(name: "wallpaper-open-close", seconds: 7, setup: { island.collapse() }, every: 0.7, tick: { i in
                if i % 2 == 0 { island.expand(tab: .home, sticky: true) } else { island.collapse() }
            }),
        ]

        if let screen = NSScreen.main {
            let l = screen.displayLink(target: linkTarget, selector: #selector(LinkTarget.frame(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        report.append("Nook performance (\(NSScreen.main.map { "\(Int($0.frame.width))x\(Int($0.frame.height)) @\($0.backingScaleFactor)x" } ?? "?"))")
        report.append("phase".padding(toLength: 22, withPad: " ", startingAt: 0) + "   cpu %   frames     late   worst ms")
        runPhase(phases, index: 0)
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    }

    private static func runPhase(_ phases: [Phase], index: Int) {
        guard index < phases.count else { finish(); return }
        let phase = phases[index]
        phase.setup()
        // Let the setup settle, then measure.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            frameTimes = []
            let cpu0 = cpuSeconds()
            let t0 = CACurrentMediaTime()
            startSample(phase.name, seconds: max(2, Int(phase.seconds) - 2))
            var tickTimer: Timer?
            if let tick = phase.tick, phase.every > 0 {
                var i = 0
                let t = Timer(timeInterval: phase.every, repeats: true) { _ in tick(i); i += 1 }
                RunLoop.main.add(t, forMode: .common)
                tickTimer = t
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + phase.seconds) {
                tickTimer?.invalidate()
                let cpu = (cpuSeconds() - cpu0) / (CACurrentMediaTime() - t0) * 100
                let intervals = zip(frameTimes.dropFirst(), frameTimes).map { ($0 - $1) * 1000 }
                let typical = intervals.sorted().dropFirst(intervals.count / 2).first ?? 16.7
                let late = intervals.filter { $0 > typical * 1.8 }.count
                let worst = intervals.max() ?? 0
                report.append(phase.name.padding(toLength: 22, withPad: " ", startingAt: 0)
                              + String(format: " %8.1f %8d %8d %10.1f", cpu, intervals.count, late, worst))
                runPhase(phases, index: index + 1)
            }
        }
    }

    /// macOS's own profiler, pointed at this process.
    private static func startSample(_ name: String, seconds: Int) {
        // The profiler pauses the app to take each sample, so it is run separately from the
        // frame measurement ("--profile").
        guard CommandLine.arguments.contains("--profile") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        p.arguments = ["\(getpid())", "\(seconds)", "1", "-mayDie", "-file", folder.appendingPathComponent("sample-\(name).txt").path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    private static func finish() {
        link?.invalidate()
        UserLibrary.shared.liveEnabled = false
        let text = report.joined(separator: "\n") + "\n"
        print(text)
        let name = CommandLine.arguments.contains("--profile") ? "perf-report-profiled.txt" : "perf-report.txt"
        try? text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        // Give the last sample time to be written.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    }
}
