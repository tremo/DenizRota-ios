import Foundation
import SwiftData
import CoreLocation
import Combine

/// Seyir yönetimi servisi - aktif seyir takibi ve kayıt işlemleri
@MainActor
class TripManager: ObservableObject {
    static let shared = TripManager()

    // MARK: - Published Properties
    @Published var isActive: Bool = false
    @Published var currentTrip: Trip?
    @Published var currentSpeed: Double = 0.0
    @Published var maxSpeed: Double = 0.0
    @Published var totalDistance: Double = 0.0
    @Published var elapsedTime: TimeInterval = 0.0
    @Published var positions: [TripPosition] = []

    // MARK: - Route Following
    @Published var targetWaypoints: [Waypoint] = []
    @Published var currentWaypointIndex: Int = 0
    @Published var distanceToNextWaypoint: Double?
    @Published var hasArrived: Bool = false

    // MARK: - Private Properties
    private var startTime: Date?
    private var timer: Timer?
    private var lastPosition: CLLocation?
    private var notifiedWaypoints: Set<UUID> = []
    private var cancellables = Set<AnyCancellable>()

    private let locationManager = LocationManager.shared
    private let notificationManager = NotificationManager.shared

    private init() {
        setupLocationObserver()
    }

    // MARK: - Setup

    private func setupLocationObserver() {
        locationManager.$currentLocation
            .sink { [weak self] location in
                guard let self = self, let location = location, self.isActive else { return }
                self.handleLocationUpdate(location)
            }
            .store(in: &cancellables)

        locationManager.$currentSpeed
            .sink { [weak self] speed in
                guard let self = self, self.isActive else { return }
                self.currentSpeed = speed
                if speed > self.maxSpeed {
                    self.maxSpeed = speed
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Trip Control

    func startTrip(waypoints: [Waypoint] = []) {
        guard !isActive else { return }

        // Reset state
        currentTrip = Trip(startDate: Date())
        positions = []
        maxSpeed = 0
        totalDistance = 0
        elapsedTime = 0
        startTime = Date()
        lastPosition = nil
        notifiedWaypoints.removeAll()
        hasArrived = false

        // Setup waypoints for route following
        targetWaypoints = waypoints.sorted { $0.orderIndex < $1.orderIndex }
        currentWaypointIndex = 0

        // Start tracking
        isActive = true
        locationManager.startTracking(waypoints: targetWaypoints)

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
        }
    }

    func stopTrip() -> Trip? {
        guard isActive, let trip = currentTrip else { return nil }

        // Stop tracking
        isActive = false
        _ = locationManager.stopTracking()
        timer?.invalidate()
        timer = nil

        // Calculate final stats
        trip.endDate = Date()
        trip.duration = elapsedTime
        trip.distance = totalDistance
        trip.avgSpeed = totalDistance > 0 ? (totalDistance / (elapsedTime / 3600)) : 0
        trip.maxSpeed = maxSpeed

        // Add positions to trip
        for position in positions {
            trip.positions.append(position)
        }

        let finishedTrip = trip
        currentTrip = nil
        targetWaypoints = []

        return finishedTrip
    }

    func pauseTrip() {
        timer?.invalidate()
        timer = nil
        _ = locationManager.stopTracking()
    }

    func resumeTrip() {
        guard isActive else { return }
        locationManager.startTracking(waypoints: targetWaypoints)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
        }
    }

    // MARK: - Location Handling

    private func handleLocationUpdate(_ location: CLLocation) {
        // Create position record
        let position = TripPosition(location: location)
        positions.append(position)

        // Calculate distance
        if let lastPos = lastPosition {
            let distance = location.distance(from: lastPos) / 1000.0 // km
            if distance < 1.0 { // Filter GPS jumps
                totalDistance += distance
            }
        }
        lastPosition = location

        // Check waypoint proximity
        checkWaypointProximity(location)
    }

    private func checkWaypointProximity(_ location: CLLocation) {
        guard !targetWaypoints.isEmpty, currentWaypointIndex < targetWaypoints.count else {
            distanceToNextWaypoint = nil
            return
        }

        let targetWaypoint = targetWaypoints[currentWaypointIndex]
        let targetLocation = CLLocation(latitude: targetWaypoint.latitude, longitude: targetWaypoint.longitude)
        let distance = location.distance(from: targetLocation)

        distanceToNextWaypoint = distance

        // Check if arrived at waypoint
        if distance <= AppConstants.waypointProximityThreshold {
            if !notifiedWaypoints.contains(targetWaypoint.id) {
                notifiedWaypoints.insert(targetWaypoint.id)

                // Send arrival notification
                notificationManager.sendArrivalNotification(
                    waypointName: targetWaypoint.name ?? "Nokta \(currentWaypointIndex + 1)",
                    distance: distance
                )

                // Move to next waypoint
                if currentWaypointIndex < targetWaypoints.count - 1 {
                    currentWaypointIndex += 1
                } else {
                    hasArrived = true
                }
            }
        }
    }

    private func updateElapsedTime() {
        guard let start = startTime else { return }
        elapsedTime = Date().timeIntervalSince(start)
    }

    // MARK: - Trip Saving

    func saveTrip(_ trip: Trip, settings: BoatSettings?, context: ModelContext) {
        // Calculate fuel usage
        if let settings = settings {
            let hours = trip.duration / 3600
            trip.fuelUsed = hours * settings.fuelRate
            trip.fuelCost = trip.fuelUsed * settings.fuelPrice
        }

        context.insert(trip)

        do {
            try context.save()
        } catch {
            print("Seyir kaydedilemedi: \(error)")
        }
    }

    func deleteTrip(_ trip: Trip, context: ModelContext) {
        context.delete(trip)

        do {
            try context.save()
        } catch {
            print("Seyir silinemedi: \(error)")
        }
    }

    // MARK: - Trip Statistics

    func getTripStats() -> TripStats {
        return TripStats(
            distance: totalDistance,
            duration: elapsedTime,
            avgSpeed: totalDistance > 0 ? (totalDistance / (elapsedTime / 3600)) : 0,
            maxSpeed: maxSpeed,
            currentSpeed: currentSpeed,
            positionCount: positions.count
        )
    }
}

// MARK: - Trip Stats Model
struct TripStats {
    var distance: Double = 0
    var duration: TimeInterval = 0
    var avgSpeed: Double = 0
    var maxSpeed: Double = 0
    var currentSpeed: Double = 0
    var positionCount: Int = 0

    var formattedDistance: String {
        distance.distanceString
    }

    var formattedDuration: String {
        duration.formattedDuration
    }

    var formattedAvgSpeed: String {
        String(format: "%.1f km/h", avgSpeed)
    }

    var formattedMaxSpeed: String {
        String(format: "%.1f km/h", maxSpeed)
    }

    var formattedCurrentSpeed: String {
        String(format: "%.1f km/h", currentSpeed)
    }
}

// MARK: - Trip History Query
extension TripManager {
    static func fetchTrips(context: ModelContext) -> [Trip] {
        let descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchTotalStats(context: ModelContext) -> TotalTripStats {
        let trips = fetchTrips(context: context)

        let totalDistance = trips.reduce(0) { $0 + $1.distance }
        let totalDuration = trips.reduce(0) { $0 + $1.duration }
        let totalFuel = trips.reduce(0) { $0 + $1.fuelUsed }
        let totalCost = trips.reduce(0) { $0 + $1.fuelCost }

        return TotalTripStats(
            tripCount: trips.count,
            totalDistance: totalDistance,
            totalDuration: totalDuration,
            totalFuel: totalFuel,
            totalCost: totalCost
        )
    }
}

// MARK: - Total Trip Stats
struct TotalTripStats {
    var tripCount: Int = 0
    var totalDistance: Double = 0
    var totalDuration: TimeInterval = 0
    var totalFuel: Double = 0
    var totalCost: Double = 0

    var formattedDistance: String {
        String(format: "%.1f km", totalDistance)
    }

    var formattedDuration: String {
        totalDuration.formattedDuration
    }

    var formattedFuel: String {
        String(format: "%.0f L", totalFuel)
    }

    var formattedCost: String {
        totalCost.currencyTRY
    }
}
