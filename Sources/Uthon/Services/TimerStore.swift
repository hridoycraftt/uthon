import AppKit

/// Countdown timer and stopwatch, shown as live activities on the island.
final class TimerStore: ObservableObject {
    static let shared = TimerStore()

    @Published private(set) var timerEnd: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var timerTotal: TimeInterval = 0
    @Published private(set) var alarmRinging = false

    @Published private(set) var stopwatchStart: Date?
    @Published private(set) var stopwatchAccumulated: TimeInterval = 0
    @Published private(set) var laps: [TimeInterval] = []

    private var ticker: Timer?
    private var alarmSound: NSSound?

    var timerActive: Bool { timerEnd != nil || pausedRemaining != nil }
    var timerPaused: Bool { pausedRemaining != nil }
    var stopwatchRunning: Bool { stopwatchStart != nil }
    var stopwatchUsed: Bool { stopwatchStart != nil || stopwatchAccumulated > 0 }

    // MARK: Timer

    func remaining(at date: Date) -> TimeInterval {
        if let end = timerEnd { return max(0, end.timeIntervalSince(date)) }
        return pausedRemaining ?? 0
    }

    func progress(at date: Date) -> Double {
        guard timerTotal > 0 else { return 0 }
        return 1 - remaining(at: date) / timerTotal
    }

    func startTimer(minutes: Double) {
        stopAlarm()
        timerTotal = minutes * 60
        pausedRemaining = nil
        timerEnd = Date().addingTimeInterval(timerTotal)
        ensureTicker()
    }

    func pauseTimer() {
        guard let end = timerEnd else { return }
        pausedRemaining = max(0, end.timeIntervalSinceNow)
        timerEnd = nil
    }

    func resumeTimer() {
        guard let remaining = pausedRemaining else { return }
        timerEnd = Date().addingTimeInterval(remaining)
        pausedRemaining = nil
        ensureTicker()
    }

    func addMinute() {
        if let end = timerEnd {
            timerEnd = end.addingTimeInterval(60)
        } else if let remaining = pausedRemaining {
            pausedRemaining = remaining + 60
        } else {
            startTimer(minutes: 1)
            return
        }
        timerTotal += 60
    }

    func cancelTimer() {
        timerEnd = nil
        pausedRemaining = nil
        stopAlarm()
    }

    func stopAlarm() {
        alarmRinging = false
        alarmSound?.stop()
        alarmSound = nil
    }

    private func ensureTicker() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard let end = timerEnd else {
            if pausedRemaining == nil {
                ticker?.invalidate()
                ticker = nil
            }
            return
        }
        if Date() >= end {
            timerEnd = nil
            pausedRemaining = nil
            ring()
        }
    }

    private func ring() {
        alarmRinging = true
        let sound = NSSound(named: "Glass")
        sound?.loops = true
        sound?.play()
        alarmSound = sound
        IslandController.shared.showPeek(.timerDone, duration: 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.alarmSound?.stop()
        }
    }

    // MARK: Stopwatch

    func elapsed(at date: Date) -> TimeInterval {
        stopwatchAccumulated + (stopwatchStart.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggleStopwatch() {
        if let start = stopwatchStart {
            stopwatchAccumulated += Date().timeIntervalSince(start)
            stopwatchStart = nil
        } else {
            stopwatchStart = Date()
        }
    }

    func lap() {
        laps.insert(elapsed(at: Date()), at: 0)
        if laps.count > 20 { laps.removeLast() }
    }

    func resetStopwatch() {
        stopwatchStart = nil
        stopwatchAccumulated = 0
        laps = []
    }

    static func format(_ seconds: TimeInterval, tenths: Bool = false) -> String {
        let value = max(0, seconds)
        let total = Int(value)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var text = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        if tenths { text += String(format: ".%d", Int((value - Double(total)) * 10)) }
        return text
    }
}
