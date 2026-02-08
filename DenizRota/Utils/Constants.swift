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

// MARK: - Cove / Anchorage Data (Koy / Demirleme Noktalari)

/// Korunaklı koy seviyesi
enum ShelterLevel: String, CaseIterable {
    case excellent = "Mükemmel"
    case good = "İyi"
    case moderate = "Orta"
    case poor = "Zayıf"
}

/// Koy / demirleme noktası
struct Cove: Identifiable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
    let mouthDirection: Double // Koyun denize açıldığı yön (derece, kuzey=0)

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Koordinat bazli sabit ID (annotation eslestirme icin)
    var stableId: String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }
}

/// Datça-Marmaris-Bozburun bölgesi bilinen koy ve demirleme noktaları
enum CoveData {
    // MARK: - Datça Yarımadası Kuzey (Hisarönü/Gökova)
    static let palamutbuku = Cove(name: "Palamutbükü", latitude: 36.72, longitude: 27.56, mouthDirection: 0)       // kuzeye bakıyor
    static let hayitbuku = Cove(name: "Hayıtbükü", latitude: 36.73, longitude: 27.52, mouthDirection: 350)         // kuzeye bakıyor
    static let domuzCiftligi = Cove(name: "Domuz Çiftliği Koyu", latitude: 36.73, longitude: 27.60, mouthDirection: 10) // kuzeye
    static let kurucabuk = Cove(name: "Kurucabük", latitude: 36.74, longitude: 27.64, mouthDirection: 350)         // kuzeye
    static let gebekum = Cove(name: "Gebekum", latitude: 36.73, longitude: 27.68, mouthDirection: 0)               // kuzeye
    static let kargi = Cove(name: "Kargı Koyu", latitude: 36.74, longitude: 27.72, mouthDirection: 340)            // kuzeybatıya
    static let bencik = Cove(name: "Bencik Koyu", latitude: 36.76, longitude: 28.05, mouthDirection: 0)            // kuzeye

    // MARK: - Datça Yarımadası Güney (Akdeniz tarafı)
    static let ovabuku = Cove(name: "Ovabükü", latitude: 36.70, longitude: 27.55, mouthDirection: 180)             // güneye bakıyor
    static let kizilbuk = Cove(name: "Kızılbük", latitude: 36.70, longitude: 27.58, mouthDirection: 190)           // güneybatıya
    static let mesudiye = Cove(name: "Mesudiye (Perili)", latitude: 36.70, longitude: 27.48, mouthDirection: 200)   // güneybatıya
    static let datcaLiman = Cove(name: "Datça Limanı", latitude: 36.73, longitude: 27.69, mouthDirection: 180)     // güneye
    static let aktur = Cove(name: "Aktur Koyu", latitude: 36.70, longitude: 27.60, mouthDirection: 170)            // güneye

    // MARK: - Knidos / Yarımada Ucu
    static let knidos = Cove(name: "Knidos Limanı", latitude: 36.69, longitude: 27.38, mouthDirection: 270)        // batıya bakıyor
    static let knidosKuzey = Cove(name: "Knidos Kuzey Koyu", latitude: 36.69, longitude: 27.37, mouthDirection: 340) // kuzeybatıya

    // MARK: - Hisarönü Körfezi
    static let orhaniye = Cove(name: "Orhaniye Koyu", latitude: 36.78, longitude: 28.09, mouthDirection: 230)      // güneybatıya
    static let selimiye = Cove(name: "Selimiye", latitude: 36.72, longitude: 28.10, mouthDirection: 180)           // güneye
    static let bozukkale = Cove(name: "Bozukkale", latitude: 36.66, longitude: 28.08, mouthDirection: 180)        // güneye
    static let sogutKoyu = Cove(name: "Söğüt Koyu", latitude: 36.73, longitude: 28.12, mouthDirection: 200)       // güneybatıya

    // MARK: - Bozburun Yarımadası
    static let bozburunLiman = Cove(name: "Bozburun Limanı", latitude: 36.67, longitude: 28.05, mouthDirection: 200) // güneybatıya
    static let serçeLiman = Cove(name: "Serçe Limanı", latitude: 36.56, longitude: 28.08, mouthDirection: 180)     // güneye
    static let taslica = Cove(name: "Taşlıca Koyu", latitude: 36.60, longitude: 28.06, mouthDirection: 220)       // güneybatıya
    static let kizilkuyruk = Cove(name: "Kızılkuyruk Koyu", latitude: 36.58, longitude: 28.04, mouthDirection: 200) // güneybatıya

    // MARK: - Marmaris Bölgesi
    static let marmarisLiman = Cove(name: "Marmaris Limanı", latitude: 36.85, longitude: 28.27, mouthDirection: 250) // batıya
    static let icmeler = Cove(name: "İçmeler", latitude: 36.83, longitude: 28.23, mouthDirection: 260)              // batıya
    static let turunç = Cove(name: "Turunç", latitude: 36.79, longitude: 28.22, mouthDirection: 220)               // güneybatıya
    static let kumlubuk = Cove(name: "Kumlubük", latitude: 36.78, longitude: 28.20, mouthDirection: 210)           // güneybatıya
    static let cennetAdasi = Cove(name: "Cennet Adası", latitude: 36.82, longitude: 28.25, mouthDirection: 240)    // güneybatıya
    static let ciftlik = Cove(name: "Çiftlik Koyu", latitude: 36.77, longitude: 28.17, mouthDirection: 200)        // güneybatıya

    // MARK: - Gökova Körfezi
    static let englishHarbour = Cove(name: "İngiliz Limanı", latitude: 36.93, longitude: 28.08, mouthDirection: 180) // güneye
    static let longoz = Cove(name: "Longoz", latitude: 36.84, longitude: 28.13, mouthDirection: 200)                // güneybatıya
    static let akcapinar = Cove(name: "Akçapınar", latitude: 36.95, longitude: 27.95, mouthDirection: 180)          // güneye

    static let all: [Cove] = [
        // Datça Kuzey
        palamutbuku, hayitbuku, domuzCiftligi, kurucabuk, gebekum, kargi, bencik,
        // Datça Güney
        ovabuku, kizilbuk, mesudiye, datcaLiman, aktur,
        // Knidos
        knidos, knidosKuzey,
        // Hisarönü
        orhaniye, selimiye, bozukkale, sogutKoyu,
        // Bozburun
        bozburunLiman, serçeLiman, taslica, kizilkuyruk,
        // Marmaris
        marmarisLiman, icmeler, turunç, kumlubuk, cennetAdasi, ciftlik,
        // Gökova
        englishHarbour, longoz, akcapinar
    ]
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

// MARK: - Shelter Level UI
extension ShelterLevel {
    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .moderate: return .orange
        case .poor: return .red
        }
    }

    var icon: String {
        switch self {
        case .excellent: return "checkmark.shield.fill"
        case .good: return "shield.fill"
        case .moderate: return "exclamationmark.shield.fill"
        case .poor: return "xmark.shield.fill"
        }
    }

    var shortDescription: String {
        switch self {
        case .excellent: return "Tam korunaklı"
        case .good: return "İyi korunaklı"
        case .moderate: return "Kısmen korunaklı"
        case .poor: return "Korunaksız"
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
