import AppKit
import EventKit

/// Functional self-test. Launch with `--self-test <report.txt>`: exercises the logic of
/// every feature on a real Mac, writes a PASS/FAIL report and exits with 1 on any failure.
/// Run by the "Visual QA" CI workflow after every change.
enum SelfTest {
    static var isActive: Bool { CommandLine.arguments.contains("--self-test") }

    private static var results: [(name: String, ok: Bool, note: String)] = []

    private static func check(_ name: String, _ ok: Bool, _ note: String = "") {
        results.append((name, ok, note))
    }

    private static func info(_ name: String, _ note: String) {
        results.append((name, true, "info: " + note))
    }

    static func run() {
        let settings = AppSettings.shared

        // Timer
        let timers = TimerStore.shared
        timers.cancelTimer()
        timers.startTimer(minutes: 2)
        check("Timer starts at 2:00", timers.timerActive && abs(timers.remaining(at: Date()) - 120) < 1.5)
        timers.pauseTimer()
        check("Timer pauses", timers.timerPaused)
        timers.addMinute()
        check("Timer +1 min while paused", abs(timers.remaining(at: Date()) - 180) < 2)
        timers.resumeTimer()
        check("Timer resumes", timers.timerActive && !timers.timerPaused)
        check("Timer progress near 0 at start", timers.progress(at: Date()) < 0.05)
        timers.cancelTimer()
        check("Timer cancels", !timers.timerActive)
        check("Format 65 s = 1:05", TimerStore.format(65) == "1:05", TimerStore.format(65))
        check("Format 3725 s = 1:02:05", TimerStore.format(3725) == "1:02:05", TimerStore.format(3725))
        check("Format tenths 5.37 = 0:05.3", TimerStore.format(5.37, tenths: true) == "0:05.3", TimerStore.format(5.37, tenths: true))

        // Stopwatch
        timers.resetStopwatch()
        timers.toggleStopwatch()
        check("Stopwatch starts", timers.stopwatchRunning)
        timers.lap()
        check("Stopwatch records a lap", timers.laps.count == 1)
        timers.toggleStopwatch()
        check("Stopwatch pauses and keeps time", !timers.stopwatchRunning && timers.stopwatchUsed)
        timers.resetStopwatch()
        check("Stopwatch resets", !timers.stopwatchUsed && timers.laps.isEmpty)

        // To-do
        let todo = TodoStore.shared
        let before = todo.items.count
        todo.add("   ")
        check("Empty to-do is ignored", todo.items.count == before)
        todo.add("Self-test task")
        if let item = todo.items.last, item.text == "Self-test task" {
            todo.toggle(item.id)
            check("To-do can be ticked", todo.items.last?.done == true)
            todo.clearDone()
            check("Clear done removes ticked items", !todo.items.contains { $0.id == item.id })
        } else {
            check("To-do is added", false)
        }

        // Shelf and shortcuts
        let shelf = ShelfStore.shared
        shelf.clear()
        let calc = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        shelf.add([calc, calc])
        check("Shelf ignores duplicates", shelf.paths.count == 1)
        shelf.remove(calc.path)
        check("Shelf removes items", shelf.paths.isEmpty)
        let shortcuts = ShortcutsStore.shared
        let count = shortcuts.paths.count
        shortcuts.add([calc])
        shortcuts.add([calc])
        check("Shortcuts ignore duplicates", shortcuts.paths.filter { $0 == calc.path }.count == 1)
        if count < shortcuts.paths.count { shortcuts.remove(calc.path) }

        // Home widgets (5 slots, music = 2)
        settings.enabledHomeWidgets = Set(HomeWidget.defaults.map(\.rawValue))
        check("Default Home uses 5 slots", settings.homeSlotsUsed == 5, "\(settings.homeSlotsUsed)")
        check("Full Home refuses another widget", !settings.canEnable(.system))
        settings.setHomeWidget(.system, true)
        check("Adding to a full Home does nothing", !settings.enabledHomeWidgets.contains(HomeWidget.system.rawValue))
        settings.setHomeWidget(.weather, false)
        check("Removing frees a slot", settings.canEnable(.system))
        settings.setHomeWidget(.system, true)
        check("Widget added after freeing room", settings.homeWidgets.contains(.system))
        let firstTwo = Array(settings.orderedHomeWidgets.prefix(2))
        if firstTwo.count == 2 {
            settings.placeHomeWidget(firstTwo[1], at: firstTwo[0])
            check("Drag reorder swaps Home widgets", settings.orderedHomeWidgets.first == firstTwo[1])
            settings.placeHomeWidget(firstTwo[0], at: firstTwo[1])
        }
        settings.enabledHomeWidgets = Set(HomeWidget.defaults.map(\.rawValue))
        check("Home order lists every widget", Set(settings.orderedHomeWidgets) == Set(HomeWidget.allCases))

        // Controls
        settings.enabledControls = Set(ControlKind.allCases.prefix(8).map(\.rawValue))
        check("Controls cap at 8", settings.controls.count == 8 && !settings.canEnableControl(.screenRecording))
        settings.enabledControls = Set(ControlKind.defaults.map(\.rawValue))
        check("Default controls", settings.controls == ControlKind.defaults)

        // Tabs
        let tabsBefore = settings.orderedIslandTabs
        settings.moveTab(.notes, by: -1)
        check("Tabs can be reordered", settings.orderedIslandTabs != tabsBefore)
        settings.islandTabOrder = tabsBefore.map(\.rawValue)
        settings.setTabVisible(.home, false)
        check("Home tab can't be hidden", settings.visibleIslandTabs.contains(.home))
        settings.hiddenIslandTabs = []

        // Island geometry
        let model = IslandModel.shared
        settings.islandScale = 1.2
        check("Island size setting scales the island",
              abs(model.expandedSize.width - model.baseExpandedSize.width * 1.2) < 0.5)
        settings.islandScale = 1.0
        check("Island fits a 1280-wide screen", model.expandedSize.width <= 1280)

        // Pop-ups
        let kinds: [PeekKind] = [.volume(level: 0, muted: false), .brightness(level: 0), .capsLock(true), .charging(percent: 1),
                                 .headphones(name: "", symbol: "", levels: nil), .track, .download(calc),
                                 .meeting(title: "", start: Date(), link: nil), .lowBattery(name: "", percent: 1),
                                 .timerDone, .screenshot(calc)]
        check("Every pop-up type is distinct", Set(kinds.map(\.category)).count == kinds.count)

        // Parsing and mapping
        check("AppleScript number '12,5' = 12.5", NowPlayingStore.number("12,5") == 12.5)
        check("AppleScript number '215.0' = 215", NowPlayingStore.number("215.0") == 215)
        check("Weather: clear day is sunny", WeatherStore.symbol(code: 0, isDay: true) == "sun.max.fill")
        check("Weather: thunderstorm", WeatherStore.symbol(code: 95, isDay: true) == "cloud.bolt.rain.fill")
        check("AirPods Pro icon", DeviceBatteryStore.headphoneSymbol(for: "Rahim's AirPods Pro") == "airpodspro")
        check("Magic Mouse icon", DeviceBatteryStore.symbol(for: "Magic Mouse") == "magicmouse.fill")
        for symbol in ["airpodspro", "magicmouse.fill", "cloud.bolt.rain.fill", "brain.head.profile", "eyedropper.halffull",
                       "menubar.dock.rectangle", "capslock.fill", "speaker.wave.3.fill", "rectangle.3.group.fill"] {
            check("SF Symbol exists: \(symbol)", NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
        }
        for kind in ControlKind.allCases {
            check("Control icon exists: \(kind.title)", NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil) != nil)
        }
        for widget in HomeWidget.allCases {
            check("Widget icon exists: \(widget.title)", NSImage(systemSymbolName: widget.symbol, accessibilityDescription: nil) != nil)
        }
        for tab in IslandTab.allCases {
            check("Tab icon exists: \(tab.title)", NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil) != nil)
        }

        // Search
        let found = AppSearch.shared.search("safa")
        check("Search finds Safari", found.first?.name == "Safari", found.map(\.name).joined(separator: ", "))
        check("Search finds Calculator", AppSearch.shared.search("calc").contains { $0.name == "Calculator" })
        check("Web search URL is encoded", AppSearch.webSearchURL("a b&c")?.absoluteString.contains("a%20b%26c") == true,
              AppSearch.webSearchURL("a b&c")?.absoluteString ?? "nil")

        // Calendar helpers
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Family call"
        event.notes = "Join here: https://zoom.us/j/123456"
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(1800)
        check("Meeting link found in notes", event.meetingLink?.host == "zoom.us", event.meetingLink?.absoluteString ?? "nil")
        event.isAllDay = true
        check("All-day event text", event.uthonTimeText == "All day", event.uthonTimeText)

        // System services
        let actions = QuickActions.shared
        actions.toggleKeepAwake()
        check("Keep Awake turns on", actions.keepAwake)
        actions.toggleKeepAwake()
        check("Keep Awake turns off", !actions.keepAwake)
        settings.hotkeyEnabled = true
        HotKey.shared.update()
        check("⌃⌥Space shortcut registers", HotKey.shared.isRegistered)
        check("Mac battery detection runs", true, DeviceBatteryStore.internalBattery() == nil ? "no battery (desktop)" : "has battery")
        BrightnessController.shared.start()
        info("Built-in display brightness", BrightnessController.shared.isAvailable ? "available" : "not available on this Mac")
        AudioController.shared.start()
        let original = AudioController.shared.volume
        AudioController.shared.setVolume(0.3)
        let readBack = AudioController.shared.volume
        if readBack == 0 && original == 0 {
            info("Volume control", "this machine has no adjustable output")
        } else {
            check("Volume can be set and read", abs(readBack - 0.3) < 0.05, "read \(readBack)")
            AudioController.shared.setVolume(original)
        }

        // Clipboard history (async: the store polls the pasteboard)
        let clipboard = ClipboardStore.shared
        clipboard.clear()
        clipboard.start()
        let board = NSPasteboard.general
        board.clearContents()
        board.setString("uthon self-test clip", forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            check("Clipboard history records copied text", clipboard.items.first?.text == "uthon self-test clip")
            board.clearContents()
            board.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
            board.setString("secret-password", forType: .string)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                check("Clipboard skips passwords", !clipboard.items.contains { $0.text == "secret-password" })
                finish()
            }
        }
    }

    private static func finish() {
        let failures = results.filter { !$0.ok }
        var report = "Uthon self-test: \(results.count - failures.count) passed, \(failures.count) failed\n\n"
        for r in results {
            report += "\(r.ok ? "PASS" : "FAIL")  \(r.name)\(r.note.isEmpty ? "" : "  [\(r.note)]")\n"
        }
        print(report)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--self-test"), i + 1 < args.count {
            try? report.write(toFile: args[i + 1], atomically: true, encoding: .utf8)
        }
        exit(failures.isEmpty ? 0 : 1)
    }
}
