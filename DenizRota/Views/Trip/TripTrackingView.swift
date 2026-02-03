import SwiftUI
import MapKit

/// Aktif seyir takip görünümü - tam ekran harita ve istatistikler
struct TripTrackingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @ObservedObject var tripManager = TripManager.shared
    @ObservedObject var locationManager = LocationManager.shared

    let waypoints: [Waypoint]
    let boatSettings: BoatSettings?
    let onTripEnd: (Trip?) -> Void

    @State private var mapRegion = MKCoordinateRegion(
        center: AppConstants.defaultMapCenter,
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var showStopConfirmation = false
    @State private var isPaused = false

    var body: some View {
        ZStack {
            // Full screen map
            Map(coordinateRegion: $mapRegion,
                showsUserLocation: true,
                annotationItems: waypoints) { waypoint in
                MapAnnotation(coordinate: waypoint.coordinate) {
                    WaypointMarker(
                        number: waypoint.orderIndex + 1,
                        riskLevel: waypoint.riskLevel,
                        isTarget: waypoint.orderIndex == tripManager.currentWaypointIndex
                    )
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .overlay(alignment: .topLeading) {
                routePolylineOverlay
            }
            .ignoresSafeArea()

            // Overlays
            VStack {
                // Top bar
                topBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()

                // Bottom panel
                bottomPanel
            }

            // Arrival notification
            if tripManager.hasArrived {
                arrivalOverlay
            }
        }
        .onAppear {
            setupMap()
            tripManager.startTrip(waypoints: waypoints)
        }
        .alert("Seyiri Bitir", isPresented: $showStopConfirmation) {
            Button("Iptal", role: .cancel) { }
            Button("Bitir", role: .destructive) {
                endTrip()
            }
        } message: {
            Text("Seyiri bitirmek istediginize emin misiniz?")
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            // Close button
            Button {
                showStopConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.red)
                    .clipShape(Circle())
            }

            Spacer()

            // Timer
            VStack(spacing: 2) {
                Text("Sure")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(tripManager.elapsedTime.formattedDuration)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            Spacer()

            // Pause/Resume button
            Button {
                isPaused.toggle()
                if isPaused {
                    tripManager.pauseTrip()
                } else {
                    tripManager.resumeTrip()
                }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(isPaused ? .green : .orange)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Bottom Panel
    private var bottomPanel: some View {
        VStack(spacing: 12) {
            // Speed display
            speedPanel

            // Stats grid
            statsGrid

            // Next waypoint info
            if !waypoints.isEmpty {
                nextWaypointInfo
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(20, corners: [.topLeft, .topRight])
    }

    private var speedPanel: some View {
        VStack(spacing: 4) {
            Text("\(tripManager.currentSpeed, specifier: "%.1f")")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("km/h")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 20) {
            StatItem(
                icon: "arrow.up.right",
                title: "Mesafe",
                value: String(format: "%.1f km", tripManager.totalDistance)
            )

            Divider()
                .frame(height: 40)

            StatItem(
                icon: "gauge.high",
                title: "Maks Hiz",
                value: String(format: "%.1f km/h", tripManager.maxSpeed)
            )

            Divider()
                .frame(height: 40)

            StatItem(
                icon: "speedometer",
                title: "Ort Hiz",
                value: tripManager.totalDistance > 0 ?
                    String(format: "%.1f km/h", tripManager.totalDistance / (tripManager.elapsedTime / 3600)) : "0.0 km/h"
            )
        }
    }

    private var nextWaypointInfo: some View {
        Group {
            if tripManager.currentWaypointIndex < waypoints.count {
                let targetWaypoint = waypoints[tripManager.currentWaypointIndex]
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading) {
                        Text("Sonraki: \(targetWaypoint.name ?? "Nokta \(tripManager.currentWaypointIndex + 1)")")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if let distance = tripManager.distanceToNextWaypoint {
                            Text("\(Int(distance)) metre")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text("\(tripManager.currentWaypointIndex + 1)/\(waypoints.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.2))
                        .cornerRadius(8)
                }
                .padding()
                .background(.blue.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Route Overlay
    private var routePolylineOverlay: some View {
        // Simplified - in real implementation use MKMapViewRepresentable with MKPolyline
        EmptyView()
    }

    // MARK: - Arrival Overlay
    private var arrivalOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Hedefe Ulasildi!")
                .font(.title)
                .fontWeight(.bold)

            Button("Seyiri Bitir") {
                endTrip()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(radius: 20)
    }

    // MARK: - Methods
    private func setupMap() {
        if let firstWaypoint = waypoints.first {
            mapRegion.center = firstWaypoint.coordinate
        } else if let userLocation = locationManager.currentLocation?.coordinate {
            mapRegion.center = userLocation
        }
    }

    private func endTrip() {
        if let trip = tripManager.stopTrip() {
            tripManager.saveTrip(trip, settings: boatSettings, context: modelContext)
            onTripEnd(trip)
        } else {
            onTripEnd(nil)
        }
        dismiss()
    }
}

// MARK: - Supporting Views
struct StatItem: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct WaypointMarker: View {
    let number: Int
    let riskLevel: RiskLevel
    let isTarget: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(riskLevel.color)
                .frame(width: isTarget ? 36 : 28, height: isTarget ? 36 : 28)
                .shadow(color: isTarget ? .blue : .clear, radius: 8)

            Text("\(number)")
                .font(isTarget ? .headline : .caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .animation(.easeInOut, value: isTarget)
    }
}

// MARK: - Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Trip Summary View
struct TripSummaryView: View {
    let trip: Trip
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Summary header
                    summaryHeader

                    // Stats
                    statsSection

                    // Map preview
                    mapPreview
                }
                .padding()
            }
            .navigationTitle("Seyir Ozeti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var summaryHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Seyir Tamamlandi")
                .font(.title2)
                .fontWeight(.bold)

            Text(trip.startDate.dateTimeStringTR)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var statsSection: some View {
        VStack(spacing: 12) {
            HStack {
                SummaryStatCard(
                    icon: "arrow.up.right.circle.fill",
                    title: "Mesafe",
                    value: String(format: "%.1f km", trip.distance),
                    color: .blue
                )
                SummaryStatCard(
                    icon: "clock.fill",
                    title: "Sure",
                    value: trip.duration.shortDuration,
                    color: .orange
                )
            }

            HStack {
                SummaryStatCard(
                    icon: "speedometer",
                    title: "Ort Hiz",
                    value: String(format: "%.1f km/h", trip.avgSpeed),
                    color: .green
                )
                SummaryStatCard(
                    icon: "gauge.high",
                    title: "Maks Hiz",
                    value: String(format: "%.1f km/h", trip.maxSpeed),
                    color: .red
                )
            }

            HStack {
                SummaryStatCard(
                    icon: "fuelpump.fill",
                    title: "Yakit",
                    value: String(format: "%.1f L", trip.fuelUsed),
                    color: .purple
                )
                SummaryStatCard(
                    icon: "turkishlirasign.circle.fill",
                    title: "Maliyet",
                    value: trip.fuelCost.currencyTRY,
                    color: .indigo
                )
            }
        }
    }

    private var mapPreview: some View {
        Group {
            if let positions = trip.positions, positions.count > 1 {
                let coords = positions.map { $0.coordinate }
                let center = coords.center ?? AppConstants.defaultMapCenter

                Map(coordinateRegion: .constant(MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))) {
                    // Start marker
                    if let first = coords.first {
                        Annotation("Baslangic", coordinate: first) {
                            Image(systemName: "flag.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    // End marker
                    if let last = coords.last {
                        Annotation("Bitis", coordinate: last) {
                            Image(systemName: "flag.checkered")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .frame(height: 200)
                .cornerRadius(12)
            }
        }
    }
}

struct SummaryStatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
            }

            Spacer()
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Speed Panel View (Standalone)
struct SpeedPanelView: View {
    let speed: Double
    let isTracking: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("\(speed, specifier: "%.1f")")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(isTracking ? .primary : .secondary)

            Text("km/h")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}
