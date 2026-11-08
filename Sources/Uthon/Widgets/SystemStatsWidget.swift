import SwiftUI

struct SystemStatsWidget: View {
    @ObservedObject private var stats = SystemStatsStore.shared

    var body: some View {
        Card("System", symbol: "cpu") {
            VStack(spacing: 10) {
                MeterRow(label: "CPU", value: stats.cpu, detail: "\(Int((stats.cpu * 100).rounded()))%")
                MeterRow(label: "Memory", value: stats.memoryFraction,
                         detail: "\(bytes(Int64(stats.memoryUsed))) of \(bytes(Int64(stats.memoryTotal)))")
                if let battery = stats.battery {
                    MeterRow(label: battery.charging ? "Battery · charging" : "Battery",
                             value: Double(battery.percent) / 100,
                             detail: "\(battery.percent)%",
                             lowIsBad: true)
                }
                if let free = stats.diskFree {
                    HStack {
                        Text(L("Disk free")).font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text(bytes(free))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }
}

struct MeterRow: View {
    let label: String
    let value: Double
    let detail: String
    var lowIsBad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L(label)).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(detail)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat(clamped)))
                        .animation(.easeOut(duration: 0.4), value: clamped)
                }
            }
            .frame(height: 5)
        }
    }

    private var clamped: Double { min(max(value, 0), 1) }

    private var color: Color {
        if lowIsBad {
            return clamped < 0.15 ? .red : (clamped < 0.3 ? .orange : .green)
        }
        return clamped > 0.85 ? .red : (clamped > 0.65 ? .orange : Theme.accent)
    }
}
