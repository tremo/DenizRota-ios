import Foundation
import CoreLocation
import SwiftData

@Model
final class Waypoint {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var orderIndex: Int
    var name: String?

    // Weather data
    var windSpeed: Double?      // km/h
    var windDirection: Double?  // degrees
    var windGusts: Double?      // km/h
    var temperature: Double?    // celsius
    var waveHeight: Double?     // meters (fetch-adjusted)
    var waveDirection: Double?  // degrees
    var wavePeriod: Double?     // seconds

    var riskLevel: RiskLevel
    var isLoading: Bool

    init(latitude: Double, longitude: Double, orderIndex: Int, name: String? = nil) {
        self.id = UUID()
        self.latitude = latitude
        self.longitude = longitude
        self.orderIndex = orderIndex
        self.name = name
        self.riskLevel = .unknown
        self.isLoading = false
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

enum RiskLevel: String, Codable {
    case green = "green"
    case yellow = "yellow"
    case red = "red"
    case unknown = "gray"

    static func calculate(windSpeed: Double?, waveHeight: Double?) -> RiskLevel {
        guard let wind = windSpeed else { return .unknown }
        let wave = waveHeight ?? 0

        if wind >= 30 || wave > 1.5 {
            return .red
        } else if wind >= 15 || wave >= 0.5 {
            return .yellow
        } else {
            return .green
        }
    }
}
