import Foundation
import Combine

/// Current weather for the city set in Settings, from the free Open-Meteo service (no account needed).
final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()

    struct Current: Equatable {
        let city: String
        let temperature: Double
        let code: Int
        let isDay: Bool
        let high: Double?
        let low: Double?

        var symbol: String { WeatherStore.symbol(code: code, isDay: isDay) }
    }

    struct Place: Equatable {
        let city: String
        let latitude: Double
        let longitude: Double
        let timeZone: TimeZone
    }

    /// The next hours: time, temperature, chance of rain (%), weather code.
    struct Hour: Equatable, Identifiable {
        let time: Date
        let temperature: Double
        let rainChance: Int
        let code: Int
        var id: Date { time }
        var symbol: String { WeatherStore.symbol(code: code, isDay: true) }
    }

    @Published private(set) var hourly: [Hour] = []
    /// 15-minute rain amounts (mm) for the next hours.
    @Published private(set) var rainSlots: [(time: Date, mm: Double)] = []
    private var lastRainAlert: Date?

    @Published private(set) var current: Current?
    /// The city's location, also used for prayer times.
    @Published private(set) var place: Place?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func start() {
        refresh()
        // Every 15 minutes, so a rain alert comes in time.
        let t = Timer(timeInterval: 900, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        AppSettings.shared.$weatherCity
            .dropFirst()
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        AppSettings.shared.$weatherFahrenheit
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &cancellables)
    }

    func refresh() {
        let city = AppSettings.shared.weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else {
            current = nil
            place = nil
            return
        }
        var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        geo?.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let geoURL = geo?.url else { return }
        Self.fetchJSON(geoURL) { [weak self] json in
            guard let results = json?["results"] as? [[String: Any]], let first = results.first,
                  let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else { return }
            let name = first["name"] as? String ?? city
            let zone = (first["timezone"] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
            self?.place = Place(city: name, latitude: lat, longitude: lon, timeZone: zone)
            self?.fetchForecast(lat: lat, lon: lon, city: name)
        }
    }

    private func fetchForecast(lat: Double, lon: Double, city: String) {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        comps?.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "minutely_15", value: "precipitation"),
            URLQueryItem(name: "forecast_hours", value: "12"),
            URLQueryItem(name: "forecast_minutely_15", value: "16"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: AppSettings.shared.weatherFahrenheit ? "fahrenheit" : "celsius"),
        ]
        guard let url = comps?.url else { return }
        Self.fetchJSON(url) { [weak self] json in
            guard let now = json?["current"] as? [String: Any],
                  let temp = now["temperature_2m"] as? Double else { return }
            let zone = self?.place?.timeZone ?? .current
            self?.hourly = Self.parseHourly(json?["hourly"] as? [String: Any], zone: zone)
            self?.rainSlots = Self.parseRain(json?["minutely_15"] as? [String: Any], zone: zone)
            self?.checkRain()
            let daily = json?["daily"] as? [String: Any]
            let high = (daily?["temperature_2m_max"] as? [Double])?.first
            let low = (daily?["temperature_2m_min"] as? [Double])?.first
            self?.current = Current(
                city: city,
                temperature: temp,
                code: now["weather_code"] as? Int ?? 0,
                isDay: (now["is_day"] as? Int ?? 1) == 1,
                high: high,
                low: low
            )
        }
    }

    /// Open-Meteo gives local times like "2026-11-14T15:00" (the city's time zone).
    static func parseTime(_ text: String, zone: TimeZone) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.date(from: text)
    }

    static func parseHourly(_ hourly: [String: Any]?, zone: TimeZone, now: Date = Date()) -> [Hour] {
        guard let times = hourly?["time"] as? [String] else { return [] }
        let temps = hourly?["temperature_2m"] as? [Double] ?? []
        let chances = hourly?["precipitation_probability"] as? [Any] ?? []
        let codes = hourly?["weather_code"] as? [Any] ?? []
        var result: [Hour] = []
        for (i, text) in times.enumerated() {
            guard let time = parseTime(text, zone: zone), time > now.addingTimeInterval(-3600), i < temps.count else { continue }
            let chance = (chances.indices.contains(i) ? chances[i] as? Int : nil) ?? 0
            let code = (codes.indices.contains(i) ? codes[i] as? Int : nil) ?? 0
            result.append(Hour(time: time, temperature: temps[i], rainChance: chance, code: code))
        }
        return Array(result.prefix(8))
    }

    static func parseRain(_ minutely: [String: Any]?, zone: TimeZone) -> [(time: Date, mm: Double)] {
        guard let times = minutely?["time"] as? [String], let amounts = minutely?["precipitation"] as? [Any] else { return [] }
        return times.enumerated().compactMap { i, text in
            guard let time = parseTime(text, zone: zone), amounts.indices.contains(i) else { return nil }
            let mm = (amounts[i] as? Double) ?? Double(amounts[i] as? Int ?? 0)
            return (time, mm)
        }
    }

    /// Minutes until rain starts within the next `lead` minutes, if it is not raining now.
    static func minutesUntilRain(_ slots: [(time: Date, mm: Double)], now: Date = Date(), lead: Int) -> Int? {
        let threshold = 0.1
        let current = slots.last { $0.time <= now }
        if let current, current.mm >= threshold { return nil }       // already raining
        guard let first = slots.first(where: { $0.time > now && $0.mm >= threshold }) else { return nil }
        let minutes = Int(first.time.timeIntervalSince(now) / 60)
        return minutes <= lead ? max(1, minutes) : nil
    }

    /// Pops up "Rain in about 30 minutes" once per shower (at most every 3 hours).
    func checkRain(now: Date = Date()) {
        let library = UserLibrary.shared
        guard library.rainAlerts, AppSettings.shared.islandEnabled,
              let minutes = Self.minutesUntilRain(rainSlots, now: now, lead: library.rainLeadMinutes) else { return }
        if let last = lastRainAlert, now.timeIntervalSince(last) < 3 * 3600 { return }
        lastRainAlert = now
        IslandController.shared.showPeek(.rain(minutes: minutes))
    }

    /// Calls back on the main queue.
    private static func fetchJSON(_ url: URL, completion: @escaping ([String: Any]?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { completion(json) }
        }.resume()
    }

    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
