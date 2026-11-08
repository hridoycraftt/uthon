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
            Section("Dock") {
                Picker("Screen edge", selection: $settings.edge) {
                    ForEach(DockEdge.allCases) { edge in
                        Text(edge.title).tag(edge)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Keep visible (pinned)", isOn: $settings.pinned)
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, newValue in LoginItem.set(newValue) }
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
                Text("Tip: move the mouse to the \(settings.edge.title.lowercased()) edge of the screen to open the dock.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 600)
    }
}
