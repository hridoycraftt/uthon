import AppKit
import SwiftUI
import EventKit

/// Functional self-test. Launch with `--self-test <report.txt>`: exercises the logic of
/// every feature on a real Mac, writes a PASS/FAIL report and exits with 1 on any failure.
/// Run by the "Visual QA" CI workflow after every change.
enum SelfTest {
    static var isActive: Bool { CommandLine.arguments.contains("--self-test") }

    private static var results: [(name: String, ok: Bool, note: String)] = []

    private static func check(_ name: String, _ ok: Bool, _ note: String = "") {
        results.append((name, ok, note))
        progress("\(ok ? "PASS" : "FAIL")  \(name)\(note.isEmpty ? "" : "  [\(note)]")")
    }

    /// Written line by line so that, if the app ever crashes, we know exactly where.
    private static func progress(_ line: String) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--self-test"), i + 1 < args.count else { return }
        let path = args[i + 1] + ".progress"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write((line + "\n").data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? (line + "\n").write(toFile: path, atomically: false, encoding: .utf8)
        }
    }

    /// Mark the start of a group of steps (shows where a crash happened).
    private static func step(_ name: String) {
        progress("--> \(name)")
    }

    private static func info(_ name: String, _ note: String) {
        results.append((name, true, "info: " + note))
    }

    static func run() {
        let settings = AppSettings.shared
        MenuTracker.shared.start()
        IslandController.shared.start()

        // Timer
        step("Timer")
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
        step("Stopwatch")
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
        step("To-do")
        let todo = TodoStore.shared
        todo.source = .uthon
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
        step("Shelf and shortcuts")
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

        // Home: pages, slots, sizes, colors, apps, folders
        step("Home: pages, slots, sizes, colors, apps, folders")
        settings.homePages = [HomeWidget.defaults.map(\.rawValue)]
        settings.widgetSizes = [:]
        settings.widgetColors = [:]
        check("Default Home uses 5 slots", settings.slotsUsed(page: 0) == 5, "\(settings.slotsUsed(page: 0))")
        check("Full page refuses another widget", !settings.canAdd(HomeItem(.system), page: 0))
        check("Adding to a full page does nothing", !settings.addToHome(HomeItem(.system), page: 0))
        settings.removeFromHome(HomeItem(.weather))
        check("Removing frees a slot", settings.canAdd(HomeItem(.system), page: 0))
        settings.addToHome(HomeItem(.system), page: 0)
        check("Widget added after freeing room", settings.homeItems(page: 0).contains(HomeItem(.system)))
        check("A widget can't be on Home twice", !settings.canAdd(HomeItem(.system), page: 0))
        let firstTwo = Array(settings.homeItems(page: 0).prefix(2))
        if firstTwo.count == 2 {
            settings.placeHomeItem(firstTwo[1], at: firstTwo[0])
            check("Drag reorder swaps Home widgets", settings.homeItems(page: 0).first == firstTwo[1])
        }
        settings.homePages = [HomeWidget.defaults.map(\.rawValue)]
        settings.setPageCount(3)
        check("Up to 3 pages", settings.pageCount == 3)
        check("Widgets can go on page 2", settings.addToHome(HomeItem(.worldClock), page: 1) && settings.pageOf(HomeItem(.worldClock)) == 1)
        settings.setPageCount(5)
        check("Never more than 3 pages", settings.pageCount == 3)
        settings.setPageCount(1)
        check("Removing pages keeps what fits", settings.pageCount == 1)
        settings.homePages = [["calendar", "todo"]]
        check("Widget can be made large", settings.setSize(HomeItem(.calendar), slots: 3) && settings.slots(of: HomeItem(.calendar)) == 3)
        check("Too big for the page is refused", !settings.setSize(HomeItem(.todo), slots: 3))
        check("Music is never smaller than 2", { settings.widgetSizes["music"] = 1; return settings.slots(of: HomeItem(.music)) == 2 }())
        settings.setColor(.ocean, for: HomeItem(.calendar))
        check("Widget color is saved", settings.color(of: HomeItem(.calendar)) == .ocean)
        settings.setColor(nil, for: HomeItem(.calendar))
        check("Widget color can be reset", settings.color(of: HomeItem(.calendar)) == nil)
        settings.widgetSizes = [:]
        let calcApp = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        check("An app can be added to Home", settings.addHomeApp(calcApp, page: 0))
        check("App tile title", settings.homeItems(page: 0).first { $0.appURL != nil }?.title == "Calculator")
        settings.removeFromHome(HomeItem(app: calcApp))
        check("Removing an app takes it off Home", !settings.isOnHome(HomeItem(app: calcApp)))
        check("A missing app is ignored", HomeItem(rawValue: "app:/Applications/Does Not Exist.app") == nil)
        let folder = settings.createFolder(name: "Tools", apps: [calcApp, URL(fileURLWithPath: "/System/Applications/Notes.app")], page: 0)
        check("Folder is created on Home", settings.isOnHome(HomeItem(folder: folder)) && HomeItem(folder: folder).title == "Tools")
        check("Folder keeps its apps", folder.urls.count == 2)
        settings.deleteFolder(folder)
        check("Folder can be deleted", !settings.isOnHome(HomeItem(folder: folder)) && !settings.appFolders.contains(folder))
        check("Apps on this Mac are listed", AppSearch.shared.allApps.count > 10, "\(AppSearch.shared.allApps.count) apps")
        check("Every built-in widget is offered", Set(HomeItem.allCases.compactMap(\.widget)) == Set(HomeWidget.allCases))

        // Undo
        step("Undo")
        settings.homePages = [HomeWidget.defaults.map(\.rawValue)]
        IslandModel.shared.registerUndo("Removed Weather")
        settings.removeFromHome(HomeItem(.weather))
        IslandModel.shared.performUndo()
        check("Undo brings a removed widget back", settings.isOnHome(HomeItem(.weather)))

        // Profiles and presets
        step("Profiles and presets")
        for preset in Profiles.presets {
            Profiles.apply(preset)
            let fits = (0..<settings.pageCount).allSatisfy { page in
                settings.page(page).compactMap(HomeItem.init(rawValue:)).reduce(0) { $0 + settings.slots(of: $1) } <= HomeWidget.maxSlots
            }
            check("Preset '\(preset.name)' fits on its pages", fits)
            check("Preset '\(preset.name)' applies its theme", settings.themeColor.rawValue == preset.theme)
        }
        let saved = Profiles.saveCurrent(as: "Self-test")
        Profiles.apply(Profiles.presets[0])
        Profiles.apply(saved)
        check("Saved profile restores its layout", settings.homePages == saved.homePages)
        Profiles.delete(saved)
        check("Profile can be deleted", !UserLibrary.shared.profiles.contains(saved))
        settings.homePages = [HomeWidget.defaults.map(\.rawValue)]
        settings.themeColor = .terracotta

        // Language
        step("Language")
        settings.language = .bangla
        check("Bangla interface translates", L("Home") == "হোম" && L("Prayer Times") == "নামাজের সময়")
        check("Unknown text stays as is", L("Rahim's AirPods") == "Rahim's AirPods")
        settings.language = .english
        check("English interface", L("Home") == "Home")
        settings.language = .system

        // Themes
        step("Themes")
        for theme in ThemeColor.allCases {
            settings.themeColor = theme
            check("Theme '\(theme.title)' gives a color", NSColor(Theme.accent).usingColorSpace(.sRGB) != nil)
        }
        settings.customAccentHex = "#3366CC"
        check("Custom hex color round-trips", Color(hex: "#3366CC")?.hexString == "#3366CC", Color(hex: "#3366CC")?.hexString ?? "nil")
        settings.themeColor = .terracotta

        // Prayer times (Dhaka, a day in March)
        step("Prayer times (Dhaka, a day in March)")
        var march = DateComponents()
        march.year = 2026; march.month = 3; march.day = 21; march.hour = 12
        let dhaka = TimeZone(identifier: "Asia/Dhaka")!
        var dhakaCal = Calendar(identifier: .gregorian)
        dhakaCal.timeZone = dhaka
        if let day = dhakaCal.date(from: march),
           let t = PrayerTimes.compute(for: day, latitude: 23.81, longitude: 90.41, timeZone: dhaka, method: .karachi, hanafi: true) {
            let f = DateFormatter()
            f.timeZone = dhaka
            f.dateFormat = "HH:mm"
            let hour = { (d: Date) in Double(dhakaCal.component(.hour, from: d)) + Double(dhakaCal.component(.minute, from: d)) / 60 }
            let note = t.all.map { "\($0.name) \(f.string(from: $0.time))" }.joined(separator: ", ")
            check("Prayer times are in order", t.fajr < t.sunrise && t.sunrise < t.dhuhr && t.dhuhr < t.asr && t.asr < t.maghrib && t.maghrib < t.isha, note)
            check("Dhaka Fajr about 4:40", abs(hour(t.fajr) - 4.67) < 0.35, note)
            check("Dhaka Dhuhr about 12:05", abs(hour(t.dhuhr) - 12.1) < 0.3, note)
            check("Dhaka Maghrib about 6:10 pm", abs(hour(t.maghrib) - 18.15) < 0.3, note)
        } else {
            check("Prayer times calculate", false)
        }

        // Special days, bookmarks, updates
        step("Special days, bookmarks, updates")
        let inThree = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        check("Special day countdown", SpecialDay(name: "Test", date: inThree).daysLeft() == 3)
        let lastYear = Calendar.current.date(byAdding: .year, value: -5, to: Date())!
        check("Yearly day counts today", SpecialDay(name: "Birthday", date: lastYear).daysLeft() == 0)
        check("Bookmark without https still opens", Bookmark(title: "x", url: "example.com").link?.absoluteString == "https://example.com")
        check("Version 0.10.0 is newer than 0.9.5", Updater.isNewer("0.10.0", than: "0.9.5"))
        check("Same version is not newer", !Updater.isNewer("0.5.0", than: "0.5.0"))
        check("Older version is not newer", !Updater.isNewer("0.4.9", than: "0.5.0"))
        check("Gradient wallpaper renders", WallpaperChanger.shared.makeGradient(index: 2) != nil)

        // The reported crash path: Edit -> + Add Widget (island grows) -> close, repeated.
        step("The reported crash path: Edit -> + Add Widget (island grows) -> close, repeated.")
        for _ in 0..<5 {
            IslandController.shared.expand(tab: .home)
            IslandModel.shared.editing = true
            IslandModel.shared.pickerOpen = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            IslandModel.shared.pickerOpen = false
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            IslandController.shared.collapse()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        }
        check("Edit → Add Widget → close five times without crashing", true)

        // Scrolling and gestures (bugs reported in v0.5)
        step("Scrolling and gestures")
        typealias SC = IslandController.ScrollContext
        let base = SC(expanded: true, tab: .home, editing: false, pickerOpen: false, scrollVolume: true,
                      swipe: .pages, pageCount: 2, hasTrack: true)
        check("Home: scroll changes volume", IslandController.scrollPolicy(base, horizontal: false) == .volume)
        var c = base; c.scrollVolume = false
        check("Volume scrolling can be turned off", IslandController.scrollPolicy(c, horizontal: false) == .pass)
        c = base; c.editing = true
        check("Editing: scroll is left to the lists", IslandController.scrollPolicy(c, horizontal: false) == .pass
              && IslandController.scrollPolicy(c, horizontal: true) == .pass)
        c = base; c.pickerOpen = true
        check("Widget gallery: scroll is left to the gallery", IslandController.scrollPolicy(c, horizontal: false) == .pass)
        c = base; c.tab = .clipboard
        check("Other tabs: scroll is left to their lists", IslandController.scrollPolicy(c, horizontal: false) == .pass)
        check("Swipe changes page", IslandController.scrollPolicy(base, horizontal: true) == .page)
        c = base; c.pageCount = 1
        check("One page: swipe changes song", IslandController.scrollPolicy(c, horizontal: true) == .song)
        c = base; c.swipe = .off
        check("Swipe can be turned off", IslandController.scrollPolicy(c, horizontal: true) == .pass)
        c = base; c.swipe = .songs
        check("Swipe can change songs", IslandController.scrollPolicy(c, horizontal: true) == .song)
        var tracker = IslandController.SwipeTracker()
        let t0 = Date()
        var fired: [Int] = []
        for i in 0..<20 { fired.append(tracker.add(-4, at: t0.addingTimeInterval(Double(i) * 0.01), gestureBegan: i == 0)) }
        check("Small swipe steps add up to one page change", fired.filter { $0 != 0 } == [1], "\(fired.filter { $0 != 0 })")
        let late = tracker.add(-40, at: t0.addingTimeInterval(1.0), gestureBegan: true)
        check("A new swipe works again", late == 1)
        check("Gallery is tall enough for two full rows", IslandModel.galleryHeight >= 280)

        // Batteries (bug reported in v0.5: only "50%" without a name)
        step("Batteries")
        let registry: [[String: Any]] = [
            ["Product": "Magic Keyboard with Touch ID", "BatteryPercent": 82, "IOClass": "AppleDeviceManagementHIDEventService"],
            ["Product": "Magic Mouse", "BatteryPercent": 9, "IOClass": "AppleDeviceManagementHIDEventService"],
            ["Product": "Battery", "BatteryPercent": 50, "IOClass": "AppleSmartBattery"],
            ["BatteryPercent": 50, "IOClass": "Unknown"],
        ]
        let plist = (try? PropertyListSerialization.data(fromPropertyList: registry, format: .xml, options: 0)) ?? Data()
        let parsed = DeviceBatteryStore.parseRegistry(plist)
        check("Keyboard and mouse are found with names", parsed.map(\.name) == ["Magic Keyboard with Touch ID", "Magic Mouse"],
              parsed.map { "\($0.name) \($0.percent)%" }.joined(separator: ", "))
        check("Nameless and Mac batteries are not listed as devices", !parsed.contains { $0.percent == 50 })
        let bluetoothJSON = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"Rahim's AirPods Pro":{"device_batteryLevelLeft":"80%","device_batteryLevelRight":"74%","device_batteryLevelCase":"40%"}},
          {"Magic Trackpad":{"device_batteryLevelMain":"63%"}}],
          "device_not_connected":[{"Old Speaker":{"device_batteryLevelMain":"10%"}}]}]}
        """
        let bt = DeviceBatteryStore.parseBluetooth(Data(bluetoothJSON.utf8))
        check("AirPods battery found (lowest earbud)", bt.contains { $0.name == "Rahim's AirPods Pro" && $0.percent == 74 })
        check("Trackpad battery found", bt.contains { $0.name == "Magic Trackpad" && $0.percent == 63 })
        check("Disconnected devices are not shown", !bt.contains { $0.name == "Old Speaker" })
        check("Keyboard icon", DeviceBatteryStore.symbol(for: "Magic Keyboard with Touch ID") == "keyboard.fill")
        check("Unknown device gets a battery icon (not headphones)", DeviceBatteryStore.symbol(for: "Some Gadget") == "battery.75percent")
        check("Short names", DeviceBatteryStore.shortName(for: "Magic Keyboard with Touch ID") == "Keyboard")
        let live = DeviceBatteryStore.readDevices()
        info("Devices on this Mac", live.isEmpty ? "none connected" : live.map { "\($0.name) \($0.percent)%" }.joined(separator: ", "))

        // Music app tiles (bug reported in v0.5: Spotify tile had no controls)
        step("Music app tiles")
        check("Music app gets a player tile", NowPlayingStore.playerName(for: URL(fileURLWithPath: "/System/Applications/Music.app")) == "Music")
        check("Other apps stay normal tiles", NowPlayingStore.playerName(for: URL(fileURLWithPath: "/System/Applications/Calculator.app")) == nil)
        check("Spotify is supported", NowPlayingStore.musicPlayers["com.spotify.client"] == "Spotify")
        for symbol in ["battery.100percent.bolt", "gamecontroller.fill", "applepencil", "battery.75percent"] {
            check("SF Symbol exists: \(symbol)", NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
        }

        // Crash guard: the island must not close while a menu is open
        step("Crash guard: the island must not close while a menu is open")
        IslandController.shared.expand(tab: .home)
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        IslandController.shared.collapse()
        check("Island stays open while a menu is open", IslandModel.shared.expanded)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
        IslandModel.shared.editing = true
        IslandModel.shared.pickerOpen = true
        IslandController.shared.collapse()
        check("Island closes after the menu", !IslandModel.shared.expanded)
        check("Closing ends editing and the gallery", !IslandModel.shared.editing && !IslandModel.shared.pickerOpen)

        // Controls
        step("Controls")
        settings.enabledControls = Set(ControlKind.allCases.prefix(8).map(\.rawValue))
        check("Controls cap at 8", settings.controls.count == 8 && !settings.canEnableControl(.screenRecording))
        settings.enabledControls = Set(ControlKind.defaults.map(\.rawValue))
        check("Default controls", settings.controls == ControlKind.defaults)

        // Tabs
        step("Tabs")
        let tabsBefore = settings.orderedIslandTabs
        settings.moveTab(.notes, by: -1)
        check("Tabs can be reordered", settings.orderedIslandTabs != tabsBefore)
        settings.islandTabOrder = tabsBefore.map(\.rawValue)
        settings.setTabVisible(.home, false)
        check("Home tab can't be hidden", settings.visibleIslandTabs.contains(.home))
        settings.hiddenIslandTabs = []

        // Island geometry
        step("Island geometry")
        let model = IslandModel.shared
        settings.islandScale = 1.2
        check("Island size setting scales the island",
              abs(model.expandedSize.width - model.baseExpandedSize.width * 1.2) < 0.5)
        settings.islandScale = 1.0
        check("Island fits a 1280-wide screen", model.expandedSize.width <= 1280)

        // Pop-ups
        step("Pop-ups")
        let kinds: [PeekKind] = [.volume(level: 0, muted: false), .brightness(level: 0), .capsLock(true), .charging(percent: 1),
                                 .headphones(name: "", symbol: "", levels: nil), .track, .download(calc),
                                 .meeting(title: "", start: Date(), link: nil), .lowBattery(name: "", percent: 1),
                                 .timerDone, .screenshot(calc), .update(version: "1"), .prayer(name: "Fajr", time: Date()),
                                 .specialDay(name: "", symbol: "gift.fill")]
        check("Every pop-up type is distinct", Set(kinds.map(\.category)).count == kinds.count)

        // Parsing and mapping
        step("Parsing and mapping")
        check("AppleScript number '12,5' = 12.5", NowPlayingStore.number("12,5") == 12.5)
        check("AppleScript number '215.0' = 215", NowPlayingStore.number("215.0") == 215)
        check("Weather: clear day is sunny", WeatherStore.symbol(code: 0, isDay: true) == "sun.max.fill")
        check("Weather: thunderstorm", WeatherStore.symbol(code: 95, isDay: true) == "cloud.bolt.rain.fill")
        check("AirPods Pro icon", DeviceBatteryStore.headphoneSymbol(for: "Rahim's AirPods Pro") == "airpodspro")
        check("Magic Mouse icon", DeviceBatteryStore.symbol(for: "Magic Mouse") == "magicmouse.fill")
        for symbol in ["globe.asia.australia.fill", "moon.stars.fill", "gift.fill", "bookmark.fill", "folder.fill",
                       "arrow.down.app.fill", "arrow.uturn.backward.circle.fill", "paintpalette", "puzzlepiece.extension",
                       "person.2.crop.square.stack", "folder.badge.plus", "airpodspro", "magicmouse.fill", "cloud.bolt.rain.fill", "brain.head.profile", "eyedropper.halffull",
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
        step("Search")
        let found = AppSearch.shared.search("safa")
        check("Search finds Safari", found.first?.name == "Safari", found.map(\.name).joined(separator: ", "))
        check("Search finds Calculator", AppSearch.shared.search("calc").contains { $0.name == "Calculator" })
        check("Web search URL is encoded", AppSearch.webSearchURL("a b&c")?.absoluteString.contains("a%20b%26c") == true,
              AppSearch.webSearchURL("a b&c")?.absoluteString ?? "nil")

        // Calendar helpers
        step("Calendar helpers")
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
        step("System services")
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
        step("Clipboard history (async: the store polls the pasteboard)")
        let clipboard = ClipboardStore.shared
        clipboard.start()
        clipboard.debugAdd("pin me")
        if let item = clipboard.items.first(where: { $0.text == "pin me" }) {
            clipboard.togglePin(item)
            check("Clipboard item can be pinned", UserLibrary.shared.pinnedClips.contains("pin me"))
            clipboard.clear()
            check("Clear keeps pinned items", clipboard.items.contains { $0.text == "pin me" })
            if let pinned = clipboard.items.first(where: { $0.text == "pin me" }) { clipboard.remove(pinned) }
            check("Pinned item can be removed", !UserLibrary.shared.pinnedClips.contains("pin me"))
        }
        clipboard.clear()
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
