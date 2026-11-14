import Foundation
import SwiftUI
import AppKit
import Network
import CoreWLAN
import CoreLocation

/// Wi-Fi signal, live upload/download rate, online state and an on-demand speed test.
final class NetworkStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = NetworkStore()

    enum Link: Equatable { case wifi, ethernet, other, offline }

    struct SpeedResult: Codable, Equatable {
        var downMbps: Double
        var upMbps: Double
        var pingMs: Double
        var date: Date
    }

    @Published private(set) var link: Link = .other
    @Published private(set) var ssid: String?
    @Published private(set) var rssi: Int?
    /// Wi-Fi link rate the Mac negotiated (Mbit/s).
    @Published private(set) var linkRate: Double?
    /// Live traffic in bytes per second.
    @Published private(set) var downRate: Double = 0
    @Published private(set) var upRate: Double = 0
    @Published private(set) var testing = false
    @Published private(set) var testPhase = ""
    @Published private(set) var lastTest: SpeedResult?
    @Published private(set) var testError: String?
    @Published private(set) var locationAllowed = false

    private var monitor: NWPathMonitor?
    private var timer: Timer?
    private var lastBytes: (down: UInt64, up: UInt64, at: Date)?
    private var location: CLLocationManager?
    private var wasOnline: Bool?

    private override init() {
        super.init()
        lastTest = Persist.load(SpeedResult.self, key: "lastSpeedTest")
    }

    var running: Bool { timer != nil }

    func start() {
        guard UserLibrary.shared.networkEnabled, timer == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.update(path: path) }
        }
        m.start(queue: DispatchQueue(label: "uthon.network"))
        monitor = m
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        updateLocationState()
        tick()
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        timer?.invalidate()
        timer = nil
        lastBytes = nil
        downRate = 0
        upRate = 0
    }

    private func update(path: NWPath) {
        let online = path.status == .satisfied
        let newLink: Link
        if !online { newLink = .offline }
        else if path.usesInterfaceType(.wifi) { newLink = .wifi }
        else if path.usesInterfaceType(.wiredEthernet) { newLink = .ethernet }
        else { newLink = .other }
        if link != newLink { link = newLink }
        if let was = wasOnline, was != online, UserLibrary.shared.networkPeeks {
            IslandController.shared.showPeek(.network(online: online), duration: 3)
        }
        wasOnline = online
    }

    private func tick() {
        // Only changed values are published: every published change redraws whatever shows it.
        var newRSSI: Int?, newRate: Double?, newSSID: String?
        if let interface = CWWiFiClient.shared().interface(), interface.powerOn() {
            let value = interface.rssiValue()
            newRSSI = value == 0 ? nil : value
            let rate = interface.transmitRate()
            newRate = rate > 0 ? rate : nil
            newSSID = interface.ssid()
        }
        if rssi != newRSSI { rssi = newRSSI }
        if linkRate != newRate { linkRate = newRate }
        if ssid != newSSID { ssid = newSSID }
        let now = Date()
        let bytes = Self.interfaceBytes()
        if let last = lastBytes {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0.2 {
                // Rounded to 100 bytes/s so a quiet connection does not redraw for nothing.
                let down = ((bytes.down >= last.down ? Double(bytes.down - last.down) / dt : 0) / 100).rounded() * 100
                let up = ((bytes.up >= last.up ? Double(bytes.up - last.up) / dt : 0) / 100).rounded() * 100
                if downRate != down { downRate = down }
                if upRate != up { upRate = up }
            }
        }
        lastBytes = (bytes.down, bytes.up, now)
    }

    /// Total bytes in/out on all physical interfaces (Wi-Fi and Ethernet: en*).
    static func interfaceBytes() -> (down: UInt64, up: UInt64) {
        var down: UInt64 = 0, up: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(pointer) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let item = entry.pointee
            if let addr = item.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               String(cString: item.ifa_name).hasPrefix("en"),
               let data = item.ifa_data?.assumingMemoryBound(to: if_data.self) {
                down += UInt64(data.pointee.ifi_ibytes)
                up += UInt64(data.pointee.ifi_obytes)
            }
            cursor = item.ifa_next
        }
        return (down, up)
    }

    // MARK: Signal

    /// 0...4 bars from the Wi-Fi signal strength.
    static func bars(rssi: Int?) -> Int {
        guard let rssi else { return 0 }
        switch rssi {
        case (-55)...: return 4
        case (-65)...: return 3
        case (-75)...: return 2
        case (-85)...: return 1
        default: return 0
        }
    }

    static func quality(rssi: Int?) -> String {
        switch bars(rssi: rssi) {
        case 4: return "Excellent"
        case 3: return "Good"
        case 2: return "Fair"
        case 1: return "Weak"
        default: return "No signal"
        }
    }

    /// "12.3 MB/s", "840 KB/s".
    static func rate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        if value >= 1_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0f KB/s", value / 1_000) }
        return String(format: "%.0f B/s", value)
    }

    static func mbps(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    // MARK: Wi-Fi name (macOS needs Location permission for it)

    func updateLocationState() {
        let status = CLLocationManager().authorizationStatus
        locationAllowed = status == .authorizedAlways || status == .authorized
    }

    func askForWiFiName() {
        let manager = location ?? CLLocationManager()
        manager.delegate = self
        location = manager
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.location?.stopUpdatingLocation()
            self?.updateLocationState()
            self?.tick()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            self?.updateLocationState()
            self?.tick()
        }
    }

    // MARK: Speed test (Cloudflare's public speed test endpoints)

    func runSpeedTest() {
        guard !testing else { return }
        testing = true
        testError = nil
        testPhase = "Ping"
        let megabytes = UserLibrary.shared.speedTestMB
        Task { [weak self] in
            let result = await Self.measure(megabytes: megabytes) { phase in
                await MainActor.run { self?.testPhase = phase }
            }
            await MainActor.run {
                guard let self else { return }
                self.testing = false
                self.testPhase = ""
                if let result {
                    self.lastTest = result
                    Persist.save(result, key: "lastSpeedTest")
                } else {
                    self.testError = L("Speed test failed. Check the internet connection.")
                }
            }
        }
    }

    private static func measure(megabytes: Int, phase: @escaping (String) async -> Void) async -> SpeedResult? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        // Ping: best of three tiny requests.
        var ping = Double.infinity
        for _ in 0..<3 {
            let start = Date()
            guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0"),
                  let reply = try? await session.data(from: url),
                  (reply.1 as? HTTPURLResponse)?.statusCode == 200 else { continue }
            ping = min(ping, Date().timeIntervalSince(start) * 1000)
        }
        guard ping.isFinite else { return nil }

        await phase("Download")
        let bytes = max(1, megabytes) * 1_000_000
        let downStart = Date()
        guard let downURL = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)"),
              let reply = try? await session.data(from: downURL),
              (reply.1 as? HTTPURLResponse)?.statusCode == 200, reply.0.count > 0 else { return nil }
        let data = reply.0
        let downSeconds = max(0.05, Date().timeIntervalSince(downStart))
        let down = Double(data.count) * 8 / downSeconds / 1_000_000

        await phase("Upload")
        let upBytes = max(1, megabytes / 3) * 1_000_000
        var request = URLRequest(url: URL(string: "https://speed.cloudflare.com/__up")!)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let upStart = Date()
        var up = 0.0
        if let reply = try? await session.upload(for: request, from: Data(count: upBytes)),
           (reply.1 as? HTTPURLResponse)?.statusCode == 200 {
            up = Double(upBytes) * 8 / max(0.05, Date().timeIntervalSince(upStart)) / 1_000_000
        }
        return SpeedResult(downMbps: down, upMbps: up, pingMs: ping, date: Date())
    }
}

// MARK: Widget

struct NetworkTile: View {
    @ObservedObject private var net = NetworkStore.shared
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var settings = AppSettings.shared

    private var wide: Bool { settings.slots(of: HomeItem(.network)) >= 2 }

    var body: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 5) {
                SectionLabel("Internet")
                if !library.networkEnabled {
                    Spacer(minLength: 0)
                    Text(L("Network monitor is off in Settings"))
                        .font(.system(size: 10)).foregroundStyle(Color.secondary)
                } else {
                    header
                    if wide {
                        HStack(alignment: .top, spacing: 14) {
                            live
                            speed
                        }
                    } else {
                        live
                    }
                    Spacer(minLength: 0)
                    testButton
                }
            }
        }
        .onAppear { net.start() }
        .contextMenu {
            MenuButton("Run speed test") { net.runSpeedTest() }
            MenuButton("Network Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") { NSWorkspace.shared.open(url) }
            }
            MenuButton("Settings…") { SettingsWindowController.shared.show(tab: .network) }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            SignalBars(bars: net.link == .wifi ? NetworkStore.bars(rssi: net.rssi) : (net.link == .offline ? 0 : 4),
                       symbol: symbol)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 9)).foregroundStyle(Color.secondary).lineLimit(1)
            }
        }
    }

    private var symbol: String {
        switch net.link {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .other: return "network"
        case .offline: return "wifi.slash"
        }
    }

    private var title: String {
        switch net.link {
        case .wifi: return net.ssid ?? "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .other: return L("Online")
        case .offline: return L("Offline")
        }
    }

    private var subtitle: String {
        switch net.link {
        case .wifi:
            var parts = [L(NetworkStore.quality(rssi: net.rssi))]
            if let rssi = net.rssi { parts.append("\(rssi) dBm") }
            return parts.joined(separator: " · ")
        case .offline: return L("No internet")
        default: return L("Connected")
        }
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(NetworkStore.rate(net.downRate), systemImage: "arrow.down")
            Label(NetworkStore.rate(net.upRate), systemImage: "arrow.up")
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
    }

    @ViewBuilder private var speed: some View {
        if let test = net.lastTest {
            VStack(alignment: .leading, spacing: 2) {
                Text("↓ \(NetworkStore.mbps(test.downMbps)) · ↑ \(NetworkStore.mbps(test.upMbps)) Mbps")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Text(L("Ping") + " \(Int(test.pingMs)) ms")
                    .font(.system(size: 9)).foregroundStyle(Color.secondary)
            }
            .lineLimit(1)
            .monospacedDigit()
        }
    }

    @ViewBuilder private var testButton: some View {
        if net.testing {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(L(net.testPhase) + "…").font(.system(size: 10, weight: .medium))
            }
        } else {
            Button { net.runSpeedTest() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                    if !wide, let test = net.lastTest {
                        Text("\(NetworkStore.mbps(test.downMbps)) Mbps")
                    } else {
                        Text(L("Speed test"))
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(net.link == .offline)
            .help(net.testError ?? L("Uses about") + " \(library.speedTestMB + library.speedTestMB / 3) MB")
        }
    }
}

struct SignalBars: View {
    let bars: Int
    let symbol: String

    var body: some View {
        Image(systemName: symbol, variableValue: Double(bars) / 4)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(bars >= 2 ? Theme.accent : (bars == 1 ? Color.orange : Color.secondary))
            .frame(width: 22)
    }
}
