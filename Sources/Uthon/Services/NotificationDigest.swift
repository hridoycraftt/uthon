import Foundation
import SwiftUI
import AppKit

/// A short summary of the notifications that came in: counts per app and sender, and, with
/// Apple Intelligence on this Mac, a one or two sentence summary in plain words.
final class NotificationDigest: ObservableObject {
    static let shared = NotificationDigest()

    struct Group: Equatable, Identifiable {
        var app: String
        var bundleID: String
        var count: Int
        var senders: [String]
        var id: String { bundleID }
    }

    @Published private(set) var aiSummary: String?
    @Published private(set) var summarizing = false
    private var timer: Timer?
    private let lastKey = "lastDigest"

    /// Groups notifications by app, most active first; senders are the titles, most frequent first.
    static func groups(_ items: [NotificationMirror.Item]) -> [Group] {
        var byApp: [String: [NotificationMirror.Item]] = [:]
        for item in items { byApp[item.bundleID, default: []].append(item) }
        return byApp.map { bundle, list in
            var counts: [String: Int] = [:]
            for item in list where !item.title.isEmpty && item.title != item.appName { counts[item.title, default: 0] += 1 }
            let senders = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
            return Group(app: list.first?.appName ?? bundle, bundleID: bundle, count: list.count, senders: senders)
        }
        .sorted { $0.count == $1.count ? $0.app < $1.app : $0.count > $1.count }
    }

    /// "Messages 3 (Ammu, Rahim) · WhatsApp 1": works on every Mac, no AI needed.
    static func plainSummary(_ items: [NotificationMirror.Item], hideSenders: Bool = false) -> String {
        let parts = groups(items).prefix(4).map { group -> String in
            let who = hideSenders || group.senders.isEmpty ? "" : " (" + group.senders.prefix(2).joined(separator: ", ") + ")"
            return "\(group.app) \(group.count)\(who)"
        }
        return parts.isEmpty ? L("No new notifications") : parts.joined(separator: " · ")
    }

    func reset() { aiSummary = nil }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Every N hours (Settings), shows a summary of what came in since the last one.
    private func tick(now: Date = Date()) {
        let library = UserLibrary.shared
        guard library.digestEnabled, library.notificationsEnabled, library.digestIntervalHours > 0 else { return }
        let last = UserDefaults.standard.object(forKey: lastKey) as? Date ?? now.addingTimeInterval(-Double(library.digestIntervalHours) * 3600)
        guard now.timeIntervalSince(last) >= Double(library.digestIntervalHours) * 3600 else { return }
        let items = NotificationMirror.shared.recent.filter { ($0.date ?? now) > last }
        UserDefaults.standard.set(now, forKey: lastKey)
        guard items.count >= 2 else { return }
        showNow(items: items)
    }

    /// Shows the summary on the island (with the AI sentence when it is available and on).
    func showNow(items: [NotificationMirror.Item]? = nil) {
        let list = items ?? NotificationMirror.shared.recent
        let plain = Self.plainSummary(list, hideSenders: UserLibrary.shared.notificationHideContent)
        IslandController.shared.showPeek(.digest(count: list.count, text: plain))
        guard UserLibrary.shared.digestUseAI, AIService.shared.isAvailable, !list.isEmpty,
              !UserLibrary.shared.notificationHideContent else { return }
        summarize(list) { summary in
            IslandController.shared.updatePeek(.digest(count: list.count, text: summary))
        }
    }

    /// Asks the on-device model for a short summary.
    func summarize(_ items: [NotificationMirror.Item], done: ((String) -> Void)? = nil) {
        guard !summarizing, !items.isEmpty else { return }
        summarizing = true
        let lines = items.prefix(40).map { "\($0.appName) — \($0.title): \([$0.subtitle, $0.body].filter { !$0.isEmpty }.joined(separator: " "))" }
        let instructions = "These are notifications from a person's Mac. Summarize what matters in one or two short sentences in \(AIService.answerLanguage): who wrote, about what, anything that needs action. No lists."
        Task {
            let text = try? await AIService.shared.ask(lines.joined(separator: "\n"), instructions: instructions)
            await MainActor.run {
                self.summarizing = false
                if let text, !text.isEmpty {
                    self.aiSummary = text
                    done?(text)
                }
            }
        }
    }
}

// MARK: Home widget

struct DigestTile: View {
    @ObservedObject private var mirror = NotificationMirror.shared
    @ObservedObject private var digest = NotificationDigest.shared
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var ai = AIService.shared

    var body: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel("Notifications")
                    Spacer(minLength: 4)
                    Text("\(mirror.recent.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(mirror.recent.isEmpty ? Color.secondary : Theme.accent))
                }
                if !library.notificationsEnabled {
                    Spacer(minLength: 0)
                    Text(L("Turn on notifications on the island in Settings"))
                        .font(.system(size: 10)).foregroundStyle(Color.secondary)
                    Button(L("Settings…")) { SettingsWindowController.shared.show(tab: .notifications) }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                } else if mirror.recent.isEmpty {
                    Spacer(minLength: 0)
                    Text(L("No new notifications")).font(.system(size: 11)).foregroundStyle(Color.secondary)
                } else {
                    if let summary = digest.aiSummary {
                        Text(summary).font(.system(size: 11)).lineLimit(3).minimumScaleFactor(0.85)
                    }
                    ForEach(NotificationDigest.groups(mirror.recent).prefix(digest.aiSummary == nil ? 3 : 1)) { group in
                        HStack(spacing: 6) {
                            if let icon = AppIconCache.icon(bundleID: group.bundleID) {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            }
                            Text(group.app).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            if !library.notificationHideContent, let first = group.senders.first {
                                Text(first).font(.system(size: 10)).foregroundStyle(Color.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 2)
                            Text("\(group.count)").font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                    HStack {
                        if ai.isAvailable && library.digestUseAI && !library.notificationHideContent {
                            Button {
                                digest.summarize(mirror.recent)
                            } label: {
                                Label(L(digest.summarizing ? "Summarizing…" : "Summarize"), systemImage: "sparkles")
                            }
                            .disabled(digest.summarizing)
                        }
                        Spacer()
                        Button(L("Clear")) {
                            mirror.clearRecent()
                            digest.reset()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

/// App icons by bundle ID, looked up once (finding an app and loading its icon is slow).
enum AppIconCache {
    private static var icons: [String: NSImage?] = [:]

    static func icon(bundleID: String) -> NSImage? {
        if let hit = icons[bundleID] { return hit }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[bundleID] = icon
        return icon
    }
}
