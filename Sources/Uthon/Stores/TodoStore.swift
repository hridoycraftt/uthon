import Foundation
import EventKit

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
}

enum TodoSource: String, CaseIterable, Identifiable {
    case uthon, reminders
    var id: String { rawValue }
    var title: String { self == .uthon ? "Uthon (this Mac only)" : "Apple Reminders (syncs with iPhone)" }
}

/// To-do list. Either kept by Uthon on this Mac, or synced with a list in Apple Reminders
/// (which also syncs with iPhone and with family members through shared lists).
final class TodoStore: ObservableObject {
    static let shared = TodoStore()
    private let key = "todos"
    private let eventStore = EKEventStore()

    @Published private(set) var items: [TodoItem] = []
    @Published private(set) var reminderLists: [String] = []
    @Published private(set) var remindersAccess: CalendarStore.Access = .notDetermined
    @Published var source: TodoSource {
        didSet {
            UserDefaults.standard.set(source.rawValue, forKey: "todoSource")
            reload()
        }
    }
    @Published var listName: String {
        didSet {
            UserDefaults.standard.set(listName, forKey: "todoList")
            if source == .reminders { fetchReminders() }
        }
    }

    private var localItems: [TodoItem] {
        didSet { Persist.save(localItems, key: key) }
    }
    /// Reminder identifier <-> stable row id, so rows keep their identity between refreshes.
    private var idForReminder: [String: UUID] = [:]
    private var reminderForID: [UUID: EKReminder] = [:]

    private init() {
        localItems = Persist.load([TodoItem].self, key: key) ?? []
        source = TodoSource(rawValue: UserDefaults.standard.string(forKey: "todoSource") ?? "") ?? .uthon
        listName = UserDefaults.standard.string(forKey: "todoList") ?? ""
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            if self?.source == .reminders { self?.fetchReminders() }
        }
        reload()
    }

    private func reload() {
        switch source {
        case .uthon:
            items = localItems
        case .reminders:
            updateAccess()
            if remindersAccess == .granted {
                fetchReminders()
            } else {
                items = []
            }
        }
    }

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: remindersAccess = .granted
        case .notDetermined: remindersAccess = .notDetermined
        default: remindersAccess = .denied
        }
    }

    func requestRemindersAccess() {
        eventStore.requestFullAccessToReminders { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.remindersAccess = granted ? .granted : .denied
                if granted { self?.fetchReminders() }
            }
        }
    }

    private var targetList: EKCalendar? {
        let lists = eventStore.calendars(for: .reminder)
        return lists.first { $0.title == listName } ?? eventStore.defaultCalendarForNewReminders()
    }

    private func fetchReminders() {
        updateAccess()
        guard remindersAccess == .granted else { return }
        reminderLists = eventStore.calendars(for: .reminder).map(\.title).sorted()
        guard let list = targetList else {
            items = []
            return
        }
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            let fetched = reminders ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                var rows: [TodoItem] = []
                var map: [UUID: EKReminder] = [:]
                for reminder in fetched {
                    let key = reminder.calendarItemIdentifier
                    let id = self.idForReminder[key] ?? UUID()
                    self.idForReminder[key] = id
                    map[id] = reminder
                    rows.append(TodoItem(id: id, text: reminder.title ?? "", done: reminder.isCompleted))
                }
                self.reminderForID = map
                self.items = rows
            }
        }
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch source {
        case .uthon:
            localItems.append(TodoItem(text: trimmed))
            items = localItems
        case .reminders:
            guard let list = targetList else { return }
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = trimmed
            reminder.calendar = list
            try? eventStore.save(reminder, commit: true)
            fetchReminders()
        }
    }

    func toggle(_ id: UUID) {
        switch source {
        case .uthon:
            guard let index = localItems.firstIndex(where: { $0.id == id }) else { return }
            localItems[index].done.toggle()
            items = localItems
        case .reminders:
            guard let reminder = reminderForID[id] else { return }
            reminder.isCompleted.toggle()
            try? eventStore.save(reminder, commit: true)
            // Show it ticked for a moment; completed reminders then leave the list.
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].done = reminder.isCompleted }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.fetchReminders() }
        }
    }

    func delete(_ id: UUID) {
        switch source {
        case .uthon:
            localItems.removeAll { $0.id == id }
            items = localItems
        case .reminders:
            guard let reminder = reminderForID[id] else { return }
            try? eventStore.remove(reminder, commit: true)
            fetchReminders()
        }
    }

    func clearDone() {
        guard source == .uthon else { return }
        localItems.removeAll { $0.done }
        items = localItems
    }
}
