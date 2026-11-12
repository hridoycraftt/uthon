import AppKit

/// Checks GitHub Releases for a newer Uthon and installs it in place, so every Mac in
/// the family stays up to date. The download is not quarantined, so no Gatekeeper prompt.
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle, checking, upToDate, available(version: String), downloading, installing, failed(String)
    }

    @Published private(set) var state: State = .idle
    private var dmgURL: URL?
    private var timer: Timer?

    static let repo = "hridoycraftt/uthon"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    struct Release: Equatable {
        let version: String
        let dmg: URL
    }

    enum CheckError: Error, Equatable {
        case offline, rateLimited, notFound, unexpected(String)

        var message: String {
            switch self {
            case .offline: return L("No internet connection")
            case .rateLimited: return L("GitHub is busy, try again later")
            case .notFound: return L("No release found")
            case .unexpected(let detail): return L("Could not check for updates") + (detail.isEmpty ? "" : " (\(detail))")
            }
        }
    }

    private var reminderTimer: Timer?
    private static let lastReminderKey = "lastUpdateReminder"

    /// Hours between update reminders for N reminders a day (3 → every 8 hours).
    static func reminderGap(perDay: Int) -> TimeInterval? {
        perDay > 0 ? 24 * 3600 / Double(perDay) : nil
    }

    /// True when a reminder is due: a newer version waits, reminders are on, and the last one
    /// was at least a gap ago.
    static func reminderDue(now: Date, last: Date?, perDay: Int, available: Bool) -> Bool {
        guard available, let gap = reminderGap(perDay: perDay) else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= gap - 60
    }

    /// Shows the update pop-up if it is time (2–3 times a day by default) so nobody stays on
    /// an old version for long.
    func remindIfDue(now: Date = Date()) {
        guard case .available(let version) = state else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastReminderKey) as? Date
        guard Self.reminderDue(now: now, last: last, perDay: UserLibrary.shared.updateRemindersPerDay, available: true) else { return }
        UserDefaults.standard.set(now, forKey: Self.lastReminderKey)
        IslandController.shared.showPeek(.update(version: version), duration: 15)
    }

    func start() {
        let t = Timer(timeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            if UserLibrary.shared.autoCheckUpdates { self?.check(silent: true) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let r = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.remindIfDue() }
        RunLoop.main.add(r, forMode: .common)
        reminderTimer = r
        if UserLibrary.shared.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.check(silent: true) }
        }
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesPage)
    }

    func check(silent: Bool = false) {
        state = .checking
        Self.latestRelease { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.state = .failed(error.message)
                case .success(let release):
                    self.dmgURL = release.dmg
                    if Self.isNewer(release.version, than: AppInfo.version) {
                        self.state = .available(version: release.version)
                        if silent { self.remindIfDue() }
                    } else {
                        self.state = .upToDate
                    }
                }
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": "Nook/\(AppInfo.version) (macOS)"]
        return URLSession(configuration: config)
    }()

    /// Finds the newest release. Tries the GitHub API first; if that is blocked or
    /// rate-limited, reads the normal releases page (which has no limit) instead.
    /// Calls back on a background queue.
    static func latestRelease(completion: @escaping (Result<Release, CheckError>) -> Void) {
        fromAPI { apiResult in
            if case .success = apiResult {
                completion(apiResult)
                return
            }
            fromReleasesPage { pageResult in
                if case .success = pageResult {
                    completion(pageResult)
                } else if case .failure(.offline) = apiResult {
                    completion(apiResult)
                } else {
                    completion(pageResult)
                }
            }
        }
    }

    static func fromAPI(completion: @escaping (Result<Release, CheckError>) -> Void) {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, error in
            if let error = error as? URLError {
                completion(.failure(error.code == .notConnectedToInternet || error.code == .networkConnectionLost ? .offline
                                    : .unexpected(error.localizedDescription)))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 403 || status == 429 { completion(.failure(.rateLimited)); return }
            if status == 404 { completion(.failure(.notFound)); return }
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                completion(.failure(.unexpected("HTTP \(status)")))
                return
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let assets = json["assets"] as? [[String: Any]] ?? []
            let dmg = assets.compactMap { $0["browser_download_url"] as? String }
                .first { $0.hasSuffix(".dmg") }
                .flatMap(URL.init(string:)) ?? dmgURL(for: version)
            completion(.success(Release(version: version, dmg: dmg)))
        }.resume()
    }

    /// github.com/<repo>/releases/latest redirects to .../releases/tag/v1.2.3.
    static func fromReleasesPage(completion: @escaping (Result<Release, CheckError>) -> Void) {
        var request = URLRequest(url: releasesPage)
        request.httpMethod = "HEAD"
        session.dataTask(with: request) { _, response, error in
            if let error = error as? URLError {
                completion(.failure(error.code == .notConnectedToInternet ? .offline : .unexpected(error.localizedDescription)))
                return
            }
            guard let finalURL = response?.url, let version = version(fromTagURL: finalURL) else {
                completion(.failure(.notFound))
                return
            }
            completion(.success(Release(version: version, dmg: dmgURL(for: version))))
        }.resume()
    }

    static func version(fromTagURL url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "tag"), index + 1 < parts.count else { return nil }
        let tag = parts[index + 1]
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return version.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil ? version : nil
    }

    static func dmgURL(for version: String) -> URL {
        URL(string: "https://github.com/\(repo)/releases/download/v\(version)/Nook-\(version).dmg")!
    }

    /// "0.10.0" > "0.9.3"
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Download the new DMG, copy the app over this one and relaunch.
    func install() {
        guard let dmgURL else { return }
        state = .downloading
        URLSession.shared.downloadTask(with: dmgURL) { [weak self] file, _, error in
            guard let file else {
                DispatchQueue.main.async { self?.state = .failed(error?.localizedDescription ?? "Download failed") }
                return
            }
            let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("Nook-update.dmg")
            try? FileManager.default.removeItem(at: dmg)
            do {
                try FileManager.default.moveItem(at: file, to: dmg)
            } catch {
                DispatchQueue.main.async { self?.state = .failed("Could not save the download") }
                return
            }
            DispatchQueue.main.async { self?.replaceAndRelaunch(dmg: dmg) }
        }.resume()
    }

    private func replaceAndRelaunch(dmg: URL) {
        state = .installing
        let current = Bundle.main.bundlePath
        // The app was renamed from Uthon to Nook: move an old "Uthon.app" to "Nook.app".
        let app = (current as NSString).lastPathComponent == "Uthon.app"
            ? ((current as NSString).deletingLastPathComponent as NSString).appendingPathComponent("Nook.app")
            : current
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("nook-mount").path
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("Nook-new.app").path
        let script = """
        set -e
        mkdir -p "\(mount)"
        hdiutil attach -nobrowse -readonly -quiet -mountpoint "\(mount)" "\(dmg.path)"
        rm -rf "\(staged)"
        if [ -d "\(mount)/Nook.app" ]; then ditto "\(mount)/Nook.app" "\(staged)"; else ditto "\(mount)/Uthon.app" "\(staged)"; fi
        hdiutil detach -quiet "\(mount)" || true
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(app)"
        if [ "\(current)" != "\(app)" ]; then rm -rf "\(current)"; fi
        ditto "\(staged)" "\(app)"
        rm -rf "\(staged)"
        open "\(app)"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        do {
            try process.run()
        } catch {
            state = .failed("Could not start the installer")
            return
        }
        // Give the script time to copy the new app out of the DMG, then quit so it can swap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { NSApp.terminate(nil) }
    }
}
