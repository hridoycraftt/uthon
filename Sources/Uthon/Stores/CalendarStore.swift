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
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .notDetermined
        default: access = .denied
        }
    }

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
            events = []
            return
        }
        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 2, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let upcoming = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        events = Array(upcoming.prefix(4))
    }
}
