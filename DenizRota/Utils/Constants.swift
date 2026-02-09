import Foundation
import CoreLocation

// MARK: - App Constants
enum AppConstants {
    static let appName = "DenizRota"
    static let appVersion = "1.0.0"

    // Cache durations
    static let weatherCacheExpiration: TimeInterval = 3600 // 1 saat
    static let weatherAutoRefreshInterval: TimeInterval = 900 // 15 dakika

    // Map defaults
    static let defaultMapCenter = CLLocationCoordinate2D(latitude: 38.5, longitude: 27.0) // Ege Denizi
    static let defaultMapZoom: Double = 9.0

    // GPS thresholds
    static let gpsAccuracyThreshold: Double = 50.0 // metre
    static let gpsJumpThreshold: Double = 1000.0 // metre
    static let distanceFilter: Double = 10.0 // metre
    static let waypointProximityThreshold: Double = 100.0 // metre

    // Risk thresholds
    static let windSpeedYellow: Double = 15.0 // km/h
    static let windSpeedRed: Double = 30.0 // km/h
    static let waveHeightYellow: Double = 0.5 // metre
    static let waveHeightRed: Double = 1.5 // metre

    // Default boat settings
    static let defaultBoatSpeed: Double = 15.0 // km/h
    static let defaultFuelRate: Double = 20.0 // L/saat
    static let defaultTankCapacity: Double = 200.0 // litre
    static let defaultFuelPrice: Double = 45.0 // TRY/L
}

// MARK: - API URLs
enum APIEndpoints {
    static let openMeteoWeather = "https://api.open-meteo.com/v1/forecast"
    static let openMeteoMarine = "https://marine-api.open-meteo.com/v1/marine"
}

// MARK: - Sea Areas (Deniz Alanlari)
struct SeaArea {
    let name: String
    let minLat: Double
    let maxLat: Double
    let minLng: Double
    let maxLng: Double

    func contains(lat: Double, lng: Double) -> Bool {
        return lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng
    }
}

enum SeaAreas {
    static let marmara = SeaArea(name: "Marmara", minLat: 40.3, maxLat: 41.1, minLng: 26.5, maxLng: 29.9)
    static let ege = SeaArea(name: "Ege", minLat: 36.5, maxLat: 40.3, minLng: 25.5, maxLng: 27.5)
    static let karadeniz = SeaArea(name: "Karadeniz", minLat: 41.0, maxLat: 43.0, minLng: 28.0, maxLng: 41.5)
    static let akdeniz = SeaArea(name: "Akdeniz", minLat: 35.5, maxLat: 37.0, minLng: 27.5, maxLng: 36.5)
    static let bogaz = SeaArea(name: "Boğaz", minLat: 40.9, maxLat: 41.3, minLng: 28.9, maxLng: 29.2)

    static let all: [SeaArea] = [marmara, ege, karadeniz, akdeniz, bogaz]

    static func isInSea(lat: Double, lng: Double) -> Bool {
        // Deniz alanında mı kontrol et
        let inSea = all.contains { $0.contains(lat: lat, lng: lng) }
        if !inSea { return false }

        // Kara hariç tutma alanlarında mı kontrol et
        for land in LandExclusions.all {
            if land.contains(lat: lat, lng: lng) {
                return false
            }
        }
        return true
    }
}

// MARK: - Land Exclusions (Kara Alanlari Hariç Tutma)
enum LandExclusions {
    // Trakya yarımadası (Marmara'nın kuzeyinde)
    static let trakya = SeaArea(name: "Trakya", minLat: 40.85, maxLat: 42.0, minLng: 26.5, maxLng: 28.0)
    // Anadolu (Marmara'nın güneyinde)
    static let anadolu = SeaArea(name: "Anadolu", minLat: 39.8, maxLat: 40.55, minLng: 28.5, maxLng: 30.5)
    // Kapıdağ Yarımadası
    static let kapidag = SeaArea(name: "Kapıdağ", minLat: 40.35, maxLat: 40.55, minLng: 27.8, maxLng: 28.3)

    static let all: [SeaArea] = [trakya, anadolu, kapidag]
}

// MARK: - Coastline Points (Kiyi Cizgisi Noktalari)
/// Türkiye kıyı çizgisi noktaları - Fetch hesaplama için kullanılır
/// Format: (longitude, latitude)
enum CoastlineData {

    // Datça Yarımadası - Kuzey Kıyı (Hisarönü/Gökova tarafı)
    static let datcaNorth: [(lng: Double, lat: Double)] = [
        (27.70, 36.75), (27.75, 36.76), (27.80, 36.77), (27.85, 36.78),
        (27.90, 36.78), (27.95, 36.77), (28.00, 36.76), (28.05, 36.75),
        (28.10, 36.74), (28.15, 36.73), (28.20, 36.72), (28.25, 36.72),
        (28.30, 36.71), (28.35, 36.71), (28.40, 36.71), (28.45, 36.71),
        (28.50, 36.72), (28.55, 36.72), (28.60, 36.73), (28.65, 36.74),
        (28.70, 36.75), (28.75, 36.76)
    ]

    // Datça Yarımadası - Güney Kıyı (Akdeniz tarafı)
    static let datcaSouth: [(lng: Double, lat: Double)] = [
        (27.70, 36.70), (27.75, 36.69), (27.80, 36.68), (27.85, 36.68),
        (27.90, 36.67), (27.95, 36.67), (28.00, 36.67), (28.05, 36.67),
        (28.10, 36.68), (28.15, 36.68), (28.20, 36.69), (28.25, 36.69),
        (28.30, 36.69), (28.35, 36.69), (28.40, 36.70), (28.45, 36.70),
        (28.50, 36.70), (28.55, 36.70), (28.60, 36.71)
    ]

    // Datça Yarımadası Ucu (Knidos)
    static let knidos: [(lng: Double, lat: Double)] = [
        (28.70, 36.69), (28.72, 36.68), (28.75, 36.68)
    ]

    // Bozburun Yarımadası
    static let bozburun: [(lng: Double, lat: Double)] = [
        (28.00, 36.65), (28.05, 36.62), (28.10, 36.60), (28.15, 36.58),
        (28.20, 36.60), (28.25, 36.62), (28.30, 36.65)
    ]

    // Marmaris - Bozburun arası
    static let marmaris: [(lng: Double, lat: Double)] = [
        (28.30, 36.78), (28.35, 36.80), (28.40, 36.82), (28.45, 36.84),
        (28.50, 36.85), (28.55, 36.84), (28.60, 36.82), (28.65, 36.80)
    ]

    // Symi Adası (Yunanistan) - Fetch hesabı için önemli
    static let symi: [(lng: Double, lat: Double)] = [
        (27.80, 36.60), (27.82, 36.58), (27.85, 36.56), (27.87, 36.55),
        (27.88, 36.58), (27.86, 36.61), (27.83, 36.62)
    ]

    // Kos Adası (kuzey kıyısı)
    static let kos: [(lng: Double, lat: Double)] = [
        (27.00, 36.85), (27.05, 36.87), (27.10, 36.88), (27.15, 36.88),
        (27.20, 36.87), (27.25, 36.86)
    ]

    // Bodrum Yarımadası
    static let bodrum: [(lng: Double, lat: Double)] = [
        (27.20, 37.05), (27.25, 37.03), (27.30, 37.00), (27.35, 36.98),
        (27.40, 36.95), (27.42, 36.92), (27.40, 36.88), (27.35, 36.85),
        (27.30, 36.83), (27.25, 36.82), (27.20, 36.83), (27.15, 36.85),
        (27.12, 36.88), (27.10, 36.92), (27.12, 36.96), (27.15, 37.00)
    ]

    // Gökova Körfezi Kuzey Kıyısı
    static let gokovaNorth: [(lng: Double, lat: Double)] = [
        (27.50, 37.05), (27.55, 37.06), (27.60, 37.07), (27.65, 37.08),
        (27.70, 37.08), (27.75, 37.08), (27.80, 37.07), (27.85, 37.06),
        (27.90, 37.04), (27.95, 37.02), (28.00, 37.00), (28.05, 36.98),
        (28.10, 36.95), (28.15, 36.92), (28.20, 36.88), (28.25, 36.85)
    ]

    // Fethiye - Ölüdeniz
    static let fethiye: [(lng: Double, lat: Double)] = [
        (29.00, 36.65), (29.05, 36.62), (29.10, 36.58), (29.12, 36.55),
        (29.10, 36.52), (29.05, 36.50), (29.00, 36.48)
    ]

    // Kaş - Kalkan
    static let kas: [(lng: Double, lat: Double)] = [
        (29.60, 36.20), (29.65, 36.18), (29.70, 36.15), (29.75, 36.12),
        (29.80, 36.10), (29.85, 36.12), (29.90, 36.15)
    ]

    // Meis Adası (Kastellorizo)
    static let meis: [(lng: Double, lat: Double)] = [
        (29.58, 36.14), (29.60, 36.12), (29.62, 36.10), (29.58, 36.08),
        (29.55, 36.10), (29.55, 36.13)
    ]

    // Tüm kıyı noktaları
    static var allPoints: [(lng: Double, lat: Double)] {
        var points: [(lng: Double, lat: Double)] = []
        points.append(contentsOf: datcaNorth)
        points.append(contentsOf: datcaSouth)
        points.append(contentsOf: knidos)
        points.append(contentsOf: bozburun)
        points.append(contentsOf: marmaris)
        points.append(contentsOf: symi)
        points.append(contentsOf: kos)
        points.append(contentsOf: bodrum)
        points.append(contentsOf: gokovaNorth)
        points.append(contentsOf: fethiye)
        points.append(contentsOf: kas)
        points.append(contentsOf: meis)
        return points
    }
}


// MARK: - Wind Direction Names
enum WindDirection {
    static let directions = ["K", "KD", "D", "GD", "G", "GB", "B", "KB"]

    static func name(for degrees: Double) -> String {
        let index = Int(round(degrees / 45.0)) % 8
        return directions[index]
    }

    static func fullName(for degrees: Double) -> String {
        let names = ["Kuzey", "Kuzeydoğu", "Doğu", "Güneydoğu", "Güney", "Güneybatı", "Batı", "Kuzeybatı"]
        let index = Int(round(degrees / 45.0)) % 8
        return names[index]
    }
}

// MARK: - Risk Level Colors
import SwiftUI

extension RiskLevel {
    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .unknown: return .gray
        }
    }

    var systemImageName: String {
        switch self {
        case .green: return "checkmark.circle.fill"
        case .yellow: return "exclamationmark.triangle.fill"
        case .red: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var displayName: String {
        switch self {
        case .green: return "Uygun"
        case .yellow: return "Dikkat"
        case .red: return "Tehlikeli"
        case .unknown: return "Bilinmiyor"
        }
    }
}


// MARK: - Boat Type Icons
extension BoatType {
    var iconName: String {
        switch self {
        case .motorlu: return "ferry"
        case .yelkenli: return "sailboat"
        case .gulet: return "ferry.fill"
        case .katamaran: return "water.waves"
        case .surat: return "bolt.fill"
        }
    }
}
