import Foundation
import CoreLocation

actor WeatherService {
    static let shared = WeatherService()

    private let weatherURL = "https://api.open-meteo.com/v1/forecast"
    private let marineURL = "https://marine-api.open-meteo.com/v1/marine"

    private var cache: [String: CacheEntry] = [:]
    private let cacheExpiration: TimeInterval = 3600 // 1 saat

    // MARK: - Public API

    func fetchWeather(for coordinate: CLLocationCoordinate2D, date: Date = Date()) async throws -> WeatherData {
        let cacheKey = cacheKey(for: coordinate, date: date)

        // Cache kontrolü
        if let cached = cache[cacheKey], !cached.isExpired {
            return cached.data
        }

        // Paralel API çağrıları
        async let weatherTask = fetchWeatherAPI(coordinate)
        async let marineTask = fetchMarineAPI(coordinate)

        let weather = try await weatherTask
        let marine = try? await marineTask // Marine opsiyonel

        // Hedef saate en yakın veriyi bul
        let weatherValues = weather.valuesForDate(date)
        let marineValues = marine?.valuesForDate(date)

        // Fetch hesaplama (kıyıya yakınsa dalga düşür)
        let fetchDistance = FetchCalculator.shared.calculateFetch(
            lat: coordinate.latitude,
            lng: coordinate.longitude,
            windDirection: weatherValues.windDirection
        )

        let adjustedWaveHeight = FetchCalculator.shared.adjustWaveHeight(
            marineValues?.waveHeight ?? 0,
            fetchKm: fetchDistance
        )

        let data = WeatherData(
            windSpeed: weatherValues.windSpeed,
            windDirection: weatherValues.windDirection,
            windGusts: weatherValues.windGusts,
            temperature: weatherValues.temperature,
            waveHeight: adjustedWaveHeight,
            waveDirection: marineValues?.waveDirection ?? 0,
            wavePeriod: marineValues?.wavePeriod ?? 0,
            fetchDistance: fetchDistance
        )

        // Cache'e kaydet
        cache[cacheKey] = CacheEntry(data: data)

        return data
    }

    // MARK: - API Calls

    private func fetchWeatherAPI(_ coordinate: CLLocationCoordinate2D) async throws -> WeatherAPIResponse {
        var components = URLComponents(string: weatherURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        return try await fetchWithRetry(url: components.url!, type: WeatherAPIResponse.self)
    }

    private func fetchMarineAPI(_ coordinate: CLLocationCoordinate2D) async throws -> MarineAPIResponse {
        var components = URLComponents(string: marineURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "hourly", value: "wave_height,wave_direction,wave_period"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        return try await fetchWithRetry(url: components.url!, type: MarineAPIResponse.self)
    }

    // Exponential backoff retry
    private func fetchWithRetry<T: Decodable>(url: URL, type: T.Type, maxRetries: Int = 3) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    throw WeatherError.invalidResponse
                }

                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                lastError = error
                let delay = pow(2.0, Double(attempt)) // 1s, 2s, 4s
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? WeatherError.unknown
    }

    // MARK: - Cache

    private func cacheKey(for coordinate: CLLocationCoordinate2D, date: Date) -> String {
        // 0.01 derece grid (yaklaşık 1km) + saat bilgisi
        let lat = (coordinate.latitude * 100).rounded() / 100
        let lng = (coordinate.longitude * 100).rounded() / 100
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let day = calendar.component(.day, from: date)
        return "\(lat),\(lng),\(day),\(hour)"
    }

    func clearCache() {
        cache.removeAll()
    }
}

// MARK: - Data Types

struct WeatherData {
    let windSpeed: Double       // km/h
    let windDirection: Double   // degrees
    let windGusts: Double       // km/h
    let temperature: Double     // celsius
    let waveHeight: Double      // meters (fetch-adjusted)
    let waveDirection: Double   // degrees
    let wavePeriod: Double      // seconds
    let fetchDistance: Double   // km

    var riskLevel: RiskLevel {
        RiskLevel.calculate(windSpeed: windSpeed, waveHeight: waveHeight)
    }

    var windDescription: String {
        let directions = ["K", "KD", "D", "GD", "G", "GB", "B", "KB"]
        let index = Int((windDirection + 22.5) / 45) % 8
        return "\(Int(windSpeed)) km/h \(directions[index])"
    }

    var waveDescription: String {
        if waveHeight < 0.1 {
            return "Sakin"
        }
        return String(format: "%.1f m", waveHeight)
    }
}

private struct CacheEntry {
    let data: WeatherData
    let timestamp: Date

    init(data: WeatherData) {
        self.data = data
        self.timestamp = Date()
    }

    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > 3600
    }
}

// MARK: - Hourly Value Types

struct HourlyWeatherValues {
    let windSpeed: Double
    let windDirection: Double
    let windGusts: Double
    let temperature: Double
}

struct HourlyMarineValues {
    let waveHeight: Double
    let waveDirection: Double
    let wavePeriod: Double
}

// MARK: - API Response Types

private struct WeatherAPIResponse: Decodable {
    let hourly: HourlyWeather

    struct HourlyWeather: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let wind_speed_10m: [Double]
        let wind_direction_10m: [Double]
        let wind_gusts_10m: [Double]
    }

    func valuesForDate(_ date: Date) -> HourlyWeatherValues {
        let index = closestIndex(times: hourly.time, to: date)
        return HourlyWeatherValues(
            windSpeed: hourly.wind_speed_10m[safe: index] ?? 0,
            windDirection: hourly.wind_direction_10m[safe: index] ?? 0,
            windGusts: hourly.wind_gusts_10m[safe: index] ?? 0,
            temperature: hourly.temperature_2m[safe: index] ?? 0
        )
    }
}

private struct MarineAPIResponse: Decodable {
    let hourly: HourlyMarine

    struct HourlyMarine: Decodable {
        let time: [String]
        let wave_height: [Double?]
        let wave_direction: [Double?]
        let wave_period: [Double?]
    }

    func valuesForDate(_ date: Date) -> HourlyMarineValues {
        let index = closestIndex(times: hourly.time, to: date)
        return HourlyMarineValues(
            waveHeight: hourly.wave_height[safe: index].flatMap { $0 } ?? 0,
            waveDirection: hourly.wave_direction[safe: index].flatMap { $0 } ?? 0,
            wavePeriod: hourly.wave_period[safe: index].flatMap { $0 } ?? 0
        )
    }
}

// MARK: - Helpers

/// ISO 8601 zaman dizisinden hedef tarihe en yakin index'i bul
private func closestIndex(times: [String], to date: Date) -> Int {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

    let calendar = Calendar.current
    let targetHour = calendar.component(.hour, from: date)
    let targetDay = calendar.ordinality(of: .day, in: .year, for: date) ?? 0

    var bestIndex = 0
    var bestDiff = Int.max

    for (i, timeStr) in times.enumerated() {
        // Format: "2024-01-15T14:00"
        if let parsed = formatter.date(from: timeStr + ":00Z") ?? parseISO(timeStr) {
            let h = calendar.component(.hour, from: parsed)
            let d = calendar.ordinality(of: .day, in: .year, for: parsed) ?? 0
            let diff = abs((d - targetDay) * 24 + (h - targetHour))
            if diff < bestDiff {
                bestDiff = diff
                bestIndex = i
            }
        }
    }
    return bestIndex
}

private func parseISO(_ str: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    formatter.timeZone = TimeZone.current
    return formatter.date(from: str)
}

// Safe array subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum WeatherError: Error {
    case invalidResponse
    case decodingError
    case unknown
}
