import AppKit
import MetalKit
import AVFoundation
import Combine
import IOKit.ps

// MARK: Rendering

/// Must match `Uniforms` in the shader header (32 bytes).
struct LiveUniforms {
    var time: Float
    var speed: Float
    var res: SIMD2<Float>
    var mouse: SIMD2<Float>
    var hue: Float
    var react: Float
}

/// Compiles the styles (once each) and draws them, on screen or into a picture.
enum LiveRenderer {
    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    static let queue: MTLCommandQueue? = device?.makeCommandQueue()
    private static var pipelines: [LiveStyle: MTLRenderPipelineState] = [:]
    private static let lock = NSLock()
    /// The last compile error, for the self-test and diagnostics.
    private(set) static var errors: [LiveStyle: String] = [:]

    static func pipeline(_ style: LiveStyle) -> MTLRenderPipelineState? {
        lock.lock(); defer { lock.unlock() }
        if let p = pipelines[style] { return p }
        guard let device else { errors[style] = "No Metal device"; return nil }
        do {
            let library = try device.makeLibrary(source: style.source, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "vmain")
            desc.fragmentFunction = library.makeFunction(name: "fmain")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            let state = try device.makeRenderPipelineState(descriptor: desc)
            pipelines[style] = state
            return state
        } catch {
            errors[style] = error.localizedDescription
            NSLog("Nook: live wallpaper \(style.rawValue) failed to compile: \(error.localizedDescription)")
            return nil
        }
    }

    static func encode(_ encoder: MTLRenderCommandEncoder, style: LiveStyle, uniforms: LiveUniforms) -> Bool {
        guard let state = pipeline(style) else { return false }
        var u = uniforms
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(&u, length: MemoryLayout<LiveUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        return true
    }

    /// One frame as a picture (gallery thumbnails, tests).
    static func snapshot(_ style: LiveStyle, width: Int, height: Int, time: Float = 6,
                         mouse: SIMD2<Float> = [0.62, 0.58], react: Float = 0.8, hue: Float = 0) -> CGImage? {
        guard let device, let queue, pipeline(style) != nil else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: desc),
              let buffer = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        let ok = encode(encoder, style: style, uniforms: LiveUniforms(time: time, speed: 1, res: [Float(width), Float(height)],
                                                                      mouse: mouse, hue: hue, react: react))
        encoder.endEncoding()
        guard ok else { return nil }
        if let blit = buffer.makeBlitCommandEncoder() {
            blit.synchronize(resource: texture)
            blit.endEncoding()
        }
        buffer.commit()
        buffer.waitUntilCompleted()
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&data, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// The view on each screen. Draws at a lower resolution than the screen (set by Quality) and
/// lets the system scale it up: soft gradients look the same and the GPU does far less work.
final class LiveMetalView: MTKView, MTKViewDelegate {
    var style: LiveStyle = .aurora
    private var time: Double = 0
    private var last: CFTimeInterval = 0
    private var mouse = SIMD2<Float>(0.5, 0.5)

    init(screenFrame frame: CGRect) {
        super.init(frame: frame, device: LiveRenderer.device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        autoResizeDrawable = false
        enableSetNeedsDisplay = false
        isPaused = false
        layer?.isOpaque = true
        delegate = self
        // Start somewhere in the middle of the animation, not at its first frame.
        time = Double.random(in: 20...200)
        updateDrawableSize()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    func updateDrawableSize() {
        let scale = (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) * LiveWallpaper.qualityScale
        let size = CGSize(width: max(64, bounds.width * scale), height: max(64, bounds.height * scale))
        if drawableSize != size { drawableSize = size }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = last == 0 ? 0 : min(now - last, 0.1)
        last = now
        let library = UserLibrary.shared
        time += dt * library.liveSpeed
        // The mouse, relative to this screen, eased so the picture never jumps.
        if let screen = window?.screen {
            let m = NSEvent.mouseLocation
            let f = screen.frame
            if f.contains(m) {
                let target = SIMD2<Float>(Float((m.x - f.minX) / f.width), Float((m.y - f.minY) / f.height))
                let ease = Float(1 - exp(-dt * 4))
                mouse += (target - mouse) * ease
            }
        }
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = LiveRenderer.queue?.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        _ = LiveRenderer.encode(encoder, style: style, uniforms: LiveUniforms(
            time: Float(time.truncatingRemainder(dividingBy: 3600)), speed: Float(library.liveSpeed),
            res: [Float(drawableSize.width), Float(drawableSize.height)], mouse: mouse,
            hue: Float(library.liveHue), react: Float(library.liveReact)))
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// A looping, silent-by-default video on the desktop.
final class LiveVideoView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: Controller

enum LiveMode: String, CaseIterable, Identifiable {
    case live, video
    var id: String { rawValue }
    var title: String { self == .live ? "Live" : "Video" }
}

/// Puts a live (or video) wallpaper behind the desktop icons on every screen, and pauses it
/// whenever nobody can see it or the Mac should save power.
final class LiveWallpaper: ObservableObject {
    static let shared = LiveWallpaper()

    /// Why it is paused right now ("" when playing).
    @Published private(set) var pauseReason = ""
    @Published private(set) var isRunning = false

    private(set) var windows: [NSWindow] = []
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var videoPathInUse = ""
    private var cancellables = Set<AnyCancellable>()
    private var powerTimer: Timer?
    private var screensAsleep = false
    /// For tests: pretend to be on battery.
    var testOnBattery: Bool?

    static var qualityScale: CGFloat {
        switch UserLibrary.shared.liveQuality {
        case "saver": return 0.35
        case "high": return 1.0
        default: return 0.6
        }
    }

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let library = UserLibrary.shared
        Publishers.MergeMany(
            library.$liveEnabled.map { _ in () }.eraseToAnyPublisher(),
            library.$liveMode.map { _ in () }.eraseToAnyPublisher(),
            library.$liveStyle.map { _ in () }.eraseToAnyPublisher(),
            library.$liveQuality.map { _ in () }.eraseToAnyPublisher(),
            library.$liveFPS.map { _ in () }.eraseToAnyPublisher(),
            library.$liveAllScreens.map { _ in () }.eraseToAnyPublisher(),
            library.$videoPath.map { _ in () }.eraseToAnyPublisher(),
            library.$videoFill.map { _ in () }.eraseToAnyPublisher(),
            library.$videoSound.map { _ in () }.eraseToAnyPublisher(),
            library.$videoVolume.map { _ in () }.eraseToAnyPublisher(),
            library.$livePauseOnBattery.map { _ in () }.eraseToAnyPublisher(),
            library.$livePauseCovered.map { _ in () }.eraseToAnyPublisher(),
            library.$livePauseLowPower.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
        .sink { [weak self] in self?.apply() }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        let ws = NSWorkspace.shared.notificationCenter
        ws.publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in self?.screensAsleep = true; self?.updatePause() }
            .store(in: &cancellables)
        ws.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in self?.screensAsleep = false; self?.updatePause() }
            .store(in: &cancellables)
        ws.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.updatePause() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updatePause() }
            .store(in: &cancellables)
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.updatePause() }
        RunLoop.main.add(t, forMode: .common)
        powerTimer = t
        apply()
    }

    // MARK: Windows

    private var screens: [NSScreen] {
        UserLibrary.shared.liveAllScreens ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
    }

    private func rebuild() {
        teardown()
        apply()
    }

    func apply() {
        let library = UserLibrary.shared
        guard library.liveEnabled else { teardown(); return }
        let mode = LiveMode(rawValue: library.liveMode) ?? .live
        if mode == .video && library.videoPath.isEmpty { teardown(); return }
        // Rebuild when the screens or the kind of content changed.
        let wantsVideo = mode == .video
        let haveVideo = windows.first?.contentView is LiveVideoView
        if windows.count != screens.count || (!windows.isEmpty && wantsVideo != haveVideo) { teardown() }
        if windows.isEmpty {
            windows = screens.map { makeWindow(for: $0, video: wantsVideo) }
        }
        if wantsVideo {
            configureVideo()
        } else {
            stopVideo()
            let style = LiveStyle(rawValue: library.liveStyle) ?? .aurora
            for view in windows.compactMap({ $0.contentView as? LiveMetalView }) {
                view.style = style
                view.preferredFramesPerSecond = library.liveFPS
                view.updateDrawableSize()
            }
        }
        isRunning = true
        updatePause()
    }

    private func makeWindow(for screen: NSScreen, video: Bool) -> NSWindow {
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        // Under the desktop icons, above the desktop picture.
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.isOpaque = true
        w.backgroundColor = .black
        w.isReleasedWhenClosed = false
        w.setFrame(screen.frame, display: false)
        let frame = NSRect(origin: .zero, size: screen.frame.size)
        w.contentView = video ? LiveVideoView(frame: frame) : LiveMetalView(screenFrame: frame)
        w.orderFront(nil)
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: w)
        return w
    }

    @objc private func occlusionChanged() { updatePause() }

    private func teardown() {
        for w in windows {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: w)
            (w.contentView as? LiveMetalView)?.isPaused = true
            w.orderOut(nil)
            w.contentView = nil
        }
        windows = []
        stopVideo()
        if isRunning { isRunning = false }
        if !pauseReason.isEmpty { pauseReason = "" }
    }

    // MARK: Video

    private func configureVideo() {
        let library = UserLibrary.shared
        if player == nil || videoPathInUse != library.videoPath {
            stopVideo()
            let item = AVPlayerItem(url: URL(fileURLWithPath: library.videoPath))
            let queue = AVQueuePlayer()
            queue.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: queue, templateItem: item)
            player = queue
            videoPathInUse = library.videoPath
        }
        player?.isMuted = !library.videoSound
        player?.volume = Float(library.videoVolume)
        for view in windows.compactMap({ $0.contentView as? LiveVideoView }) {
            view.playerLayer.player = player
            view.playerLayer.videoGravity = library.videoFill ? .resizeAspectFill : .resizeAspect
        }
    }

    private func stopVideo() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        videoPathInUse = ""
    }

    var videoPlayer: AVQueuePlayer? { player }

    // MARK: Pausing

    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }

    /// Why it should rest now, or nil to play. (Pure, so it can be tested.)
    static func pauseReason(asleep: Bool, battery: Bool, lowPower: Bool, allCovered: Bool,
                            pauseOnBattery: Bool, pauseLowPower: Bool, pauseCovered: Bool) -> String? {
        if asleep { return "Display asleep" }
        if pauseOnBattery && battery { return "Paused on battery" }
        if pauseLowPower && lowPower { return "Paused in Low Power Mode" }
        if pauseCovered && allCovered { return "Paused while covered" }
        return nil
    }

    func updatePause() {
        guard !windows.isEmpty else { return }
        let library = UserLibrary.shared
        let visible = windows.map { $0.occlusionState.contains(.visible) }
        let reason = Self.pauseReason(asleep: screensAsleep, battery: testOnBattery ?? Self.onBattery,
                                      lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                      allCovered: !visible.contains(true),
                                      pauseOnBattery: library.livePauseOnBattery, pauseLowPower: library.livePauseLowPower,
                                      pauseCovered: library.livePauseCovered)
        for (w, isVisible) in zip(windows, visible) {
            if let view = w.contentView as? LiveMetalView {
                // A screen nobody can see (full-screen app, covered) rests on its own.
                view.isPaused = reason != nil || (library.livePauseCovered && !isVisible)
            }
        }
        if let player {
            if reason == nil { if player.rate == 0 { player.play() } } else { player.pause() }
        }
        let text = reason ?? ""
        if pauseReason != text { pauseReason = text }
    }
}

/// Gallery pictures of every style, made once in the background.
final class LiveThumbnails: ObservableObject {
    static let shared = LiveThumbnails()
    @Published private(set) var images: [LiveStyle: NSImage] = [:]
    private var started = false

    func load() {
        guard !started else { return }
        started = true
        DispatchQueue.global(qos: .userInitiated).async {
            for style in LiveStyle.allCases {
                guard let cg = LiveRenderer.snapshot(style, width: 320, height: 200) else { continue }
                let image = NSImage(cgImage: cg, size: NSSize(width: 160, height: 100))
                DispatchQueue.main.async { self.images[style] = image }
            }
        }
    }
}
