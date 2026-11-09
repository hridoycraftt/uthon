import SwiftUI
import AppKit
import EventKit
import AVFoundation

// MARK: Home (customizable widgets)

struct IslandHome: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var model = IslandModel.shared

    private var page: Int { min(model.homePage, settings.pageCount - 1) }

    var body: some View {
        VStack(spacing: 8) {
            if let id = model.openFolder, let folder = settings.appFolders.first(where: { $0.id == id }) {
                FolderGrid(folder: folder)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else {
                EditableRow(
                    items: settings.homeItems(page: page),
                    allItems: HomeItem.allCases.filter { !settings.isOnHome($0) || settings.pageOf($0) == page },
                    maxSlots: HomeWidget.maxSlots,
                    editing: model.editing,
                    canAdd: { settings.canAdd($0, page: page) },
                    setEnabled: { item, on in
                        if on {
                            settings.addToHome(item, page: page)
                        } else {
                            model.registerUndo(L("Removed") + " " + L(item.title))
                            settings.removeFromHome(item)
                        }
                    },
                    place: { settings.placeHomeItem($0, at: $1) },
                    onAdd: openGallery,
                    onPresets: openPresets
                ) { item in
                    HomeWidgetView(item: item)
                        .contextMenu { TileMenu(item: item) }
                }
                .frame(height: model.pickerOpen ? 158 : nil)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: page)
            }
            if model.pickerOpen {
                WidgetGallery(page: page)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if settings.pageCount > 1 || model.editing {
                PageDots(page: page)
                    .offset(y: 12)
            }
        }
        .overlay {
            if settings.homeItems(page: page).isEmpty && !model.editing && model.openFolder == nil {
                VStack(spacing: 8) {
                    Text(L("This page is empty")).font(.system(size: 12)).foregroundStyle(Color.secondary)
                    Button(L("Add widgets")) { openGallery() }
                        .buttonStyle(AccentButtonStyle())
                }
            }
        }
        .contextMenu {
            MenuButton(model.editing ? "Done Editing" : "Edit Home") { withAnimation { model.editing.toggle() } }
            MenuButton("Add Widget…") { openGallery() }
            MenuButton("Presets…") { openPresets() }
            MenuButton("More Settings…") { SettingsWindowController.shared.show(tab: .home) }
        }
        .onChange(of: model.editing) { _, editing in
            if !editing { withAnimation(IslandModel.spring) { model.pickerOpen = false } }
        }
    }

    private func openGallery() {
        withAnimation(IslandModel.spring) {
            model.gallerySection = 0
            model.editing = true
            model.pickerOpen = true
        }
    }

    private func openPresets() {
        withAnimation(IslandModel.spring) {
            model.gallerySection = 2
            model.editing = true
            model.pickerOpen = true
        }
    }
}

/// Little page dots under Home (and "+" to add a page while editing).
private struct PageDots: View {
    let page: Int
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var model = IslandModel.shared

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<settings.pageCount, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.homePage = index }
                } label: {
                    Capsule()
                        .fill(index == page ? Theme.accent : Color.secondary.opacity(0.35))
                        .frame(width: index == page ? 16 : 6, height: 6)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .buttonStyle(.plain)
                .help(L("Page") + " \(index + 1)")
            }
            if model.editing && settings.pageCount < HomeWidget.maxPages {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        settings.setPageCount(settings.pageCount + 1)
                        model.homePage = settings.pageCount - 1
                    }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 11)).foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help(L("Add a page"))
            }
        }
    }
}

/// Right-click menu on any Home tile: remove, size, color, move to another page.
struct TileMenu: View {
    let item: HomeItem
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Menu(L("Size")) {
            ForEach([(1, "Small"), (2, "Medium"), (3, "Large")], id: \.0) { size, name in
                if size >= item.minSlots {
                    MenuButton((settings.slots(of: item) == size ? "✓ " : "") + L(name)) {
                        if !settings.setSize(item, slots: size) {
                            IslandModel.shared.notify(L("Not enough room on this page for a bigger widget"))
                        }
                    }
                }
            }
        }
        Menu(L("Color")) {
            MenuButton((settings.color(of: item) == nil ? "✓ " : "") + L("Default")) { settings.setColor(nil, for: item) }
            ForEach(ThemeColor.widgetChoices) { color in
                MenuButton((settings.color(of: item) == color ? "✓ " : "") + L(color.title)) { settings.setColor(color, for: item) }
            }
        }
        if settings.pageCount > 1 {
            Menu(L("Move to page")) {
                ForEach(0..<settings.pageCount, id: \.self) { index in
                    MenuButton(L("Page") + " \(index + 1)") {
                        guard settings.pageOf(item) != index else { return }
                        let snapshot = settings.homePages
                        settings.removeFromHome(item)
                        if !settings.addToHome(item, page: index) { settings.homePages = snapshot }
                    }
                }
            }
        }
        if let folder = item.folder {
            MenuButton("Delete Folder") {
                IslandModel.shared.registerUndo(L("Removed") + " " + folder.name)
                settings.deleteFolder(folder)
            }
        }
        Divider()
        MenuButton("Remove", role: .destructive) {
            IslandModel.shared.registerUndo(L("Removed") + " " + L(item.title))
            settings.removeFromHome(item)
        }
        MenuButton("Edit Home") { withAnimation { IslandModel.shared.editing = true } }
    }
}

struct HomeWidgetView: View {
    let item: HomeItem
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        content
            .overlay {
                if let color = settings.color(of: item) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(color.color.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(color.color.opacity(0.55), lineWidth: 1))
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let widget = item.widget {
            switch widget {
            case .music: IslandMusicTile()
            case .calendar: IslandCalendarTile()
            case .weather: WeatherTile()
            case .shortcuts: IslandShortcutsTile()
            case .system: SystemTile()
            case .batteries: BatteriesTile()
            case .todo: TodoTile()
            case .controls: MiniControlsTile()
            case .notes: NoteTile()
            case .bookmarks: BookmarksTile()
            case .worldClock: WorldClockTile()
            case .prayer: PrayerTile()
            case .countdown: CountdownTile()
            }
        } else if let folder = item.folder {
            FolderTile(folder: folder)
        } else if let url = item.appURL {
            if let player = NowPlayingStore.playerName(for: url) {
                MusicAppTile(url: url, player: player)
            } else {
                AppTile(url: url)
            }
        }
    }
}

/// Spotify or Music placed on Home: the same full player as the Music widget
/// (artwork, song, artist, progress, controls), but only for that app.
struct MusicAppTile: View {
    let url: URL
    let player: String

    var body: some View {
        IslandMusicTile(onlyPlayer: player, appURL: url)
            .onAppear { NowPlayingStore.shared.refresh() }
            .contextMenu {
                MenuButton("Open") { NSWorkspace.shared.open(url) }
            }
    }
}

/// An app from this Mac placed on Home: tap to open it.
struct AppTile: View {
    let url: URL
    @State private var hover = false

    private var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
            IslandController.shared.collapse()
        } label: {
            WidgetTile {
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 56, height: 56)
                        .scaleEffect(hover ? 1.06 : 1)
                    Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Circle()
                        .fill(isRunning ? Theme.accent : Color.clear)
                        .frame(width: 4, height: 4)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hover = h } }
        .help("Open \(url.lastPathComponent)")
    }
}

/// "+ Add Widget": a gallery of Uthon widgets and every app on this Mac (and folders of apps).
struct WidgetGallery: View {
    let page: Int
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var model = IslandModel.shared
    @State private var query = ""
    @State private var message: String?
    @State private var makingFolder = false
    @State private var folderName = ""
    @State private var folderApps: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("", selection: $model.gallerySection) {
                    Text(L("Uthon Widgets")).tag(0)
                    Text(L("Apps on this Mac")).tag(1)
                    Text(L("Presets")).tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 340)
                if model.gallerySection == 1 {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color.secondary)
                        TextField(L("Search apps"), text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .frame(width: 160)
                    Button {
                        withAnimation { makingFolder.toggle(); folderApps = [] }
                    } label: {
                        Label(makingFolder ? L("Cancel") : L("New Folder"), systemImage: makingFolder ? "xmark" : "folder.badge.plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
                Spacer()
                if let message {
                    Text(L(message))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.orange)
                        .lineLimit(1)
                        .transition(.opacity)
                }
                Text("\(settings.slotsUsed(page: page))/\(HomeWidget.maxSlots)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                    .help(L("Slots used on this page"))
                Button {
                    withAnimation(IslandModel.spring) { model.pickerOpen = false }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help(L("Close the gallery"))
            }
            if makingFolder && model.gallerySection == 1 {
                HStack(spacing: 8) {
                    TextField(L("Folder name"), text: $folderName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    Text(L("Tap apps to put them in the folder") + " (\(folderApps.count))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Button(L("Create Folder")) {
                        if settings.slotsUsed(page: page) < HomeWidget.maxSlots {
                            settings.createFolder(name: folderName, apps: folderApps, page: page)
                            withAnimation { makingFolder = false; folderApps = []; folderName = ""; message = nil }
                        } else {
                            message = L("No room: remove a widget first")
                        }
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(folderApps.count < 2)
                }
            }
            ScrollView(.vertical, showsIndicators: true) {
                if model.gallerySection == 2 {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
                        ForEach(HomePreset.all) { preset in
                            PresetCard(preset: preset)
                        }
                    }
                } else if model.gallerySection == 0 {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(HomeWidget.allCases) { widget in
                            let item = HomeItem(widget)
                            GalleryCell(title: L(widget.title),
                                        subtitle: subtitle(for: item),
                                        added: settings.isOnHome(item)) {
                                Image(systemName: widget.symbol)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(Theme.accent.opacity(0.15)))
                            } action: {
                                toggle(item)
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                        ForEach(apps) { app in
                            let item = HomeItem(app: app.url)
                            let picked = folderApps.contains(app.url)
                            GalleryCell(title: app.name, subtitle: makingFolder ? (picked ? L("In folder ✓") : L("Tap to pick")) : nil,
                                        added: makingFolder ? picked : settings.isOnHome(item)) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 40, height: 40)
                            } action: {
                                if makingFolder {
                                    if picked { folderApps.removeAll { $0 == app.url } } else { folderApps.append(app.url) }
                                } else {
                                    toggle(item)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassChip(radius: 20)
        .animation(.easeOut(duration: 0.2), value: message)
    }

    private func subtitle(for item: HomeItem) -> String {
        if let p = settings.pageOf(item), settings.pageCount > 1 { return L("Added on page") + " \(p + 1)" }
        return item.slots > 1 ? "\(item.slots) " + L("slots") : "1 " + L("slot")
    }

    private var apps: [AppSearch.Result] {
        let all = AppSearch.shared.allApps
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) }
    }

    private func toggle(_ item: HomeItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            if settings.isOnHome(item) {
                model.registerUndo(L("Removed") + " " + L(item.title))
                settings.removeFromHome(item)
                message = nil
            } else if settings.canAdd(item, page: page) {
                settings.addToHome(item, page: page)
                message = nil
            } else {
                message = L("No room: remove a widget first") + " (\(settings.slotsUsed(page: page))/\(HomeWidget.maxSlots))"
            }
        }
    }
}

private struct GalleryCell<Icon: View>: View {
    let title: String
    let subtitle: String?
    let added: Bool
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                icon()
                Text(L(title))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(added && subtitle == nil ? L("Added ✓") : (subtitle ?? L("Tap to add")))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(added ? Theme.accent : Color.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(added ? 0.12 : (hover ? 0.08 : 0.04)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(added ? Theme.accent.opacity(0.7) : Color.clear, lineWidth: 1.2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(added ? "Tap to remove from Home" : "Tap to add to Home")
    }
}

/// Common frame for Home widgets.
struct WidgetTile<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassChip(radius: 20)
    }
}

struct WeatherTile: View {
    @ObservedObject private var weather = WeatherStore.shared

    var body: some View {
        WidgetTile {
            if let w = weather.current {
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.city.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(w.temperature.rounded()))°")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Image(systemName: w.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 20))
                    }
                    Spacer(minLength: 0)
                    if let high = w.high, let low = w.low {
                        Text("H \(Int(high.rounded()))°  L \(Int(low.rounded()))°")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Weather")
                    Spacer(minLength: 0)
                    Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: 22))
                    Button(L("Set your city")) { SettingsWindowController.shared.show(tab: .general) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

struct SystemTile: View {
    @ObservedObject private var stats = SystemStatsStore.shared

    var body: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("System")
                Spacer(minLength: 6)
                HStack(spacing: 0) {
                    gauge("CPU", stats.cpu)
                    Spacer(minLength: 4)
                    gauge("RAM", stats.memoryFraction)
                }
                Spacer(minLength: 0)
            }
        }
        .onAppear { SystemStatsStore.shared.setActive(true) }
        .onDisappear { SystemStatsStore.shared.setActive(false) }
    }
}

extension SystemTile {
    fileprivate func gauge(_ label: String, _ value: Double) -> some View {
        let color: Color = value > 0.85 ? .red : (value > 0.65 ? .orange : Theme.accent)
        return VStack(spacing: 4) {
            ZStack {
                RingProgress(progress: value, lineWidth: 6, color: color)
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 54, height: 54)
            Text(L(label))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Batteries of the Mac (MacBooks only) and wireless devices, as rings like the System widget.
/// Small: two rings. Medium: up to four rings with names. Large: rings with full names and status.
struct BatteriesTile: View {
    @ObservedObject private var store = DeviceBatteryStore.shared
    @ObservedObject private var settings = AppSettings.shared

    struct Entry: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let percent: Int
        let charging: Bool
    }

    private var entries: [Entry] {
        var list: [Entry] = []
        if let mac = DeviceBatteryStore.internalBattery() {
            list.append(Entry(id: "mac", name: "Mac", symbol: "laptopcomputer", percent: mac.percent, charging: mac.pluggedIn))
        }
        list += store.devices.map { Entry(id: $0.id, name: $0.name, symbol: $0.symbol, percent: $0.percent, charging: false) }
        return list
    }

    var body: some View {
        let size = settings.slots(of: HomeItem(.batteries))
        let list = entries
        WidgetTile {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Batteries")
                if list.isEmpty {
                    Spacer(minLength: 0)
                    Text(L(store.lastChecked == nil ? "Looking for devices…" : "No wireless devices connected"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                    Button(L("Details")) { SettingsWindowController.shared.show(tab: .widgets) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer(minLength: 0)
                } else if size >= 3 {
                    Spacer(minLength: 6)
                    VStack(spacing: 8) {
                        ForEach(list.prefix(4)) { entry in largeRow(entry) }
                    }
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 4)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(list.prefix(size >= 2 ? 4 : 2)) { entry in
                            gauge(entry, showName: size >= 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear {
            DeviceBatteryStore.requestBluetoothAccess()
            store.refreshDevices()
            // Look again once the Bluetooth permission prompt has been answered.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { store.refreshDevices() }
        }
    }

    static func color(for percent: Int) -> Color {
        percent < 20 ? .red : (percent <= 50 ? .orange : .green)
    }

    private func label(_ entry: Entry) -> String {
        L(DeviceBatteryStore.shortName(for: entry.name))
    }

    /// A ring with the device icon inside and the level (and name) below.
    private func gauge(_ entry: Entry, showName: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RingProgress(progress: Double(entry.percent) / 100, lineWidth: 5, color: Self.color(for: entry.percent))
                Image(systemName: entry.charging ? "bolt.fill" : entry.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(entry.charging ? Color.green : Color.primary)
            }
            .frame(width: 48, height: 48)
            Text("\(entry.percent)%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if showName {
                Text(label(entry))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .help("\(entry.name): \(entry.percent)%")
    }

    /// Large size: ring, full name, a status word and a level bar.
    private func largeRow(_ entry: Entry) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RingProgress(progress: Double(entry.percent) / 100, lineWidth: 3.5, color: Self.color(for: entry.percent))
                Image(systemName: entry.charging ? "bolt.fill" : entry.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(entry.charging ? Color.green : Color.primary)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(entry.percent)%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                HStack(spacing: 6) {
                    LevelBar(level: Float(entry.percent) / 100, color: Self.color(for: entry.percent))
                    Text(L(entry.charging ? "Charging" : (entry.percent < 20 ? "Charge soon" : (entry.percent <= 50 ? "OK" : "Good"))))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(entry.charging ? Color.green : Self.color(for: entry.percent))
                        .fixedSize()
                }
            }
        }
    }
}

struct TodoTile: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var draft = ""

    var body: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("To-do")
                ForEach(store.items.filter { !$0.done }.prefix(3)) { item in
                    HStack(spacing: 6) {
                        Button { withAnimation { store.toggle(item.id) } } label: {
                            Image(systemName: "circle").font(.system(size: 12)).foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                        Text(item.text).font(.system(size: 11)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                TextField(L("Add a task"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit {
                        store.add(draft)
                        draft = ""
                    }
            }
        }
    }
}

struct MiniControlsTile: View {
    @ObservedObject private var actions = QuickActions.shared

    var body: some View {
        WidgetTile {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    mini(actions.keepAwake ? "cup.and.saucer.fill" : "cup.and.saucer", active: actions.keepAwake, help: "Keep awake") {
                        actions.toggleKeepAwake()
                    }
                    mini(actions.darkMode ? "moon.fill" : "sun.max.fill", active: actions.darkMode, help: "Dark mode") {
                        actions.toggleDarkMode()
                    }
                }
                HStack(spacing: 8) {
                    mini(AudioController.shared.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                         active: AudioController.shared.isMuted, help: "Mute") {
                        AudioController.shared.toggleMute()
                        actions.objectWillChange.send()
                    }
                    mini("camera.viewfinder", active: false, help: "Screenshot") { actions.screenshot() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func mini(_ symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(active ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(active ? Theme.accent : Color.primary.opacity(0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L(help))
    }
}

struct NoteTile: View {
    @ObservedObject private var notes = NotesStore.shared

    var body: some View {
        Button {
            withAnimation { IslandModel.shared.tab = .notes }
        } label: {
            WidgetTile {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Note")
                    Text(notes.text.isEmpty ? "Tap to write a note" : notes.text)
                        .font(.system(size: 11))
                        .foregroundStyle(notes.text.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct IslandMusicTile: View {
    /// Set for a Spotify/Music app tile: show and control only that app.
    var onlyPlayer: String? = nil
    var appURL: URL? = nil
    @ObservedObject private var player = NowPlayingStore.shared

    private var current: NowPlayingStore.Track? {
        guard let track = player.track else { return nil }
        if let only = onlyPlayer, track.player != only { return nil }
        return track
    }

    private func send(_ command: String) {
        if let only = onlyPlayer {
            player.command(command, player: only)
        } else {
            player.command(command)
        }
    }

    var body: some View {
        Group {
            if let track = current {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 11) {
                        ArtworkView(image: player.artwork, bundleID: track.bundleID, size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text(track.artist.isEmpty ? track.player : track.artist)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        EqualizerBars(playing: track.isPlaying)
                            .frame(width: 16, height: 13)
                            .opacity(track.isPlaying ? 1 : 0.4)
                    }
                    if track.duration > 0 {
                        ProgressRow(track: track)
                    }
                    HStack(spacing: 28) {
                        Spacer()
                        control("backward.fill") { send("previous track") }
                        control(track.isPlaying ? "pause.fill" : "play.fill", size: 19) { send("playpause") }
                        control("forward.fill") { send("next track") }
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 6) {
                    if let appURL {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                            .resizable()
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Color.secondary)
                    }
                    Text(L("Nothing playing"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                    if let only = onlyPlayer {
                        Button {
                            player.command("play", player: only)
                        } label: {
                            Label(L("Play on") + " " + only, systemImage: "play.fill")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    } else {
                        Button(L("Open Music")) { player.openMusic() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassChip(radius: 20)
    }

    private func control(_ symbol: String, size: CGFloat = 13, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
    }
}

struct ProgressRow: View {
    let track: NowPlayingStore.Track

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = track.currentPosition(at: context.date)
            let fraction = track.duration > 0 ? min(max(position / track.duration, 0), 1) : 0
            HStack(spacing: 8) {
                Text(Self.time(position))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.14))
                        Capsule()
                            .fill(Color.primary.opacity(0.85))
                            .frame(width: max(3, geo.size.width * CGFloat(fraction)))
                    }
                }
                .frame(height: 4)
                Text(Self.time(track.duration))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct IslandCalendarTile: View {
    @ObservedObject private var calendar = CalendarStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Text(context.date.formatted(.dateTime.weekday(.wide).locale(Localization.locale)).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text(context.date, format: .dateTime.day())
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(context.date, format: .dateTime.month(.wide))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer(minLength: 0)
            switch calendar.access {
            case .granted:
                if let next = calendar.events.first {
                    Text(next.title ?? "Event")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(next.uthonTimeText)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                } else {
                    Text(L("No more events"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
            case .notDetermined:
                Button(L("Connect calendar")) { calendar.requestAccess() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            case .denied:
                Text(L("Calendar off"))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassChip(radius: 20)
    }
}

struct IslandShortcutsTile: View {
    @ObservedObject private var store = ShortcutsStore.shared
    private let columns = [GridItem(.fixed(38), spacing: 8), GridItem(.fixed(38), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(store.paths.prefix(4)), id: \.self) { path in
                let url = URL(fileURLWithPath: path)
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 34, height: 34)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .help(FileManager.default.displayName(atPath: url.path))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassChip(radius: 20)
    }
}

// MARK: Shelf

struct IslandShelf: View {
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var model = IslandModel.shared

    var body: some View {
        HStack(spacing: 10) {
            if shelf.paths.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .light))
                    Text(L("Drop files on the island to keep them here"))
                        .font(.system(size: 11))
                }
                .foregroundStyle(model.dropTargeted ? Theme.accent : Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(model.dropTargeted ? Theme.accent : Color.secondary.opacity(0.4),
                                      style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.paths, id: \.self) { path in
                            ShelfTile(url: URL(fileURLWithPath: path)) { shelf.remove(path) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassChip(radius: 20)
                VStack(spacing: 8) {
                    ShelfAction(symbol: "paperplane.fill", title: "AirDrop") { airDrop() }
                    ShelfAction(symbol: "trash", title: "Clear") { shelf.clear() }
                }
                .frame(width: 86)
            }
        }
    }

    private func airDrop() {
        let urls = shelf.paths.map { URL(fileURLWithPath: $0) }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }
}

struct ShelfTile: View {
    let url: URL
    let onRemove: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 70)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.10 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .contextMenu {
            MenuButton("Open") { NSWorkspace.shared.open(url) }
            MenuButton("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            MenuButton("Remove from Shelf", action: onRemove)
        }
        .help(L("Double-click to open, or drag it out"))
    }
}

struct ShelfAction: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                Text(L(title)).font(.system(size: 10, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassChip(radius: 16)
    }
}

// MARK: Reminder

struct IslandReminder: View {
    let kind: CareReminders.Kind

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: kind.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(L(kind.title)).font(.system(size: 15, weight: .semibold))
                Text(L(kind.subtitle))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Button(L("Done")) { CareReminders.shared.complete() }
                    .buttonStyle(AccentButtonStyle())
                Button(L("Later")) { CareReminders.shared.snooze() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassChip(radius: 22)
    }
}

// MARK: Shared

struct ArtworkView: View {
    let image: NSImage?
    let bundleID: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .padding(size * 0.08)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .background(Color.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

// MARK: Controls (quick actions)

struct IslandControls: View {
    @ObservedObject private var actions = QuickActions.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var model = IslandModel.shared
    @ObservedObject private var timers = TimerStore.shared

    var body: some View {
        EditableRow(
            items: settings.controls,
            allItems: settings.orderedControls,
            maxSlots: ControlKind.maxSlots,
            editing: model.editing,
            canAdd: { settings.canEnableControl($0) },
            setEnabled: { settings.setControl($0, $1) },
            place: { settings.placeControl($0, at: $1) }
        ) { kind in
            let state = actions.state(of: kind)
            ControlTile(symbol: state.symbol, title: kind.title, subtitle: state.subtitle, active: state.active) {
                actions.perform(kind)
            }
        }
        .contextMenu {
            MenuButton(model.editing ? "Done Editing" : "Edit Controls") { withAnimation { model.editing.toggle() } }
        }
        .onAppear { actions.refresh() }
    }
}

/// Control Center style tile: big round icon on top, name and state below.
private struct ControlTile: View {
    let symbol: String
    let title: String
    let subtitle: String
    let active: Bool
    let action: () -> Void
    @State private var hover = false
    @State private var tapped = 0

    var body: some View {
        Button {
            tapped += 1
            action()
        } label: {
            VStack(spacing: 0) {
                Spacer(minLength: 6)
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(active ? Color.white : Color.primary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(active ? Theme.accent : Color.primary.opacity(hover ? 0.16 : 0.10)))
                    .symbolEffect(.bounce, value: tapped)
                    .contentTransition(.symbolEffect(.replace))
                Spacer(minLength: 8)
                Text(L(title))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(L(subtitle))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .glassChip(radius: 22)
        .scaleEffect(hover ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
    }
}

// MARK: Search

struct IslandSearch: View {
    @State private var query = ""
    @State private var results: [AppSearch.Result] = []
    @State private var selection = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.secondary)
                TextField(L("Search apps, files or the web…"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .focused($focused)
                    .onSubmit(openSelection)
                    .onChange(of: query) { _, value in
                        results = AppSearch.shared.search(value)
                        selection = 0
                    }
                if !query.isEmpty {
                    IconButton(symbol: "xmark.circle.fill", help: "Clear") { query = "" }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassChip(radius: 14)

            if query.isEmpty {
                Text(L("Type an app name and press Return. Tip: ⌃⌥Space opens the island from anywhere."))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(results.prefix(4).enumerated()), id: \.element.id) { index, app in
                        SearchResultTile(icon: NSWorkspace.shared.icon(forFile: app.url.path), title: app.name,
                                         selected: index == selection) { open(app.url) }
                    }
                    SearchResultTile(icon: nil, symbol: "doc.text.magnifyingglass", title: "Files",
                                     selected: results.isEmpty && selection == 0) {
                        AppSearch.searchFiles(query)
                        IslandController.shared.collapse()
                    }
                    SearchResultTile(icon: nil, symbol: "globe", title: "Web", selected: false) {
                        if let url = AppSearch.webSearchURL(query) { open(url) }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            focused = true
        }
    }

    private func openSelection() {
        if results.indices.contains(selection) {
            open(results[selection].url)
        } else if let url = AppSearch.webSearchURL(query) {
            open(url)
        }
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        query = ""
        IslandController.shared.collapse()
    }
}

private struct SearchResultTile: View {
    let icon: NSImage?
    var symbol: String = ""
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 40, height: 40)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 20))
                        .frame(width: 40, height: 40)
                }
                Text(L(title))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.14 : (hover ? 0.08 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Timer & stopwatch

struct IslandTimerTab: View {
    @ObservedObject private var timers = TimerStore.shared
    @State private var customMinutes = 20
    private let presets: [Double] = [1, 3, 5, 10, 15, 25, 45, 60]

    var body: some View {
        HStack(spacing: 10) {
            timerPanel
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .glassChip(radius: 20)
            stopwatchPanel
                .padding(12)
                .frame(width: 230)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .glassChip(radius: 20)
        }
    }

    @ViewBuilder private var timerPanel: some View {
        if timers.timerActive || timers.alarmRinging {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                HStack(spacing: 16) {
                    ZStack {
                        RingProgress(progress: timers.alarmRinging ? 1 : timers.progress(at: context.date), lineWidth: 6)
                        Image(systemName: timers.alarmRinging ? "bell.fill" : "timer")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .symbolEffect(.bounce, value: timers.alarmRinging)
                    }
                    .frame(width: 74, height: 74)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(timers.alarmRinging ? "Time's up!" : TimerStore.format(timers.remaining(at: context.date)))
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        HStack(spacing: 8) {
                            if timers.alarmRinging {
                                Button(L("Stop")) { timers.stopAlarm() }.buttonStyle(AccentButtonStyle())
                            } else {
                                Button(timers.timerPaused ? "Resume" : "Pause") {
                                    timers.timerPaused ? timers.resumeTimer() : timers.pauseTimer()
                                }
                                .buttonStyle(AccentButtonStyle())
                                SmallPill(title: "+1 min") { timers.addMinute() }
                                SmallPill(title: "Cancel") { timers.cancelTimer() }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Timer")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(presets, id: \.self) { minutes in
                        SmallPill(title: "\(Int(minutes)) min", fill: true) { timers.startTimer(minutes: minutes) }
                    }
                }
                HStack(spacing: 8) {
                    IconButton(symbol: "minus", help: "Less") { customMinutes = max(1, customMinutes - 5) }
                    Text("\(customMinutes) min")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 60)
                        .contentTransition(.numericText())
                    IconButton(symbol: "plus", help: "More") { customMinutes = min(180, customMinutes + 5) }
                    Spacer()
                    Button(L("Start")) { timers.startTimer(minutes: Double(customMinutes)) }
                        .buttonStyle(AccentButtonStyle())
                }
            }
        }
    }

    private var stopwatchPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Stopwatch")
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                Text(TimerStore.format(timers.elapsed(at: context.date), tenths: true))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                Button(timers.stopwatchRunning ? "Pause" : (timers.stopwatchUsed ? "Resume" : "Start")) {
                    timers.toggleStopwatch()
                }
                .buttonStyle(AccentButtonStyle())
                if timers.stopwatchRunning {
                    SmallPill(title: "Lap") { timers.lap() }
                } else if timers.stopwatchUsed {
                    SmallPill(title: "Reset") { timers.resetStopwatch() }
                }
            }
            ForEach(Array(timers.laps.prefix(2).enumerated()), id: \.offset) { index, lap in
                HStack {
                    Text("Lap \(timers.laps.count - index)")
                    Spacer()
                    Text(TimerStore.format(lap, tenths: true)).monospacedDigit()
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)
            }
        }
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(L(text).uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Color.secondary)
    }
}

struct SmallPill: View {
    let title: String
    var fill = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(L(title))
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: fill ? .infinity : nil)
                .background(Capsule().fill(Color.primary.opacity(hover ? 0.16 : 0.09)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Clipboard

struct IslandClipboard: View {
    @ObservedObject private var store = ClipboardStore.shared
    @State private var copiedID: UUID?

    var body: some View {
        if store.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 22, weight: .light))
                Text(AppSettings.shared.clipboardEnabled ? "Things you copy will appear here" : "Clipboard history is off in Settings")
                    .font(.system(size: 11))
            }
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.items) { item in
                            Button {
                                store.copy(item)
                                withAnimation(.easeOut(duration: 0.15)) { copiedID = item.id }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    withAnimation { if copiedID == item.id { copiedID = nil } }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    if let image = item.image {
                                        Image(nsImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(maxWidth: .infinity, maxHeight: 70)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    } else {
                                        Text(item.text)
                                            .font(.system(size: 11))
                                            .lineLimit(5)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .topLeading)
                                    }
                                    Spacer(minLength: 0)
                                    HStack {
                                        if item.pinned {
                                            Image(systemName: "pin.fill").foregroundStyle(Theme.accent)
                                        }
                                        Text(item.pinned ? L("Pinned") : item.date.formatted(.relative(presentation: .named)))
                                        Spacer()
                                        if copiedID == item.id {
                                            Label(L("Copied"), systemImage: "checkmark").foregroundStyle(Theme.accent)
                                        }
                                    }
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.secondary)
                                }
                                .padding(10)
                                .frame(width: 150)
                                .frame(maxHeight: .infinity)
                                .glassChip(radius: 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                MenuButton("Copy") { store.copy(item) }
                                if !item.isImage {
                                    MenuButton(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
                                }
                                MenuButton("Remove") { store.remove(item) }
                            }
                            .help(L("Click to copy again"))
                        }
                    }
                }
                VStack {
                    IconButton(symbol: "trash", help: "Clear history") { store.clear() }
                    Spacer()
                }
            }
        }
    }
}

// MARK: Notes

struct IslandNotes: View {
    @ObservedObject private var notes = NotesStore.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $notes.text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
            if notes.text.isEmpty {
                Text(L("Jot something down… it is saved automatically."))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .glassChip(radius: 20)
    }
}

// MARK: Mirror (camera)

struct IslandMirror: View {
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if status == .denied || status == .restricted {
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash").font(.system(size: 22, weight: .light))
                        Button(L("Allow camera in Settings")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    }
                    .foregroundStyle(Color.secondary)
                } else {
                    CameraPreview()
                }
            }
            .frame(width: 240)
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Mirror")
                Text(L("Check your look before a call."))
                    .font(.system(size: 13, weight: .medium))
                Text(L("The camera only runs while this tab is open. Nothing is recorded."))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.start()
        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {}

    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: ()) {
        nsView.stop()
    }
}

final class CameraPreviewView: NSView {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                guard granted else { return }
                DispatchQueue.main.async { [weak self] in self?.configureAndRun() }
            }
        default:
            break
        }
    }

    private func configureAndRun() {
        if session.inputs.isEmpty,
           let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if previewLayer == nil {
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = bounds
            if let connection = preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            layer?.addSublayer(preview)
            previewLayer = preview
        }
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            if session.isRunning { session.stopRunning() }
        }
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}
