import AppKit
import Combine

/// Gentle water and posture reminders. When one is due the dock slides in
/// with a card; nothing needs notification permission.
final class CareReminders: ObservableObject {
    static let shared = CareReminders()

    enum Kind: String, Equatable {
        case water, posture

        var title: String {
            switch self {
            case .water: return "Time for a glass of water"
            case .posture: return "Sit up straight and stretch"
            }
        }

        var subtitle: String {
            switch self {
            case .water: return "A small sip keeps the headache away."
            case .posture: return "Roll your shoulders, look away from the screen."
            }
        }

        var symbol: String {
            switch self {
            case .water: return "drop.fill"
            case .posture: return "figure.stand"
            }
        }
    }

    @Published private(set) var active: Kind?
    @Published private(set) var nextWater: Date?
    @Published private(set) var nextPosture: Date?
    @Published private(set) var glassesToday: Int = 0

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastSignature = ""
    private let glassesKey = "glassesToday"
    private let glassesDayKey = "glassesDay"

    func start() {
        loadGlasses()
        reschedule(force: true)
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        AppSettings.shared.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.reschedule(force: false) } }
            .store(in: &cancellables)
    }

    private func reschedule(force: Bool) {
        let s = AppSettings.shared
        let signature = "\(s.waterEnabled)-\(s.waterMinutes)-\(s.postureEnabled)-\(s.postureMinutes)"
        guard force || signature != lastSignature else { return }
        lastSignature = signature
        let now = Date()
        nextWater = s.waterEnabled ? now.addingTimeInterval(Double(s.waterMinutes) * 60) : nil
        nextPosture = s.postureEnabled ? now.addingTimeInterval(Double(s.postureMinutes) * 60) : nil
    }

    private func check() {
        loadGlasses()
        guard active == nil else { return }
        let now = Date()
        let s = AppSettings.shared
        if let due = nextWater, now >= due {
            nextWater = now.addingTimeInterval(Double(s.waterMinutes) * 60)
            fire(.water)
        } else if let due = nextPosture, now >= due {
            nextPosture = now.addingTimeInterval(Double(s.postureMinutes) * 60)
            fire(.posture)
        }
    }

    private func fire(_ kind: Kind) {
        active = kind
        NSSound(named: "Glass")?.play()
        DockController.shared.show()
    }

    /// "Done": closes the card (and counts a glass for water).
    func complete() {
        if active == .water { addGlass() }
        active = nil
    }

    /// "Later": ask again in 5 minutes.
    func snooze() {
        let later = Date().addingTimeInterval(5 * 60)
        switch active {
        case .water: nextWater = later
        case .posture: nextPosture = later
        case nil: break
        }
        active = nil
    }

    func addGlass() {
        loadGlasses()
        glassesToday += 1
        UserDefaults.standard.set(glassesToday, forKey: glassesKey)
    }

    private func loadGlasses() {
        let today = Self.dayString(Date())
        let defaults = UserDefaults.standard
        if defaults.string(forKey: glassesDayKey) != today {
            defaults.set(today, forKey: glassesDayKey)
            defaults.set(0, forKey: glassesKey)
        }
        let count = defaults.integer(forKey: glassesKey)
        if count != glassesToday { glassesToday = count }
    }

    private static func dayString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
