import SwiftUI
import AppKit
import EventKit

struct ClockWidget: View {
    @ObservedObject private var calendar = CalendarStore.shared

    var body: some View {
        Card("Today", symbol: "calendar") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 36, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
            }
            Divider().opacity(0.5)
            events
        }
        .onAppear { calendar.refresh() }
    }

    @ViewBuilder
    private var events: some View {
        switch calendar.access {
        case .notDetermined:
            Button("Show my calendar events") { calendar.requestAccess() }
                .buttonStyle(AccentButtonStyle())
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Text("Calendar access is off.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
            }
        case .granted:
            if calendar.events.isEmpty {
                Text("Nothing else on the calendar today")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(calendar.events.enumerated()), id: \.offset) { _, event in
                        EventRow(event: event)
                    }
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: EKEvent

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.calendar?.color ?? .systemOrange))
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    private var timeText: String {
        let cal = Calendar.current
        let start: Date = event.startDate
        let end: Date = event.endDate
        var prefix = ""
        if cal.isDateInTomorrow(start) {
            prefix = "Tomorrow · "
        } else if !cal.isDateInToday(start) {
            prefix = start.formatted(.dateTime.weekday(.abbreviated)) + " · "
        }
        if event.isAllDay { return prefix + "All day" }
        return prefix + start.formatted(date: .omitted, time: .shortened)
            + " – " + end.formatted(date: .omitted, time: .shortened)
    }
}
