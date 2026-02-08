import Foundation
import CoreLocation
import MapKit

/// OpenStreetMap Overpass API servisi
/// Haritadaki gorunen bolgeye gore dinamik olarak koy/bay/demirleme verisi ceker
actor OverpassService {
    static let shared = OverpassService()

    private let overpassURL = "https://overpass-api.de/api/interpreter"

    // Cache: grid-aligned bbox key -> [Cove]
    private var cache: [String: (coves: [Cove], timestamp: Date)] = [:]
    private let cacheExpiration: TimeInterval = 3600 // 1 saat

    // MARK: - Public API

    /// Belirli bir harita bolgesindeki koylari Overpass API'den cek
    /// Region cok buyukse (zoom out) bos dondurur
    func fetchCoves(region: MKCoordinateRegion) async throws -> [Cove] {
        // Zoom out fazlaysa sorgu yapma (performans)
        guard region.span.latitudeDelta < 2.0 && region.span.longitudeDelta < 2.0 else {
            return []
        }

        let bbox = gridAlignedBBox(from: region)
        let cacheKey = String(format: "%.1f,%.1f,%.1f,%.1f", bbox.south, bbox.west, bbox.north, bbox.east)

        // Cache kontrolu
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheExpiration {
            return cached.coves
        }

        let query = buildQuery(bbox: bbox)
        let coves = try await executeQuery(query)

        // Cache'e kaydet
        cache[cacheKey] = (coves: coves, timestamp: Date())

        return coves
    }

    // MARK: - Bounding Box

    private struct BBox {
        let south: Double
        let west: Double
        let north: Double
        let east: Double
    }

    /// Grid-aligned bounding box hesapla (cache reuse icin 0.2 derece grid)
    private func gridAlignedBBox(from region: MKCoordinateRegion) -> BBox {
        let gridSize = 0.2
        let south = floor((region.center.latitude - region.span.latitudeDelta / 2) / gridSize) * gridSize
        let north = ceil((region.center.latitude + region.span.latitudeDelta / 2) / gridSize) * gridSize
        let west = floor((region.center.longitude - region.span.longitudeDelta / 2) / gridSize) * gridSize
        let east = ceil((region.center.longitude + region.span.longitudeDelta / 2) / gridSize) * gridSize
        return BBox(south: south, west: west, north: north, east: east)
    }

    // MARK: - Query Building

    private func buildQuery(bbox: BBox) -> String {
        let bboxStr = String(format: "%.4f,%.4f,%.4f,%.4f", bbox.south, bbox.west, bbox.north, bbox.east)
        return """
        [out:json][timeout:15];
        (
          node["natural"="bay"](\(bboxStr));
          way["natural"="bay"](\(bboxStr));
          node["seamark:type"="anchorage"](\(bboxStr));
          way["seamark:type"="anchorage"](\(bboxStr));
          node["seamark:type"="harbour"](\(bboxStr));
          way["seamark:type"="harbour"](\(bboxStr));
          node["leisure"="marina"](\(bboxStr));
          way["leisure"="marina"](\(bboxStr));
          node["seamark:type"="mooring"](\(bboxStr));
        );
        out body geom;
        """
    }

    // MARK: - API Execution

    private func executeQuery(_ query: String) async throws -> [Cove] {
        guard let url = URL(string: overpassURL) else {
            throw OverpassError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20

        // URL-encode the query properly
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "data", value: query)]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OverpassError.apiError
        }

        return try parseResponse(data)
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> [Cove] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else {
            throw OverpassError.parseError
        }

        var coves: [Cove] = []
        var seenCoordinates = Set<String>() // Tekrarlari onle

        for element in elements {
            guard let type = element["type"] as? String else { continue }

            let tags = element["tags"] as? [String: String] ?? [:]
            let name = tags["name"] ?? tags["seamark:name"] ?? tags["name:tr"] ?? tags["name:en"]

            var latitude: Double?
            var longitude: Double?
            var wayNodes: [(lat: Double, lng: Double)] = []

            if type == "node" {
                latitude = element["lat"] as? Double
                longitude = element["lon"] as? Double
            } else if type == "way" {
                // out body geom ile way'lerin geometrisi gelir
                if let geometry = element["geometry"] as? [[String: Any]] {
                    for node in geometry {
                        if let lat = node["lat"] as? Double, let lng = node["lon"] as? Double {
                            wayNodes.append((lat: lat, lng: lng))
                        }
                    }
                }

                // Merkez noktayi geometriden hesapla
                if !wayNodes.isEmpty {
                    latitude = wayNodes.map(\.lat).reduce(0, +) / Double(wayNodes.count)
                    longitude = wayNodes.map(\.lng).reduce(0, +) / Double(wayNodes.count)
                }
            }

            guard let lat = latitude, let lng = longitude else { continue }

            // Tekrar kontrolu (yakin koordinatlar)
            let coordKey = String(format: "%.4f,%.4f", lat, lng)
            guard !seenCoordinates.contains(coordKey) else { continue }
            seenCoordinates.insert(coordKey)

            // Isim olustur
            let coveName: String
            if let name = name, !name.isEmpty {
                coveName = name
            } else {
                coveName = String(format: "Koy (%.3f, %.3f)", lat, lng)
            }

            // Agiz yonunu hesapla
            let mouthDirection: Double
            if wayNodes.count >= 3 {
                mouthDirection = calculateMouthDirection(
                    center: (lat: lat, lng: lng),
                    wayNodes: wayNodes
                )
            } else {
                mouthDirection = estimateMouthDirection(lat: lat, lng: lng)
            }

            coves.append(Cove(
                name: coveName,
                latitude: lat,
                longitude: lng,
                mouthDirection: mouthDirection
            ))
        }

        return coves
    }

    // MARK: - Mouth Direction Calculation

    /// Way geometrisinden koyun agiz yonunu hesapla
    /// Open way (ilk != son nokta): first-last arasi aciklik agiz
    /// Closed way: en uzun kenar agiz
    private func calculateMouthDirection(
        center: (lat: Double, lng: Double),
        wayNodes: [(lat: Double, lng: Double)]
    ) -> Double {
        let first = wayNodes.first!
        let last = wayNodes.last!

        // Acik way mi kontrol et (ilk ve son nokta farkli mi)
        let isOpen = coordDistance(from: first, to: last) > 0.0001 // ~11m

        if isOpen {
            // Agiz, ilk ve son nokta arasinda
            let mouthMid = (lat: (first.lat + last.lat) / 2, lng: (first.lng + last.lng) / 2)
            return bearing(from: center, to: mouthMid)
        } else {
            // Kapali way - en uzun kenari bul (agiz orada)
            var maxDist = 0.0
            var maxMid = center

            for i in 0..<wayNodes.count - 1 {
                let d = coordDistance(from: wayNodes[i], to: wayNodes[i + 1])
                if d > maxDist {
                    maxDist = d
                    maxMid = (
                        lat: (wayNodes[i].lat + wayNodes[i + 1].lat) / 2,
                        lng: (wayNodes[i].lng + wayNodes[i + 1].lng) / 2
                    )
                }
            }

            return bearing(from: center, to: maxMid)
        }
    }

    /// Node (nokta) verisi icin agiz yonunu tahmin et
    /// 8 yone bakarak en yakin deniz alanini bul
    private func estimateMouthDirection(lat: Double, lng: Double) -> Double {
        let directions: [(angle: Double, dLat: Double, dLng: Double)] = [
            (0, 0.01, 0),        // K
            (45, 0.01, 0.01),    // KD
            (90, 0, 0.01),       // D
            (135, -0.01, 0.01),  // GD
            (180, -0.01, 0),     // G
            (225, -0.01, -0.01), // GB
            (270, 0, -0.01),     // B
            (315, 0.01, -0.01)   // KB
        ]

        // Hangi yon denize aciliyor kontrol et
        for step in 1...10 {
            let scale = Double(step)
            for dir in directions {
                let checkLat = lat + dir.dLat * scale
                let checkLng = lng + dir.dLng * scale
                if SeaAreas.isInSea(lat: checkLat, lng: checkLng) {
                    return dir.angle
                }
            }
        }

        // Varsayilan: guney (Turkiye kiyilarinda cogu koy guneye bakar)
        return 180
    }

    // MARK: - Geometry Helpers

    private func coordDistance(from a: (lat: Double, lng: Double), to b: (lat: Double, lng: Double)) -> Double {
        let dLat = a.lat - b.lat
        let dLng = a.lng - b.lng
        return sqrt(dLat * dLat + dLng * dLng)
    }

    private func bearing(from a: (lat: Double, lng: Double), to b: (lat: Double, lng: Double)) -> Double {
        let dLng = b.lng - a.lng
        let dLat = b.lat - a.lat
        var angle = atan2(dLng, dLat) * 180.0 / .pi
        if angle < 0 { angle += 360 }
        return angle
    }
}

// MARK: - Errors

enum OverpassError: Error, LocalizedError {
    case invalidURL
    case apiError
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Gecersiz API URL"
        case .apiError: return "Overpass API hatasi"
        case .parseError: return "Veri ayristirma hatasi"
        }
    }
}
