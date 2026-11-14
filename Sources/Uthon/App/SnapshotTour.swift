import AppKit
import SwiftUI

/// Visual QA. Launch with `--snapshot-tour <folder> [--dark]` and Nook renders every
/// island tab, pop-up, closed state and the side dock into PNGs, captures the live
/// screen a few times (real glass), then quits. Used by the "Visual QA" CI workflow.
enum SnapshotTour {
    static var isActive: Bool { CommandLine.arguments.contains("--snapshot-tour") }

    private static var dark: Bool { CommandLine.arguments.contains("--dark") }
    private static var suffix: String { dark ? "dark" : "light" }

    private static var folder: URL {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot-tour"), i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1])
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("uthon-shots")
    }

    private static var steps: [(String, @MainActor () -> Void)] = []

    @MainActor
    static func run() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let s = AppSettings.shared
        s.appearance = dark ? .dark : .light
        s.islandEnabled = true
        s.sideDockEnabled = true
        s.pinned = false
        s.hotkeyEnabled = false
        s.homePages = [HomeWidget.defaults.map(\.rawValue), ["bookmarks", "worldClock", "prayer", "countdown", "todo"],
                       ["app:/System/Applications/Music.app", "batteries", "system", "controls", "notes"]]
        s.weatherCity = "Dhaka"
        UserLibrary.shared.specialDays = [SpecialDay(name: "Ammu's birthday", date: Calendar.current.date(byAdding: .day, value: 12, to: Date())!)]
        seed()

        let model = IslandModel.shared

        // 1. Deterministic renders of every screen (layout check).
        for tab in IslandTab.allCases where tab != .mirror {
            add("tab-\(tab.rawValue)") {
                model.tab = tab
                render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-\(tab.rawValue)")
            }
        }
        add("home-page-2") {
            model.tab = .home
            model.homePage = 1
            render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-home-page2")
            model.homePage = 0
        }
        add("bangla") {
            s.language = .bangla
            s.themeColor = .ocean
            model.tab = .home
            render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-home-bangla")
            s.language = .system
            s.themeColor = .terracotta
        }
        add("edit-mode") {
            model.tab = .home
            model.editing = true
            render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-home-editing")
            model.tab = .controls
            render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-controls-editing")
            model.editing = false
        }
        add("gallery") {
            model.tab = .home
            model.editing = true
            model.pickerOpen = true
            render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-home-gallery")
        }
        add("live-gallery") {
            IslandController.shared.expand(tab: .home, sticky: true)
            model.editing = true
            model.pickerOpen = true
        }
        add("capture-gallery") {
            capture("screen-island-gallery")
            model.pickerOpen = false
            model.editing = false
        }
        add("live-presets") {
            IslandController.shared.expand(tab: .home, sticky: true)
            model.editing = true
            model.gallerySection = 2
            model.pickerOpen = true
        }
        add("capture-presets") {
            capture("screen-island-presets")
            model.pickerOpen = false
            model.gallerySection = 0
            model.editing = false
        }
        add("live-edit") {
            IslandController.shared.expand(tab: .home, sticky: true)
            model.editing = true
        }
        add("capture-edit") {
            capture("screen-island-editing")
            model.editing = false
            IslandController.shared.collapse()
        }
        add("home-new-widgets") {
            s.homePages[1] = ["verse", "network", "bookmarks", "countdown"]
            model.tab = .home
            model.homePage = 1
            render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-home-new-widgets")
            s.language = .bangla
            render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-home-new-widgets-bangla")
            s.language = .system
            s.setSize(HomeItem(.verse), slots: 3)
            render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-home-new-widgets-wide")
            s.widgetSizes = [:]
            model.homePage = 0
        }
        add("long-hadith") {
            let saved = DailyVerseStore.shared.current
            DailyVerseStore.shared.debugSet(DailyText(
                isQuran: false,
                arabic: "حَدَّثَنَا يُوسُفُ بْنُ مُوسَى، حَدَّثَنَا عَاصِمُ بْنُ يُوسُفَ الْيَرْبُوعِيُّ، حَدَّثَنَا أَبُو شِهَابٍ، عَنْ إِسْمَاعِيلَ بْنِ أَبِي خَالِدٍ، عَنْ قَيْسِ بْنِ أَبِي حَازِمٍ، عَنْ جَرِيرِ بْنِ عَبْدِ اللَّهِ، قَالَ قَالَ النَّبِيُّ صلى الله عليه وسلم ‏\"‏ إِنَّكُمْ سَتَرَوْنَ رَبَّكُمْ عِيَانًا ‏\"‏‏.‏",
                translation: "জারীর ইবনু ‘আবদুল্লাহ্ (রাঃ) হতে বর্ণিত। নবী সাল্লাল্লাহু আলাইহি ওয়াসাল্লাম বলেছেনঃ অবশ্যই তোমরা তোমাদের রবকে দিব্যচক্ষে দেখতে পাবে। [৫৫৪] (আধুনিক প্রকাশনী- ৬৯১৮, ইসলামিক ফাউন্ডেশন- ৬৯২৮)",
                reference: "Sahih al-Bukhari 7435", link: "https://sunnah.com/bukhari:7435",
                day: DailyVerseStore.dayKey(), translationKey: "bangla"))
            s.homePages[1] = ["batteries", "verse", "notes"]
            model.tab = .home
            model.homePage = 1
            render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-home-long-hadith")
            model.homePage = 0
            _ = saved
        }
        add("live-verse-reader") { VerseReader.show() }
        add("capture-verse-reader") {
            capture("screen-verse-reader")
            NSApp.windows.first { $0.title == L("Quran & Hadith") }?.orderOut(nil)
        }
        add("new-widgets-2") {
            UserLibrary.shared.notificationsEnabled = true
            for (i, who) in ["Ammu", "Ammu", "Rahim"].enumerated() {
                NotificationMirror.shared.deliver(.init(id: Int64(100 + i), bundleID: i < 2 ? "com.apple.MobileSMS" : "net.whatsapp.WhatsApp",
                                                        appName: i < 2 ? "Messages" : "WhatsApp", title: who, subtitle: "", body: "Hello", date: Date()))
            }
            IslandController.shared.dismissPeek()
            UserLibrary.shared.ramadanMode = "on"
            s.homePages[1] = ["digest", "ramadan", "weather", "notes"]
            s.setSize(HomeItem(.weather), slots: 2)
            model.tab = .home
            model.homePage = 1
            render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-home-ai-widgets")
            model.homePage = 0
            s.widgetSizes = [:]
            UserLibrary.shared.ramadanMode = "auto"
        }
        add("bottom-dock-render") {
            let lib = UserLibrary.shared
            lib.bottomDockItems = BottomDockItem.allCases.map(\.rawValue)
            let width = BottomDockController.width(items: lib.bottomDockItems, appCount: lib.bottomDockAppURLs.count, scale: 1)
            render(BottomDockView(forcedItems: BottomDockItem.allCases), size: CGSize(width: width, height: BottomDockController.baseHeight), shape: false, name: "bottom-dock")
            lib.bottomDockItems = ["apps", "clock", "music", "weather"]
        }
        add("controls-counts") {
            model.tab = .controls
            for count in [2, 3, 4, 6] {
                for kind in ControlKind.allCases { s.setControl(kind, false) }
                for kind in ControlKind.allCases.prefix(count) { s.setControl(kind, true) }
                render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-controls-\(count)")
            }
        }
        add("controls-full") {
            for kind in ControlKind.allCases where s.canEnableControl(kind) { s.setControl(kind, true) }
            model.tab = .controls
            render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-controls-full")
            s.language = .bangla
            render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "tab-controls-full-bangla")
            s.language = .system
            model.tab = .home
        }
        // A 14" MacBook with a notch and larger text (small screen, small island):
        // every tab and pop-up must fit with nothing cut off, in English and Bangla.
        add("small-notch") {
            let saved = (model.hasNotch, model.notchSize, model.screenSize)
            model.hasNotch = true
            model.notchSize = CGSize(width: 185, height: 32)
            model.screenSize = CGSize(width: 1147, height: 745)
            print("small-notch scale: \(IslandModel.scale), base \(model.baseExpandedSize)")
            for language in [AppLanguage.english, .bangla] {
                s.language = language
                let suffix = language == .bangla ? "-bn" : ""
                for tab in IslandTab.allCases where tab != .mirror {
                    model.tab = tab
                    render(ExpandedIsland(), size: model.baseExpandedSize, shape: true, name: "small-tab-\(tab.rawValue)\(suffix)")
                }
                for (name, kind) in [("volume", PeekKind.volume(level: 0.6, muted: false)), ("track", .track),
                                     ("notification", .notification(NotificationPeek(bundleID: "com.apple.MobileSMS", app: "Messages",
                                                                                      title: "Ammu", text: "Dinner is ready, come home soon!")))] {
                    render(PeekView(kind: kind), size: model.basePeekSize(kind), shape: true, name: "small-peek-\(name)\(suffix)")
                }
            }
            s.language = .system
            model.tab = .home
            (model.hasNotch, model.notchSize, model.screenSize) = saved
        }
        let peeks: [(String, PeekKind)] = [
            ("notification", .notification(NotificationPeek(bundleID: "com.apple.MobileSMS", app: "Messages", title: "Ammu",
                                                            text: "Dinner is ready, come home soon! Bring some sweets on the way."))),
            ("network-offline", .network(online: false)),
            ("update", .update(version: "0.6.15")),
            ("digest", .digest(count: 5, text: "Messages 3 (Ammu, Rahim) · WhatsApp 2 (Office group)")),
            ("smartclip", .smartClip(SmartClip(kind: .address, value: "Road 12, Dhanmondi, Dhaka", source: "Road 12, Dhanmondi, Dhaka"))),
            ("ramadan", .ramadan(isIftar: true, time: Date())),
            ("rain", .rain(minutes: 30)),
            ("verse", .verse(reference: "Ash-Sharh 94:6", text: "নিশ্চয় কষ্টের সাথে স্বস্তি রয়েছে।", isQuran: true)),
            ("volume", .volume(level: 0.62, muted: false)),
            ("brightness", .brightness(level: 0.4)),
            ("capslock", .capsLock(true)),
            ("charging", .charging(percent: 76)),
            ("airpods", .headphones(name: "Rahim's AirPods Pro", symbol: "airpodspro",
                                    levels: HeadphoneLevels(left: 80, right: 75, caseLevel: 40, single: nil))),
            ("track", .track),
            ("download", .download(URL(fileURLWithPath: "/System/Applications/Calculator.app"))),
            ("meeting", .meeting(title: "Family call", start: Date().addingTimeInterval(240), link: URL(string: "https://meet.google.com/abc"))),
            ("lowbattery", .lowBattery(name: "Magic Mouse", percent: 9)),
            ("timerdone", .timerDone),
        ]
        for (name, kind) in peeks {
            add("peek-\(name)") {
                render(PeekView(kind: kind), size: model.basePeekSize(kind), shape: true, name: "peek-\(name)")
            }
        }
        add("dock") {
            render(DockContentView(), size: CGSize(width: 300, height: 1400), shape: false, name: "dock")
        }

        // 2. Live captures of the real windows (shows the actual glass on this macOS).
        add("live-page2-open") {
            IslandController.shared.expand(tab: .home, sticky: true)
        }
        add("live-page2-switch") {
            // Same as tapping the second page dot.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.homePage = 1 }
        }
        add("capture-page2") {
            print("state before page-2 capture: homePage=\(model.homePage) pages=\(s.pageCount) expanded=\(model.expanded) tab=\(model.tab)")
            capture("screen-island-page2")
        }
        add("live-page3") { withAnimation { model.homePage = 2 } }
        add("capture-page3") { capture("screen-island-page3") }
        add("live-sizes") {
            s.homePages[2] = ["system", "batteries", "controls", "notes", "weather"]
            s.widgetSizes = [:]
        }
        add("capture-sizes-small") { capture("screen-sizes-small") }
        add("live-sizes-medium") {
            s.setSize(HomeItem(.system), slots: 2)
            s.setSize(HomeItem(.batteries), slots: 2)
        }
        add("capture-sizes-medium") { capture("screen-sizes-medium") }
        add("live-sizes-large") { s.setSize(HomeItem(.system), slots: 3) }
        add("capture-sizes-large") { capture("screen-sizes-large") }
        add("live-bangla") {
            model.homePage = 0
            s.language = .bangla
            s.themeColor = .ocean
        }
        add("capture-bangla") { capture("screen-island-bangla") }
        add("live-home") {
            s.language = .system
            s.themeColor = .terracotta
            IslandController.shared.expand(tab: .home, sticky: true)
        }
        add("capture-home") { capture("screen-island-home") }
        add("live-hijri-header") { UserLibrary.shared.hijriInHeader = true }
        add("capture-hijri-header") { capture("screen-island-hijri-header") }
        add("live-hijri-header-off") { UserLibrary.shared.hijriInHeader = false }
        add("capture-hijri-header-off") { capture("screen-island-hijri-header-off") }
        add("live-controls") { model.tab = .controls }
        add("capture-controls") { capture("screen-island-controls") }
        // Opening animation: frames taken while the island grows, to check it grows out of
        // the middle (the island's centre must stay on the screen's centre in every frame).
        add("live-anim-reset") {
            IslandController.shared.collapse()
            model.tab = .home
        }
        add("live-anim-open") {
            IslandController.shared.expand(tab: .home, sticky: true)
            for (i, delay) in [0.0, 0.05, 0.1, 0.15, 0.22, 0.3, 0.45].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { captureNow("anim-open-\(i)") }
            }
        }
        add("live-anim-close") {
            IslandController.shared.collapse()
            for (i, delay) in [0.0, 0.05, 0.1, 0.18, 0.3].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { captureNow("anim-close-\(i)") }
            }
        }
        add("live-peek") {
            IslandController.shared.collapse()
            IslandController.shared.showPeek(.volume(level: 0.5, muted: false), duration: 10)
        }
        add("capture-peek") { capture("screen-peek-volume") }
        add("live-dock") {
            IslandController.shared.dismissPeek()
            DockController.shared.show(sticky: true)
        }
        add("capture-dock") { capture("screen-dock") }
        add("live-settings") {
            DockController.shared.hide()
            SettingsWindowController.shared.show(tab: .island)
        }
        add("capture-settings") { capture("screen-settings") }
        add("live-settings-home") { SettingsWindowController.shared.show(tab: .home) }
        add("capture-settings-home") { capture("screen-settings-home") }
        add("live-settings-look") { SettingsWindowController.shared.show(tab: .look) }
        add("capture-settings-look") { capture("screen-settings-look") }
        add("live-settings-widgets") { SettingsWindowController.shared.show(tab: .widgets) }
        add("capture-settings-widgets") { capture("screen-settings-widgets") }
        for tab in [SettingsTab.verse, .network, .notifications, .night, .bottomDock, .ramadan, .dock] {
            add("live-settings-\(tab.rawValue)") { SettingsWindowController.shared.show(tab: tab) }
            add("capture-settings-\(tab.rawValue)") { capture("screen-settings-\(tab.rawValue)") }
        }
        add("live-bottom-dock") {
            SettingsWindowController.shared.hide()
            UserLibrary.shared.bottomDockEnabled = true
            UserLibrary.shared.bottomDockAutoHide = false
        }
        add("capture-bottom-dock") { capture("screen-bottom-dock") }
        // The bar follows the macOS Dock: make the Dock bigger, then smaller again.
        add("live-dock-bigger") { setDockTileSize(44) }
        add("live-dock-bigger-wait") { }
        add("capture-dock-bigger") {
            print("bottom dock scale with big Dock: \(BottomDockController.shared.baseScale)")
            capture("screen-bottom-dock-bigger")
        }
        add("live-dock-smaller") { setDockTileSize(30) }
        add("live-dock-smaller-wait") { }
        add("capture-dock-smaller") {
            print("bottom dock scale with small Dock: \(BottomDockController.shared.baseScale)")
            capture("screen-bottom-dock-smaller")
        }
        add("live-notification") {
            UserLibrary.shared.notificationsEnabled = true
            NotificationMirror.shared.deliver(.init(id: -1, bundleID: "com.apple.MobileSMS", appName: "Messages", title: "Ammu",
                                                    subtitle: "", body: "Dinner is ready, come home soon!", date: Date()))
        }
        add("capture-notification") { capture("screen-peek-notification") }
        add("live-night") {
            IslandController.shared.dismissPeek()
            UserLibrary.shared.dimTarget = .uthon
            UserLibrary.shared.dimStrength = 0.5
            NightDimmer.shared.start()
            NightDimmer.shared.preview(seconds: 6)
            IslandController.shared.expand(tab: .home, sticky: true)
        }
        add("capture-night") { capture("screen-night-dim") }
        add("live-wallpaper-sheet") { writeLiveSheet() }
        add("live-wallpaper-on") {
            IslandController.shared.collapse()
            let lib = UserLibrary.shared
            lib.livePauseCovered = false
            lib.livePauseOnBattery = false
            lib.liveMode = "live"
            lib.liveStyle = "aurora"
            lib.liveEnabled = true
            LiveWallpaper.shared.start()
        }
        add("capture-live-aurora") { capture("screen-live-aurora") }
        add("live-wallpaper-glass") {
            UserLibrary.shared.liveStyle = "glass"
            CGWarpMouseCursorPosition(CGPoint(x: 300, y: 450))
        }
        add("capture-live-glass") { capture("screen-live-glass") }
        add("live-wallpaper-crystal") { UserLibrary.shared.liveStyle = "crystal" }
        add("capture-live-crystal") { capture("screen-live-crystal") }
        add("live-wallpaper-settings") { SettingsWindowController.shared.show(tab: .wallpaper) }
        add("live-wallpaper-settings-wait") { }
        add("capture-live-settings") { capture("screen-settings-wallpaper") }
        add("live-wallpaper-off") {
            SettingsWindowController.shared.hide()
            UserLibrary.shared.liveEnabled = false
        }
        add("live-onboarding") {
            IslandController.shared.collapse()
            UserLibrary.shared.bottomDockEnabled = false
            OnboardingWindowController.shared.show()
        }
        add("capture-onboarding") { capture("screen-onboarding") }
        add("quit") { exit(0) }

        next(0)
    }

    private static func setDockTileSize(_ size: Int) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "defaults write com.apple.dock tilesize -int \(size); killall Dock"]
        try? p.run()
    }

    private static func add(_ name: String, _ action: @escaping @MainActor () -> Void) {
        steps.append((name, action))
    }

    @MainActor
    private static func next(_ index: Int) {
        guard index < steps.count else { exit(0) }
        let (name, action) = steps[index]
        print("snapshot step: \(name)")
        action()
        let delay: Double = name.hasPrefix("live") || name == "glass-lab" ? 1.6 : 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { next(index + 1) } }
    }

    private static func seed() {
        NowPlayingStore.shared.debugSet(NowPlayingStore.Track(
            player: "Music", bundleID: "com.apple.Music", title: "Tumi Robe Nirobe", artist: "Rabindranath Tagore",
            album: "Gitabitan", isPlaying: true, position: 74, duration: 215, fetchedAt: Date()
        ))
        ClipboardStore.shared.debugAdd("Meeting at 7pm with the whole family")
        ClipboardStore.shared.debugAdd("https://github.com/hridoycraftt/uthon")
        ClipboardStore.shared.debugAdd("Grocery: rice, lentils, eggs, milk, tea")
        if TodoStore.shared.items.isEmpty {
            TodoStore.shared.add("Pay electricity bill")
            TodoStore.shared.add("Call grandma")
            TodoStore.shared.add("Buy birthday cake")
        }
        NotesStore.shared.text = "Ideas for the weekend:\n- Picnic at the park\n- Movie night"
        ShelfStore.shared.add([URL(fileURLWithPath: "/System/Applications/Notes.app"),
                               URL(fileURLWithPath: "/System/Applications/Calendar.app")])
        TimerStore.shared.toggleStopwatch()
        DailyVerseStore.shared.debugSet(DailyText(
            isQuran: true, arabic: "إِنَّ مَعَ ٱلْعُسْرِ يُسْرًا",
            translation: "নিশ্চয় কষ্টের সাথে স্বস্তি রয়েছে।", reference: "Ash-Sharh 94:6",
            link: "https://quran.com/94/6", day: DailyVerseStore.dayKey(), translationKey: "bangla"))
        NetworkStore.shared.start()
    }

    @MainActor
    private static func render<V: View>(_ view: V, size: CGSize, shape: Bool, name: String) {
        let background = dark ? Color(white: 0.12) : Color(white: 0.9)
        let content = ZStack(alignment: .top) {
            if shape {
                NotchShape(topRadius: IslandModel.expandedFlare, bottomRadius: 32).fill(background)
            } else {
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous).fill(background)
            }
            view
            // Show where the hardware notch would cover the island (red outline).
            if shape, IslandModel.shared.hasNotch {
                let n = IslandModel.shared.notchSize
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red, lineWidth: 1))
                    .frame(width: n.width / IslandModel.scale, height: n.height / IslandModel.scale)
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            print("render failed: \(name)")
            return
        }
        try? png.write(to: folder.appendingPathComponent("\(name)-\(suffix).png"))
    }

    /// Every live wallpaper, each drawn with the mouse on the left and on the right, so the
    /// reaction can be seen side by side.
    private static func writeLiveSheet() {
        let w = 480, h = 300, columns = 4
        let styles = LiveStyle.allCases
        let rows = (styles.count + columns - 1) / columns
        guard let ctx = CGContext(data: nil, width: w * 2 * columns + (columns - 1) * 12, height: rows * (h + 12),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        for (i, style) in styles.enumerated() {
            let col = i % columns, row = i / columns
            let x = col * (w * 2 + 12), y = ctx.height - (row + 1) * (h + 12)
            if let a = LiveRenderer.snapshot(style, width: w, height: h, mouse: [0.2, 0.3], react: 1) {
                ctx.draw(a, in: CGRect(x: x, y: y, width: w, height: h))
            }
            if let b = LiveRenderer.snapshot(style, width: w, height: h, mouse: [0.8, 0.75], react: 1) {
                ctx.draw(b, in: CGRect(x: x + w, y: y, width: w, height: h))
            }
        }
        guard let image = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("live-wallpapers-\(suffix).png"))
        for style in styles where LiveRenderer.errors[style] != nil {
            print("live wallpaper \(style.rawValue) error: \(LiveRenderer.errors[style] ?? "")")
        }
    }

    /// Screenshot without waiting, so an animation keeps running while frames are taken.
    private static func captureNow(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", "0,0,\(Int(NSScreen.main?.frame.width ?? 1024)),360",
                             folder.appendingPathComponent("\(name)-\(suffix).png").path]
        try? process.run()
    }

    private static func capture(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", folder.appendingPathComponent("\(name)-\(suffix).png").path]
        try? process.run()
        process.waitUntilExit()
    }
}

/// A test window showing every glass technique side by side, to compare on a real screen.
enum GlassLab {
    private static var window: NSPanel?

    static func show() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 260),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .floating
        panel.contentView = HostingContainer.make(GlassLabView(), size: panel.frame.size)
        panel.center()
        panel.orderFrontRegardless()
        window = panel
    }
}

private struct GlassLabView: View {
    var body: some View {
        HStack(spacing: 16) {
            sample("SwiftUI glassEffect") { shape in
                #if compiler(>=6.2)
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular, in: shape)
                } else {
                    Text("needs macOS 26")
                }
                #else
                Text("old compiler")
                #endif
            }
            sample("Clear glass") { shape in
                #if compiler(>=6.2)
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.clear, in: shape)
                } else {
                    Text("needs macOS 26")
                }
                #else
                Text("old compiler")
                #endif
            }
            sample("HUD material") { shape in BehindWindowBlur(shape: shape, material: .hudWindow) }
            sample("Popover material") { shape in BehindWindowBlur(shape: shape, material: .popover) }
            sample("Full-screen UI") { shape in BehindWindowBlur(shape: shape, material: .fullScreenUI) }
        }
        .padding(20)
    }

    private func sample<V: View>(_ title: String, @ViewBuilder _ glass: (RoundedRectangle) -> V) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return ZStack {
            glass(shape)
            Text(title).font(.system(size: 13, weight: .semibold))
        }
        .frame(width: 170, height: 200)
    }
}
