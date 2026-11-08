import Foundation
import CoreGraphics

/// Built-in display brightness (iMac / MacBook) through the DisplayServices framework.
/// Changes are noticed by polling a few times a second, which is very cheap.
final class BrightnessController {
    static let shared = BrightnessController()

    private typealias GetFunction = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (UInt32, Float) -> Int32

    private var getBrightness: GetFunction?
    private var setBrightness: SetFunction?
    private var last: Float?
    private var timer: Timer?

    var isAvailable: Bool { getBrightness != nil && current != nil }

    func start() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW) {
            if let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
                getBrightness = unsafeBitCast(symbol, to: GetFunction.self)
            }
            if let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
                setBrightness = unsafeBitCast(symbol, to: SetFunction.self)
            }
        }
        guard getBrightness != nil, current != nil else { return }
        last = current
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var current: Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        return getBrightness(CGMainDisplayID(), &value) == 0 ? value : nil
    }

    func set(_ value: Float) {
        _ = setBrightness?(CGMainDisplayID(), max(0, min(1, value)))
    }

    func nudge(_ delta: Float) {
        guard let value = current else { return }
        set(value + delta)
        poll()
    }

    private func poll() {
        guard let value = current else { return }
        defer { last = value }
        // Ignore the slow drift of automatic brightness; key presses move it in bigger steps.
        if let last, abs(value - last) > 0.02, AppSettings.shared.hudEnabled {
            IslandController.shared.showPeek(.brightness(level: value), duration: 1.6)
        }
    }
}
