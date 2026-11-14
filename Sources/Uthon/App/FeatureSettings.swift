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
            Section {
                Toggle(L("Show a summary of new notifications"), isOn: $library.digestEnabled)
                Picker(L("Every"), selection: $library.digestIntervalHours) {
                    ForEach([1, 2, 3, 4, 6, 8, 12], id: \.self) { Text("\($0) " + L($0 == 1 ? "hour" : "hours")).tag($0) }
                }
                .disabled(!library.digestEnabled)
                Toggle(L("Summarize in words with Apple Intelligence (on this Mac)"), isOn: $library.digestUseAI)
                    .disabled(!library.digestEnabled || !AIService.shared.isAvailable)
                if !AIService.shared.isAvailable {
                    Text(L(AIService.shared.availability.message) + " — " + L("without it the summary lists who wrote and how often."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HomeWidgetToggle(widget: .digest)
                Button(L("Show the summary now")) { NotificationDigest.shared.showNow() }
            } header: {
                Text(L("Summary"))
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
                                Image(nsImage: FileIconCache.icon(url.path)).resizable().frame(width: 18, height: 18)
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

    private var status: String {
        if !library.dimEnabled { return L("Off") }
        if dimmer.isPaused { return L("Paused until 6 AM") }
        if dimmer.level > 0.001 { return L("Dimming now") + " · \(Int((dimmer.level * 100).rounded()))%" }
        let w = dimmer.nightWindow(now: Date())
        if library.dimSchedule == .darkMode { return L("Starts when macOS switches to Dark Mode") }
        return L("Starts at") + " " + w.start.formatted(.dateTime.hour().minute().locale(Localization.locale))
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: dimmer.level > 0.001 ? "moon.fill" : "moon")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.indigo.gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(isOn: $library.dimEnabled) {
                            Text(L("Dim at night")).font(.system(size: 15, weight: .semibold))
                        }
                        .toggleStyle(.switch)
                        Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text(L("Lowers the light of your screens at night and makes them a little warmer, gliding in and out over half an hour. Blacks stay black and text stays sharp. Works on a MacBook, an iMac and external displays."))
            }

            Section(L("When")) {
                Picker(L("Schedule"), selection: $library.dimSchedule) {
                    ForEach(DimSchedule.allCases) { Text(L($0.title)).tag($0) }
                }
                if library.dimSchedule == .sun {
                    if let place = weather.place,
                       let sun = NightDimmer.sunTimes(for: Date(), latitude: place.latitude, longitude: place.longitude, timeZone: place.timeZone) {
                        LabeledContent(place.city) {
                            HStack(spacing: 10) {
                                Label(clock(sun.sunset, place.timeZone), systemImage: "sunset.fill")
                                Label(clock(sun.sunrise, place.timeZone), systemImage: "sunrise.fill")
                            }
                            .foregroundStyle(.secondary)
                        }
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

            Section {
                HStack(spacing: 8) {
                    Text(L("Strength"))
                    Image(systemName: "sun.max").foregroundStyle(.secondary)
                    Slider(value: $library.dimStrength, in: 0.1...0.6, step: 0.05)
                    Image(systemName: "sun.min").foregroundStyle(.secondary)
                    Text("\(Int((library.dimStrength * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Text(L("Warmth"))
                    Image(systemName: "circle.fill").foregroundStyle(Color(white: 0.85))
                    Slider(value: $library.dimWarmth, in: 0...1, step: 0.1)
                    Image(systemName: "circle.fill").foregroundStyle(Color.orange)
                    Text(library.dimWarmth < 0.05 ? L("None") : "\(Int((library.dimWarmth * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
                Picker(L("Dim"), selection: $library.dimTarget) {
                    Text(L("Every screen")).tag(DimTarget.screen)
                    Text(L("Only Nook")).tag(DimTarget.uthon)
                }
                .pickerStyle(.segmented)
                HStack {
                    Button {
                        dimmer.preview()
                    } label: {
                        Label(dimmer.previewing ? L("Previewing…") : L("Preview"), systemImage: "eye")
                    }
                    .disabled(dimmer.previewing)
                    Spacer()
                    Toggle(L("Not tonight (until 6 AM)"), isOn: Binding(
                        get: { dimmer.isPaused },
                        set: { $0 ? dimmer.pauseForTonight() : dimmer.resume() }
                    ))
                }
            } header: {
                Text(L("How much"))
            } footer: {
                Text(L("Moving a slider shows the result for a moment."))
            }
            .disabled(!library.dimEnabled)
            .onChange(of: library.dimStrength) { _, _ in dimmer.preview(seconds: 2.5) }
            .onChange(of: library.dimWarmth) { _, _ in dimmer.preview(seconds: 2.5) }
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
                        Image(nsImage: FileIconCache.icon(path)).resizable().frame(width: 20, height: 20)
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

// MARK: AI assistant

struct AISettings: View {
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var ai = AIService.shared
    @State private var testAnswer = ""

    var body: some View {
        Form {
            Section {
                Toggle(L("Show the AI tab on the island"), isOn: $library.aiEnabled)
                HStack {
                    Image(systemName: ai.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(ai.isAvailable ? .green : .orange)
                    Text(L(ai.availability.message))
                    Spacer()
                    if ai.availability == .notEnabled {
                        Button(L("Open settings…")) { ai.openAppleIntelligenceSettings() }
                    }
                }
            } footer: {
                Text(L("Uses Apple Intelligence on this Mac: private, free, works offline. Ask questions, summarize, fix writing, translate between Bangla and English, write replies."))
            }
            Section(L("Answers")) {
                Picker(L("Answer in"), selection: $library.aiAnswerLanguage) {
                    Text(L("Same as Nook")).tag("auto")
                    Text("বাংলা").tag("bn")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
                HStack {
                    Button(L("Try it")) {
                        testAnswer = "…"
                        Task {
                            let answer = (try? await ai.ask("Say hello in one short friendly sentence.",
                                                            instructions: "Reply in \(AIService.answerLanguage)."))
                                ?? L("Could not answer that. Try rephrasing.")
                            await MainActor.run { testAnswer = answer }
                        }
                    }
                    .disabled(!ai.isAvailable || ai.busy)
                    Text(testAnswer).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .disabled(!library.aiEnabled)
        }
        .formStyle(.grouped)
    }
}

// MARK: Ramadan & Hijri

struct RamadanSettings: View {
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var weather = WeatherStore.shared
    @State private var playing = false

    private func clock(_ date: Date) -> String { Ramadan.clock(date) }

    var body: some View {
        Form {
            // At a glance: today's Hijri date and, in Ramadan, the next sehri and iftar.
            Section {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.mint.gradient))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Hijri.text(for: context.date))
                                .font(.system(size: 17, weight: .semibold))
                            Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Localization.locale)))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(L(Hijri.ramadanActive ? "Ramadan mode is on" : "Ramadan mode is off"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Hijri.ramadanActive ? Color.mint : Color.secondary)
                        }
                        Spacer(minLength: 8)
                        if Hijri.ramadanActive, let next = Ramadan.next(after: context.date) {
                            VStack(alignment: .trailing, spacing: 4) {
                                timeChip(L("Sehri ends"), next.sehriEnds, symbol: "sunrise.fill", now: context.date)
                                timeChip(L("Iftar"), next.iftar, symbol: "sunset.fill", now: context.date)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Picker(L("Ramadan mode"), selection: $library.ramadanMode) {
                    Text(L("Automatic")).tag("auto")
                    Text(L("Always on")).tag("on")
                    Text(L("Off")).tag("off")
                }
                .pickerStyle(.segmented)
                HomeWidgetToggle(widget: .ramadan)
            } footer: {
                Text(L("Automatic turns Ramadan mode on during the month of Ramadan only: the widget counts down to sehri and iftar, and the reminders below are sent."))
            }

            Section(L("Hijri date")) {
                Toggle(L("Show the Hijri date at the top of the island"), isOn: $library.hijriInHeader)
                Picker(L("Adjust for my country"), selection: $library.hijriAdjust) {
                    ForEach(-2...2, id: \.self) { n in
                        Text(n == 0 ? L("None") : (n > 0 ? "+\(n)" : "\(n)")).tag(n)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent(L("Today"), value: Hijri.text())
                Text(L("The Hijri date follows the Umm al-Qura calendar. Moon sighting can differ by a day or two in your country: adjust it here."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker(L("Before sehri ends"), selection: $library.sehriReminderMinutes) {
                    Text(L("Off")).tag(0)
                    ForEach([10, 15, 30, 45, 60], id: \.self) { Text("\($0) " + L("minutes before")).tag($0) }
                }
                Toggle(L("At iftar time"), isOn: $library.iftarReminder)
                if weather.place == nil {
                    HStack {
                        Label(L("Set your city to get sehri and iftar times."), systemImage: "location.slash")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Set your city")) { SettingsWindowController.shared.show(tab: .general) }
                    }
                }
            } header: {
                Text(L("Reminders"))
            } footer: {
                if library.ramadanMode == "off" {
                    Text(L("Turn on Ramadan mode to get these reminders."))
                }
            }
            .disabled(library.ramadanMode == "off")

            Section {
                HStack {
                    Picker(L("Sound"), selection: $library.prayerSound) {
                        Text(L("No sound")).tag("off")
                        Divider()
                        ForEach(Ramadan.systemSounds, id: \.self) { Text($0).tag($0) }
                        if library.prayerSound.hasPrefix("/") {
                            Divider()
                            Text((library.prayerSound as NSString).lastPathComponent).tag(library.prayerSound)
                        }
                    }
                    Button {
                        if playing { Ramadan.stopSound(); playing = false }
                        else { Ramadan.playPrayerSound(); playing = true }
                    } label: {
                        Image(systemName: playing ? "stop.fill" : "play.fill").frame(width: 14)
                    }
                    .help(L(playing ? "Stop" : "Play"))
                    .disabled(library.prayerSound == "off")
                }
                Button(L("Choose my own sound (e.g. adhan)…")) { Ramadan.pickSoundFile() }
            } header: {
                Text(L("Sound at prayer time and iftar"))
            } footer: {
                Text(L("Your own audio file stays on your Mac; Nook only plays it."))
            }
            .onChange(of: library.prayerSound) { _, _ in Ramadan.stopSound(); playing = false }
            .onDisappear { Ramadan.stopSound(); playing = false }
            // The button goes back to "play" when the sound ends by itself.
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                if playing && !Ramadan.isPlaying { playing = false }
            }
        }
        .formStyle(.grouped)
    }

    private func timeChip(_ title: String, _ time: Date, symbol: String, now: Date) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(Color.orange)
            Text(title + " " + clock(time)).foregroundStyle(.primary)
            Text(Ramadan.countdown(to: time, from: now)).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
    }
}
