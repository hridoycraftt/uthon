import Foundation

/// Islamic prayer times calculated on the Mac from the sun's position (no internet needed
/// once the city's location is known). Standard astronomical method, as used by most apps.
enum PrayerTimes {
    struct Times: Equatable {
        let fajr: Date
        let sunrise: Date
        let dhuhr: Date
        let asr: Date
        let maghrib: Date
        let isha: Date

        var all: [(name: String, time: Date)] {
            [("Fajr", fajr), ("Sunrise", sunrise), ("Dhuhr", dhuhr), ("Asr", asr), ("Maghrib", maghrib), ("Isha", isha)]
        }

        /// The five prayers (sunrise is not a prayer).
        var prayers: [(name: String, time: Date)] { all.filter { $0.name != "Sunrise" } }

        func next(after now: Date = Date()) -> (name: String, time: Date)? {
            prayers.first { $0.time > now }
        }
    }

    static func compute(for date: Date, latitude: Double, longitude: Double, timeZone: TimeZone,
                        method: PrayerMethod, hanafi: Bool) -> Times? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day,
              let midnight = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }

        let jd = julianDate(year: year, month: month, day: day) - longitude / (15 * 24)
        let tzHours = Double(timeZone.secondsFromGMT(for: midnight)) / 3600

        func sun(_ t: Double) -> (decl: Double, eqt: Double) {
            let d = jd + t - 2451545.0
            let g = fix(357.529 + 0.98560028 * d, 360)
            let q = fix(280.459 + 0.98564736 * d, 360)
            let l = fix(q + 1.915 * dsin(g) + 0.020 * dsin(2 * g), 360)
            let e = 23.439 - 0.00000036 * d
            let ra = fix(darctan2(dcos(e) * dsin(l), dcos(l)) / 15, 24)
            let eqt = q / 15 - ra
            let decl = darcsin(dsin(e) * dsin(l))
            return (decl, eqt)
        }

        func midDay(_ t: Double) -> Double {
            fix(12 - sun(t).eqt, 24)
        }

        func sunAngleTime(_ angle: Double, _ t: Double, ccw: Bool) -> Double? {
            let decl = sun(t).decl
            let noon = midDay(t)
            let value = (-dsin(angle) - dsin(decl) * dsin(latitude)) / (dcos(decl) * dcos(latitude))
            guard value >= -1, value <= 1 else { return nil }   // sun never reaches this angle today
            let span = darccos(value) / 15
            return noon + (ccw ? -span : span)
        }

        func asrTime(_ factor: Double, _ t: Double) -> Double? {
            let decl = sun(t).decl
            let angle = -darccot(factor + dtan(abs(latitude - decl)))
            return sunAngleTime(angle, t, ccw: false)
        }

        let angles = method.angles
        guard let fajr = sunAngleTime(angles.fajr, 5.0 / 24, ccw: true),
              let sunrise = sunAngleTime(0.833, 6.0 / 24, ccw: true),
              let asr = asrTime(hanafi ? 2 : 1, 13.0 / 24),
              let maghrib = sunAngleTime(0.833, 18.0 / 24, ccw: false) else { return nil }
        let dhuhr = midDay(12.0 / 24)
        let isha: Double
        if method == .makkah {
            isha = maghrib + 1.5
        } else {
            guard let value = sunAngleTime(angles.isha, 18.0 / 24, ccw: false) else { return nil }
            isha = value
        }

        func toDate(_ hours: Double) -> Date {
            let local = hours + tzHours - longitude / 15
            return midnight.addingTimeInterval(local * 3600)
        }

        return Times(fajr: toDate(fajr), sunrise: toDate(sunrise), dhuhr: toDate(dhuhr + 1.0 / 60),
                     asr: toDate(asr), maghrib: toDate(maghrib + 1.0 / 60), isha: toDate(isha))
    }

    private static func julianDate(year: Int, month: Int, day: Int) -> Double {
        var y = Double(year), m = Double(month)
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = floor(y / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + Double(day) + b - 1524.5
    }

    private static func fix(_ value: Double, _ mod: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: mod)
        return r < 0 ? r + mod : r
    }

    private static func dsin(_ d: Double) -> Double { sin(d * .pi / 180) }
    private static func dcos(_ d: Double) -> Double { cos(d * .pi / 180) }
    private static func dtan(_ d: Double) -> Double { tan(d * .pi / 180) }
    private static func darcsin(_ x: Double) -> Double { asin(x) * 180 / .pi }
    private static func darccos(_ x: Double) -> Double { acos(x) * 180 / .pi }
    private static func darctan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) * 180 / .pi }
    private static func darccot(_ x: Double) -> Double { atan(1 / x) * 180 / .pi }
}
