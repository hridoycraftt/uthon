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

    private init() {
        current = Persist.load(DailyText.self, key: "dailyText")
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
        let wantsQuran = Self.wantsQuran(library.verseSource, day: Self.dayIndex())
        return current.day != Self.dayKey()
            || current.translationKey != library.verseTranslation.rawValue
            || (library.verseSource != .both && current.isQuran != wantsQuran)
    }

    /// Load today's text unless it is already here. `another` picks a random one now.
    func refresh(another: Bool = false) {
        guard UserLibrary.shared.verseEnabled else { return }
        guard another || needsRefresh else { return }
        guard !loading else { return }
        let library = UserLibrary.shared
        let day = Self.dayIndex()
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
                if text.translation.count <= 700 || attempt == 4 { result = text }
            }
            await MainActor.run {
                guard let self else { return }
                self.loading = false
                if var result {
                    result.day = Self.dayKey()
                    self.current = result
                    Persist.save(result, key: "dailyText")
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
        .help(store.current.map { "\($0.translation)\n— \($0.reference)" } ?? "")
        .contextMenu {
            if let text = store.current {
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
        if library.verseShowArabic, !text.arabic.isEmpty {
            Text(text.arabic)
                .font(.system(size: wide ? 18 : 16, weight: .regular))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(wide ? 3 : 2)
                .environment(\.layoutDirection, .rightToLeft)
        }
        Text(text.translation)
            .font(.system(size: wide ? 13 : 12))
            .lineLimit(library.verseShowArabic && !text.arabic.isEmpty ? 3 : 5)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        Spacer(minLength: 0)
        Text(text.reference)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .lineLimit(1)
    }
}
