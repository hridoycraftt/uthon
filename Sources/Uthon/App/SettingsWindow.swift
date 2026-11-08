import SwiftUI
import AppKit
import ServiceManagement

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "\(AppInfo.name) Settings"
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
    @ObservedObject private var settings = AppSettings.shared
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Look") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, newValue in LoginItem.set(newValue) }
            }

            Section("Top island") {
                Toggle("Show the island at the top of the screen", isOn: $settings.islandEnabled)
                Picker("Open island style", selection: $settings.islandStyle) {
                    ForEach(IslandStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.islandEnabled)
                Text("Hover over the notch (or the top centre of the screen) to open it. Drop files on it to put them on the shelf.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Side dock") {
                Toggle("Show the side dock", isOn: $settings.sideDockEnabled)
                Picker("Screen edge", selection: $settings.edge) {
                    ForEach(DockEdge.allCases) { edge in
                        Text(edge.title).tag(edge)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.sideDockEnabled)
                Toggle("Keep visible (pinned)", isOn: $settings.pinned)
                    .disabled(!settings.sideDockEnabled)
            }

            Section("Widgets") {
                ForEach(WidgetKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { settings.isVisible(kind) },
                        set: { settings.setVisible(kind, $0) }
                    )) {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            }

            Section("Care reminders") {
                Toggle("Drink water", isOn: $settings.waterEnabled)
                Stepper("Every \(settings.waterMinutes) minutes",
                        value: $settings.waterMinutes, in: 10...180, step: 5)
                    .disabled(!settings.waterEnabled)
                Toggle("Posture & stretch", isOn: $settings.postureEnabled)
                Stepper("Every \(settings.postureMinutes) minutes",
                        value: $settings.postureMinutes, in: 10...180, step: 5)
                    .disabled(!settings.postureEnabled)
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
        .frame(width: 440, height: 680)
    }
}
