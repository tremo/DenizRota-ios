import SwiftUI
import MapKit

struct MapView: View {
    @EnvironmentObject var locationManager: LocationManager
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 38.5, longitude: 27.0), // Ege
            span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
        )
    )

    @State private var isRouteMode = false
    @State private var waypoints: [WaypointAnnotation] = []
    @State private var showingSpeedPanel = false

    var body: some View {
        ZStack {
            // Harita
            Map(position: $cameraPosition, interactionModes: .all) {
                // Kullanıcı konumu
                if let location = locationManager.currentLocation {
                    Annotation("Konum", coordinate: location.coordinate) {
                        ZStack {
                            Circle()
                                .fill(.blue.opacity(0.2))
                                .frame(width: 60, height: 60)

                            Circle()
                                .fill(.blue)
                                .frame(width: 16, height: 16)
                        }
                    }
                }

                // Waypoint'ler
                ForEach(waypoints) { waypoint in
                    Annotation(waypoint.name ?? "", coordinate: waypoint.coordinate) {
                        WaypointMarkerView(
                            number: waypoint.index + 1,
                            riskLevel: waypoint.riskLevel
                        )
                    }
                }

                // Rota çizgisi
                if waypoints.count > 1 {
                    MapPolyline(coordinates: waypoints.map(\.coordinate))
                        .stroke(.blue, lineWidth: 3)
                }
            }
            .mapStyle(.standard)
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
            }
            .onTapGesture { position in
                if isRouteMode {
                    // Tap to add waypoint - coordinate conversion needed
                }
            }

            // UI Overlay
            VStack {
                Spacer()

                // Hız paneli (seyir aktifken)
                if locationManager.isTracking {
                    SpeedPanelView(speed: locationManager.currentSpeed)
                        .padding(.bottom, 20)
                }

                // Alt butonlar
                HStack(spacing: 16) {
                    // Rota modu
                    Button {
                        isRouteMode.toggle()
                    } label: {
                        Image(systemName: isRouteMode ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.title2)
                            .padding(12)
                            .background(isRouteMode ? .blue : .white)
                            .foregroundStyle(isRouteMode ? .white : .blue)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }

                    Spacer()

                    // Seyir başlat/bitir
                    Button {
                        if locationManager.isTracking {
                            stopTrip()
                        } else {
                            startTrip()
                        }
                    } label: {
                        Image(systemName: locationManager.isTracking ? "stop.fill" : "play.fill")
                            .font(.title)
                            .padding(16)
                            .background(locationManager.isTracking ? .red : .green)
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }

            // Konum izni uyarısı
            if !locationManager.hasAnyPermission {
                PermissionOverlay()
            }
        }
    }

    private func startTrip() {
        let waypointsForTracking = waypoints.map { annotation in
            let wp = Waypoint(
                latitude: annotation.coordinate.latitude,
                longitude: annotation.coordinate.longitude,
                orderIndex: annotation.index,
                name: annotation.name
            )
            return wp
        }

        locationManager.startTracking(waypoints: waypointsForTracking)
    }

    private func stopTrip() {
        if let result = locationManager.stopTracking() {
            // Trip kaydet
            print("Trip completed: \(result.totalDistance) km")
        }
    }
}

// MARK: - Waypoint Annotation

struct WaypointAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let index: Int
    var name: String?
    var riskLevel: RiskLevel = .unknown
}

// MARK: - Waypoint Marker

struct WaypointMarkerView: View {
    let number: Int
    let riskLevel: RiskLevel

    var body: some View {
        ZStack {
            Circle()
                .fill(riskColor)
                .frame(width: 32, height: 32)
                .shadow(radius: 2)

            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
    }

    private var riskColor: Color {
        switch riskLevel {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Speed Panel

struct SpeedPanelView: View {
    let speed: Double

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f", speed))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("km/h")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 4)
    }
}

// MARK: - Permission Overlay

struct PermissionOverlay: View {
    @EnvironmentObject var locationManager: LocationManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Konum İzni Gerekli")
                .font(.title2.bold())

            Text("Seyir takibi ve rota oluşturma için konum erişimine izin vermeniz gerekiyor.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("İzin Ver") {
                locationManager.requestPermission()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(40)
    }
}

#Preview {
    MapView()
        .environmentObject(LocationManager.shared)
}
