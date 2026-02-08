import Foundation
import CoreLocation

/// Rüzgar sığınağı analiz servisi
/// Koy ağız yönü ile rüzgar yönü arasındaki açı farkına göre korunma seviyesi hesaplar
struct ShelterAnalyzer {
    static let shared = ShelterAnalyzer()

    /// Bir koyun mevcut rüzgar koşullarına göre korunma seviyesini hesapla
    /// - Parameters:
    ///   - cove: Analiz edilecek koy
    ///   - windDirection: Rüzgarın geldiği yön (derece, kuzey=0)
    ///   - windSpeed: Rüzgar hızı (km/h)
    /// - Returns: Korunma seviyesi
    func analyzeShelter(cove: Cove, windDirection: Double, windSpeed: Double) -> ShelterLevel {
        // Rüzgar hızı çok düşükse her yer uygun
        if windSpeed < 5 {
            return .excellent
        }

        let angleDiff = angleDifference(from: windDirection, to: cove.mouthDirection)

        // angleDiff: rüzgar yönü ile koy ağız yönü arasındaki açı farkı
        // Rüzgar koyun arkasından geliyorsa (ağız yönünün tersi) = excellent
        // Rüzgar ağızdan giriyorsa = poor
        if angleDiff >= 150 && angleDiff <= 210 {
            return .excellent
        } else if (angleDiff >= 90 && angleDiff < 150) || (angleDiff > 210 && angleDiff <= 270) {
            return .good
        } else if (angleDiff >= 45 && angleDiff < 90) || (angleDiff > 270 && angleDiff <= 315) {
            return .moderate
        } else {
            return .poor
        }
    }

    /// Verilen koylari analiz edip sonuclari dondur (shelter seviyesine gore sirali)
    func analyzeCoves(_ coves: [Cove], windDirection: Double, windSpeed: Double) -> [CoveShelterResult] {
        coves.map { cove in
            let level = analyzeShelter(cove: cove, windDirection: windDirection, windSpeed: windSpeed)
            return CoveShelterResult(cove: cove, shelterLevel: level, windDirection: windDirection, windSpeed: windSpeed)
        }
        .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// İki açı arasındaki farkı 0-360 aralığında hesapla
    private func angleDifference(from direction1: Double, to direction2: Double) -> Double {
        var diff = direction2 - direction1
        // Normalize to 0-360
        diff = diff.truncatingRemainder(dividingBy: 360)
        if diff < 0 { diff += 360 }
        return diff
    }
}

/// Koy korunma analiz sonucu
struct CoveShelterResult: Identifiable {
    let id = UUID()
    let cove: Cove
    let shelterLevel: ShelterLevel
    let windDirection: Double
    let windSpeed: Double

    /// Sıralama için (excellent=0, good=1, moderate=2, poor=3)
    var sortOrder: Int {
        switch shelterLevel {
        case .excellent: return 0
        case .good: return 1
        case .moderate: return 2
        case .poor: return 3
        }
    }
}
