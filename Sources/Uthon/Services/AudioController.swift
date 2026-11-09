import Foundation
import CoreAudio
import AudioToolbox

/// Reads and sets the system output volume, and notices when headphones connect.
final class AudioController {
    static let shared = AudioController()

    private(set) var device = AudioObjectID(kAudioObjectUnknown)
    private var listenedDevice: AudioObjectID?
    private var volumeBlock: AudioObjectPropertyListenerBlock?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
            self?.defaultDeviceChanged(announce: true)
        }
        defaultDeviceChanged(announce: false)
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func defaultDeviceChanged(announce: Bool) {
        removeVolumeListeners()
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        device = id
        addVolumeListeners()
        if announce, isBluetooth(id), let name = name(of: id) {
            DeviceBatteryStore.shared.headphonesConnected(name: name)
        }
    }

    private func addVolumeListeners() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeChanged() }
        volumeBlock = block
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var addr = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
            if AudioObjectHasProperty(device, &addr) {
                AudioObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main, block)
            }
        }
        listenedDevice = device
    }

    private func removeVolumeListeners() {
        guard let old = listenedDevice, let block = volumeBlock else { return }
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var addr = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
            if AudioObjectHasProperty(old, &addr) {
                AudioObjectRemovePropertyListenerBlock(old, &addr, DispatchQueue.main, block)
            }
        }
        listenedDevice = nil
        volumeBlock = nil
    }

    private func volumeChanged() {
        let fromScroll = Date().timeIntervalSince(IslandController.shared.lastScrollVolume) < 1
        guard AppSettings.shared.hudEnabled || fromScroll else { return }
        IslandController.shared.showPeek(.volume(level: volume, muted: isMuted), duration: 1.6)
    }

    // MARK: Volume

    var volume: Float {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(device, &addr) else { return 0 }
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return value
    }

    func setVolume(_ newValue: Float) {
        var value = Float32(max(0, min(1, newValue)))
        var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(device, &addr) else { return }
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if value > 0 && isMuted { setMuted(false) }
    }

    func nudge(_ delta: Float) {
        setVolume(volume + delta)
    }

    var isMuted: Bool {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return value != 0
    }

    func setMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        var addr = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(device, &addr) else { return }
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    // MARK: Device info

    func isBluetooth(_ id: AudioObjectID) -> Bool {
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = Self.address(kAudioDevicePropertyTransportType)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    func name(of id: AudioObjectID) -> String? {
        var nameRef: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var addr = Self.address(kAudioObjectPropertyName)
        let status = withUnsafeMutablePointer(to: &nameRef) { pointer in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, pointer)
        }
        guard status == noErr, let nameRef else { return nil }
        return nameRef.takeRetainedValue() as String
    }
}
