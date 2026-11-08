import AppKit
import ApplicationServices

/// Optional: takes over the volume, mute and brightness keys so the island shows
/// instead of the macOS popup. Needs Accessibility permission.
final class MediaKeyTap {
    static let shared = MediaKeyTap()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Turn the tap on or off to match the settings. Safe to call often.
    func update(prompt: Bool = false) {
        let s = AppSettings.shared
        if s.replaceSystemHUD && s.islandEnabled {
            enable(prompt: prompt)
        } else {
            disable()
        }
    }

    private func enable(prompt: Bool) {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            if prompt { Self.requestTrust() }
            return
        }
        let mask = CGEventMask(1 << 14)   // NX_SYSDEFINED: media and brightness keys
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in MediaKeyTap.handle(type: type, event: event) },
            userInfo: nil
        ) else { return }
        tap = newTap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
    }

    private func disable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private static func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = shared.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF0000) >> 16
        let keyFlags = data & 0x0000FFFF
        let isDown = ((keyFlags & 0xFF00) >> 8) == 0xA
        let fine = nsEvent.modifierFlags.contains(.option) && nsEvent.modifierFlags.contains(.shift)
        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0

        switch keyCode {
        case 0:   // volume up
            if isDown { DispatchQueue.main.async { AudioController.shared.nudge(step) } }
            return nil
        case 1:   // volume down
            if isDown { DispatchQueue.main.async { AudioController.shared.nudge(-step) } }
            return nil
        case 7:   // mute
            if isDown { DispatchQueue.main.async { AudioController.shared.toggleMute() } }
            return nil
        case 2:   // brightness up
            guard BrightnessController.shared.isAvailable else { return Unmanaged.passUnretained(event) }
            if isDown { DispatchQueue.main.async { BrightnessController.shared.nudge(step) } }
            return nil
        case 3:   // brightness down
            guard BrightnessController.shared.isAvailable else { return Unmanaged.passUnretained(event) }
            if isDown { DispatchQueue.main.async { BrightnessController.shared.nudge(-step) } }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
