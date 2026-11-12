import SwiftUI
import AppKit
import ApplicationServices

/// "Show on Home" switch for a widget: adds it to the first page with room.
struct HomeWidgetToggle: View {
    let widget: HomeWidget
    @ObservedObject private var settings = AppSettings.shared
    @State private var noRoom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(L("Show on Home"), isOn: Binding(
                get: { settings.isOnHome(HomeItem(widget)) },
                set: { on in
                    if on {
                        noRoom = !Self.add(widget)
                    } else {
                        settings.removeFromHome(HomeItem(widget))
                        noRoom = false
                    }
                }
            ))
            if noRoom {
                Text(L("Home is full. Remove a widget or add a page in Home settings."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @discardableResult
    static func add(_ widget: HomeWidget) -> Bool {
        let settings = AppSettings.shared
        let item = HomeItem(widget)
        if settings.isOnHome(item) { return true }
        for page in 0..<HomeWidget.maxPages {
            if page >= settings.pageCount { settings.setPageCount(page + 1) }
            if settings.addToHome(item, page: page) { return true }
        }
        return false
    }
}

// MARK: Quran & Hadith

struct VerseSettings: View {
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var store = DailyVerseStore.shared

    var body: some View {
        Form {
            Section {
                Toggle(L("Daily Quran & Hadith"), isOn: $library.verseEnabled)
                HomeWidgetToggle(widget: .verse)
                    .disabled(!library.verseEnabled)
            } footer: {
                Text(L("A new ayah or hadith as often as you like (every hour up to once a day), with its meaning. It is kept on this Mac, so it also shows without internet."))
            }
            Section(L("What to show")) {
                Picker(L("Show"), selection: $library.verseSource) {
                    ForEach(VerseSource.allCases) { Text(L($0.title)).tag($0) }
                }
                Picker(L("Meaning in"), selection: $library.verseTranslation) {
                    ForEach(VerseTranslation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(L("Show the Arabic text"), isOn: $library.verseShowArabic)
                Picker(L("A new one every"), selection: $library.verseIntervalHours) {
                    ForEach(DailyVerseStore.intervals, id: \.self) { h in
                        Text(h == 24 ? L("Day (24 hours)") : "\(h) " + L(h == 1 ? "hour" : "hours")).tag(h)
                    }
                }
                Toggle(L("Show the new one on the island when it arrives"), isOn: $library.verseNewPeek)
                LabeledContent(L("Next one"), value: DailyVerseStore.nextChange(hours: library.verseIntervalHours)
                    .formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(Localization.locale)))
            }
            .disabled(!library.verseEnabled)
            Section(L("Today")) {
                if let text = store.current {
                    VStack(alignment: .leading, spacing: 6) {
                        if library.verseShowArabic, !text.arabic.isEmpty {
                            Text(text.arabic)
                                .font(.system(size: 16))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(4)
                        }
                        Text(text.translation).lineLimit(6)
                        Text(text.reference).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                    .textSelection(.enabled)
                } else if let error = store.error {
                    Text(error).foregroundStyle(.secondary)
                } else {
                    Text(L("Loading…")).foregroundStyle(.secondary)
                }
                HStack {
                    Button(L("Show another")) { store.refresh(another: true) }
                    if let text = store.current, let url = URL(string: text.link) {
                        Button(L("Read on the web")) { NSWorkspace.shared.open(url) }
                    }
                    if store.loading { ProgressView().controlSize(.small) }
                }
            }
            .disabled(!library.verseEnabled)
            Section {
                Text(L("Quran: Arabic (Uthmani) and translations from alquran.cloud (Bangla: Muhiuddin Khan, English: Saheeh International). Hadith: Sahih al-Bukhari and Sahih Muslim from the open hadith-api collection. Nook does not write or change any text."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Sources"))
            }
        }
        .formStyle(.grouped)
        .onAppear { store.refresh() }
    }
}

// MARK: Internet & Wi-Fi

struct NetworkSettings: View {
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var net = NetworkStore.shared

    var body: some View {
        Form {
            Section {
                Toggle(L("Watch the internet connection"), isOn: $library.networkEnabled)
                HomeWidgetToggle(widget: .network)
                    .disabled(!library.networkEnabled)
                Toggle(L("Pop up when the internet drops or comes back"), isOn: $library.networkPeeks)
                    .disabled(!library.networkEnabled)
            } footer: {
                Text(L("Shows Wi-Fi signal and live download and upload speed. Uses almost no battery."))
            }
            Section(L("Speed test")) {
                Picker(L("Test size"), selection: $library.speedTestMB) {
                    Text("10 MB").tag(10)
                    Text("25 MB").tag(25)
                    Text("50 MB").tag(50)
                }
                .pickerStyle(.segmented)
                HStack {
                    Button(net.testing ? L(net.testPhase) + "…" : L("Run speed test")) { net.runSpeedTest() }
                        .disabled(net.testing || net.link == .offline)
                    if net.testing { ProgressView().controlSize(.small) }
                    Spacer()
                    if let test = net.lastTest {
                        Text("↓ \(NetworkStore.mbps(test.downMbps))  ↑ \(NetworkStore.mbps(test.upMbps)) Mbps · \(Int(test.pingMs)) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = net.testError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            .disabled(!library.networkEnabled)
            Section {
                LabeledContent(L("Connection"), value: connection)
                if net.link == .wifi {
                    LabeledContent(L("Signal"), value: L(NetworkStore.quality(rssi: net.rssi)) + (net.rssi.map { " (\($0) dBm)" } ?? ""))
                    if let rate = net.linkRate {
                        LabeledContent(L("Link speed"), value: "\(Int(rate)) Mbps")
                    }
                    LabeledContent(L("Network name"), value: net.ssid ?? L("Hidden by macOS"))
                }
                if net.ssid == nil {
                    Button(L("Show the Wi-Fi name…")) { net.askForWiFiName() }
                }
            } header: {
                Text(L("Right now"))
            } footer: {
                Text(L("macOS shows the Wi-Fi name only to apps allowed to use Location. Nook never stores or sends your location."))
            }
            .disabled(!library.networkEnabled)
        }
        .formStyle(.grouped)
        .onAppear { net.start() }
    }

    private var connection: String {
        switch net.link {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .other: return L("Online")
        case .offline: return L("Offline")
        }
    }
}

// MARK: Notifications

struct NotificationSettings: View {
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var mirror = NotificationMirror.shared

    var body: some View {
        Form {
            Section {
                Toggle(L("Show notifications on the island"), isOn: $library.notificationsEnabled)
            } footer: {
                Text(L("New messages from WhatsApp, Messages, Mail and other apps appear for a moment on the island. macOS still shows its own banners as usual."))
            }
            Section {
                HStack {
                    Image(systemName: mirror.hasAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(mirror.hasAccess ? .green : .orange)
                    Text(mirror.hasAccess ? L("Full Disk Access is on") : L("Full Disk Access is needed"))
                    Spacer()
                    Button(L("Check again")) { mirror.checkAccess() }
                }
                if !mirror.hasAccess {
                    Text(L("macOS doesn't let apps read other apps' notifications directly. With Full Disk Access, Nook reads the notification list on this Mac. Nothing leaves your Mac."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(L("Open Full Disk Access settings…")) { mirror.openFullDiskAccessSettings() }
                    Text(L("Turn on Nook in the list (use + to add it from Applications if it's missing), then come back and press Check again."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L("Permission"))
            }
            .disabled(!library.notificationsEnabled)
            Section(L("How they look")) {
                Toggle(L("Hide the message (show only the app)"), isOn: $library.notificationHideContent)
                Toggle(L("Skip notifications from the app I'm using"), isOn: $library.notificationQuietWhenFocused)
                LabeledSlider(title: "Show for", value: $library.notificationSeconds, range: 0.5...10, step: 0.5) {
                    ($0.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int($0))" : String(format: "%.1f", $0)) + " " + L("sec")
                }
                Button(L("Show a test notification")) {
                    NotificationMirror.shared.deliver(.init(
                        id: -1, bundleID: "com.apple.MobileSMS", appName: "Messages",
                        title: L("Mum"), subtitle: "", body: L("Dinner is ready, come home soon!"), date: Date()))
                }
            }
            .disabled(!library.notificationsEnabled)
            Section {
                let apps = Array(Set(mirror.seenApps + library.mutedNotificationApps)).sorted()
                if apps.isEmpty {
                    Text(L("Apps appear here after they send a notification."))
                        .foregroundStyle(.secondary)
                }
                ForEach(apps, id: \.self) { bundle in
                    Toggle(isOn: Binding(
                        get: { !library.mutedNotificationApps.contains(bundle) },
                        set: { on in
                            if on { library.mutedNotificationApps.removeAll { $0 == bundle } }
                            else if !library.mutedNotificationApps.contains(bundle) { library.mutedNotificationApps.append(bundle) }
                        }
                    )) {
                        HStack {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                            }
                            Text(NotificationMirror.appName(for: bundle))
                        }
                    }
                }
            } header: {
                Text(L("Apps"))
            } footer: {
                Text(L("Turn an app off to keep its notifications off the island."))
            }
            .disabled(!library.notificationsEnabled)
        }
        .formStyle(.grouped)
        .onAppear { mirror.checkAccess() }
    }
}

// MARK: Night dimming

struct NightSettings: View {
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var dimmer = NightDimmer.shared
    @ObservedObject private var weather = WeatherStore.shared

    var body: some View {
        Form {
            Section {
                Toggle(L("Dim at night"), isOn: $library.dimEnabled)
            } footer: {
                Text(L("Gently darkens the screen at night, fading in and out over half an hour. Works on a MacBook, an iMac and external displays."))
            }
            Section(L("When")) {
                Picker(L("Schedule"), selection: $library.dimSchedule) {
                    ForEach(DimSchedule.allCases) { Text(L($0.title)).tag($0) }
                }
                if library.dimSchedule == .sun {
                    if let place = weather.place,
                       let sun = NightDimmer.sunTimes(for: Date(), latitude: place.latitude, longitude: place.longitude, timeZone: place.timeZone) {
                        LabeledContent(place.city, value: L("Sunset") + " " + clock(sun.sunset, place.timeZone) + " · " + L("Sunrise") + " " + clock(sun.sunrise, place.timeZone))
                    } else {
                        HStack {
                            Text(L("Set your city to follow sunset. Until then: 7 PM to 6 AM."))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(L("Set your city")) { SettingsWindowController.shared.show(tab: .general) }
                        }
                    }
                }
                if library.dimSchedule == .custom {
                    Picker(L("From"), selection: $library.dimStartHour) {
                        ForEach(0..<24, id: \.self) { Text(hour($0)).tag($0) }
                    }
                    Picker(L("Until"), selection: $library.dimEndHour) {
                        ForEach(0..<24, id: \.self) { Text(hour($0)).tag($0) }
                    }
                }
            }
            .disabled(!library.dimEnabled)
            Section(L("How much")) {
                LabeledSlider(title: "Strength", value: $library.dimStrength, range: 0.1...0.6, step: 0.05) { "\(Int(($0 * 100).rounded()))%" }
                Picker(L("Dim"), selection: $library.dimTarget) {
                    ForEach(DimTarget.allCases) { Text(L($0.title)).tag($0) }
                }
                HStack {
                    Button(dimmer.previewing ? L("Previewing…") : L("Preview")) { dimmer.preview() }
                        .disabled(dimmer.previewing)
                    Spacer()
                    Text(L("Now") + ": \(Int((dimmer.level * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Toggle(L("Not tonight (until 6 AM)"), isOn: Binding(
                    get: { dimmer.isPaused },
                    set: { $0 ? dimmer.pauseForTonight() : dimmer.resume() }
                ))
            }
            .disabled(!library.dimEnabled)
        }
        .formStyle(.grouped)
    }

    private func clock(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Localization.locale
        f.timeZone = zone
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func hour(_ h: Int) -> String {
        let date = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour().minute().locale(Localization.locale))
    }
}

// MARK: Bottom dock

struct BottomDockSettings: View {
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var bottom = BottomDockController.shared
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section {
                Toggle(L("Show the bottom dock"), isOn: $library.bottomDockEnabled)
                Picker(L("Place"), selection: $library.bottomDockSide) {
                    ForEach(BottomDockSide.allCases) { Text(L($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!library.bottomDockEnabled)
                Toggle(L("Hide until the mouse reaches the bottom edge"), isOn: $library.bottomDockAutoHide)
                    .disabled(!library.bottomDockEnabled)
            } footer: {
                Text(L("A second dock beside the macOS Dock with your apps and live info. It stays out of full-screen apps."))
            }
            Section(L("Size and position")) {
                Toggle(L("Match the macOS Dock's size"), isOn: $library.bottomDockMatchDock)
                LabeledSlider(title: library.bottomDockMatchDock ? "Fine-tune" : "Size", value: $library.bottomDockScale,
                              range: 0.7...1.4, step: 0.05) { "\(Int(($0 * 100).rounded()))%" }
                LabeledSlider(title: "Distance", value: $library.bottomDockOffset, range: 0...400, step: 4) { "\(Int($0)) pt" }
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(trusted ? .green : .secondary)
                    Text(trusted ? L("Sits right next to the macOS Dock.") : L("Allow Accessibility so it knows exactly where the macOS Dock ends. Without it, Nook works it out from the Dock's settings."))
                        .font(.caption)
                    Spacer()
                    if !trusted {
                        Button(L("Allow…")) {
                            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
                        }
                        Button(L("Check again")) { trusted = AXIsProcessTrusted() }
                    }
                }
                if !trusted {
                    Text(L("Already turned on for Nook but still not working? macOS ties the permission to each version. In System Settings > Privacy & Security > Accessibility, select Nook (or the old Uthon), press − to remove it, then press Allow… here again."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(L("Open Accessibility settings…")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else if library.bottomDockMatchDock {
                    Text(L("Same height as the macOS Dock; it grows and shrinks with it."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if library.bottomDockEnabled, bottom.droppedCount > 0 {
                    Label(L("Not enough room beside the Dock, so the last items are hidden. Turn some items off, make it smaller, or make the macOS Dock smaller.")
                          + " (\(bottom.droppedCount) " + L("hidden") + ")",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if library.bottomDockEnabled, bottom.fitScale < 0.99 {
                    Text(L("Made a little smaller to fit beside the Dock."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!library.bottomDockEnabled)
            Section(L("What it shows")) {
                ForEach(BottomDockItem.allCases) { item in
                    Toggle(isOn: Binding(get: { library.isBottomDockItemOn(item) },
                                         set: { library.setBottomDockItem(item, $0) })) {
                        Label(L(item.title), systemImage: item.symbol)
                    }
                }
            }
            .disabled(!library.bottomDockEnabled)
            Section {
                ForEach(Array(library.bottomDockApps.enumerated()), id: \.element) { index, path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 20, height: 20)
                        Text(FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""))
                        Spacer()
                        Button { library.moveBottomDockApp(path, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless).disabled(index == 0)
                        Button { library.moveBottomDockApp(path, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless).disabled(index == library.bottomDockApps.count - 1)
                        Button { library.bottomDockApps.removeAll { $0 == path } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button(L("Add Apps…")) { library.pickBottomDockApps() }
            } header: {
                Text(L("Apps"))
            }
            .disabled(!library.bottomDockEnabled || !library.isBottomDockItemOn(.apps))
        }
        .formStyle(.grouped)
        .onAppear { trusted = AXIsProcessTrusted() }
        // Notice the permission as soon as it is given in System Settings.
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            let now = AXIsProcessTrusted()
            if now != trusted { trusted = now }
        }
    }
}
