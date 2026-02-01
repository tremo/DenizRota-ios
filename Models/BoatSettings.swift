import Foundation
import SwiftData

@Model
final class BoatSettings {
    var boatName: String
    var boatType: BoatType
    var avgSpeed: Double        // km/h
    var fuelRate: Double        // liters/hour
    var tankCapacity: Double    // liters
    var fuelPrice: Double       // TRY/liter

    init() {
        self.boatName = "Teknem"
        self.boatType = .motorlu
        self.avgSpeed = 15
        self.fuelRate = 20
        self.tankCapacity = 200
        self.fuelPrice = 45
    }

    // Firestore'dan gelen veriyle oluştur
    init(from data: [String: Any]) {
        self.boatName = data["boatName"] as? String ?? "Teknem"
        self.boatType = BoatType(rawValue: data["boatType"] as? String ?? "motorlu") ?? .motorlu
        self.avgSpeed = data["avgSpeed"] as? Double ?? 15
        self.fuelRate = data["fuelRate"] as? Double ?? 20
        self.tankCapacity = data["tankCapacity"] as? Double ?? 200
        self.fuelPrice = data["fuelPrice"] as? Double ?? 45
    }

    // Firestore'a kaydetmek için
    var asDictionary: [String: Any] {
        [
            "boatName": boatName,
            "boatType": boatType.rawValue,
            "avgSpeed": avgSpeed,
            "fuelRate": fuelRate,
            "tankCapacity": tankCapacity,
            "fuelPrice": fuelPrice
        ]
    }
}

enum BoatType: String, Codable, CaseIterable {
    case motorlu = "motorlu"
    case yelkenli = "yelkenli"
    case gulet = "gulet"
    case katamaran = "katamaran"
    case surat = "sürat"

    var displayName: String {
        switch self {
        case .motorlu: return "Motorlu Tekne"
        case .yelkenli: return "Yelkenli"
        case .gulet: return "Gulet"
        case .katamaran: return "Katamaran"
        case .surat: return "Sürat Teknesi"
        }
    }
}
