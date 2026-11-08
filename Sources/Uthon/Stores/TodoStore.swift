import Foundation

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
}

final class TodoStore: ObservableObject {
    static let shared = TodoStore()
    private let key = "todos"

    @Published private(set) var items: [TodoItem] {
        didSet { Persist.save(items, key: key) }
    }

    private init() {
        items = Persist.load([TodoItem].self, key: key) ?? []
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(TodoItem(text: trimmed))
    }

    func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].done.toggle()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clearDone() {
        items.removeAll { $0.done }
    }
}
