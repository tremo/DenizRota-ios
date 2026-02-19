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

    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: AppConstants.defaultMapCenter,
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    ))
    @State private var showStopConfirmation = false
    @State private var isPaused = false

    var body: some View {
        ZStack {
            // Full screen map
            Map(position: $cameraPosition) {
                UserAnnotation()
                ForEach(waypoints) { waypoint in
                    Annotation("", coordinate: waypoint.coordinate) {
                        WaypointMarker(
                            number: waypoint.orderIndex + 1,
                            riskLevel: waypoint.riskLevel,
                            isTarget: waypoint.orderIndex == tripManager.currentWaypointIndex
                        )
                    }
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
        HStack(spacing: 12) {
            // Close button
            Button {
                showStopConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.red)
                    .clipShape(Circle())
            }

            // Current speed - prominent
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(tripManager.currentSpeed, specifier: "%.1f")")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("km/h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Duration
            Text(tripManager.elapsedTime.formattedDuration)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()

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
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(isPaused ? .green : .orange)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    // MARK: - Bottom Panel
    private var bottomPanel: some View {
        VStack(spacing: 6) {
            // Compact stats row
            HStack(spacing: 0) {
                compactStat(
                    value: String(format: "%.1f", tripManager.totalDistance),
                    unit: "km",
                    label: "Mesafe"
                )

                Divider().frame(height: 28)

                compactStat(
                    value: String(format: "%.1f", tripManager.maxSpeed),
                    unit: "km/h",
                    label: "Maks"
                )

                Divider().frame(height: 28)

                let avgSpeed = tripManager.totalDistance > 0 ?
                    tripManager.totalDistance / (tripManager.elapsedTime / 3600) : 0.0
                compactStat(
                    value: String(format: "%.1f", avgSpeed),
                    unit: "km/h",
                    label: "Ort"
                )
            }

            // Next waypoint (compact single line)
            if tripManager.currentWaypointIndex < waypoints.count {
                let targetWaypoint = waypoints[tripManager.currentWaypointIndex]
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)

                    Text(targetWaypoint.name ?? "Nokta \(tripManager.currentWaypointIndex + 1)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let distance = tripManager.distanceToNextWaypoint {
                        Text("· \(Int(distance))m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(tripManager.currentWaypointIndex + 1)/\(waypoints.count)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15))
                        .cornerRadius(6)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(16, corners: [.topLeft, .topRight])
    }

    private func compactStat(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
        let center: CLLocationCoordinate2D
        if let firstWaypoint = waypoints.first {
            center = firstWaypoint.coordinate
        } else if let userLocation = locationManager.currentLocation?.coordinate {
            center = userLocation
        } else {
            return
        }
        cameraPosition = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        ))
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
            if trip.positions.count > 1 {
                let coords = trip.positions.map { $0.coordinate }
                let center = coords.center ?? AppConstants.defaultMapCenter

                Map(initialPosition: .region(MKCoordinateRegion(
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

