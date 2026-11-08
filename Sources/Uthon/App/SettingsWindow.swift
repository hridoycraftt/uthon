import SwiftUI
import AppKit
import ServiceManagement

enum SettingsTab: Hashable {
    case general, island, alerts, dock, care
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
            w.title = "Customize \(AppInfo.name)"
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

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            IslandSettings().tabItem { Label("Island", systemImage: "capsule.tophalf.filled") }.tag(SettingsTab.island)
            AlertsSettings().tabItem { Label("Alerts", systemImage: "bell.badge") }.tag(SettingsTab.alerts)
            DockSettings().tabItem { Label("Side Dock", systemImage: "sidebar.right") }.tag(SettingsTab.dock)
            CareSettings().tabItem { Label("Care", systemImage: "heart") }.tag(SettingsTab.care)
        }
        .frame(width: 520, height: 660)
    }
}

private struct GeneralSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Look") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Glass", selection: $settings.glassClarity) {
                    ForEach(GlassClarity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(glassNote)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Startup & shortcut") {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, newValue in LoginItem.set(newValue) }
                Toggle("⌃⌥Space opens the island from anywhere", isOn: $settings.hotkeyEnabled)
            }
            Section("Weather") {
                TextField("City", text: $settings.weatherCity, prompt: Text("e.g. Dhaka"))
                Picker("Unit", selection: $settings.weatherFahrenheit) {
                    Text("°C").tag(false)
                    Text("°F").tag(true)
                }
                .pickerStyle(.segmented)
                Text("Uses the free Open-Meteo service. Only the city name is sent.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("Everything stays on this Mac: no account, no tracking, no cloud. Clipboard history is kept in memory only and skips passwords.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Text("\(AppInfo.name) \(AppInfo.version)")
                    Spacer()
                    Text("Made for family").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private var glassNote: String {
    if #available(macOS 26.0, *) {
        return "Automatic uses Apple's Liquid Glass, exactly like macOS 26 itself. Clear and Frosted are manual overrides."
    }
    return "Automatic uses the same frosted material as macOS Control Center on this Mac. Clear and Frosted are manual overrides."
}

private struct IslandSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Top island") {
                Toggle("Show the island at the top of the screen", isOn: $settings.islandEnabled)
                Picker("Open island", selection: $settings.islandStyle) {
                    ForEach(IslandStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.islandEnabled)
            }
            Section("Size") {
                LabeledSlider(title: "Island size", value: $settings.islandScale, range: 0.85...1.4, step: 0.05,
                              format: { "\(Int(($0 * 100).rounded()))%" })
                LabeledSlider(title: "Tab icon size", value: $settings.tabIconSize, range: 11...22, step: 1,
                              format: { "\(Int($0)) pt" })
            }
            Section {
                ForEach(Array(settings.orderedHomeWidgets.enumerated()), id: \.element) { index, widget in
                    ReorderRow(
                        title: widget.slots > 1 ? "\(widget.title) (2 slots)" : widget.title,
                        symbol: widget.symbol,
                        isOn: Binding(
                            get: { settings.enabledHomeWidgets.contains(widget.rawValue) },
                            set: { settings.setHomeWidget(widget, $0) }
                        ),
                        locked: !settings.canEnable(widget),
                        canMoveUp: index > 0,
                        canMoveDown: index < settings.orderedHomeWidgets.count - 1,
                        move: { settings.moveHomeWidget(widget, by: $0) }
                    )
                }
            } header: {
                Text("Home widgets · \(settings.homeSlotsUsed) of \(HomeWidget.maxSlots) slots used")
            } footer: {
                Text("Choose what the Home tab shows and in which order. Music takes two slots. Tip: press Edit on the open island to do this right there.")
            }
            Section {
                ForEach(Array(settings.orderedControls.enumerated()), id: \.element) { index, kind in
                    ReorderRow(
                        title: kind.title,
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
                Text("Controls · \(settings.controls.count) of \(ControlKind.maxSlots)")
            }
            Section {
                ForEach(Array(settings.orderedIslandTabs.enumerated()), id: \.element) { index, tab in
                    ReorderRow(
                        title: tab.title,
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
                Text("Tabs")
            } footer: {
                Text("Turn tabs on or off and use the arrows to change their order, like customizing Control Center on iPhone.")
            }
            Section("Live activities (closed island)") {
                Toggle("Music: artwork and equalizer", isOn: $settings.liveMusic)
                Toggle("Timer and stopwatch countdown", isOn: $settings.liveTimers)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlertsSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var trusted = MediaKeyTap.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Volume and brightness", isOn: $settings.hudEnabled)
                Toggle("Replace the macOS volume/brightness popup", isOn: $settings.replaceSystemHUD)
                    .disabled(!settings.hudEnabled)
                    .onChange(of: settings.replaceSystemHUD) { _, on in
                        if on { MediaKeyTap.shared.update(prompt: true) } else { MediaKeyTap.shared.update() }
                        trusted = MediaKeyTap.isTrusted
                    }
                if settings.replaceSystemHUD && !trusted {
                    HStack {
                        Text("Needs Accessibility permission").font(.footnote).foregroundStyle(.orange)
                        Spacer()
                        Button("Open Settings") { MediaKeyTap.openAccessibilitySettings() }
                    }
                }
            } header: {
                Text("Island pop-ups")
            } footer: {
                Text("Scroll on the open island to change volume; swipe sideways to skip songs.")
            }
            Section {
                Toggle("New song", isOn: $settings.peekTrack)
                Toggle("AirPods and headphones connect (with battery)", isOn: $settings.peekHeadphones)
                Toggle("Upcoming meeting (5 minutes before, with Join)", isOn: $settings.peekMeetings)
                Toggle("Finished downloads", isOn: $settings.peekDownloads)
                Toggle("New screenshots", isOn: $settings.peekScreenshots)
                Toggle("Caps Lock", isOn: $settings.peekCapsLock)
                if DeviceBatteryStore.shared.hasInternalBattery {
                    Toggle("Charging animation", isOn: $settings.peekCharging)
                }
                Toggle("Clipboard history", isOn: $settings.clipboardEnabled)
            }
        }
        .formStyle(.grouped)
        .onAppear { trusted = MediaKeyTap.isTrusted }
    }
}

private struct DockSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Side dock") {
                Toggle("Show the side dock", isOn: $settings.sideDockEnabled)
                LabeledSlider(title: "Dock size", value: $settings.dockScale, range: 0.85...1.4, step: 0.05,
                              format: { "\(Int(($0 * 100).rounded()))%" })
                    .disabled(!settings.sideDockEnabled)
                Picker("Screen edge", selection: $settings.edge) {
                    ForEach(DockEdge.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.sideDockEnabled)
                Toggle("Keep visible (pinned)", isOn: $settings.pinned)
                    .disabled(!settings.sideDockEnabled)
            }
            Section {
                ForEach(Array(settings.orderedWidgets.enumerated()), id: \.element) { index, kind in
                    ReorderRow(
                        title: kind.title,
                        symbol: kind.symbol,
                        isOn: Binding(get: { settings.isVisible(kind) }, set: { settings.setVisible(kind, $0) }),
                        locked: false,
                        canMoveUp: index > 0,
                        canMoveDown: index < settings.orderedWidgets.count - 1,
                        move: { settings.moveWidget(kind, by: $0) }
                    )
                }
            } header: {
                Text("Widgets")
            } footer: {
                Text("Turn widgets on or off and change their order.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct CareSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Care reminders") {
                Toggle("Drink water", isOn: $settings.waterEnabled)
                Stepper("Every \(settings.waterMinutes) minutes", value: $settings.waterMinutes, in: 10...180, step: 5)
                    .disabled(!settings.waterEnabled)
                Toggle("Posture & stretch", isOn: $settings.postureEnabled)
                Stepper("Every \(settings.postureMinutes) minutes", value: $settings.postureMinutes, in: 10...180, step: 5)
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
            Text(title)
            Spacer()
            Button { withAnimation { move(-1) } } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
            Button { withAnimation { move(1) } } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
            Toggle("", isOn: $isOn)
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
            Text(title)
            Slider(value: $value, in: range, step: step)
            Text(format(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
