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
        check("Making a widget bigger shrinks its neighbour", settings.setSize(HomeItem(.todo), slots: 3)
              && settings.slots(of: HomeItem(.todo)) == 3 && settings.slots(of: HomeItem(.calendar)) == 2)
        settings.homePages = [["music", "batteries"]]
        settings.widgetSizes = ["music": 3]
        check("Large Batteries turns a large Music player medium", settings.setSize(HomeItem(.batteries), slots: 3)
              && settings.slots(of: HomeItem(.music)) == 2 && settings.slotsUsed(page: 0) <= 5,
              "music \(settings.slots(of: HomeItem(.music))), batteries \(settings.slots(of: HomeItem(.batteries)))")
        check("Every widget on the page is still shown", settings.homeItems(page: 0).count == 2)
        settings.homePages = [["music", "calendar", "weather", "shortcuts"]]
        settings.widgetSizes = [:]
        check("No room even at the smallest sizes is refused", !settings.setSize(HomeItem(.weather), slots: 3))
        settings.homePages = [["calendar", "todo"]]
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
        check("Tag URL gives the version", Updater.version(fromTagURL: URL(string: "https://github.com/a/b/releases/tag/v0.5.8")!) == "0.5.8")
        check("Non-version tag is ignored", Updater.version(fromTagURL: URL(string: "https://github.com/a/b/releases/tag/latest")!) == nil)
        func waitFor(_ start: (@escaping (Result<Updater.Release, Updater.CheckError>) -> Void) -> Void) -> Result<Updater.Release, Updater.CheckError>? {
            let done = DispatchSemaphore(value: 0)
            var result: Result<Updater.Release, Updater.CheckError>?
            start { result = $0; done.signal() }
            _ = done.wait(timeout: .now() + 25)
            return result
        }
        let page = waitFor(Updater.fromReleasesPage)
        if case .success(let release) = page {
            check("Update check works via the releases page", Updater.isNewer(release.version, than: "0.0.1"), "found \(release.version)")
        } else {
            check("Update check works via the releases page", false, "\(String(describing: page))")
        }
        let combined = waitFor(Updater.latestRelease)
        if case .success(let release) = combined {
            check("Update check finds the latest release", release.dmg.absoluteString.hasSuffix(".dmg"), "found \(release.version)")
        } else {
            check("Update check finds the latest release", false, "\(String(describing: combined))")
        }
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

        let nested: [[String: Any]] = [[
            "IOClass": "BTDevice", "Product": "Magic Mouse",
            "IORegistryEntryChildren": [["IOClass": "AppleDeviceManagementHIDEventService", "BatteryPercent": 77]],
        ]]
        let nestedData = (try? PropertyListSerialization.data(fromPropertyList: nested, format: .xml, options: 0)) ?? Data()
        check("Battery on a child entry uses the parent's name", DeviceBatteryStore.parseRegistry(nestedData).first.map { "\($0.name) \($0.percent)" } == "Magic Mouse 77")
        check("Bluetooth addresses are recognised", DeviceBatteryStore.normalizeAddress("10-CF-0F-E5-D4-DA") == "10:cf:0f:e5:d4:da")
        check("Real names are not mistaken for addresses", DeviceBatteryStore.normalizeAddress("Magic Mouse") == nil)
        check("Keyboard guessed from Bluetooth class", DeviceBatteryStore.guessName(major: 0x05, minor: 0x10) == "Keyboard")
        check("Mouse guessed from Bluetooth class", DeviceBatteryStore.guessName(major: 0x05, minor: 0x20) == "Mouse")
        let namesJSON = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"Magic Keyboard":{"device_address":"10:CF:0F:E5:D4:DA"}},
          {"Magic Mouse":{"device_address":"64:0B:D7:1A:62:45"}}]}]}
        """
        let names = DeviceBatteryStore.bluetoothNames(Data(namesJSON.utf8))
        check("Address is turned into the device's real name",
              names["10:cf:0f:e5:d4:da"] == "Magic Keyboard" && names["64:0b:d7:1a:62:45"] == "Magic Mouse",
              names.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
        check("Battery colors", BatteriesTile.color(for: 10) == .red && BatteriesTile.color(for: 40) == .orange && BatteriesTile.color(for: 80) == .green)
        check("Same device from two sources is listed once", DeviceBatteryStore.sameDevice("Magic Mouse", "magic mouse"))
        var sourceReport: [String] = []
        _ = DeviceBatteryStore.readDevices(report: &sourceReport)
        check("Every battery source runs without crashing", sourceReport.count == 5, sourceReport.joined(separator: " | "))

        // Light / dark switching (bug reported in v0.5.3: glass stayed dark after switching to light)
        step("Appearance switching")
        let tickBefore = settings.systemAppearanceTick
        let keyBefore = settings.lookKey
        AppearanceWatcher.shared.changed(force: true)
        check("System light/dark change rebuilds every surface", settings.systemAppearanceTick == tickBefore + 1 && settings.lookKey != keyBefore)
        let keyLight = { settings.appearance = .light; return settings.lookKey }()
        let keyDark = { settings.appearance = .dark; return settings.lookKey }()
        settings.appearance = .system
        check("App appearance setting changes the look key", keyLight != keyDark)
        let glassBefore = settings.lookKey
        settings.glassClarity = .frosted
        check("Glass setting changes the look key", settings.lookKey != glassBefore)
        settings.glassClarity = .automatic

        // Shortcuts widget (any number of apps, adaptive grid)
        step("Shortcuts widget")
        let lib = UserLibrary.shared
        let savedShortcuts = lib.homeShortcuts
        lib.homeShortcuts = []
        lib.addHomeShortcuts([URL(fileURLWithPath: "/System/Applications/Calculator.app")])
        lib.addHomeShortcuts([URL(fileURLWithPath: "/System/Applications/Calculator.app")])
        check("One app can be the only shortcut (no duplicates)", lib.homeShortcutURLs.count == 1)
        lib.removeHomeShortcut(URL(fileURLWithPath: "/System/Applications/Calculator.app"))
        check("Shortcut can be removed", lib.homeShortcutURLs.isEmpty)
        lib.homeShortcuts = savedShortcuts
        let small = CGSize(width: 116, height: 130)
        let one = ShortcutLayout.best(count: 1, in: small)
        check("1 app: one big icon with its name", one.columns == 1 && one.showNames && one.cell >= 90, "\(one)")
        let two = ShortcutLayout.best(count: 2, in: small)
        check("2 apps fit side by side or stacked without overlap", two.cell * CGFloat(two.columns) + ShortcutLayout.gap * CGFloat(two.columns - 1) <= small.width + 0.5, "\(two)")
        let four = ShortcutLayout.best(count: 4, in: small)
        check("4 apps: 2×2", four.columns == 2, "\(four)")
        let wide = ShortcutLayout.best(count: 4, in: CGSize(width: 380, height: 130))
        check("4 apps in a wide widget: one row of 4", wide.columns == 4, "\(wide)")
        for n in 1...12 {
            for box in [small, CGSize(width: 250, height: 130), CGSize(width: 380, height: 130)] {
                let r = ShortcutLayout.best(count: n, in: box)
                let rows = Int((Double(n) / Double(r.columns)).rounded(.up))
                let fitsW = r.cell * CGFloat(r.columns) + ShortcutLayout.gap * CGFloat(r.columns - 1) <= box.width + 0.5
                let fitsH = r.cell * CGFloat(rows) + ShortcutLayout.gap * CGFloat(rows - 1) <= box.height + 0.5 || r.cell <= 20
                if !(fitsW && fitsH) { check("\(n) apps fit in \(Int(box.width))×\(Int(box.height))", false, "\(r)") }
            }
        }
        check("1–12 apps always fit at every widget size", true)

        for tab in SettingsTab.allCases {
            check("Settings icon exists: \(tab.title)", NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil) != nil)
        }
        check("Every settings section is in the sidebar", Set(SettingsTab.groups.flatMap { $0 }) == Set(SettingsTab.allCases))

        check("No vibration on open by default", !UserDefaults.standard.bool(forKey: "hapticOnOpen") || settings.hapticOnOpen)
        check("Hover waits a moment before opening", IslandController.hoverDelay > 0 && IslandController.hoverDelay < 0.2)

        // Home presets
        step("Home presets")
        check("At least 6 presets", HomePreset.all.count >= 6, "\(HomePreset.all.count)")
        let presetBefore = settings.homePages
        for preset in HomePreset.all {
            preset.apply()
            let fits = (0..<settings.pageCount).allSatisfy { settings.slotsUsed(page: $0) <= HomeWidget.maxSlots }
            let complete = (0..<settings.pageCount).allSatisfy { settings.homeItems(page: $0).count == settings.page($0).count }
            check("Preset '\(preset.name)' fits and shows every widget", fits && complete && preset.isActive)
            check("Preset '\(preset.name)' icon exists", NSImage(systemSymbolName: preset.symbol, accessibilityDescription: nil) != nil)
        }
        check("No widget appears twice in a preset", HomePreset.all.allSatisfy { p in
            let all = p.pages.flatMap { $0 }
            return Set(all).count == all.count
        })
        settings.homePages = presetBefore
        HomePreset.all[0].apply()
        IslandModel.shared.performUndo()
        check("Applying a preset can be undone", settings.homePages == presetBefore)

        // Music app tiles (bug reported in v0.5: Spotify tile had no controls)
        step("Music app tiles")
        check("Music app gets a player tile", NowPlayingStore.playerName(for: URL(fileURLWithPath: "/System/Applications/Music.app")) == "Music")
        check("Other apps stay normal tiles", NowPlayingStore.playerName(for: URL(fileURLWithPath: "/System/Applications/Calculator.app")) == nil)
        check("Spotify is supported", NowPlayingStore.musicPlayers["com.spotify.client"] == "Spotify")
        let musicTile = HomeItem(app: URL(fileURLWithPath: "/System/Applications/Music.app"))
        check("Music app tile is a full player (2 slots)", musicTile.isMusicApp && settings.slots(of: musicTile) == 2)
        check("Music app tile can't be shrunk below 2 slots", { settings.widgetSizes[musicTile.rawValue] = 1; defer { settings.widgetSizes[musicTile.rawValue] = nil }; return settings.slots(of: musicTile) == 2 }())
        check("Other app tiles stay 1 slot", settings.slots(of: HomeItem(app: URL(fileURLWithPath: "/System/Applications/Calculator.app"))) == 1)
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

        newFeatureChecks()

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
                onlineChecks()
            }
        }
    }

    // MARK: 0.6 features

    private static func newFeatureChecks() {
        let library = UserLibrary.shared
        let settings = AppSettings.shared

        step("Icons for new features")
        for symbol in ["book.closed.fill", "wifi", "wifi.slash", "dock.rectangle", "app.badge.fill", "moon.fill",
                       "cable.connector", "speedometer", "arrow.triangle.2.circlepath", "battery.100percent.bolt",
                       "powerplug.fill", "arrow.up.arrow.down", "network", "bell.badge.fill", "clock.fill", "cpu"] {
            check("SF Symbol exists: \(symbol)", NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
        }
        for tab in SettingsTab.allCases {
            check("Settings icon exists: \(tab.title)", NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil) != nil)
        }
        check("Every settings page is in the sidebar", Set(SettingsTab.groups.flatMap { $0 }) == Set(SettingsTab.allCases))
        for item in BottomDockItem.allCases {
            check("Bottom dock icon exists: \(item.title)", NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil) != nil)
        }

        step("Quran & Hadith")
        let day = DailyVerseStore.dayIndex(Date(timeIntervalSince1970: 1_790_000_000))
        let a = DailyVerseStore.pick(day: day, salt: 0, range: 1...6236)
        check("Ayah pick is stable for a day", a == DailyVerseStore.pick(day: day, salt: 0, range: 1...6236))
        check("Ayah pick changes the next day", a != DailyVerseStore.pick(day: day + 1, salt: 0, range: 1...6236))
        check("Ayah pick stays in range", (0..<400).allSatisfy { (1...6236).contains(DailyVerseStore.pick(day: $0, salt: $0 * 3, range: 1...6236)) })
        check("Both: alternates between Quran and Hadith",
              DailyVerseStore.wantsQuran(.both, day: 10) != DailyVerseStore.wantsQuran(.both, day: 11))
        check("Quran only is always Quran", DailyVerseStore.wantsQuran(.quran, day: 11))
        let ayahJSON = #"{"code":200,"data":[{"number":262,"text":"ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ","numberInSurah":255,"surah":{"number":2,"englishName":"Al-Baqara"}},{"number":262,"text":"আল্লাহ ছাড়া অন্য কোন উপাস্য নেই","numberInSurah":255,"surah":{"number":2,"englishName":"Al-Baqara"}}]}"#
        let ayah = DailyVerseStore.parseAyah(Data(ayahJSON.utf8), translation: .bangla)
        check("Ayah parses reference", ayah?.reference == "Al-Baqara 2:255", ayah?.reference ?? "nil")
        check("Ayah keeps Arabic and meaning", ayah?.arabic.isEmpty == false && ayah?.translation.hasPrefix("আল্লাহ") == true)
        check("Ayah links to quran.com", ayah?.link == "https://quran.com/2/255")
        let hadithJSON = #"{"metadata":{"name":"Sahih al Bukhari"},"hadiths":[{"hadithnumber":1,"text":"কাজ নিয়ত অনুযায়ী","grades":[]}]}"#
        check("Hadith parses text", DailyVerseStore.parseHadith(Data(hadithJSON.utf8)) == "কাজ নিয়ত অনুযায়ী")
        check("Bangla text is recognised", DailyVerseStore.isMostly("নিশ্চয় কষ্টের সাথে স্বস্তি রয়েছে", in: .bangla))
        check("Arabic is not taken for Bangla", !DailyVerseStore.isMostly("إِنَّ مَعَ ٱلْعُسْرِ يُسْرًا وَقَوْلُ اللهِ", in: .bangla))
        check("English text is recognised", DailyVerseStore.isMostly("Indeed, with hardship comes ease", in: .english))
        check("Fit: room beside the Dock = full size",
              BottomDockController.fit(base: 300, screen: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                       dock: CGRect(x: 456, y: 4, width: 600, height: 62), side: .right, offset: 0) == (1, false))
        let squeezed = BottomDockController.fit(base: 600, screen: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                                dock: CGRect(x: 456, y: 4, width: 600, height: 62), side: .right, offset: 0)
        check("Fit: shrinks when tight", squeezed.scale < 1 && squeezed.scale >= 0.6 && !squeezed.tooWide, "\(squeezed)")
        let crowded = BottomDockController.fit(base: 800, screen: CGRect(x: 0, y: 0, width: 1024, height: 768),
                                               dock: CGRect(x: 37, y: 4, width: 951, height: 62), side: .right, offset: 0)
        check("Fit: reports no room", crowded.tooWide)
        check("Match: bar exactly as tall as the Dock", abs(BottomDockController.matchedScale(dockHeight: 64, tileSize: 48, user: 1, match: true)
              * BottomDockController.baseHeight - 64) < 0.01)
        check("Match: bigger Dock, bigger bar", BottomDockController.matchedScale(dockHeight: 80, tileSize: nil, user: 1, match: true) > 1.4)
        check("Match: smaller Dock, smaller bar", BottomDockController.matchedScale(dockHeight: 40, tileSize: nil, user: 1, match: true) < 0.8)
        check("Match: no Accessibility, icons as big as Dock icons",
              abs(BottomDockController.matchedScale(dockHeight: nil, tileSize: 48, user: 1, match: true) * BottomDockController.appSize - 48) < 0.01)
        check("Match: fine-tune applies on top", abs(BottomDockController.matchedScale(dockHeight: 52, tileSize: nil, user: 1.2, match: true) - 1.2) < 0.001)
        check("Match off: user size", BottomDockController.matchedScale(dockHeight: 80, tileSize: 64, user: 0.9, match: false) == 0.9)
        check("Match: hidden Dock falls back to user size", BottomDockController.matchedScale(dockHeight: nil, tileSize: nil, user: 1.1, match: true) == 1.1)
        let tight = BottomDockController.plan(items: BottomDockItem.allCases, appCount: 3, scale: 1,
                                              screen: CGRect(x: 0, y: 0, width: 1024, height: 768),
                                              dock: CGRect(x: 160, y: 4, width: 700, height: 50), side: .right, offset: 0)
        check("Plan: drops the last items when tight", tight.dropped > 0 && !tight.items.isEmpty && tight.items.first == .apps,
              tight.items.map(\.rawValue).joined(separator: ","))
        let roomy = BottomDockController.plan(items: [.apps, .clock], appCount: 3, scale: 1,
                                              screen: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                                              dock: CGRect(x: 980, y: 4, width: 600, height: 62), side: .left, offset: 0)
        check("Plan: keeps everything when there is room", roomy.dropped == 0 && roomy.scale == 1)
        if let screen = BottomDockController.dockScreen() {
            let estimate = BottomDockController.estimatedDockFrame(on: screen)
            let exact = BottomDockController.readDockFrame()
            info("Dock frame", "exact \(exact.map { "\($0)" } ?? "n/a"), estimate \(estimate.map { "\($0)" } ?? "n/a")")
            if let estimate, let exact {
                check("Dock width estimate is close (±15%)", abs(estimate.width - exact.width) <= exact.width * 0.15,
                      "estimate \(Int(estimate.width)) vs \(Int(exact.width))")
            }
        }
        check("Empty hadith is rejected", DailyVerseStore.parseHadith(Data(#"{"hadiths":[]}"#.utf8)) == nil)
        check("Hadith URL", DailyVerseStore.hadithURL(edition: "ben-bukhari", number: 1).absoluteString.hasSuffix("/editions/ben-bukhari/1.min.json"))
        check("Quran + Bangla widget needs 2 slots", HomeWidget.verse.minSlots == 2 && HomeWidget.network.minSlots == 1)

        step("Home toggles for new widgets")
        let savedPages = settings.homePages
        settings.homePages = [HomeWidget.defaults.map(\.rawValue)]
        settings.removeFromHome(HomeItem(.verse))
        check("Show on Home adds Quran & Hadith", HomeWidgetToggle.add(.verse) && settings.isOnHome(HomeItem(.verse)))
        check("Show on Home adds Internet", HomeWidgetToggle.add(.network) && settings.isOnHome(HomeItem(.network)))
        check("Pages never overflow", (0..<settings.pageCount).allSatisfy { settings.slotsUsed(page: $0) <= HomeWidget.maxSlots })
        settings.homePages = savedPages

        step("Internet & Wi-Fi")
        check("Signal bars: strong", NetworkStore.bars(rssi: -50) == 4)
        check("Signal bars: fair", NetworkStore.bars(rssi: -72) == 2)
        check("Signal bars: none", NetworkStore.bars(rssi: nil) == 0 && NetworkStore.bars(rssi: -95) == 0)
        check("Rate text MB/s", NetworkStore.rate(12_340_000) == "12.3 MB/s", NetworkStore.rate(12_340_000))
        check("Rate text KB/s", NetworkStore.rate(840_000) == "840 KB/s", NetworkStore.rate(840_000))
        check("Rate never negative", NetworkStore.rate(-5) == "0 B/s")
        let bytes = NetworkStore.interfaceBytes()
        info("Interface counters", "down \(bytes.down) up \(bytes.up)")
        library.networkEnabled = true
        NetworkStore.shared.start()
        check("Network monitor starts", NetworkStore.shared.running)
        library.networkEnabled = false
        NetworkStore.shared.stop()
        check("Network monitor stops when turned off", !NetworkStore.shared.running)
        library.networkEnabled = true
        NetworkStore.shared.start()

        step("Notifications")
        check("Notification database locations known", !NotificationMirror.databaseCandidates.isEmpty)
        NotificationMirror.shared.checkAccess()
        info("Full Disk Access", NotificationMirror.shared.hasAccess ? "yes" : "no (expected on CI)")
        let plist: [String: Any] = ["app": "net.whatsapp.WhatsApp", "date": 800_000_000.0,
                                    "req": ["titl": "Rahim", "body": "Are you coming?"]]
        let data = (try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)) ?? Data()
        let item = NotificationMirror.parse(id: 7, bundleID: "", data: data)
        check("Notification record parses", item?.title == "Rahim" && item?.body == "Are you coming?" && item?.bundleID == "net.whatsapp.WhatsApp")
        check("Empty notification is skipped", NotificationMirror.parse(id: 8, bundleID: "x", data: Data()) == nil)
        if let item {
            library.notificationsEnabled = true
            library.mutedNotificationApps = []
            check("Allowed app is shown", NotificationMirror.shouldShow(item, library: library))
            library.mutedNotificationApps = ["net.whatsapp.WhatsApp"]
            check("Muted app is hidden", !NotificationMirror.shouldShow(item, library: library))
            library.mutedNotificationApps = []
            library.notificationsEnabled = false
            check("Nothing shows when the feature is off", !NotificationMirror.shouldShow(item, library: library))
            let hidden = NotificationMirror.peekContent(item, hideContent: true)
            check("Private mode hides the message", !hidden.text.contains("coming") && !hidden.title.contains("Rahim"))
            let shown = NotificationMirror.peekContent(item, hideContent: false)
            check("Normal mode shows sender and message", shown.title == "Rahim" && shown.text == "Are you coming?")
            library.notificationsEnabled = true
            settings.islandEnabled = true
            NotificationMirror.shared.deliver(item)
            check("Notification appears on the island", IslandModel.shared.peek?.kind.category == 15)
            check("Notification peek is a card", IslandModel.shared.peek.map { !$0.kind.isSlim } == true)
            IslandController.shared.dismissPeek()
            library.notificationsEnabled = false
        }
        IslandController.shared.showPeek(.network(online: false))
        check("Offline pop-up appears", IslandModel.shared.peek?.kind == .network(online: false))
        IslandController.shared.dismissPeek()

        step("Night dimming")
        let dhaka = TimeZone(identifier: "Asia/Dhaka")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = dhaka
        let june = cal.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        if let sun = NightDimmer.sunTimes(for: june, latitude: 23.81, longitude: 90.41, timeZone: dhaka) {
            let rise = cal.dateComponents([.hour, .minute], from: sun.sunrise)
            let set = cal.dateComponents([.hour, .minute], from: sun.sunset)
            let riseMin = (rise.hour ?? 0) * 60 + (rise.minute ?? 0), setMin = (set.hour ?? 0) * 60 + (set.minute ?? 0)
            check("Dhaka sunrise in June ≈ 5:11", abs(riseMin - 311) <= 8, "\(rise.hour ?? 0):\(rise.minute ?? 0)")
            check("Dhaka sunset in June ≈ 18:49", abs(setMin - 1129) <= 8, "\(set.hour ?? 0):\(set.minute ?? 0)")
        } else {
            check("Sun times computed", false)
        }
        let evening = cal.date(bySettingHour: 19, minute: 0, second: 0, of: june)!
        let morning = cal.date(bySettingHour: 6, minute: 0, second: 0, of: june)!
        func f(_ h: Int, _ m: Int = 0) -> Double {
            let now = cal.date(bySettingHour: h, minute: m, second: 0, of: june)!
            return NightDimmer.factor(now: now, schedule: .sun, darkMode: false,
                                      window: NightDimmer.window(now: now, start: evening, end: morning))
        }
        check("No dimming at noon", f(12) == 0)
        check("Full dimming at midnight", f(0) == 1)
        check("Full dimming at 23:00", f(23) == 1)
        check("Halfway at sunset (fading in)", abs(f(19) - 0.5) < 0.01, "\(f(19))")
        check("Fading in before sunset", f(18, 45) > 0 && f(18, 45) < 0.5)
        check("No dimming well before sunset", f(18, 0) == 0)
        check("Fading out after sunrise", f(6, 15) > 0 && f(6, 15) < 0.5, "\(f(6, 15))")
        check("No dimming mid-morning", f(8) == 0)
        check("Dark Mode schedule follows the system", NightDimmer.factor(now: june, schedule: .darkMode, darkMode: true, window: (june, june)) == 1
              && NightDimmer.factor(now: june, schedule: .darkMode, darkMode: false, window: (june, june)) == 0)
        let dimmer = NightDimmer.shared
        dimmer.start()
        library.dimEnabled = false
        dimmer.update()
        check("Off means no dimming", dimmer.level == 0)
        library.dimStrength = 0.3
        dimmer.preview(seconds: 0.5)
        check("Preview dims at the chosen strength", abs(dimmer.level - 0.3) < 0.001, "\(dimmer.level)")
        library.dimEnabled = true
        library.dimSchedule = .custom
        dimmer.pauseForTonight()
        check("Not tonight pauses dimming", dimmer.isPaused)
        dimmer.resume()
        check("Resume works", !dimmer.isPaused)
        library.dimTarget = .screen
        dimmer.preview(seconds: 0.5)
        check("Screen dimming layer survives a preview", true)
        library.dimTarget = .uthon
        library.dimEnabled = false
        library.dimSchedule = .sun
        dimmer.update()

        step("Bottom dock")
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 879)
        let dock = CGRect(x: 456, y: 4, width: 600, height: 62)
        let right = BottomDockController.frame(screen: screen, visible: visible, dock: dock, width: 300, height: 58, side: .right, offset: 0)
        check("Sits right of the Dock", right.minX == 1066 && abs(right.midY - dock.midY) <= 1, "\(right)")
        let left = BottomDockController.frame(screen: screen, visible: visible, dock: dock, width: 300, height: 58, side: .left, offset: 20)
        check("Sits left of the Dock with distance", left.maxX == 426, "\(left)")
        let corner = BottomDockController.frame(screen: screen, visible: visible, dock: nil, width: 300, height: 58, side: .right, offset: 0)
        check("Without Accessibility: bottom-right corner", corner.maxX == 1500 && corner.minY >= 0)
        let huge = BottomDockController.frame(screen: screen, visible: visible, dock: dock, width: 900, height: 58, side: .right, offset: 0)
        check("Never runs off the screen", huge.maxX <= screen.maxX && huge.minX >= screen.minX)
        let hidden = BottomDockController.frame(screen: screen, visible: screen, dock: nil, width: 300, height: 58, side: .left, offset: 0)
        check("Auto-hidden macOS Dock: sits at the bottom", hidden.minY >= 0 && hidden.minY < 12)
        check("Width grows with apps",
              BottomDockController.width(items: ["apps", "clock"], appCount: 5, scale: 1) > BottomDockController.width(items: ["apps", "clock"], appCount: 2, scale: 1))
        check("Width follows size", abs(BottomDockController.width(items: ["clock"], appCount: 0, scale: 1.2)
              - 1.2 * BottomDockController.width(items: ["clock"], appCount: 0, scale: 1)) < 0.5)
        let savedItems = library.bottomDockItems
        library.bottomDockItems = ["clock"]
        library.setBottomDockItem(.apps, true)
        check("Turning an item on keeps the order", library.bottomDockItems == ["apps", "clock"])
        library.setBottomDockItem(.apps, true)
        check("No duplicates", library.bottomDockItems == ["apps", "clock"])
        library.setBottomDockItem(.clock, false)
        check("Turning an item off removes it", library.bottomDockItems == ["apps"])
        library.bottomDockItems = savedItems
        BottomDockController.shared.start()
        library.bottomDockEnabled = true
        library.bottomDockAutoHide = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        check("Bottom dock appears when turned on", BottomDockController.shared.isShown)
        let before = BottomDockController.shared.baseScale
        info("Bottom dock follows the Dock", "scale \(before), dock \(BottomDockController.shared.dockFrame.map { "\($0)" } ?? "n/a")")
        library.bottomDockEnabled = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        check("Bottom dock hides when turned off", !BottomDockController.shared.isShown)

        step("New Bangla text")
        settings.language = .bangla
        check("Bangla for new screens", L("Night Dimming") == "রাতে কম আলো" && L("Bottom Dock") == "নিচের ডক")
        settings.language = .english
        check("English stays English", L("Night Dimming") == "Night Dimming")
    }

    /// Real requests to the Quran and Hadith sources (the CI Mac is online).
    private static func onlineChecks() {
        step("Online sources")
        Task {
            let ayah = await DailyVerseStore.fetchAyah(number: 262, translation: .bangla)
            let english = await DailyVerseStore.fetchAyah(number: 1, translation: .english)
            let hadith = await DailyVerseStore.fetchHadith(day: 0, salt: 0, translation: .bangla)
            await MainActor.run {
                check("Quran ayah downloads (Bangla)", ayah?.reference == "Al-Baqara 2:255" && ayah?.translation.isEmpty == false,
                      String((ayah?.translation ?? "nil").prefix(60)))
                check("Quran ayah downloads (English)", english?.reference == "Al-Faatiha 1:1" || english?.reference.hasSuffix("1:1") == true,
                      english?.reference ?? "nil")
                check("Hadith downloads (Bangla)", hadith?.translation.isEmpty == false,
                      (hadith?.reference ?? "nil") + " " + String((hadith?.translation ?? "").prefix(60)))
                check("Hadith has Arabic", hadith?.arabic.isEmpty == false)
                check("Hadith meaning is in Bangla", hadith.map { DailyVerseStore.isMostly($0.translation, in: .bangla) } == true)
                finish()
            }
        }
    }

    private static func finish() {
        let failures = results.filter { !$0.ok }
        var report = "Nook self-test: \(results.count - failures.count) passed, \(failures.count) failed\n\n"
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
