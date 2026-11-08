import Foundation
import IOKit
import IOKit.ps

/// Battery levels of Magic Mouse / Keyboard / Trackpad, headphones on connect,
/// and the Mac's own battery (MacBook only: iMacs have none, so nothing shows there).
final class DeviceBatteryStore: ObservableObject {
    static let shared = DeviceBatteryStore()

    struct Device: Identifiable, Equatable {
        let name: String
        let percent: Int
        var id: String { name }
        var symbol: String { DeviceBatteryStore.symbol(for: name) }
    }

    @Published private(set) var devices: [Device] = []
    /// True only on Macs with a built-in battery (MacBooks).
    @Published private(set) var hasInternalBattery = false

    private var warned: Set<String> = []
    private var deviceTimer: Timer?
    private var powerTimer: Timer?
    private var lastCharging: Bool?

    func start() {
        refreshDevices()
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.refreshDevices() }
        RunLoop.main.add(t, forMode: .common)
        deviceTimer = t

        // Charging animation: only if this Mac has a battery.
        if let battery = Self.internalBattery() {
            hasInternalBattery = true
            lastCharging = battery.pluggedIn
            let p = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.checkPower() }
            RunLoop.main.add(p, forMode: .common)
            powerTimer = p
        }
    }

    // MARK: MacBook charging

    private func checkPower() {
        guard let battery = Self.internalBattery() else { return }
        defer { lastCharging = battery.pluggedIn }
        if let last = lastCharging, !last, battery.pluggedIn, AppSettings.shared.peekCharging {
            IslandController.shared.showPeek(.charging(percent: battery.percent), duration: 3.5)
        }
    }

    static func internalBattery() -> (percent: Int, charging: Bool, pluggedIn: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = info[kIOPSIsChargingKey] as? Bool ?? false
            let pluggedIn = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (current * 100 / max, charging, pluggedIn)
        }
        return nil
    }

    // MARK: Magic Mouse / Keyboard / Trackpad

    func refreshDevices() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = Self.readHIDBatteries()
            DispatchQueue.main.async {
                self?.devices = found
                self?.checkLow()
            }
        }
    }

    private func checkLow() {
        for device in devices {
            if device.percent <= 15, !warned.contains(device.name) {
                warned.insert(device.name)
                IslandController.shared.showPeek(.lowBattery(name: device.name, percent: device.percent), duration: 6)
            } else if device.percent > 30 {
                warned.remove(device.name)
            }
        }
    }

    private static func readHIDBatteries() -> [Device] {
        var result: [Device] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let percent = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            let name = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            if let percent, let name, !result.contains(where: { $0.name == name }) {
                result.append(Device(name: name, percent: percent))
            }
        }
        return result
    }

    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("mouse") { return "magicmouse.fill" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if n.contains("keyboard") { return "keyboard.fill" }
        return headphoneSymbol(for: name)
    }

    // MARK: Headphones

    static func headphoneSymbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    func headphonesConnected(name: String) {
        guard AppSettings.shared.peekHeadphones else { return }
        let symbol = Self.headphoneSymbol(for: name)
        IslandController.shared.showPeek(.headphones(name: name, symbol: symbol, levels: nil), duration: 5)
        DispatchQueue.global(qos: .utility).async {
            let levels = Self.bluetoothBattery(for: name)
            DispatchQueue.main.async {
                guard let levels else { return }
                IslandController.shared.updatePeek(.headphones(name: name, symbol: symbol, levels: levels))
            }
        }
    }

    /// Reads AirPods-style battery levels from System Information (takes about a second).
    private static func bluetoothBattery(for name: String) -> HeadphoneLevels? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        var found: [String: Any]?
        func search(_ object: Any) {
            if found != nil { return }
            if let dict = object as? [String: Any] {
                if let info = dict[name] as? [String: Any] {
                    found = info
                    return
                }
                for value in dict.values { search(value) }
            } else if let array = object as? [Any] {
                for value in array { search(value) }
            }
        }
        search(json)
        guard let info = found else { return nil }

        func percent(_ key: String) -> Int? {
            guard let text = info[key] as? String else { return nil }
            return Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        }
        let levels = HeadphoneLevels(
            left: percent("device_batteryLevelLeft"),
            right: percent("device_batteryLevelRight"),
            caseLevel: percent("device_batteryLevelCase"),
            single: percent("device_batteryLevelMain")
        )
        return levels.isEmpty ? nil : levels
    }
}

struct HeadphoneLevels: Equatable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var single: Int?

    var isEmpty: Bool { left == nil && right == nil && caseLevel == nil && single == nil }
}
