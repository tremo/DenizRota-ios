import Foundation
import CoreLocation

actor WeatherService {
    static let shared = WeatherService()

    private let weatherURL = "https://api.open-meteo.com/v1/forecast"
    private let marineURL = "https://marine-api.open-meteo.com/v1/marine"

    private var cache: [String: CacheEntry] = [:]
    private var windCache: [String: WindCacheEntry] = [:]
    private var weatherResponseCache: [String: (response: WeatherAPIResponse, timestamp: Date)] = [:]
    private var marineResponseCache: [String: (response: MarineAPIResponse, timestamp: Date)] = [:]
    private let cacheExpiration: TimeInterval = 3600 // 1 saat

    // MARK: - Public API

    /// Sadece ruzgar verisi (Marine API cagrilmaz - wind grid icin optimize)
    func fetchWindOnly(for coordinate: CLLocationCoordinate2D, date: Date = Date()) async throws -> WindOnlyData {
        let key = cacheKey(for: coordinate, date: date)

        // Tam hava durumu cache'inde varsa oradan al
        if let cached = cache[key], !cached.isExpired {
            return WindOnlyData(windSpeed: cached.data.windSpeed, windDirection: cached.data.windDirection, windGusts: cached.data.windGusts)
        }

        // Ruzgar cache'inde varsa oradan al
        if let cached = windCache[key], !cached.isExpired {
            return cached.data
        }

        // Raw response cache'ten al veya API cagir (sadece Weather, Marine yok)
        let weather = try await getCachedOrFetchWeatherAPI(coordinate)
        let values = weather.valuesForDate(date)

        let data = WindOnlyData(windSpeed: values.windSpeed, windDirection: values.windDirection, windGusts: values.windGusts)
        windCache[key] = WindCacheEntry(data: data)
        return data
    }

    func fetchWeather(for coordinate: CLLocationCoordinate2D, date: Date = Date(), coastlinePoints: [(lng: Double, lat: Double)]? = nil) async throws -> WeatherData {
        let cacheKey = cacheKey(for: coordinate, date: date)

        // Cache kontrolü
        if let cached = cache[cacheKey], !cached.isExpired {
            return cached.data
        }

        // Paralel API çağrıları (response cache ile)
        async let weatherTask = getCachedOrFetchWeatherAPI(coordinate)
        async let marineTask = getCachedOrFetchMarineAPI(coordinate)

        let weather = try await weatherTask
        let marine = try? await marineTask // Marine opsiyonel

        // Hedef saate en yakın veriyi bul
        let weatherValues = weather.valuesForDate(date)
        let marineValues = marine?.valuesForDate(date)

        // Fetch hesaplama ve dalga yüksekliği ayarlama
        let windSpeed = weatherValues.windSpeed
        let fetchDistance: Double
        let adjustedWaveHeight: Double

        if windSpeed < 5 {
            // Rüzgar çok düşükse fetch hesabı anlamsız (yön güvenilmez)
            // Swell baskın olduğu için toplam dalga yüksekliğini doğrudan kullan
            fetchDistance = 0
            adjustedWaveHeight = marineValues?.waveHeight ?? 0
        } else {
            fetchDistance = FetchCalculator.shared.calculateFetch(
                lat: coordinate.latitude,
                lng: coordinate.longitude,
                windDirection: weatherValues.windDirection,
                coastlinePoints: coastlinePoints
            )

            let swellHeight = marineValues?.swellWaveHeight ?? 0
            let windWaveHeight = marineValues?.windWaveHeight ?? 0

            if swellHeight > 0 || windWaveHeight > 0 {
                // Ayrı bileşenler mevcut: sadece rüzgar dalgasına fetch ayarı uygula, swell olduğu gibi
                let adjustedWindWave = FetchCalculator.shared.adjustWaveHeight(windWaveHeight, fetchKm: fetchDistance)
                // Toplam: sqrt(swell² + windWave²) — dalga enerjisi süperpozisyonu
                adjustedWaveHeight = sqrt(swellHeight * swellHeight + adjustedWindWave * adjustedWindWave)
            } else {
                // Eski API yanıtı (ayrı bileşen yok): toplam dalgaya fetch uygula (eski davranış)
                adjustedWaveHeight = FetchCalculator.shared.adjustWaveHeight(
                    marineValues?.waveHeight ?? 0,
                    fetchKm: fetchDistance
                )
            }
        }

        let data = WeatherData(
            windSpeed: windSpeed,
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

    // MARK: - Response Cache Layer
    // Raw API response'lari koordinat bazinda cache'ler (saat bilgisi yok).
    // API 72 saatlik veri dondurur - saat degistiginde tekrar fetch gerekmez.

    private func getCachedOrFetchWeatherAPI(_ coordinate: CLLocationCoordinate2D) async throws -> WeatherAPIResponse {
        let key = coordCacheKey(for: coordinate)
        if let cached = weatherResponseCache[key],
           Date().timeIntervalSince(cached.timestamp) < cacheExpiration {
            return cached.response
        }
        let response = try await fetchWeatherAPI(coordinate)
        weatherResponseCache[key] = (response: response, timestamp: Date())
        return response
    }

    private func getCachedOrFetchMarineAPI(_ coordinate: CLLocationCoordinate2D) async throws -> MarineAPIResponse {
        let key = coordCacheKey(for: coordinate)
        if let cached = marineResponseCache[key],
           Date().timeIntervalSince(cached.timestamp) < cacheExpiration {
            return cached.response
        }
        let response = try await fetchMarineAPI(coordinate)
        marineResponseCache[key] = (response: response, timestamp: Date())
        return response
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
            URLQueryItem(name: "hourly", value: "wave_height,wave_direction,wave_period,swell_wave_height,wind_wave_height"),
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

    /// Koordinat + saat bazli cache key (islenmis veri icin)
    private func cacheKey(for coordinate: CLLocationCoordinate2D, date: Date) -> String {
        // 0.001 derece grid (~111m) + tarih/saat bilgisi
        let lat = (coordinate.latitude * 1000).rounded() / 1000
        let lng = (coordinate.longitude * 1000).rounded() / 1000
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let hour = calendar.component(.hour, from: date)
        return "\(lat),\(lng),\(year)-\(month)-\(day),\(hour)"
    }

    /// Koordinat bazli cache key (raw response icin, saat yok)
    private func coordCacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude * 1000).rounded() / 1000
        let lng = (coordinate.longitude * 1000).rounded() / 1000
        return "\(lat),\(lng)"
    }

    func clearCache() {
        cache.removeAll()
        windCache.removeAll()
        weatherResponseCache.removeAll()
        marineResponseCache.removeAll()
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

// MARK: - Wind Only Data (Marine API olmadan)

struct WindOnlyData {
    let windSpeed: Double       // km/h
    let windDirection: Double   // degrees
    let windGusts: Double       // km/h
}

private struct WindCacheEntry {
    let data: WindOnlyData
    let timestamp: Date

    init(data: WindOnlyData) {
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
    let waveHeight: Double      // Toplam dalga yüksekliği (swell + wind)
    let waveDirection: Double
    let wavePeriod: Double
    let swellWaveHeight: Double // Uzak fırtınadan gelen swell
    let windWaveHeight: Double  // Yerel rüzgarın oluşturduğu dalga
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
        let swell_wave_height: [Double?]?  // Opsiyonel: eski cache/response'larda olmayabilir
        let wind_wave_height: [Double?]?   // Opsiyonel: eski cache/response'larda olmayabilir
    }

    func valuesForDate(_ date: Date) -> HourlyMarineValues {
        let index = closestIndex(times: hourly.time, to: date)
        let totalWave = hourly.wave_height[safe: index].flatMap { $0 } ?? 0
        let swellWave = hourly.swell_wave_height?[safe: index].flatMap { $0 } ?? 0
        let windWave = hourly.wind_wave_height?[safe: index].flatMap { $0 } ?? 0

        return HourlyMarineValues(
            waveHeight: totalWave,
            waveDirection: hourly.wave_direction[safe: index].flatMap { $0 } ?? 0,
            wavePeriod: hourly.wave_period[safe: index].flatMap { $0 } ?? 0,
            swellWaveHeight: swellWave,
            windWaveHeight: windWave
        )
    }
}

// MARK: - Helpers

/// ISO 8601 zaman dizisinden hedef tarihe en yakin index'i bul
/// Open-Meteo timezone=auto ile yerel saat döndürür ("2024-01-15T14:00" formatında)
private func closestIndex(times: [String], to date: Date) -> Int {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    formatter.timeZone = TimeZone.current // API timezone=auto ile yerel saat döndürüyor

    let calendar = Calendar.current
    let targetHour = calendar.component(.hour, from: date)
    let targetDay = calendar.ordinality(of: .day, in: .year, for: date) ?? 0

    var bestIndex = 0
    var bestDiff = Int.max

    for (i, timeStr) in times.enumerated() {
        if let parsed = formatter.date(from: timeStr) {
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
