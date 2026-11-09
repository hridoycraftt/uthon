import Foundation
import AppKit
import SQLite3

/// Shows new notifications (WhatsApp, Messages, Mail...) on the island.
///
/// macOS has no API for one app to read another app's notifications, so this reads the
/// Notification Center database on this Mac. That needs Full Disk Access, which the user
/// grants in System Settings. Nothing leaves the Mac; macOS's own banners keep working.
final class NotificationMirror: ObservableObject {
    static let shared = NotificationMirror()

    struct Item: Equatable {
        var id: Int64
        var bundleID: String
        var appName: String
        var title: String
        var subtitle: String
        var body: String
        var date: Date?
    }

    /// Apps that have sent notifications since Uthon started watching (for the mute list).
    @Published private(set) var seenApps: [String] = []
    @Published private(set) var hasAccess = false
    @Published private(set) var lastItem: Item?

    private var timer: Timer?
    private var lastID: Int64 = -1

    var running: Bool { timer != nil }

    /// Where macOS keeps the Notification Center database (it moved in macOS 15).
    static var databaseCandidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = [home + "/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        let darwinUserDir = Self.darwinUserDir()
        if !darwinUserDir.isEmpty { paths.append(darwinUserDir + "com.apple.notificationcenter/db2/db") }
        return paths
    }

    private static func darwinUserDir() -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count)
        return length > 0 ? String(cString: buffer) : ""
    }

    static var databasePath: String? {
        databaseCandidates.first { FileManager.default.isReadableFile(atPath: $0) }
    }

    func checkAccess() {
        if let path = Self.databasePath, let db = Self.open(path) {
            sqlite3_close(db)
            hasAccess = true
        } else {
            hasAccess = false
        }
    }

    func start() {
        guard UserLibrary.shared.notificationsEnabled, timer == nil else { return }
        checkAccess()
        lastID = latestID() ?? -1
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Reading

    private static func open(_ path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        let uri = "file:" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path) + "?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        sqlite3_busy_timeout(db, 300)
        // A real query: opening succeeds even when Full Disk Access is missing.
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM record", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            sqlite3_close(db)
            return nil
        }
        return db
    }

    private func latestID() -> Int64? {
        guard let path = Self.databasePath, let db = Self.open(path) else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT max(rec_id) FROM record", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    private func poll() {
        guard let path = Self.databasePath, let db = Self.open(path) else {
            if hasAccess { hasAccess = false }
            return
        }
        defer { sqlite3_close(db) }
        if !hasAccess { hasAccess = true }
        if lastID < 0 {
            lastID = latestID() ?? 0
            return
        }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT r.rec_id, a.identifier, r.data FROM record r JOIN app a ON a.app_id = r.app_id WHERE r.rec_id > ? ORDER BY r.rec_id LIMIT 20"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_int64(stmt, 1, lastID)
        var fresh: [Item] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            lastID = max(lastID, id)
            let bundle = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            var data = Data()
            if let bytes = sqlite3_column_blob(stmt, 2) {
                data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 2)))
            }
            if let item = Self.parse(id: id, bundleID: bundle, data: data) { fresh.append(item) }
        }
        for item in fresh { deliver(item) }
    }

    /// Notification records are binary property lists: { app, date, req: { titl, subt, body } }.
    static func parse(id: Int64, bundleID: String, data: Data) -> Item? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        let request = plist["req"] as? [String: Any] ?? [:]
        let bundle = (plist["app"] as? String) ?? bundleID
        let title = (request["titl"] as? String) ?? ""
        let subtitle = (request["subt"] as? String) ?? ""
        let body = (request["body"] as? String) ?? ""
        guard !(title.isEmpty && body.isEmpty) else { return nil }
        var date: Date?
        if let seconds = plist["date"] as? Double { date = Date(timeIntervalSinceReferenceDate: seconds) }
        return Item(id: id, bundleID: bundle, appName: appName(for: bundle), title: title,
                    subtitle: subtitle, body: body, date: date)
    }

    static func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    /// Decide whether to show a notification, then show it.
    func deliver(_ item: Item) {
        let library = UserLibrary.shared
        if !seenApps.contains(item.bundleID) { seenApps.append(item.bundleID) }
        guard Self.shouldShow(item, library: library) else { return }
        lastItem = item
        IslandController.shared.showPeek(.notification(Self.peekContent(item, hideContent: library.notificationHideContent)),
                                         duration: library.notificationSeconds)
    }

    static func shouldShow(_ item: Item, library: UserLibrary) -> Bool {
        guard library.notificationsEnabled else { return false }
        if library.mutedNotificationApps.contains(item.bundleID) { return false }
        if item.bundleID == Bundle.main.bundleIdentifier { return false }
        if library.notificationQuietWhenFocused,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == item.bundleID { return false }
        return true
    }

    static func peekContent(_ item: Item, hideContent: Bool) -> NotificationPeek {
        if hideContent {
            return NotificationPeek(bundleID: item.bundleID, app: item.appName,
                                    title: item.appName, text: L("New notification"))
        }
        let title = item.title.isEmpty ? item.appName : item.title
        let text = [item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: " · ")
        return NotificationPeek(bundleID: item.bundleID, app: item.appName, title: title, text: text)
    }
}

/// What a notification peek shows.
struct NotificationPeek: Equatable {
    var bundleID: String
    var app: String
    var title: String
    var text: String
}
