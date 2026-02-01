import Foundation
import CoreLocation

actor WeatherService {
    static let shared = WeatherService()

    private let weatherURL = "https://api.open-meteo.com/v1/forecast"
    private let marineURL = "https://marine-api.open-meteo.com/v1/marine"

    private var cache: [String: CacheEntry] = [:]
    private let cacheExpiration: TimeInterval = 3600 // 1 saat

    // MARK: - Public API

    func fetchWeather(for coordinate: CLLocationCoordinate2D) async throws -> WeatherData {
        let cacheKey = cacheKey(for: coordinate)

        // Cache kontrolü
        if let cached = cache[cacheKey], !cached.isExpired {
            return cached.data
        }

        // Paralel API çağrıları
        async let weatherTask = fetchWeatherAPI(coordinate)
        async let marineTask = fetchMarineAPI(coordinate)

        let weather = try await weatherTask
        let marine = try? await marineTask // Marine opsiyonel

        // Fetch hesaplama (kıyıya yakınsa dalga düşür)
        let fetchDistance = FetchCalculator.shared.calculateFetch(
            lat: coordinate.latitude,
            lng: coordinate.longitude,
            windDirection: weather.windDirection
        )

        let adjustedWaveHeight = FetchCalculator.shared.adjustWaveHeight(
            marine?.waveHeight ?? 0,
            fetchKm: fetchDistance
        )

        let data = WeatherData(
            windSpeed: weather.windSpeed,
            windDirection: weather.windDirection,
            windGusts: weather.windGusts,
            temperature: weather.temperature,
            waveHeight: adjustedWaveHeight,
            waveDirection: marine?.waveDirection ?? 0,
            wavePeriod: marine?.wavePeriod ?? 0,
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
            URLQueryItem(name: "current", value: "temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        return try await fetchWithRetry(url: components.url!, type: WeatherAPIResponse.self)
    }

    private func fetchMarineAPI(_ coordinate: CLLocationCoordinate2D) async throws -> MarineAPIResponse {
        var components = URLComponents(string: marineURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "wave_height,wave_direction,wave_period"),
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

    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        // 0.01 derece grid (yaklaşık 1km)
        let lat = (coordinate.latitude * 100).rounded() / 100
        let lng = (coordinate.longitude * 100).rounded() / 100
        return "\(lat),\(lng)"
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

// MARK: - API Response Types

private struct WeatherAPIResponse: Decodable {
    let current: CurrentWeather

    struct CurrentWeather: Decodable {
        let temperature_2m: Double
        let wind_speed_10m: Double
        let wind_direction_10m: Double
        let wind_gusts_10m: Double
    }

    var temperature: Double { current.temperature_2m }
    var windSpeed: Double { current.wind_speed_10m }
    var windDirection: Double { current.wind_direction_10m }
    var windGusts: Double { current.wind_gusts_10m }
}

private struct MarineAPIResponse: Decodable {
    let current: CurrentMarine

    struct CurrentMarine: Decodable {
        let wave_height: Double?
        let wave_direction: Double?
        let wave_period: Double?
    }

    var waveHeight: Double { current.wave_height ?? 0 }
    var waveDirection: Double { current.wave_direction ?? 0 }
    var wavePeriod: Double { current.wave_period ?? 0 }
}

enum WeatherError: Error {
    case invalidResponse
    case decodingError
    case unknown
}
