import Foundation
import CoreLocation
import MapKit

// MARK: - Overpass API Response Types

struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

struct OverpassElement: Decodable {
    let type: String
    let id: Int
    let lat: Double?
    let lon: Double?
    let nodes: [Int]?
    let tags: [String: String]?
}

// MARK: - Coastline Result

struct CoastlineResult: Sendable {
    let polylines: [[[Double]]]  // [[lat, lng], ...] dizileri - Sendable uyumlu
    let allPoints: [[Double]]    // [[lng, lat], ...] - FetchCalculator icin

    var coordinatePolylines: [[CLLocationCoordinate2D]] {
        polylines.map { line in
            line.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
        }
    }

    var coastlinePoints: [(lng: Double, lat: Double)] {
        allPoints.map { (lng: $0[0], lat: $0[1]) }
    }

    static let empty = CoastlineResult(polylines: [], allPoints: [])
}

// MARK: - Coastline Service

actor CoastlineService {
    static let shared = CoastlineService()

    private var cache: [String: CoastlineResult] = [:]

    /// Verilen bounding box icin Overpass API'den kiyi cizgisini cek
    func fetchCoastline(
        south: Double,
        west: Double,
        north: Double,
        east: Double
    ) async throws -> CoastlineResult {
        // Cache key: bbox'i 0.01 dereceye yuvarla (gereksiz tekrar istekleri onle)
        let s = (south * 100).rounded(.down) / 100
        let w = (west * 100).rounded(.down) / 100
        let n = (north * 100).rounded(.up) / 100
        let e = (east * 100).rounded(.up) / 100
        let cacheKey = "\(s),\(w),\(n),\(e)"

        if let cached = cache[cacheKey] {
            return cached
        }

        let query = """
        [out:json][timeout:30];
        way["natural"="coastline"](\(s),\(w),\(n),\(e));
        (._;>;);
        out body;
        """

        let urlString = "https://overpass-api.de/api/interpreter"
        guard let url = URL(string: urlString) else {
            throw CoastlineError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "data=\(query)".data(using: .utf8)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CoastlineError.invalidResponse
        }

        let overpass = try JSONDecoder().decode(OverpassResponse.self, from: data)

        // Node'lari id -> koordinat haritasina cevir
        var nodeMap: [Int: CLLocationCoordinate2D] = [:]
        for element in overpass.elements where element.type == "node" {
            guard let lat = element.lat, let lon = element.lon else { continue }
            nodeMap[element.id] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        // Way'leri polyline'lara cevir
        var polylines: [[[Double]]] = []
        var allPoints: [[Double]] = []
        var addedPoints = Set<String>()

        for element in overpass.elements where element.type == "way" {
            guard let nodeIds = element.nodes else { continue }
            var coords: [[Double]] = []
            for nodeId in nodeIds {
                if let coord = nodeMap[nodeId] {
                    coords.append([coord.latitude, coord.longitude])
                    // Tekrarsiz nokta listesi (FetchCalculator icin)
                    let pointKey = "\(coord.longitude),\(coord.latitude)"
                    if !addedPoints.contains(pointKey) {
                        addedPoints.insert(pointKey)
                        allPoints.append([coord.longitude, coord.latitude])
                    }
                }
            }
            if coords.count > 1 {
                polylines.append(coords)
            }
        }

        let result = CoastlineResult(polylines: polylines, allPoints: allPoints)
        cache[cacheKey] = result
        return result
    }

    /// Rota waypoint'lerinin bounding box'i icin kiyi cizgisi cek
    func fetchCoastlineForRoute(waypoints: [(lat: Double, lng: Double)]) async throws -> CoastlineResult {
        guard !waypoints.isEmpty else { return .empty }

        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLng = Double.greatestFiniteMagnitude
        var maxLng = -Double.greatestFiniteMagnitude

        for wp in waypoints {
            minLat = min(minLat, wp.lat)
            maxLat = max(maxLat, wp.lat)
            minLng = min(minLng, wp.lng)
            maxLng = max(maxLng, wp.lng)
        }

        // Padding ekle (~20 km ≈ 0.18 derece)
        let padding = 0.18
        return try await fetchCoastline(
            south: minLat - padding,
            west: minLng - padding,
            north: maxLat + padding,
            east: maxLng + padding
        )
    }

    /// MKCoordinateRegion icin kiyi cizgisi cek
    func fetchCoastline(for region: MKCoordinateRegion) async throws -> CoastlineResult {
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let north = region.center.latitude + region.span.latitudeDelta / 2
        let west = region.center.longitude - region.span.longitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        return try await fetchCoastline(south: south, west: west, north: north, east: east)
    }

    func clearCache() {
        cache.removeAll()
    }
}

// MARK: - Errors

enum CoastlineError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Gecersiz URL"
        case .invalidResponse: return "Gecersiz API yaniti"
        case .decodingError: return "Veri cozumleme hatasi"
        }
    }
}
