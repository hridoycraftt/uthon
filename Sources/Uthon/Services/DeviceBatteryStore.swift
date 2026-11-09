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
            let found = Self.readDevices()
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

    /// Wireless devices with a battery: Magic Keyboard / Mouse / Trackpad from the I/O registry,
    /// plus anything else Bluetooth reports (AirPods, headphones, game controllers...).
    static func readDevices() -> [Device] {
        var result = parseRegistry(run("/usr/sbin/ioreg", ["-r", "-a", "-k", "BatteryPercent"]))
        for device in parseBluetooth(run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]))
        where !result.contains(where: { $0.name == device.name }) {
            result.append(device)
        }
        return result.sorted { order($0.name) < order($1.name) }
    }

    private static func order(_ name: String) -> Int {
        let n = name.lowercased()
        if n.contains("keyboard") { return 0 }
        if n.contains("mouse") { return 1 }
        if n.contains("trackpad") { return 2 }
        return 3
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return Data() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    /// `ioreg -r -a -k BatteryPercent` output (a plist array of devices).
    static func parseRegistry(_ data: Data) -> [Device] {
        guard !data.isEmpty,
              let list = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [[String: Any]] else { return [] }
        var result: [Device] = []
        for entry in list {
            let ioClass = entry["IOClass"] as? String ?? ""
            if ioClass.contains("AppleSmartBattery") { continue }   // the Mac's own battery is shown separately
            guard let percent = (entry["BatteryPercent"] as? NSNumber)?.intValue, (0...100).contains(percent) else { continue }
            let rawName = (entry["Product"] as? String) ?? (entry["DeviceName"] as? String) ?? (entry["Name"] as? String) ?? ""
            let name = rawName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !result.contains(where: { $0.name == name }) else { continue }
            result.append(Device(name: name, percent: percent))
        }
        return result
    }

    /// `system_profiler SPBluetoothDataType -json`: connected devices that report a battery level.
    static func parseBluetooth(_ data: Data) -> [Device] {
        guard !data.isEmpty, let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var result: [Device] = []
        func percent(_ value: Any?) -> Int? {
            guard let text = value as? String else { return nil }
            return Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        }
        func visit(_ object: Any, connected: Bool) {
            if let dict = object as? [String: Any] {
                for (key, value) in dict {
                    let isConnectedList = key == "device_connected"
                    if connected, let info = value as? [String: Any] {
                        let levels = [percent(info["device_batteryLevelMain"]),
                                      percent(info["device_batteryLevelLeft"]),
                                      percent(info["device_batteryLevelRight"])].compactMap { $0 }
                        if let level = levels.min(), !result.contains(where: { $0.name == key }) {
                            result.append(Device(name: key, percent: level))
                            continue
                        }
                    }
                    visit(value, connected: connected || isConnectedList)
                }
            } else if let array = object as? [Any] {
                for value in array { visit(value, connected: connected) }
            }
        }
        visit(json, connected: false)
        return result
    }

    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("mouse") { return "magicmouse.fill" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if n.contains("keyboard") { return "keyboard.fill" }
        if n.contains("airpods") || n.contains("beats") || n.contains("headphone") || n.contains("buds") {
            return headphoneSymbol(for: name)
        }
        if n.contains("controller") || n.contains("gamepad") { return "gamecontroller.fill" }
        if n.contains("pencil") { return "applepencil" }
        return "battery.75percent"
    }

    /// Short label for tight spaces: "Magic Keyboard with Touch ID" -> "Keyboard".
    static func shortName(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("keyboard") { return "Keyboard" }
        if n.contains("mouse") { return "Mouse" }
        if n.contains("trackpad") { return "Trackpad" }
        if n.contains("airpods") { return "AirPods" }
        return name
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
