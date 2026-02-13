import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    private let locationManager = CLLocationManager()

    // Published properties
    @Published var currentLocation: CLLocation?
    @Published var currentSpeed: Double = 0         // km/h
    @Published var isTracking = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // Trip tracking state
    private var tripPositions: [CLLocation] = []
    private var tripStartTime: Date?
    private var maxSpeed: Double = 0

    // Waypoint tracking for arrival notifications
    private var activeWaypoints: [Waypoint] = []
    private var notifiedWaypoints: Set<UUID> = []
    private let arrivalThreshold: Double = 100 // meters

    override init() {
        super.init()
        setupLocationManager()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 10 // minimum 10m hareket

        // Background location için kritik ayarlar
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true

        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Permissions

    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    var hasAlwaysPermission: Bool {
        authorizationStatus == .authorizedAlways
    }

    var hasAnyPermission: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    // MARK: - Trip Tracking

    func startTracking(waypoints: [Waypoint] = []) {
        guard hasAnyPermission else {
            requestPermission()
            return
        }

        isTracking = true
        tripStartTime = Date()
        tripPositions.removeAll()
        maxSpeed = 0

        // Hedefe varış bildirimi için waypoint'leri kaydet
        activeWaypoints = waypoints
        notifiedWaypoints.removeAll()

        locationManager.startUpdatingLocation()

        print("Trip tracking started")
    }

    /// Demir alarmı için konum güncellemelerini başlat (trip tracking olmadan)
    func startLocationUpdates() {
        guard hasAnyPermission else {
            requestPermission()
            return
        }
        locationManager.startUpdatingLocation()
    }

    /// Demir alarmı için konum güncellemelerini durdur (sadece tracking de aktif değilse)
    func stopLocationUpdatesIfNeeded() {
        guard !isTracking else { return }
        guard AnchorAlarmManager.shared.state != .active else { return }
        locationManager.stopUpdatingLocation()
    }

    func stopTracking() -> TripResult? {
        // Demir alarmı aktifse konum güncellemelerini durdurma
        if AnchorAlarmManager.shared.state != .active {
            locationManager.stopUpdatingLocation()
        }
        isTracking = false

        guard let startTime = tripStartTime else { return nil }

        let result = TripResult(
            startTime: startTime,
            endTime: Date(),
            positions: tripPositions,
            maxSpeed: maxSpeed
        )

        // State temizle
        tripPositions.removeAll()
        tripStartTime = nil
        maxSpeed = 0
        activeWaypoints.removeAll()
        notifiedWaypoints.removeAll()

        print("Trip tracking stopped. Positions: \(result.positions.count)")

        return result
    }

    // MARK: - Waypoint Proximity

    private func checkWaypointProximity(_ location: CLLocation) {
        for waypoint in activeWaypoints {
            // Zaten bildirim gönderildiyse atla
            guard !notifiedWaypoints.contains(waypoint.id) else { continue }

            let distance = location.distance(from: waypoint.location)

            if distance <= arrivalThreshold {
                notifiedWaypoints.insert(waypoint.id)
                NotificationManager.shared.sendArrivalNotification(
                    waypointName: waypoint.name,
                    distance: distance
                )
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            processLocation(location)
        }
    }

    private func processLocation(_ location: CLLocation) {
        // Accuracy filtresi - 50m üstü güvenilir değil
        guard location.horizontalAccuracy <= 50 && location.horizontalAccuracy >= 0 else {
            return
        }

        // GPS noise filtresi - 1km üstü atlama gerçekçi değil
        if let lastPosition = tripPositions.last {
            let distance = location.distance(from: lastPosition)
            if distance > 1000 {
                print("GPS jump filtered: \(distance)m")
                return
            }
        }

        // State güncelle
        currentLocation = location

        let speedKmh = max(0, location.speed * 3.6)
        currentSpeed = speedKmh

        // Tracking aktifse kaydet
        if isTracking {
            tripPositions.append(location)

            if speedKmh > maxSpeed {
                maxSpeed = speedKmh
            }

            // Waypoint yakınlık kontrolü
            checkWaypointProximity(location)
        }

        // Demir alarmı kontrolü (tracking bağımsız, her zaman çalışır)
        AnchorAlarmManager.shared.checkLocation(location)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus

            if authorizationStatus == .authorizedAlways {
                print("Always authorization granted")
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

// MARK: - Trip Result

struct TripResult {
    let startTime: Date
    let endTime: Date
    let positions: [CLLocation]
    let maxSpeed: Double

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var totalDistance: Double {
        var distance: Double = 0
        for i in 1..<positions.count {
            distance += positions[i].distance(from: positions[i-1])
        }
        return distance / 1000 // km
    }

    var averageSpeed: Double {
        guard duration > 0 else { return 0 }
        return totalDistance / (duration / 3600)
    }
}
