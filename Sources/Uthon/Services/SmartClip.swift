import Foundation
import AppKit
import EventKit
import NaturalLanguage

/// Recognises what was copied (a link, email, phone number, address, date or text in
/// another language) and offers the obvious next step: open it, map it, add it to the
/// calendar, translate it... Everything is detected on this Mac.
struct SmartClip: Equatable {
    enum Kind: String, Equatable {
        case link, email, phone, address, date, translateToBangla, translateToEnglish
    }

    var kind: Kind
    /// What the action works on (the URL, the address, the text to translate...).
    var value: String
    /// For dates: the moment found in the text.
    var date: Date?
    /// The copied text, for titles.
    var source: String

    var symbol: String {
        switch kind {
        case .link: return "safari.fill"
        case .email: return "envelope.fill"
        case .phone: return "phone.fill"
        case .address: return "map.fill"
        case .date: return "calendar.badge.plus"
        case .translateToBangla, .translateToEnglish: return "character.bubble.fill"
        }
    }

    /// "Copied a link"
    var headline: String {
        switch kind {
        case .link: return "Copied a link"
        case .email: return "Copied an email address"
        case .phone: return "Copied a phone number"
        case .address: return "Copied an address"
        case .date: return "Copied a date"
        case .translateToBangla: return "Copied English text"
        case .translateToEnglish: return "Copied Bangla text"
        }
    }

    /// The button: "Open", "Show on map"...
    var actionTitle: String {
        switch kind {
        case .link: return "Open"
        case .email: return "Write email"
        case .phone: return "Call"
        case .address: return "Show on map"
        case .date: return "Add to Calendar"
        case .translateToBangla: return "To Bangla"
        case .translateToEnglish: return "To English"
        }
    }

    // MARK: Detection

    /// The most useful action for this text, or nil when there is nothing special about it.
    static func detect(_ raw: String) -> SmartClip? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000 else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber, .address, .date]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            let matches = detector.matches(in: text, options: [], range: range)
            // Only when the match is most of what was copied (a paragraph with a date in it is just text).
            let covering = matches.filter { Double($0.range.length) >= Double(range.length) * 0.6 }
            for match in covering {
                switch match.resultType {
                case .link:
                    if let url = match.url {
                        if url.scheme == "mailto" {
                            return SmartClip(kind: .email, value: url.absoluteString.replacingOccurrences(of: "mailto:", with: ""), source: text)
                        }
                        return SmartClip(kind: .link, value: url.absoluteString, source: text)
                    }
                case .phoneNumber:
                    if let number = match.phoneNumber { return SmartClip(kind: .phone, value: number, source: text) }
                case .address:
                    return SmartClip(kind: .address, value: text, source: text)
                case .date:
                    if let date = match.date { return SmartClip(kind: .date, value: text, date: date, source: text) }
                default:
                    break
                }
            }
        }
        // Text in one language: offer the other (only for real sentences, not single words or code).
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        guard words >= 3 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .english?:
            return SmartClip(kind: .translateToBangla, value: text, source: text)
        case .bengali?:
            return SmartClip(kind: .translateToEnglish, value: text, source: text)
        default:
            return nil
        }
    }

    // MARK: Actions

    func perform() {
        switch kind {
        case .link:
            if let url = URL(string: value) { NSWorkspace.shared.open(url) }
        case .email:
            if let url = URL(string: "mailto:" + value) { NSWorkspace.shared.open(url) }
        case .phone:
            let digits = value.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:" + digits) { NSWorkspace.shared.open(url) }
        case .address:
            var comps = URLComponents(string: "maps://")
            comps?.queryItems = [URLQueryItem(name: "q", value: value)]
            if let url = comps?.url { NSWorkspace.shared.open(url) }
        case .date:
            if let date { Self.addToCalendar(title: source, date: date) }
        case .translateToBangla, .translateToEnglish:
            let action: AIAction = kind == .translateToBangla ? .toBangla : .toEnglish
            if AIService.shared.isAvailable {
                AIService.shared.pending = (value, action)
                IslandController.shared.expand(tab: .assistant, sticky: true)
            } else {
                var comps = URLComponents(string: "https://translate.google.com/")
                comps?.queryItems = [URLQueryItem(name: "sl", value: "auto"),
                                     URLQueryItem(name: "tl", value: kind == .translateToBangla ? "bn" : "en"),
                                     URLQueryItem(name: "text", value: value)]
                if let url = comps?.url { NSWorkspace.shared.open(url) }
            }
        }
    }

    /// Adds a one-hour event at the copied date (asks for calendar access the first time).
    static func addToCalendar(title: String, date: Date) {
        let store = EKEventStore()
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                guard granted, let calendar = store.defaultCalendarForNewEvents else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
                    return
                }
                let event = EKEvent(eventStore: store)
                event.title = String(title.prefix(80))
                event.startDate = date
                event.endDate = date.addingTimeInterval(3600)
                event.calendar = calendar
                do {
                    try store.save(event, span: .thisEvent)
                    IslandModel.shared.notice = L("Added to Calendar")
                    CalendarStore.shared.refresh()
                } catch {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
                }
            }
        }
    }

    /// Called for every newly copied text: offers the action on the island if it is useful.
    static func didCopy(_ text: String) {
        let library = UserLibrary.shared
        guard library.smartClipEnabled, library.smartClipPeek, let clip = detect(text) else { return }
        IslandController.shared.showPeek(.smartClip(clip))
    }
}
