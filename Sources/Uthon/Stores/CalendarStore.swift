import Foundation
import EventKit

final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()

    enum Access { case notDetermined, granted, denied }

    private let store = EKEventStore()
    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var events: [EKEvent] = []

    private init() {
        updateAccess()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    private func updateAccess() {
        let new: Access
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: new = .granted
        case .notDetermined: new = .notDetermined
        default: new = .denied
        }
        if access != new { access = new }
    }

    private let queryQueue = DispatchQueue(label: "nook.calendar.query", qos: .utility)

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                self?.refresh()
            }
        }
    }

    /// Upcoming events for today and tomorrow (at most 4).
    func refresh() {
        updateAccess()
        guard access == .granted else {
            if !events.isEmpty { events = [] }
            return
        }
        // The calendar database is read off the main thread, so opening the island never waits.
        let store = self.store
        queryQueue.async { [weak self] in
            let cal = Calendar.current
            let now = Date()
            let start = cal.startOfDay(for: now)
            guard let end = cal.date(byAdding: .day, value: 2, to: start) else { return }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let upcoming = Array(store.events(matching: predicate)
                .filter { $0.endDate > now }
                .sorted { $0.startDate < $1.startDate }
                .prefix(4))
            DispatchQueue.main.async {
                guard let self else { return }
                func key(_ e: [EKEvent]) -> [String] {
                    e.map { "\($0.eventIdentifier ?? "")|\($0.startDate.timeIntervalSince1970)|\($0.endDate.timeIntervalSince1970)|\($0.title ?? "")" }
                }
                if key(self.events) != key(upcoming) { self.events = upcoming }
            }
        }
    }
}
