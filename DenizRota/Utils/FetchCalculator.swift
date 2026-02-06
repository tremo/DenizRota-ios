import Foundation
import CoreLocation

/// Kıyı fetch hesaplayıcısı
/// Fetch: Rüzgarın açık denizde kat ettiği mesafe. Kısa fetch = küçük dalgalar.
final class FetchCalculator {
    static let shared = FetchCalculator()

    // Fetch mesafesine göre dalga düşürme faktörleri
    private let fetchFactors: [(maxKm: Double, factor: Double)] = [
        (3, 0.1),    // < 3 km: çok kısa fetch - neredeyse düz
        (5, 0.2),    // 3-5 km: kısa fetch
        (10, 0.35),  // 5-10 km: orta-kısa fetch
        (20, 0.5),   // 10-20 km: orta fetch
        (50, 0.7),   // 20-50 km: uzun fetch
    ]

    private init() {}

    // MARK: - Public API

    /// Belirtilen noktadan rüzgar yönünde kıyıya olan mesafeyi hesaplar
    func calculateFetch(lat: Double, lng: Double, windDirection: Double) -> Double {
        // Rüzgarın geldiği yöne doğru ilerle (180° ters)
        let checkDirection = (windDirection + 180).truncatingRemainder(dividingBy: 360)
        let directionRad = checkDirection * .pi / 180

        var distance: Double = 0
        let stepKm: Double = 0.5 // 500m adımlar
        let maxDistance: Double = 100 // max 100km kontrol

        var currentLat = lat
        var currentLng = lng

        // Rüzgar yönünde ilerleyerek karaya çarpana kadar devam et
        while distance < maxDistance {
            // 0.5 km ≈ 0.0045 derece (latitude)
            let latStep = cos(directionRad) * 0.0045
            let lngStep = sin(directionRad) * 0.0045 / cos(currentLat * .pi / 180)

            currentLat += latStep
            currentLng += lngStep
            distance += stepKm

            if isPointOnLand(lat: currentLat, lng: currentLng) {
                return distance
            }
        }

        // Karaya çarpmadan 100km'yi geçti = açık deniz
        return maxDistance
    }

    /// Dalga yüksekliğini fetch mesafesine göre ayarla
    func adjustWaveHeight(_ waveHeight: Double, fetchKm: Double) -> Double {
        let factor = getWaveAdjustmentFactor(fetchKm: fetchKm)
        return waveHeight * factor
    }

    // MARK: - Private

    private func getWaveAdjustmentFactor(fetchKm: Double) -> Double {
        for (maxKm, factor) in fetchFactors {
            if fetchKm < maxKm {
                return factor
            }
        }
        return 1.0 // Açık deniz
    }

    /// Kara kontrolü - SeaAreas ve CoastlineData kullanarak
    private func isPointOnLand(lat: Double, lng: Double) -> Bool {
        // SeaAreas.isInSea() ile deniz alanı kontrolü (kod tekrarını önler)
        if SeaAreas.isInSea(lat: lat, lng: lng) {
            // Deniz alanı içinde ama kıyı şeridinde olabilir
            return isNearCoastline(lat: lat, lng: lng)
        }

        // Deniz alanı dışında - Türkiye sınırları içindeyse kara
        let turkeyBounds = (
            minLat: 35.8, maxLat: 42.1,
            minLng: 25.6, maxLng: 44.8
        )

        guard lat >= turkeyBounds.minLat && lat <= turkeyBounds.maxLat &&
              lng >= turkeyBounds.minLng && lng <= turkeyBounds.maxLng else {
            return false // Türkiye dışı = açık deniz
        }

        return true
    }

    /// Kıyı şeridine yakınlık kontrolü - CoastlineData'daki detaylı noktaları kullanır
    private func isNearCoastline(lat: Double, lng: Double) -> Bool {
        let threshold = 0.015 // ~1.5 km

        for point in CoastlineData.allPoints {
            let distance = sqrt(pow(lat - point.lat, 2) + pow(lng - point.lng, 2))
            if distance < threshold {
                return true
            }
        }

        return false
    }
}
