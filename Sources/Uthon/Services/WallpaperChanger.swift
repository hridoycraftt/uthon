import AppKit

/// Changes the desktop picture once a day (or on demand): beautiful built-in gradients,
/// or a random picture from a folder the user picks.
final class WallpaperChanger {
    static let shared = WallpaperChanger()

    private var timer: Timer?
    private let dayKey = "wallpaperLastDay"

    static let gradients: [(Color1: NSColor, Color2: NSColor)] = [
        (NSColor(red: 0.98, green: 0.55, blue: 0.40, alpha: 1), NSColor(red: 0.45, green: 0.20, blue: 0.55, alpha: 1)),
        (NSColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1), NSColor(red: 0.05, green: 0.10, blue: 0.30, alpha: 1)),
        (NSColor(red: 0.20, green: 0.70, blue: 0.55, alpha: 1), NSColor(red: 0.05, green: 0.25, blue: 0.30, alpha: 1)),
        (NSColor(red: 0.95, green: 0.75, blue: 0.35, alpha: 1), NSColor(red: 0.85, green: 0.30, blue: 0.35, alpha: 1)),
        (NSColor(red: 0.60, green: 0.50, blue: 0.95, alpha: 1), NSColor(red: 0.95, green: 0.55, blue: 0.75, alpha: 1)),
        (NSColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1), NSColor(red: 0.35, green: 0.30, blue: 0.45, alpha: 1)),
        (NSColor(red: 0.55, green: 0.85, blue: 0.95, alpha: 1), NSColor(red: 0.20, green: 0.35, blue: 0.70, alpha: 1)),
        (NSColor(red: 0.95, green: 0.60, blue: 0.55, alpha: 1), NSColor(red: 0.98, green: 0.85, blue: 0.65, alpha: 1)),
    ]

    func start() {
        let t = Timer(timeInterval: 1800, repeats: true) { [weak self] _ in self?.dailyCheck() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        dailyCheck()
    }

    private func dailyCheck() {
        let lib = UserLibrary.shared
        guard lib.wallpaperSource != .off, lib.wallpaperDaily else { return }
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: dayKey) != today else { return }
        UserDefaults.standard.set(today, forKey: dayKey)
        next()
    }

    /// Set the next wallpaper now. Returns false if nothing could be set.
    @discardableResult
    func next() -> Bool {
        let url: URL?
        switch UserLibrary.shared.wallpaperSource {
        case .off: return false
        case .gradients: url = makeGradient(index: Int.random(in: 0..<Self.gradients.count))
        case .folder: url = randomImage(in: UserLibrary.shared.wallpaperFolder)
        }
        guard let url else { return false }
        var ok = false
        for screen in NSScreen.screens {
            if (try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])) != nil { ok = true }
        }
        return ok
    }

    private func randomImage(in folder: String) -> URL? {
        guard !folder.isEmpty else { return nil }
        let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "webp"]
        let items = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)) ?? []
        return items.filter { exts.contains($0.pathExtension.lowercased()) }.randomElement()
    }

    /// Renders a soft two-color gradient to a new PNG (a new file name each time, so macOS refreshes).
    func makeGradient(index: Int) -> URL? {
        let pair = Self.gradients[index % Self.gradients.count]
        let size = NSSize(width: 2880, height: 1800)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSGradient(starting: pair.Color1, ending: pair.Color2)?.draw(in: NSRect(origin: .zero, size: size), angle: -60)
        // A soft glow for depth.
        if let glow = NSGradient(starting: NSColor.white.withAlphaComponent(0.25), ending: NSColor.white.withAlphaComponent(0)) {
            glow.draw(in: NSBezierPath(ovalIn: NSRect(x: size.width * 0.55, y: size.height * 0.45, width: size.width * 0.6, height: size.height * 0.8)),
                      relativeCenterPosition: .zero)
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Uthon/Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Clean up older generated files.
        for old in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: old)
        }
        let url = folder.appendingPathComponent("uthon-\(Int(Date().timeIntervalSince1970)).png")
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
