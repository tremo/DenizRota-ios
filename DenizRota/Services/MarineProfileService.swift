import Foundation
import CoreLocation

// MARK: - Seamark Object Model

struct SeamarkObject: Identifiable {
    let id: Int
    let type: String
    let name: String?
    let latitude: Double
    let longitude: Double
    let tags: [String: String]
    var distanceMeters: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var localizedType: String {
        switch type {
        case "buoy_lateral": return "Yanlama Şamandırası"
        case "buoy_cardinal": return "Kardinal Şamandıra"
        case "buoy_special_purpose": return "Özel Şamandıra"
        case "buoy_safe_water": return "Güvenli Su Şamandırası"
        case "buoy_isolated_danger": return "Tehlike Şamandırası"
        case "light_major": return "Büyük Fener"
        case "light_minor": return "Küçük Fener"
        case "light_vessel": return "Fener Gemisi"
        case "beacon_lateral": return "Yanlama İşareti"
        case "beacon_cardinal": return "Kardinal İşaret"
        case "beacon_special_purpose": return "Özel İşaret"
        case "daymark": return "Gündüz İşareti"
        case "landmark": return "Kara İşareti"
        case "harbour": return "Liman"
        case "harbour_basin": return "Liman Havzası"
        case "small_craft_facility": return "Küçük Tekne Tesisi"
        case "anchorage": return "Demir Yeri"
        case "anchorage_area": return "Demir Sahası"
        case "mooring": return "Bağlama Noktası"
        case "pontoon": return "Ponton"
        case "rock": return "Kayalık"
        case "wreck": return "Batık"
        case "obstruction": return "Engel"
        case "separation_zone": return "Trafik Ayrım Bölgesi"
        case "recommended_track": return "Önerilen Güzergah"
        case "radar_reflector": return "Radar Reflektörü"
        case "radar_station": return "Radar İstasyonu"
        case "calling_in_point": return "Telsiz Bildirme Noktası"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var symbolName: String {
        switch type {
        case "buoy_lateral", "buoy_cardinal", "buoy_special_purpose",
             "buoy_safe_water", "buoy_isolated_danger":
            return "circle.fill"
        case "light_major", "light_minor", "light_vessel":
            return "lightbulb.fill"
        case "beacon_lateral", "beacon_cardinal", "beacon_special_purpose", "daymark":
            return "antenna.radiowaves.left.and.right"
        case "landmark":
            return "triangle.fill"
        case "harbour", "harbour_basin":
            return "building.2.fill"
        case "small_craft_facility", "pontoon":
            return "ferry.fill"
        case "anchorage", "anchorage_area":
            return "location.north.fill"
        case "mooring":
            return "link"
        case "rock", "wreck", "obstruction":
            return "exclamationmark.triangle.fill"
        case "separation_zone", "recommended_track":
            return "arrow.triangle.2.circlepath"
        case "radar_reflector", "radar_station":
            return "dot.radiowaves.left.and.right"
        default:
            return "info.circle.fill"
        }
    }

    var symbolColorName: String {
        switch type {
        case "rock", "wreck", "obstruction", "buoy_isolated_danger": return "red"
        case "light_major", "light_minor", "light_vessel": return "yellow"
        case "harbour", "harbour_basin", "small_craft_facility", "pontoon": return "blue"
        case "anchorage", "anchorage_area", "mooring": return "green"
        case "buoy_cardinal": return "orange"
        default: return "orange"
        }
    }

    // Fener karakteristikleri varsa göster (örn: "Fl W 4s")
    var lightCharacteristics: String? {
        let character = tags["seamark:light:character"]
        let colour = tags["seamark:light:colour"]
        let period = tags["seamark:light:period"]
        let range = tags["seamark:light:range"]

        var parts: [String] = []
        if let c = character { parts.append(c) }
        if let col = colour { parts.append(col.capitalized) }
        if let p = period { parts.append("\(p)s") }
        if let r = range { parts.append("\(r)M") }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // Varsa VHF kanalı
    var vhfChannel: String? {
        tags["seamark:radio_station:channel"] ?? tags["communication:vhf_channel"]
    }

    // Varsa yükseklik
    var elevation: String? {
        guard let elev = tags["seamark:light:height"] ?? tags["height"] else { return nil }
        return "\(elev)m"
    }
}

// MARK: - Marine Profile Service

actor MarineProfileService {
    static let shared = MarineProfileService()

    private var cache: [String: [SeamarkObject]] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheExpiry: TimeInterval = 300 // 5 dakika

    // MARK: - Public API

    /// Verilen koordinat etrafındaki seamark nesnelerini getirir
    func fetchNearby(latitude: Double, longitude: Double, radius: Int = 600) async throws -> [SeamarkObject] {
        let cacheKey = "\(Int(latitude * 100)),\(Int(longitude * 100))"

        if let cached = cache[cacheKey],
           let ts = cacheTimestamps[cacheKey],
           Date().timeIntervalSince(ts) < cacheExpiry {
            return cached
        }

        let query = """
        [out:json][timeout:15];
        (
          node["seamark:type"](around:\(radius),\(latitude),\(longitude));
        );
        out body;
        """

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://overpass-api.de/api/interpreter?data=\(encoded)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(OverpassResponse.self, from: data)
        let center = CLLocation(latitude: latitude, longitude: longitude)

        let objects = response.elements.compactMap { element -> SeamarkObject? in
            guard let tags = element.tags,
                  let seamarkType = tags["seamark:type"] else { return nil }

            let objLocation = CLLocation(latitude: element.lat, longitude: element.lon)
            let distance = center.distance(from: objLocation)

            return SeamarkObject(
                id: element.id,
                type: seamarkType,
                name: tags["name"] ?? tags["seamark:name"],
                latitude: element.lat,
                longitude: element.lon,
                tags: tags,
                distanceMeters: distance
            )
        }.sorted { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }

        cache[cacheKey] = objects
        cacheTimestamps[cacheKey] = Date()

        return objects
    }

    func clearCache() {
        cache.removeAll()
        cacheTimestamps.removeAll()
    }

    // MARK: - Private Decodable Models

    private struct OverpassResponse: Decodable {
        let elements: [Element]

        struct Element: Decodable {
            let id: Int
            let lat: Double
            let lon: Double
            let tags: [String: String]?
        }
    }
}
