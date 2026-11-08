import AppKit

/// The last 25 pieces of text you copied. Kept in memory only (cleared when Uthon quits),
/// and items marked as passwords by password managers are skipped.
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let date: Date
    }

    @Published private(set) var items: [Item] = []
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private static let skipTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "com.agilebits.onepassword",
    ]

    func start() {
        let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        guard AppSettings.shared.clipboardEnabled else { return }
        let types = Set((board.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: Self.skipTypes) else { return }
        guard let text = board.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0.text == text }
        items.insert(Item(text: text, date: Date()), at: 0)
        if items.count > 25 { items.removeLast(items.count - 25) }
    }

    func copy(_ item: Item) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(item.text, forType: .string)
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }
}

/// A single scratch note that is always one hover away.
final class NotesStore: ObservableObject {
    static let shared = NotesStore()
    private let key = "quickNote"

    @Published var text: String {
        didSet { UserDefaults.standard.set(text, forKey: key) }
    }

    private init() {
        text = UserDefaults.standard.string(forKey: key) ?? ""
    }
}
