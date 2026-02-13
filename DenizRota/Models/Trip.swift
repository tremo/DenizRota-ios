import Foundation
import CoreLocation
import SwiftData

@Model
final class Trip {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var duration: TimeInterval  // seconds
    var distance: Double        // km
    var avgSpeed: Double        // km/h
    var maxSpeed: Double        // km/h
    var fuelUsed: Double        // liters
    var fuelCost: Double        // TRY

    @Relationship(deleteRule: .cascade)
    var positions: [TripPosition]

    init(startDate: Date) {
        self.id = UUID()
        self.startDate = startDate
        self.duration = 0
        self.distance = 0
        self.avgSpeed = 0
        self.maxSpeed = 0
        self.fuelUsed = 0
        self.fuelCost = 0
        self.positions = []
    }

    func calculateStats(fuelRate: Double, fuelPrice: Double) {
        guard let endDate = endDate else { return }

        duration = endDate.timeIntervalSince(startDate)

        // Pozisyonlari kronolojik sirala (SwiftData relationship sirasiz olabilir)
        let sortedPositions = positions.sorted { $0.timestamp < $1.timestamp }

        // Mesafe hesapla
        var totalDistance: Double = 0
        for i in 1..<sortedPositions.count {
            let prev = sortedPositions[i-1].location
            let curr = sortedPositions[i].location
            totalDistance += curr.distance(from: prev)
        }
        distance = totalDistance / 1000 // meters -> km

        // Hız hesapla
        if duration > 0 {
            avgSpeed = distance / (duration / 3600)
        }

        // Yakıt hesapla
        let hours = duration / 3600
        fuelUsed = hours * fuelRate
        fuelCost = fuelUsed * fuelPrice
    }
}

@Model
final class TripPosition {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var speed: Double           // km/h
    var accuracy: Double        // meters

    init(location: CLLocation) {
        self.id = UUID()
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.timestamp = location.timestamp
        self.speed = max(0, location.speed * 3.6) // m/s -> km/h
        self.accuracy = location.horizontalAccuracy
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
