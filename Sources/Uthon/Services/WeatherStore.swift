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

    @Published private(set) var current: Current?
    /// The city's location, also used for prayer times.
    @Published private(set) var place: Place?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func start() {
        refresh()
        let t = Timer(timeInterval: 1800, repeats: true) { [weak self] _ in self?.refresh() }
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
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: AppSettings.shared.weatherFahrenheit ? "fahrenheit" : "celsius"),
        ]
        guard let url = comps?.url else { return }
        Self.fetchJSON(url) { [weak self] json in
            guard let now = json?["current"] as? [String: Any],
                  let temp = now["temperature_2m"] as? Double else { return }
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
