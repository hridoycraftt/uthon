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
    private let apiURL = URL(string: "https://api.github.com/repos/hridoycraftt/uthon/releases/latest")!

    func start() {
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            if UserLibrary.shared.autoCheckUpdates { self?.check(silent: true) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        if UserLibrary.shared.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.check(silent: true) }
        }
    }

    func check(silent: Bool = false) {
        state = .checking
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    self.state = .failed(error?.localizedDescription ?? "Could not reach GitHub")
                    return
                }
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = json["assets"] as? [[String: Any]] ?? []
                self.dmgURL = assets.compactMap { $0["browser_download_url"] as? String }
                    .first { $0.hasSuffix(".dmg") }
                    .flatMap(URL.init(string:))
                if Self.isNewer(version, than: AppInfo.version), self.dmgURL != nil {
                    self.state = .available(version: version)
                    if silent { IslandController.shared.showPeek(.update(version: version), duration: 12) }
                } else {
                    self.state = .upToDate
                }
            }
        }.resume()
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
            let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("Uthon-update.dmg")
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
        let app = Bundle.main.bundlePath
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("uthon-mount").path
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("Uthon-new.app").path
        let script = """
        set -e
        mkdir -p "\(mount)"
        hdiutil attach -nobrowse -readonly -quiet -mountpoint "\(mount)" "\(dmg.path)"
        rm -rf "\(staged)"
        ditto "\(mount)/Uthon.app" "\(staged)"
        hdiutil detach -quiet "\(mount)" || true
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(app)"
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
