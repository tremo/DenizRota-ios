import SwiftUI
import SwiftData

struct RouteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.updatedAt, order: .reverse) private var routes: [Route]

    @State private var selectedRoute: Route?
    @State private var showingDeleteAlert = false
    @State private var routeToDelete: Route?

    var body: some View {
        Group {
            if routes.isEmpty {
                EmptyRoutesView()
            } else {
                List {
                    ForEach(routes) { route in
                        RouteRowView(route: route)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedRoute = route
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    routeToDelete = route
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .sheet(item: $selectedRoute) { route in
            RouteDetailView(route: route)
        }
        .alert("Rotayi Sil", isPresented: $showingDeleteAlert) {
            Button("Sil", role: .destructive) {
                if let route = routeToDelete {
                    deleteRoute(route)
                }
            }
            Button("Iptal", role: .cancel) {
                routeToDelete = nil
            }
        } message: {
            Text("Bu rotayi silmek istediginizden emin misiniz? Bu islem geri alinamaz.")
        }
    }

    private func deleteRoute(_ route: Route) {
        modelContext.delete(route)
        routeToDelete = nil
    }
}

// MARK: - Empty State

struct EmptyRoutesView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Rota Yok", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        } description: {
            Text("Harita sekmesinde rota modu acarak yeni rotalar olusturabilirsiniz.")
        }
    }
}

// MARK: - Route Row

struct RouteRowView: View {
    let route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(route.name)
                    .font(.headline)

                Spacer()

                // Risk gostergesi
                if let maxRisk = route.sortedWaypoints.map(\.riskLevel).max(by: { riskOrder($0) < riskOrder($1) }) {
                    Circle()
                        .fill(riskColor(maxRisk))
                        .frame(width: 12, height: 12)
                }
            }

            HStack(spacing: 16) {
                Label("\(route.waypoints.count) nokta", systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(String(format: "%.1f km", route.totalDistance), systemImage: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let duration = route.estimatedDuration()
                let hours = Int(duration / 3600)
                let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
                Label("\(hours)s \(minutes)d", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(route.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func riskOrder(_ level: RiskLevel) -> Int {
        switch level {
        case .red: return 3
        case .yellow: return 2
        case .green: return 1
        case .unknown: return 0
        }
    }

    private func riskColor(_ level: RiskLevel) -> Color {
        switch level {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Route Detail View

struct RouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let route: Route

    var body: some View {
        NavigationStack {
            List {
                Section("Ozet") {
                    LabeledContent("Toplam Mesafe", value: String(format: "%.1f km", route.totalDistance))

                    let duration = route.estimatedDuration()
                    let hours = Int(duration / 3600)
                    let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
                    LabeledContent("Tahmini Sure", value: "\(hours)s \(minutes)d")

                    LabeledContent("Tahmini Yakit", value: String(format: "%.1f L", route.estimatedFuel()))
                }

                Section("Waypoint'ler (\(route.waypoints.count))") {
                    ForEach(route.sortedWaypoints) { waypoint in
                        WaypointRowView(waypoint: waypoint)
                    }
                }
            }
            .navigationTitle(route.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Waypoint Row

struct WaypointRowView: View {
    let waypoint: Waypoint

    var body: some View {
        HStack {
            // Numara ve risk rengi
            ZStack {
                Circle()
                    .fill(riskColor)
                    .frame(width: 28, height: 28)

                Text("\(waypoint.orderIndex + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(waypoint.name ?? "Waypoint \(waypoint.orderIndex + 1)")
                    .font(.subheadline)

                Text(String(format: "%.4f, %.4f", waypoint.latitude, waypoint.longitude))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Hava durumu bilgisi
            if let windSpeed = waypoint.windSpeed {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(windSpeed)) km/h")
                        .font(.caption.bold())

                    if let wave = waypoint.waveHeight {
                        Text(String(format: "%.1f m", wave))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var riskColor: Color {
        switch waypoint.riskLevel {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        case .unknown: return .gray
        }
    }
}

#Preview {
    NavigationStack {
        RouteListView()
    }
    .modelContainer(for: [Route.self], inMemory: true)
}
