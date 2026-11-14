import AppKit

/// Recently copied text and images. Text you pin is kept (even after restarting);
/// everything else lives in memory only. Items marked as passwords are skipped.
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let image: NSImage?
        let date: Date
        var pinned = false

        var isImage: Bool { image != nil }

        static func == (a: Item, b: Item) -> Bool { a.id == b.id && a.pinned == b.pinned }
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
        guard timer == nil else { return }
        items = UserLibrary.shared.pinnedClips.map { Item(text: $0, image: nil, date: Date(), pinned: true) }
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

        if let text = board.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let wasPinned = items.contains { $0.text == text && $0.pinned }
            items.removeAll { $0.text == text && !$0.isImage }
            insert(Item(text: text, image: nil, date: Date(), pinned: wasPinned))
            SmartClip.didCopy(text)
        } else if UserLibrary.shared.clipboardImages,
                  board.canReadObject(forClasses: [NSImage.self], options: nil),
                  let image = NSImage(pasteboard: board) {
            insert(Item(text: "Image \(Int(image.size.width))×\(Int(image.size.height))", image: image, date: Date()))
        }
    }

    private func insert(_ item: Item) {
        items.insert(item, at: 0)
        sortPinnedFirst()
        trim()
    }

    private func sortPinnedFirst() {
        let pinned = items.filter(\.pinned)
        let rest = items.filter { !$0.pinned }
        items = pinned + rest
    }

    private func trim() {
        let limit = max(5, UserLibrary.shared.clipboardLimit)
        var unpinned = 0
        items = items.filter { item in
            if item.pinned { return true }
            unpinned += 1
            return unpinned <= limit
        }
    }

    /// Used only by tests and the screenshot tour.
    func debugAdd(_ text: String) {
        insert(Item(text: text, image: nil, date: Date()))
    }

    func copy(_ item: Item) {
        let board = NSPasteboard.general
        board.clearContents()
        if let image = item.image {
            board.writeObjects([image])
        } else {
            board.setString(item.text, forType: .string)
        }
    }

    func togglePin(_ item: Item) {
        guard !item.isImage, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        sortPinnedFirst()
        UserLibrary.shared.pinnedClips = items.filter(\.pinned).map(\.text)
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        UserLibrary.shared.pinnedClips = items.filter(\.pinned).map(\.text)
    }

    /// Clears everything except pinned items.
    func clear() {
        items.removeAll { !$0.pinned }
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
