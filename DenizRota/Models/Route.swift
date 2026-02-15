import Foundation
import CoreLocation
import SwiftData

@Model
final class Route {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade)
    var waypoints: [Waypoint]

    init(name: String = "Yeni Rota") {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.waypoints = []
    }

    // Toplam mesafe (km)
    var totalDistance: Double {
        guard waypoints.count > 1 else { return 0 }

        var distance: Double = 0
        let sorted = waypoints.sorted { $0.orderIndex < $1.orderIndex }

        for i in 1..<sorted.count {
            let prev = sorted[i-1].location
            let curr = sorted[i].location
            distance += curr.distance(from: prev)
        }

        return distance / 1000 // meters -> km
    }

    // Tahmini süre (saat) - varsayılan 15 km/h
    func estimatedDuration(avgSpeed: Double = 15) -> TimeInterval {
        guard avgSpeed > 0 else { return 0 }
        return (totalDistance / avgSpeed) * 3600 // saat -> saniye
    }

    // Tahmini yakıt (litre)
    func estimatedFuel(fuelRate: Double = 20) -> Double {
        let hours = estimatedDuration() / 3600
        return hours * fuelRate
    }

    // Waypoint ekle
    func addWaypoint(latitude: Double, longitude: Double, name: String? = nil) {
        let waypoint = Waypoint(
            latitude: latitude,
            longitude: longitude,
            orderIndex: waypoints.count,
            name: name
        )
        waypoints.append(waypoint)
        updatedAt = Date()
    }

    // Waypoint sil
    func removeWaypoint(_ waypoint: Waypoint) {
        waypoints.removeAll { $0.id == waypoint.id }
        // Sıralamayı ve isimleri güncelle
        for (index, wp) in waypoints.sorted(by: { $0.orderIndex < $1.orderIndex }).enumerated() {
            wp.orderIndex = index
            if wp.name == nil || wp.name?.hasPrefix("Nokta ") == true {
                wp.name = "Nokta \(index + 1)"
            }
        }
        updatedAt = Date()
    }

    // Waypoint'leri yeniden sırala
    func reorderWaypoints() {
        for (index, wp) in waypoints.sorted(by: { $0.orderIndex < $1.orderIndex }).enumerated() {
            wp.orderIndex = index
            if wp.name == nil || wp.name?.hasPrefix("Nokta ") == true {
                wp.name = "Nokta \(index + 1)"
            }
        }
        updatedAt = Date()
    }

    // Sıralı waypoint listesi
    var sortedWaypoints: [Waypoint] {
        waypoints.sorted { $0.orderIndex < $1.orderIndex }
    }

    // Firestore'dan gelen veriyle oluştur
    init(from data: [String: Any], waypoints: [Waypoint] = []) {
        self.id = UUID(uuidString: data["id"] as? String ?? "") ?? UUID()
        self.name = data["name"] as? String ?? "Rota"
        self.createdAt = (data["createdAt"] as? Date) ?? Date()
        self.updatedAt = (data["updatedAt"] as? Date) ?? Date()
        self.waypoints = waypoints
    }

    // Firestore'a kaydetmek için
    var asDictionary: [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "totalDistance": totalDistance,
            "waypointCount": waypoints.count
        ]
    }
}
