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

    /// Basitleştirilmiş kara kontrolü - Türkiye kıyıları için
    private func isPointOnLand(lat: Double, lng: Double) -> Bool {
        // Türkiye ana kara sınırları (yaklaşık)
        let turkeyBounds = (
            minLat: 35.8,
            maxLat: 42.1,
            minLng: 25.6,
            maxLng: 44.8
        )

        // Türkiye sınırları dışındaysa deniz say
        guard lat >= turkeyBounds.minLat && lat <= turkeyBounds.maxLat &&
              lng >= turkeyBounds.minLng && lng <= turkeyBounds.maxLng else {
            return false
        }

        // Deniz alanları (Türkiye etrafındaki denizler)
        let seaAreas: [(name: String, bounds: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double))] = [
            // Ege Denizi
            ("Ege", (minLat: 35.5, maxLat: 40.5, minLng: 23.0, maxLng: 27.5)),
            // Akdeniz
            ("Akdeniz", (minLat: 35.5, maxLat: 37.0, minLng: 27.5, maxLng: 36.5)),
            // Marmara Denizi
            ("Marmara", (minLat: 40.3, maxLat: 41.1, minLng: 26.5, maxLng: 29.9)),
            // Karadeniz (güney kıyısı)
            ("Karadeniz", (minLat: 41.0, maxLat: 42.5, minLng: 27.5, maxLng: 42.0))
        ]

        // Deniz alanı içindeyse kara değil
        for area in seaAreas {
            let b = area.bounds
            if lat >= b.minLat && lat <= b.maxLat && lng >= b.minLng && lng <= b.maxLng {
                // Ama kıyı şeridinde olabilir - daha detaylı kontrol gerekir
                // Basit yaklaşım: kıyıya çok yakınsa (0.05°) kara say
                return isNearCoastline(lat: lat, lng: lng)
            }
        }

        // Deniz alanı dışında ve Türkiye içindeyse kara
        return true
    }

    /// Kıyı şeridine yakınlık kontrolü
    private func isNearCoastline(lat: Double, lng: Double) -> Bool {
        // Ana kıyı noktaları (basitleştirilmiş)
        let coastlinePoints: [(lat: Double, lng: Double)] = [
            // Kuzey Ege
            (40.0, 26.0), (39.5, 26.5), (39.0, 26.8), (38.5, 26.5),
            // Güney Ege
            (38.0, 26.8), (37.5, 27.0), (37.0, 27.4), (36.7, 28.0),
            // Akdeniz
            (36.5, 29.0), (36.2, 30.0), (36.5, 31.0), (36.8, 32.0),
            (36.5, 33.0), (36.2, 34.0), (36.5, 35.0), (36.8, 36.0)
        ]

        let threshold = 0.1 // ~11 km

        for point in coastlinePoints {
            let distance = sqrt(pow(lat - point.lat, 2) + pow(lng - point.lng, 2))
            if distance < threshold {
                return true
            }
        }

        return false
    }
}
