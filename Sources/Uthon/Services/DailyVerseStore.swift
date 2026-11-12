import Foundation
import SwiftUI
import AppKit

/// What the Daily Verse widget shows.
enum VerseSource: String, CaseIterable, Identifiable {
    case quran, hadith, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quran: return "Quran ayah"
        case .hadith: return "Hadith"
        case .both: return "Both (alternate daily)"
        }
    }
}

enum VerseTranslation: String, CaseIterable, Identifiable {
    case bangla, english
    var id: String { rawValue }
    var title: String { self == .bangla ? "বাংলা" : "English" }
}

/// One ayah or hadith, as fetched from an established source. The text is never
/// written by Uthon itself: the Arabic and the translation come from the source.
struct DailyText: Codable, Equatable {
    var isQuran: Bool
    var arabic: String
    var translation: String
    /// "Al-Baqara 2:255" or "Sahih al-Bukhari 1".
    var reference: String
    /// Web page with the full text (quran.com / sunnah.com).
    var link: String
    /// yyyy-MM-dd this text was picked for.
    var day: String
    var translationKey: String
}

/// Fetches a daily Quran ayah (alquran.cloud: Uthmani text + Muhiuddin Khan's Bangla or
/// Saheeh International English) or a hadith (Sahih al-Bukhari / Sahih Muslim, from the
/// open hadith-api collection), and keeps the last one for offline use.
final class DailyVerseStore: ObservableObject {
    static let shared = DailyVerseStore()

    @Published private(set) var current: DailyText?
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    private let d = UserDefaults.standard
    private var task: Task<Void, Never>?

    private var timer: Timer?

    private init() {
        current = Persist.load(DailyText.self, key: "dailyText")
    }

    /// Checks once a minute whether the next text is due (cheap: no network unless it is).
    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    /// Screenshots and tests: show a fixed text without going online.
    func debugSet(_ text: DailyText?) {
        current = text
        error = nil
    }

    static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// How often a new text comes, in hours (Settings: 1, 2, 3, 4, 5, 6, 7, 8, 12 or 24).
    static let intervals = [1, 2, 3, 4, 5, 6, 7, 8, 12, 24]

    /// Number of the current period (local time), so a new text comes every `hours` hours.
    static func slotIndex(_ date: Date = Date(), hours: Int) -> Int {
        let local = date.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: date)) - 1_577_836_800
        return max(0, Int(local / (Double(max(hours, 1)) * 3600)))
    }

    /// Identifies the current period, e.g. "6h-1234".
    static func slotKey(_ date: Date = Date(), hours: Int) -> String {
        "\(hours)h-\(slotIndex(date, hours: hours))"
    }

    /// When the next text is due.
    static func nextChange(after date: Date = Date(), hours: Int) -> Date {
        let h = Double(max(hours, 1)) * 3600
        let offset = Double(TimeZone.current.secondsFromGMT(for: date))
        let local = date.timeIntervalSince1970 + offset
        return Date(timeIntervalSince1970: (floor(local / h) + 1) * h - offset)
    }

    /// Day number since 2020, used to pick the same text for everyone on a given day.
    static func dayIndex(_ date: Date = Date()) -> Int {
        let start = Date(timeIntervalSince1970: 1_577_836_800)
        return max(0, Int(date.timeIntervalSince(start) / 86400))
    }

    /// Which kind to show today for the chosen source.
    static func wantsQuran(_ source: VerseSource, day: Int) -> Bool {
        switch source {
        case .quran: return true
        case .hadith: return false
        case .both: return day % 2 == 0
        }
    }

    /// Deterministic pick for a day: spread over the whole range, different each day.
    static func pick(day: Int, salt: Int, range: ClosedRange<Int>) -> Int {
        let span = range.upperBound - range.lowerBound + 1
        let mixed = (day &* 7919 &+ salt &* 104_729) % span
        return range.lowerBound + (mixed < 0 ? mixed + span : mixed)
    }

    var needsRefresh: Bool {
        let library = UserLibrary.shared
        guard let current else { return true }
        let hours = library.verseIntervalHours
        let wantsQuran = Self.wantsQuran(library.verseSource, day: Self.slotIndex(hours: hours))
        return current.day != Self.slotKey(hours: hours)
            || current.translationKey != library.verseTranslation.rawValue
            || (library.verseSource != .both && current.isQuran != wantsQuran)
    }

    /// Load today's text unless it is already here. `another` picks a random one now.
    func refresh(another: Bool = false) {
        guard UserLibrary.shared.verseEnabled else { return }
        guard another || needsRefresh else { return }
        guard !loading else { return }
        let library = UserLibrary.shared
        let hours = library.verseIntervalHours
        let day = Self.slotIndex(hours: hours)
        let scheduled = !another
        let quran: Bool
        if another, library.verseSource == .both { quran = Bool.random() }
        else { quran = Self.wantsQuran(library.verseSource, day: day) }
        let translation = library.verseTranslation
        let salt = another ? Int.random(in: 1...100_000) : 0
        loading = true
        error = nil
        task?.cancel()
        task = Task { [weak self] in
            var result: DailyText?
            // A few tries: skip very long passages so the widget stays readable.
            for attempt in 0..<5 where result == nil {
                if Task.isCancelled { break }
                let text = quran
                    ? await Self.fetchAyah(number: Self.pick(day: day, salt: salt + attempt, range: 1...6236), translation: translation)
                    : await Self.fetchHadith(day: day, salt: salt + attempt, translation: translation)
                guard let text, Self.isMostly(text.translation, in: translation) else { continue }
                // Prefer passages that fit the Home tile; the reader window shows any length.
                let short = Self.tidy(text.translation).count <= 320 && text.arabic.count <= 360
                if short || attempt == 4 { result = text }
            }
            await MainActor.run {
                guard let self else { return }
                self.loading = false
                if var result {
                    result.day = Self.slotKey(hours: hours)
                    let isNew = self.current?.reference != result.reference
                    self.current = result
                    Persist.save(result, key: "dailyText")
                    // A new scheduled text: optionally show it on the island.
                    if scheduled, isNew, UserLibrary.shared.verseNewPeek {
                        IslandController.shared.showPeek(.verse(reference: result.reference,
                                                                text: Self.tidy(result.translation),
                                                                isQuran: result.isQuran), duration: 10)
                    }
                } else {
                    self.error = L("Couldn't load. Check the internet connection.")
                }
            }
        }
    }

    /// True when most letters are in the chosen language's script (Bangla or Latin), so a
    /// passage that is mostly Arabic is never shown as the "meaning".
    static func isMostly(_ text: String, in translation: VerseTranslation) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 8 else { return false }
        let matching = letters.filter { scalar in
            translation == .bangla ? (0x0980...0x09FF).contains(scalar.value) : scalar.isASCII
        }.count
        return Double(matching) / Double(letters.count) >= 0.6
    }

    /// For the small tile only: drops the book references some hadith translations end with,
    /// e.g. "[৫৫৪] (আধুনিক প্রকাশনী- ৬৯১৮, ইসলামিক ফাউন্ডেশন- ৬৯২৮)". The reader shows the full text.
    static func tidy(_ text: String) -> String {
        var t = text
        for pattern in [#"\s*\((আধুনিক প্রকাশনী|ইসলামিক ফাউন্ডেশন|ইসলামিক ফা)[^)]*\)?\s*$"#,
                        #"\s*\[[০-৯0-9,\s\-]+\]\s*$"#] {
            if let range = t.range(of: pattern, options: .regularExpression) { t.removeSubrange(range) }
        }
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    // MARK: Sources

    private static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Nook", forHTTPHeaderField: "User-Agent")
        guard let reply = try? await URLSession.shared.data(for: request),
              (reply.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return reply.0
    }

    static func ayahURL(number: Int, translation: VerseTranslation) -> URL {
        let edition = translation == .bangla ? "bn.bengali" : "en.sahih"
        return URL(string: "https://api.alquran.cloud/v1/ayah/\(number)/editions/quran-uthmani,\(edition)")!
    }

    static func fetchAyah(number: Int, translation: VerseTranslation) async -> DailyText? {
        guard let data = await get(ayahURL(number: number, translation: translation)) else { return nil }
        return parseAyah(data, translation: translation)
    }

    static func parseAyah(_ data: Data, translation: VerseTranslation) -> DailyText? {
        struct Response: Decodable {
            struct Ayah: Decodable {
                struct Surah: Decodable { let number: Int; let englishName: String }
                let text: String
                let numberInSurah: Int
                let surah: Surah
            }
            let data: [Ayah]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.data.count >= 2 else { return nil }
        let arabic = response.data[0], meaning = response.data[1]
        let s = arabic.surah.number, a = arabic.numberInSurah
        let text = meaning.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return DailyText(isQuran: true,
                         arabic: arabic.text.trimmingCharacters(in: .whitespacesAndNewlines),
                         translation: text,
                         reference: "\(arabic.surah.englishName) \(s):\(a)",
                         link: "https://quran.com/\(s)/\(a)",
                         day: dayKey(), translationKey: translation.rawValue)
    }

    /// (edition slug, display name, sunnah.com slug, highest hadith number)
    static let collections: [(slug: String, name: String, web: String, count: Int)] = [
        ("bukhari", "Sahih al-Bukhari", "bukhari", 7563),
        ("muslim", "Sahih Muslim", "muslim", 7450),
    ]

    static func hadithURL(edition: String, number: Int) -> URL {
        URL(string: "https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions/\(edition)/\(number).min.json")!
    }

    static func fetchHadith(day: Int, salt: Int, translation: VerseTranslation) async -> DailyText? {
        let collection = collections[(day + salt) % collections.count]
        let number = pick(day: day, salt: salt, range: 1...collection.count)
        let lang = translation == .bangla ? "ben" : "eng"
        guard let data = await get(hadithURL(edition: "\(lang)-\(collection.slug)", number: number)),
              let meaning = parseHadith(data) else { return nil }
        let arabicData = await get(hadithURL(edition: "ara-\(collection.slug)", number: number))
        let arabic = arabicData.flatMap(parseHadith) ?? ""
        return DailyText(isQuran: false, arabic: arabic, translation: meaning,
                         reference: "\(collection.name) \(number)",
                         link: "https://sunnah.com/\(collection.web):\(number)",
                         day: dayKey(), translationKey: translation.rawValue)
    }

    static func parseHadith(_ data: Data) -> String? {
        struct Response: Decodable {
            struct Hadith: Decodable { let text: String }
            let hadiths: [Hadith]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let text = response.hadiths.map(\.text).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

// MARK: Widget

struct VerseTile: View {
    @ObservedObject private var store = DailyVerseStore.shared
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var settings = AppSettings.shared

    private var wide: Bool { settings.slots(of: HomeItem(.verse)) >= 3 }

    var body: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    SectionLabel(store.current?.isQuran == false ? "Hadith" : "Quran")
                    Spacer(minLength: 4)
                    if store.loading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button { store.refresh(another: true) } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L("Show another"))
                    }
                }
                if !library.verseEnabled {
                    Spacer(minLength: 0)
                    Text(L("Daily Quran & Hadith is off in Settings"))
                        .font(.system(size: 10)).foregroundStyle(Color.secondary)
                } else if let text = store.current {
                    content(text)
                } else if let error = store.error {
                    Spacer(minLength: 0)
                    Text(error).font(.system(size: 10)).foregroundStyle(Color.secondary)
                    Button(L("Try again")) { store.refresh(another: true) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Spacer(minLength: 0)
                    Text(L("Loading…")).font(.system(size: 10)).foregroundStyle(Color.secondary)
                }
            }
        }
        .onAppear { store.refresh() }
        .contentShape(Rectangle())
        .onTapGesture { if store.current != nil { VerseReader.show() } }
        .help(L("Click to read in full"))
        .contextMenu {
            if let text = store.current {
                MenuButton("Read in full") { VerseReader.show() }
                MenuButton("Read on the web") { if let url = URL(string: text.link) { NSWorkspace.shared.open(url) } }
                MenuButton("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(text.arabic)\n\n\(text.translation)\n— \(text.reference)", forType: .string)
                }
            }
            MenuButton("Show another") { store.refresh(another: true) }
            MenuButton("Settings…") { SettingsWindowController.shared.show(tab: .verse) }
        }
    }

    @ViewBuilder private func content(_ text: DailyText) -> some View {
        let meaning = DailyVerseStore.tidy(text.translation)
        // Long Arabic (a hadith's chain of narrators) would crowd the tile: there it stays in the reader.
        let showArabic = library.verseShowArabic && !text.arabic.isEmpty && text.arabic.count <= (wide ? 220 : 130)
        if showArabic {
            Text(text.arabic)
                .font(.system(size: wide ? 17 : 15))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .environment(\.layoutDirection, .rightToLeft)
        }
        // Takes whatever height is left, shrinking a little before it shortens with "…".
        Text(meaning)
            .font(.system(size: wide ? 13 : 12))
            .lineLimit(nil)
            .minimumScaleFactor(0.72)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
        HStack(spacing: 6) {
            Text(text.reference)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button { VerseReader.show() } label: {
                HStack(spacing: 3) {
                    Text(L("Read in full"))
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Open the whole text in a window"))
        }
    }
}


// MARK: Reader window

/// A small window with the whole ayah or hadith: the complete Arabic, the full meaning and
/// the reference, scrollable, for passages too long for the Home tile.
enum VerseReader {
    private static var window: NSWindow?

    static func show() {
        IslandController.shared.collapse()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.minSize = NSSize(width: 380, height: 300)
            w.contentView = NSHostingView(rootView: VerseReaderView())
            w.center()
            window = w
        }
        window?.title = L("Quran & Hadith")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct VerseReaderView: View {
    @ObservedObject private var store = DailyVerseStore.shared
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            if let text = store.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L(text.isQuran ? "Quran" : "Hadith").uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.accent)
                        if library.verseShowArabic, !text.arabic.isEmpty {
                            Text(text.arabic)
                                .font(.system(size: 22))
                                .lineSpacing(8)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .environment(\.layoutDirection, .rightToLeft)
                                .textSelection(.enabled)
                        }
                        Text(text.translation)
                            .font(.system(size: 15))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Text(text.reference)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 34)
                    .padding(.bottom, 20)
                }
                Divider()
                HStack(spacing: 10) {
                    Button(L("Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(text.arabic)\n\n\(text.translation)\n— \(text.reference)", forType: .string)
                    }
                    Button(L("Read on the web")) { if let url = URL(string: text.link) { NSWorkspace.shared.open(url) } }
                    Spacer()
                    if store.loading { ProgressView().controlSize(.small) }
                    Button(L("Show another")) { store.refresh(another: true) }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            } else {
                Text(store.error ?? L("Loading…"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 380, minHeight: 300)
        .background(.regularMaterial)
        .id(settings.lookKey)
        .environment(\.locale, Localization.locale)
    }
}
