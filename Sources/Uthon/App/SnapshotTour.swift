import AppKit
import SwiftUI

/// Visual QA. Launch with `--snapshot-tour <folder> [--dark]` and Uthon renders every
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
        let peeks: [(String, PeekKind)] = [
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
        add("live-controls") { model.tab = .controls }
        add("capture-controls") { capture("screen-island-controls") }
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
        add("live-onboarding") { OnboardingWindowController.shared.show() }
        add("capture-onboarding") { capture("screen-onboarding") }
        add("quit") { exit(0) }

        next(0)
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
