import Foundation
import SwiftData
import CoreLocation

/// Rota yönetimi servisi - rota oluşturma, düzenleme ve hesaplama işlemleri
@MainActor
class RouteManager: ObservableObject {
    static let shared = RouteManager()

    @Published var currentRoute: Route?
    @Published var isRouteMode: Bool = false
    @Published var isLoadingWeather: Bool = false

    private let weatherService = WeatherService.shared

    private init() {}

    // MARK: - Route Mode

    func startRouteMode() {
        currentRoute = Route(name: "Yeni Rota")
        isRouteMode = true
    }

    func endRouteMode() {
        isRouteMode = false
    }

    func cancelRoute() {
        currentRoute = nil
        isRouteMode = false
    }

    // MARK: - Waypoint Management

    func addWaypoint(at coordinate: CLLocationCoordinate2D) {
        guard let route = currentRoute else { return }

        let name = "Nokta \(route.waypoints.count + 1)"
        route.addWaypoint(latitude: coordinate.latitude, longitude: coordinate.longitude, name: name)
        objectWillChange.send()
    }

    func removeWaypoint(_ waypoint: Waypoint) {
        guard let route = currentRoute else { return }
        route.removeWaypoint(waypoint)
        reorderWaypoints()
        objectWillChange.send()
    }

    func removeLastWaypoint() {
        guard let route = currentRoute,
              let last = route.waypoints.max(by: { $0.orderIndex < $1.orderIndex }) else { return }
        route.removeWaypoint(last)
        objectWillChange.send()
    }

    func reorderWaypoints() {
        guard let route = currentRoute else { return }
        route.reorderWaypoints()
    }

    func clearRoute() {
        guard let route = currentRoute else { return }
        let waypointsToRemove = Array(route.waypoints)
        for waypoint in waypointsToRemove {
            route.removeWaypoint(waypoint)
        }
        objectWillChange.send()
    }

    // MARK: - Weather Loading

    func loadWeatherForAllWaypoints(departureDate: Date = Date()) async {
        guard let route = currentRoute, !route.waypoints.isEmpty else { return }

        isLoadingWeather = true

        // Koordinatlari onceden cikart (Sendable uyumluluk icin)
        let coordinates = route.waypoints.map { $0.coordinate }
        for waypoint in route.waypoints { waypoint.isLoading = true }

        await withTaskGroup(of: (Int, WeatherData?).self) { group in
            for (index, coordinate) in coordinates.enumerated() {
                group.addTask {
                    let weather = try? await self.weatherService.fetchWeather(for: coordinate, date: departureDate)
                    return (index, weather)
                }
            }

            for await (index, weather) in group {
                guard index < route.waypoints.count else { continue }
                let waypoint = route.waypoints[index]
                if let weather = weather {
                    waypoint.updateWeather(from: weather)
                }
                waypoint.isLoading = false
            }
        }

        isLoadingWeather = false
        objectWillChange.send()
    }

    func loadWeatherForWaypoint(_ waypoint: Waypoint, departureDate: Date = Date()) async {
        waypoint.isLoading = true

        if let weather = try? await weatherService.fetchWeather(for: waypoint.coordinate, date: departureDate) {
            waypoint.updateWeather(from: weather)
        }

        waypoint.isLoading = false
        objectWillChange.send()
    }

    // MARK: - Route Statistics

    func calculateRouteStats(with settings: BoatSettings?) -> RouteStats {
        guard let route = currentRoute else {
            return RouteStats()
        }

        let totalDistance = route.totalDistance
        let avgSpeed = settings?.avgSpeed ?? AppConstants.defaultBoatSpeed
        let fuelRate = settings?.fuelRate ?? AppConstants.defaultFuelRate
        let fuelPrice = settings?.fuelPrice ?? AppConstants.defaultFuelPrice

        let estimatedHours = totalDistance / avgSpeed
        let fuelNeeded = estimatedHours * fuelRate
        let fuelCost = fuelNeeded * fuelPrice

        let maxRisk = route.sortedWaypoints.map { $0.riskLevel }.max { a, b in
            riskPriority(a) < riskPriority(b)
        } ?? .unknown

        return RouteStats(
            totalDistance: totalDistance,
            estimatedDuration: estimatedHours * 3600, // saniye
            fuelNeeded: fuelNeeded,
            fuelCost: fuelCost,
            waypointCount: route.waypoints.count,
            maxRiskLevel: maxRisk
        )
    }

    private func riskPriority(_ level: RiskLevel) -> Int {
        switch level {
        case .green: return 0
        case .yellow: return 1
        case .red: return 2
        case .unknown: return -1
        }
    }

    // MARK: - Route Saving

    func saveCurrentRoute(name: String, context: ModelContext) -> Route? {
        guard let route = currentRoute else { return nil }

        route.name = name
        route.updatedAt = Date()
        context.insert(route)

        do {
            try context.save()
            currentRoute = nil
            isRouteMode = false
            return route
        } catch {
            print("Rota kaydedilemedi: \(error)")
            return nil
        }
    }

    // MARK: - Route Loading

    func loadRoute(_ route: Route) {
        currentRoute = route
        isRouteMode = true
        objectWillChange.send()
    }

    func duplicateRoute(_ route: Route, context: ModelContext) -> Route? {
        let newRoute = Route(name: "\(route.name) (Kopya)")

        for waypoint in route.sortedWaypoints {
            newRoute.addWaypoint(latitude: waypoint.latitude, longitude: waypoint.longitude, name: waypoint.name)
            if let newWp = newRoute.waypoints.last {
                newWp.windSpeed = waypoint.windSpeed
                newWp.windDirection = waypoint.windDirection
                newWp.windGusts = waypoint.windGusts
                newWp.temperature = waypoint.temperature
                newWp.waveHeight = waypoint.waveHeight
                newWp.waveDirection = waypoint.waveDirection
                newWp.wavePeriod = waypoint.wavePeriod
            }
        }

        context.insert(newRoute)

        do {
            try context.save()
            return newRoute
        } catch {
            print("Rota kopyalanamadı: \(error)")
            return nil
        }
    }

    func deleteRoute(_ route: Route, context: ModelContext) {
        context.delete(route)
        do {
            try context.save()
        } catch {
            print("Rota silinemedi: \(error)")
        }
    }

    // MARK: - Estimated Arrival

    func calculateEstimatedArrival(departureDate: Date, settings: BoatSettings?) -> Date {
        let stats = calculateRouteStats(with: settings)
        return departureDate.addingTimeInterval(stats.estimatedDuration)
    }
}

// MARK: - Route Stats Model
struct RouteStats {
    var totalDistance: Double = 0
    var estimatedDuration: TimeInterval = 0
    var fuelNeeded: Double = 0
    var fuelCost: Double = 0
    var waypointCount: Int = 0
    var maxRiskLevel: RiskLevel = .unknown

    var estimatedHours: Double {
        estimatedDuration / 3600
    }

    var formattedDuration: String {
        estimatedDuration.shortDuration
    }

    var formattedDistance: String {
        String(format: "%.1f km", totalDistance)
    }

    var formattedFuel: String {
        String(format: "%.0f L", fuelNeeded)
    }

    var formattedCost: String {
        fuelCost.currencyTRY
    }
}

// MARK: - Waypoint Weather Update Extension
extension Waypoint {
    func updateWeather(from data: WeatherData) {
        windSpeed = data.windSpeed
        windDirection = data.windDirection
        windGusts = data.windGusts
        temperature = data.temperature

        // Dalga yüksekliğini doğrudan ata (WeatherService'te zaten fetch-adjusted)
        self.waveHeight = data.waveHeight

        waveDirection = data.waveDirection
        wavePeriod = data.wavePeriod
        riskLevel = data.riskLevel
    }
}
