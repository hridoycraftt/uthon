import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

enum SettingsTab: Hashable {
    case general, look, home, island, widgets, alerts, profiles, dock, care
}

/// Which Settings tab is showing (so other parts of the app can open a specific one).
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var tab: SettingsTab = .general
}

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(tab: SettingsTab) {
        SettingsRouter.shared.tab = tab
        show()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = L("Customize") + " \(AppInfo.name)"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Uthon: login item change failed: \(error.localizedDescription)")
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralSettings().tabItem { Label(L("General"), systemImage: "gearshape") }.tag(SettingsTab.general)
            LookSettings().tabItem { Label(L("Look"), systemImage: "paintpalette") }.tag(SettingsTab.look)
            HomeSettings().tabItem { Label(L("Home"), systemImage: "square.grid.2x2") }.tag(SettingsTab.home)
            IslandSettings().tabItem { Label(L("Island"), systemImage: "capsule.tophalf.filled") }.tag(SettingsTab.island)
            WidgetDataSettings().tabItem { Label(L("Widgets"), systemImage: "puzzlepiece.extension") }.tag(SettingsTab.widgets)
            AlertsSettings().tabItem { Label(L("Alerts"), systemImage: "bell.badge") }.tag(SettingsTab.alerts)
            ProfilesSettings().tabItem { Label(L("Profiles"), systemImage: "person.2.crop.square.stack") }.tag(SettingsTab.profiles)
            DockSettings().tabItem { Label(L("Side Dock"), systemImage: "sidebar.right") }.tag(SettingsTab.dock)
            CareSettings().tabItem { Label(L("Care"), systemImage: "heart") }.tag(SettingsTab.care)
        }
        .frame(width: 660, height: 680)
        .id(settings.lookKey)
        .environment(\.locale, Localization.locale)
    }
}

private var glassNote: String {
    if #available(macOS 26.0, *) {
        return L("Automatic uses Apple's Liquid Glass, exactly like macOS 26 itself. Clear and Frosted are manual overrides.")
    }
    return L("Automatic uses the same frosted material as macOS Control Center on this Mac. Clear and Frosted are manual overrides.")
}

// MARK: General

private struct GeneralSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var updater = Updater.shared
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section(L("Startup & shortcut")) {
                Toggle(L("Open at login"), isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, newValue in LoginItem.set(newValue) }
                Toggle(L("⌃⌥Space opens the island from anywhere"), isOn: $settings.hotkeyEnabled)
                Button(L("Show the welcome guide again")) { OnboardingWindowController.shared.show() }
            }
            Section(L("City (weather and prayer times)")) {
                TextField(L("City"), text: $settings.weatherCity, prompt: Text(L("e.g. Dhaka")))
                Picker(L("Unit"), selection: $settings.weatherFahrenheit) {
                    Text(L("°C")).tag(false)
                    Text(L("°F")).tag(true)
                }
                .pickerStyle(.segmented)
                Text(L("Uses the free Open-Meteo service. Only the city name is sent."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(L("Updates")) {
                Toggle(L("Check for updates automatically"), isOn: $library.autoCheckUpdates)
                HStack {
                    Text(L("This version") + ": \(AppInfo.version)")
                    Spacer()
                    switch updater.state {
                    case .checking:
                        ProgressView().controlSize(.small)
                    case .available(let version):
                        Button(L("Install") + " \(version)") { updater.install() }
                    case .downloading, .installing:
                        ProgressView().controlSize(.small)
                        Text(L("Installing…")).foregroundStyle(.secondary)
                    case .upToDate:
                        Text(L("Up to date ✓")).foregroundStyle(.secondary)
                        Button(L("Check now")) { updater.check() }
                    case .failed(let message):
                        Text(L(message)).foregroundStyle(.orange).lineLimit(1)
                        Button(L("Try again")) { updater.check() }
                    case .idle:
                        Button(L("Check now")) { updater.check() }
                    }
                }
            }
            Section(L("Wallpaper")) {
                Picker(L("Change wallpaper"), selection: $library.wallpaperSource) {
                    ForEach(WallpaperSource.allCases) { Text(L($0.title)).tag($0) }
                }
                if library.wallpaperSource == .folder {
                    HStack {
                        Text(library.wallpaperFolder.isEmpty ? L("No folder chosen") : library.wallpaperFolder)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Choose…")) {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            if panel.runModal() == .OK, let url = panel.url { library.wallpaperFolder = url.path }
                        }
                    }
                }
                if library.wallpaperSource != .off {
                    Toggle(L("A new wallpaper every day"), isOn: $library.wallpaperDaily)
                    Button(L("Change wallpaper now")) { WallpaperChanger.shared.next() }
                }
            }
            Section(L("Privacy")) {
                Text(L("Everything stays on this Mac: no account, no tracking, no cloud. Clipboard history skips passwords, and only pinned text is saved."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Look (themes, language)

private struct LookSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var custom: Color = AppSettings.shared.themeColor == .custom
        ? (Color(hex: AppSettings.shared.customAccentHex) ?? .orange) : .orange

    var body: some View {
        Form {
            Section(L("Theme color")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                    ForEach(ThemeColor.allCases) { theme in
                        Button {
                            settings.themeColor = theme
                        } label: {
                            VStack(spacing: 5) {
                                Circle()
                                    .fill(theme == .custom ? custom : theme.color)
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(settings.themeColor == theme ? 0.9 : 0), lineWidth: 2.5).padding(-4))
                                    .overlay(theme == .custom ? Image(systemName: "eyedropper").font(.system(size: 11)).foregroundStyle(.white) : nil)
                                Text(L(theme.title)).font(.system(size: 10))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                if settings.themeColor == .custom {
                    ColorPicker(L("Custom color"), selection: $custom, supportsOpacity: false)
                        .onChange(of: custom) { _, color in settings.customAccentHex = color.hexString }
                }
                Toggle(L("Tint the glass with the theme color"), isOn: $settings.tintGlass)
            }
            Section(L("Appearance")) {
                Picker(L("Mode"), selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text(L($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(L("Glass"), selection: $settings.glassClarity) {
                    ForEach(GlassClarity.allCases) { Text(L($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(glassNote).font(.footnote).foregroundStyle(.secondary)
            }
            Section(L("Language")) {
                Picker(L("Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0 == .system ? L("System") : $0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section(L("Size")) {
                LabeledSlider(title: L("Island size"), value: $settings.islandScale, range: 0.85...1.4, step: 0.05,
                              format: { "\(Int(($0 * 100).rounded()))%" })
                LabeledSlider(title: L("Tab icon size"), value: $settings.tabIconSize, range: 11...22, step: 1,
                              format: { "\(Int($0)) pt" })
                LabeledSlider(title: L("Dock size"), value: $settings.dockScale, range: 0.85...1.4, step: 0.05,
                              format: { "\(Int(($0 * 100).rounded()))%" })
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Home (pages, widgets, sizes, colors)

private struct HomeSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Stepper(L("Home pages") + ": \(settings.pageCount)", value: Binding(
                    get: { settings.pageCount },
                    set: { settings.setPageCount($0) }
                ), in: 1...HomeWidget.maxPages)
                Picker(L("Sideways swipe on Home"), selection: $settings.homeSwipe) {
                    ForEach(HomeSwipe.allCases) { Text(L($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(L("Tip: press Edit on the open island to add, remove and drag widgets right there."))
            }
            ForEach(0..<settings.pageCount, id: \.self) { page in
                Section {
                    let items = settings.homeItems(page: page)
                    ForEach(Array(items.enumerated()), id: \.element) { index, item in
                        HomeItemRow(item: item, canUp: index > 0, canDown: index < items.count - 1)
                    }
                    if items.isEmpty {
                        Text(L("This page is empty")).foregroundStyle(.secondary)
                    }
                    HStack {
                        Menu(L("Add widget")) {
                            ForEach(HomeWidget.allCases) { widget in
                                let item = HomeItem(widget)
                                Button(L(widget.title)) { settings.addToHome(item, page: page) }
                                    .disabled(!settings.canAdd(item, page: page))
                            }
                        }
                        .fixedSize()
                        Button(L("Add an app…")) {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.application]
                            panel.allowsMultipleSelection = true
                            panel.directoryURL = URL(fileURLWithPath: "/Applications")
                            if panel.runModal() == .OK {
                                for url in panel.urls { settings.addHomeApp(url, page: page) }
                            }
                        }
                        Button(L("New folder…")) {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.application]
                            panel.allowsMultipleSelection = true
                            panel.directoryURL = URL(fileURLWithPath: "/Applications")
                            panel.message = L("Pick the apps for the folder")
                            if panel.runModal() == .OK, !panel.urls.isEmpty {
                                settings.createFolder(name: L("Folder"), apps: panel.urls, page: page)
                            }
                        }
                        .disabled(settings.slotsUsed(page: page) >= HomeWidget.maxSlots)
                    }
                } header: {
                    Text(L("Page") + " \(page + 1) · \(settings.slotsUsed(page: page))/\(HomeWidget.maxSlots) " + L("slots"))
                }
            }
            if !settings.appFolders.isEmpty {
                Section(L("Folders")) {
                    ForEach($settings.appFolders) { $folder in
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                            TextField(L("Name"), text: $folder.name).labelsHidden()
                            Text("\(folder.urls.count) " + L("apps")).foregroundStyle(.secondary)
                            Button(L("Delete")) { settings.deleteFolder(folder) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct HomeItemRow: View {
    let item: HomeItem
    let canUp: Bool
    let canDown: Bool
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let url = item.appURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
                } else {
                    Image(systemName: item.symbol)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill((settings.color(of: item)?.color ?? Theme.accent).opacity(0.9)))
                        .foregroundStyle(.white)
                }
            }
            Text(L(item.title)).lineLimit(1)
            Spacer()
            Picker("", selection: Binding(
                get: { settings.slots(of: item) },
                set: { if !settings.setSize(item, slots: $0) { NSSound.beep() } }
            )) {
                if item.minSlots <= 1 { Text(L("Small")).tag(1) }
                Text(L("Medium")).tag(2)
                Text(L("Large")).tag(3)
            }
            .labelsHidden()
            .frame(width: 92)
            Picker("", selection: Binding(
                get: { settings.color(of: item)?.rawValue ?? "" },
                set: { settings.setColor(ThemeColor(rawValue: $0), for: item) }
            )) {
                Text(L("Default")).tag("")
                ForEach(ThemeColor.widgetChoices) { Text(L($0.title)).tag($0.rawValue) }
            }
            .labelsHidden()
            .frame(width: 100)
            Button { withAnimation { settings.moveHomeItem(item, by: -1) } } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(!canUp)
            Button { withAnimation { settings.moveHomeItem(item, by: 1) } } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(!canDown)
            Button { withAnimation { settings.removeFromHome(item) } } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(L("Remove"))
        }
    }
}

// MARK: Island

private struct IslandSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section(L("Top island")) {
                Toggle(L("Show the island at the top of the screen"), isOn: $settings.islandEnabled)
                Picker(L("Open island"), selection: $settings.islandStyle) {
                    ForEach(IslandStyle.allCases) { Text(L($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.islandEnabled)
            }
            Section {
                ForEach(Array(settings.orderedIslandTabs.enumerated()), id: \.element) { index, tab in
                    ReorderRow(
                        title: L(tab.title),
                        symbol: tab.symbol,
                        isOn: Binding(
                            get: { tab == .home || !settings.hiddenIslandTabs.contains(tab.rawValue) },
                            set: { settings.setTabVisible(tab, $0) }
                        ),
                        locked: tab == .home,
                        canMoveUp: index > 0,
                        canMoveDown: index < settings.orderedIslandTabs.count - 1,
                        move: { settings.moveTab(tab, by: $0) }
                    )
                }
            } header: {
                Text(L("Tabs"))
            } footer: {
                Text(L("Turn tabs on or off and use the arrows to change their order, like customizing Control Center on iPhone."))
            }
            Section {
                ForEach(Array(settings.orderedControls.enumerated()), id: \.element) { index, kind in
                    ReorderRow(
                        title: L(kind.title),
                        symbol: kind.symbol,
                        isOn: Binding(
                            get: { settings.enabledControls.contains(kind.rawValue) },
                            set: { settings.setControl(kind, $0) }
                        ),
                        locked: !settings.canEnableControl(kind),
                        canMoveUp: index > 0,
                        canMoveDown: index < settings.orderedControls.count - 1,
                        move: { settings.moveControl(kind, by: $0) }
                    )
                }
            } header: {
                Text(L("Controls") + " · \(settings.controls.count)/\(ControlKind.maxSlots)")
            }
            Section(L("Live activities (closed island)")) {
                Toggle(L("Music: artwork and equalizer"), isOn: $settings.liveMusic)
                Toggle(L("Timer and stopwatch countdown"), isOn: $settings.liveTimers)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Widgets (bookmarks, clocks, prayer, special days, to-do, clipboard)

private struct WidgetDataSettings: View {
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var todos = TodoStore.shared
    @ObservedObject private var weather = WeatherStore.shared
    @State private var newZone = "Asia/Dhaka"
    @State private var newDayName = ""
    @State private var newDayDate = Date()

    var body: some View {
        Form {
            Section(L("Bookmarks")) {
                ForEach($library.bookmarks) { $bookmark in
                    HStack {
                        TextField(L("Name"), text: $bookmark.title).labelsHidden().frame(width: 140)
                        TextField(L("https://"), text: $bookmark.url)
                        Button { library.bookmarks.removeAll { $0.id == bookmark.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button(L("Add bookmark")) { library.bookmarks.append(Bookmark(title: L("New"), url: "https://")) }
            }
            Section(L("World clock")) {
                ForEach(library.worldClocks, id: \.self) { zone in
                    HStack {
                        Text(WorldClockTile.cityName(TimeZone(identifier: zone) ?? .current))
                        Text(zone).foregroundStyle(.secondary).font(.footnote)
                        Spacer()
                        Button { library.worldClocks.removeAll { $0 == zone } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Picker(L("Add a city"), selection: $newZone) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                    }
                    Button(L("Add")) { if !library.worldClocks.contains(newZone) { library.worldClocks.append(newZone) } }
                }
            }
            Section(L("Prayer times")) {
                if let place = weather.place {
                    Text(L("Location") + ": \(place.city)").foregroundStyle(.secondary)
                } else {
                    Text(L("Set your city in General to see prayer times")).foregroundStyle(.orange)
                }
                Picker(L("Calculation method"), selection: $library.prayerMethod) {
                    ForEach(PrayerMethod.allCases) { Text($0.title).tag($0) }
                }
                Toggle(L("Hanafi Asr (later Asr time)"), isOn: $library.prayerHanafi)
                Toggle(L("Show an alert on the island at each prayer time"), isOn: $library.prayerAlerts)
            }
            Section(L("Birthdays & special days")) {
                ForEach($library.specialDays) { $day in
                    HStack {
                        TextField(L("Name"), text: $day.name).labelsHidden()
                        DatePicker("", selection: $day.date, displayedComponents: .date).labelsHidden()
                        Toggle(L("Every year"), isOn: $day.yearly).toggleStyle(.checkbox)
                        Button { library.specialDays.removeAll { $0.id == day.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField(L("e.g. Ammu's birthday"), text: $newDayName)
                    DatePicker("", selection: $newDayDate, displayedComponents: .date).labelsHidden()
                    Button(L("Add")) {
                        guard !newDayName.isEmpty else { return }
                        library.specialDays.append(SpecialDay(name: newDayName, date: newDayDate))
                        newDayName = ""
                    }
                }
                Toggle(L("Show it on the island on the day"), isOn: $library.specialDayAlerts)
            }
            Section(L("To-do list")) {
                Picker(L("Keep to-dos in"), selection: $todos.source) {
                    ForEach(TodoSource.allCases) { Text(L($0.title)).tag($0) }
                }
                if todos.source == .reminders {
                    switch todos.remindersAccess {
                    case .granted:
                        Picker(L("Reminders list"), selection: $todos.listName) {
                            Text(L("Default list")).tag("")
                            ForEach(todos.reminderLists, id: \.self) { Text($0).tag($0) }
                        }
                        Text(L("Tip: share this list with your family in the Reminders app, and everyone sees the same to-dos."))
                            .font(.footnote).foregroundStyle(.secondary)
                    case .notDetermined:
                        Button(L("Allow access to Reminders")) { todos.requestRemindersAccess() }
                    case .denied:
                        Text(L("Reminders access is off. Turn it on in System Settings → Privacy & Security → Reminders."))
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            }
            Section(L("Clipboard")) {
                Toggle(L("Also keep copied images"), isOn: $library.clipboardImages)
                Stepper(L("Keep the last") + " \(library.clipboardLimit) " + L("items"), value: $library.clipboardLimit, in: 5...100, step: 5)
                Text(L("Right-click an item in the Clipboard tab to pin it. Pinned text is kept even after restarting."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Alerts

private struct AlertsSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var trusted = MediaKeyTap.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle(L("Volume and brightness"), isOn: $settings.hudEnabled)
                Toggle(L("Replace the macOS volume/brightness popup"), isOn: $settings.replaceSystemHUD)
                    .disabled(!settings.hudEnabled)
                    .onChange(of: settings.replaceSystemHUD) { _, on in
                        if on { MediaKeyTap.shared.update(prompt: true) } else { MediaKeyTap.shared.update() }
                        trusted = MediaKeyTap.isTrusted
                    }
                if settings.replaceSystemHUD && !trusted {
                    HStack {
                        Text(L("Needs Accessibility permission")).font(.footnote).foregroundStyle(.orange)
                        Spacer()
                        Button(L("Open Settings")) { MediaKeyTap.openAccessibilitySettings() }
                    }
                }
            } header: {
                Text(L("Island pop-ups"))
            } footer: {
                Text(L("Scroll on the open island to change volume; swipe sideways to change page or song."))
            }
            Section {
                Toggle(L("New song"), isOn: $settings.peekTrack)
                Toggle(L("AirPods and headphones connect (with battery)"), isOn: $settings.peekHeadphones)
                Toggle(L("Upcoming meeting (5 minutes before, with Join)"), isOn: $settings.peekMeetings)
                Toggle(L("Finished downloads"), isOn: $settings.peekDownloads)
                Toggle(L("New screenshots"), isOn: $settings.peekScreenshots)
                Toggle(L("Caps Lock"), isOn: $settings.peekCapsLock)
                if DeviceBatteryStore.shared.hasInternalBattery {
                    Toggle(L("Charging animation"), isOn: $settings.peekCharging)
                }
                Toggle(L("Clipboard history"), isOn: $settings.clipboardEnabled)
            }
        }
        .formStyle(.grouped)
        .onAppear { trusted = MediaKeyTap.isTrusted }
    }
}

// MARK: Profiles

private struct ProfilesSettings: View {
    @ObservedObject private var library = UserLibrary.shared
    @State private var newName = ""

    var body: some View {
        Form {
            Section {
                ForEach(Profiles.presets) { profile in
                    ProfileRow(profile: profile, active: library.activeProfile == profile.id)
                }
            } header: {
                Text(L("Ready-made layouts"))
            } footer: {
                Text(L("One tap changes Home pages, controls, tabs and the theme color."))
            }
            Section(L("My profiles")) {
                ForEach(library.profiles) { profile in
                    HStack {
                        ProfileRow(profile: profile, active: library.activeProfile == profile.id)
                        Button(L("Update")) { Profiles.update(profile) }
                            .help(L("Save the current layout into this profile"))
                        Button { Profiles.delete(profile) } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField(L("Profile name, e.g. Abbu's Mac"), text: $newName)
                    Button(L("Save current layout")) {
                        Profiles.saveCurrent(as: newName)
                        newName = ""
                    }
                }
                Text(L("Profiles are also in the menu bar, so anyone in the family can switch in one click."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProfileRow: View {
    let profile: LayoutProfile
    let active: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: profile.symbol)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((ThemeColor(rawValue: profile.theme)?.color ?? Theme.accent).opacity(0.9)))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(L(profile.name)).fontWeight(.semibold)
                Text("\(profile.homePages.count) " + L("pages") + " · \(profile.controls.count) " + L("controls"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if active {
                Text(L("In use ✓")).foregroundStyle(Theme.accent).font(.footnote.weight(.semibold))
            } else {
                Button(L("Use")) { Profiles.apply(profile) }
            }
        }
    }
}

// MARK: Side dock & care

private struct DockSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section(L("Side dock")) {
                Toggle(L("Show the side dock"), isOn: $settings.sideDockEnabled)
                Picker(L("Screen edge"), selection: $settings.edge) {
                    ForEach(DockEdge.allCases) { Text(L($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.sideDockEnabled)
                Toggle(L("Keep visible (pinned)"), isOn: $settings.pinned)
                    .disabled(!settings.sideDockEnabled)
            }
            Section {
                ForEach(Array(settings.orderedWidgets.enumerated()), id: \.element) { index, kind in
                    ReorderRow(
                        title: L(kind.title),
                        symbol: kind.symbol,
                        isOn: Binding(get: { settings.isVisible(kind) }, set: { settings.setVisible(kind, $0) }),
                        locked: false,
                        canMoveUp: index > 0,
                        canMoveDown: index < settings.orderedWidgets.count - 1,
                        move: { settings.moveWidget(kind, by: $0) }
                    )
                }
            } header: {
                Text(L("Widgets"))
            } footer: {
                Text(L("Turn widgets on or off and change their order."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct CareSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section(L("Care reminders")) {
                Toggle(L("Drink water"), isOn: $settings.waterEnabled)
                Stepper(L("Every") + " \(settings.waterMinutes) " + L("minutes"), value: $settings.waterMinutes, in: 10...180, step: 5)
                    .disabled(!settings.waterEnabled)
                Toggle(L("Posture & stretch"), isOn: $settings.postureEnabled)
                Stepper(L("Every") + " \(settings.postureMinutes) " + L("minutes"), value: $settings.postureMinutes, in: 10...180, step: 5)
                    .disabled(!settings.postureEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

/// A row with an on/off switch and up/down arrows (customize like iOS).
private struct ReorderRow: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    let locked: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accent.opacity(isOn ? 0.9 : 0.25)))
                .foregroundStyle(.white)
            Text(L(title))
            Spacer()
            Button { withAnimation { move(-1) } } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
            Button { withAnimation { move(1) } } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
            Toggle(L(""), isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(locked)
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        HStack {
            Text(L(title))
            Slider(value: $value, in: range, step: step)
            Text(format(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
