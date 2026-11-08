import SwiftUI

struct CareWidget: View {
    @ObservedObject private var care = CareReminders.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Card("Care", symbol: "heart") {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                VStack(spacing: 10) {
                    row(symbol: "drop.fill", tint: .blue, title: "Water",
                        detail: detail(enabled: settings.waterEnabled, next: care.nextWater)) {
                        Button {
                            care.addGlass()
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(care.glassesToday)").monospacedDigit()
                                Image(systemName: "plus")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .help("Glasses of water today, tap to add one")
                    }
                    row(symbol: "figure.stand", tint: .green, title: "Posture",
                        detail: detail(enabled: settings.postureEnabled, next: care.nextPosture)) {
                        EmptyView()
                    }
                }
            }
        }
    }

    private func detail(enabled: Bool, next: Date?) -> String {
        guard enabled, let next else { return "Off" }
        if next <= Date() { return "Due now" }
        return "Next " + next.formatted(.relative(presentation: .numeric))
    }

    private func row<Accessory: View>(symbol: String, tint: Color, title: String, detail: String,
                                      @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
            accessory()
        }
    }
}

struct ReminderBanner: View {
    let kind: CareReminders.Kind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.system(size: 13, weight: .semibold))
                    Text(kind.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 12) {
                Button("Done") { CareReminders.shared.complete() }
                    .buttonStyle(AccentButtonStyle())
                Button("Later (5 min)") { CareReminders.shared.snooze() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.accent.opacity(0.14))
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
