import SwiftUI
import SwiftData
import MapKit

struct TripHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]

    @State private var selectedTrip: Trip?
    @State private var showingDeleteAlert = false
    @State private var tripToDelete: Trip?

    var body: some View {
        Group {
            if trips.isEmpty {
                EmptyTripsView()
            } else {
                List {
                    // Istatistikler
                    Section("Toplam Istatistikler") {
                        HStack {
                            StatCard(
                                title: "Seyir",
                                value: "\(trips.count)",
                                icon: "location.circle"
                            )

                            StatCard(
                                title: "Mesafe",
                                value: String(format: "%.0f km", totalDistance),
                                icon: "arrow.left.and.right"
                            )

                            StatCard(
                                title: "Sure",
                                value: totalDurationText,
                                icon: "clock"
                            )
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    // Seyir listesi
                    Section("Gecmis Seyirler") {
                        ForEach(trips) { trip in
                            TripRowView(trip: trip)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedTrip = trip
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        tripToDelete = trip
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("Sil", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .sheet(item: $selectedTrip) { trip in
            TripDetailView(trip: trip)
        }
        .alert("Seyiri Sil", isPresented: $showingDeleteAlert) {
            Button("Sil", role: .destructive) {
                if let trip = tripToDelete {
                    deleteTrip(trip)
                }
            }
            Button("Iptal", role: .cancel) {
                tripToDelete = nil
            }
        } message: {
            Text("Bu seyir kaydini silmek istediginizden emin misiniz?")
        }
    }

    private var totalDistance: Double {
        trips.reduce(0) { $0 + $1.distance }
    }

    private var totalDuration: TimeInterval {
        trips.reduce(0) { $0 + $1.duration }
    }

    private var totalDurationText: String {
        let hours = Int(totalDuration / 3600)
        return "\(hours)s"
    }

    private func deleteTrip(_ trip: Trip) {
        modelContext.delete(trip)
        tripToDelete = nil
    }
}

// MARK: - Empty State

struct EmptyTripsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Seyir Yok", systemImage: "location.circle")
        } description: {
            Text("Henuz kayitli seyiriniz yok. Harita sekmesinde bir seyir baslatarak kayit olusturabilirsiniz.")
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)

            Text(value)
                .font(.headline)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Trip Row

struct TripRowView: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(trip.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)

                Spacer()

                // Sure
                let hours = Int(trip.duration / 3600)
                let minutes = Int((trip.duration.truncatingRemainder(dividingBy: 3600)) / 60)
                Text("\(hours)s \(minutes)d")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label(String(format: "%.1f km", trip.distance), systemImage: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(String(format: "%.1f km/h", trip.avgSpeed), systemImage: "speedometer")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(String(format: "Max %.1f", trip.maxSpeed), systemImage: "gauge.high")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if trip.fuelUsed > 0 {
                HStack(spacing: 16) {
                    Label(String(format: "%.1f L", trip.fuelUsed), systemImage: "fuelpump")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Label(String(format: "%.0f TL", trip.fuelCost), systemImage: "turkishlirasign.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Trip Detail View

struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Harita
                    if !trip.positions.isEmpty {
                        Map(position: $cameraPosition) {
                            // Rota cizgisi
                            MapPolyline(coordinates: trip.positions.map(\.coordinate))
                                .stroke(.blue, lineWidth: 3)

                            // Baslangic noktasi
                            if let first = trip.positions.first {
                                Annotation("Baslangic", coordinate: first.coordinate) {
                                    Image(systemName: "flag.fill")
                                        .foregroundStyle(.green)
                                }
                            }

                            // Bitis noktasi
                            if let last = trip.positions.last {
                                Annotation("Bitis", coordinate: last.coordinate) {
                                    Image(systemName: "flag.checkered")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }

                    // Istatistikler
                    VStack(spacing: 16) {
                        // Mesafe ve Sure
                        HStack(spacing: 20) {
                            DetailStatView(
                                title: "Mesafe",
                                value: String(format: "%.2f km", trip.distance),
                                icon: "arrow.left.and.right",
                                color: .blue
                            )

                            let hours = Int(trip.duration / 3600)
                            let minutes = Int((trip.duration.truncatingRemainder(dividingBy: 3600)) / 60)
                            DetailStatView(
                                title: "Sure",
                                value: "\(hours)s \(minutes)d",
                                icon: "clock",
                                color: .purple
                            )
                        }

                        // Hiz
                        HStack(spacing: 20) {
                            DetailStatView(
                                title: "Ort. Hiz",
                                value: String(format: "%.1f km/h", trip.avgSpeed),
                                icon: "speedometer",
                                color: .green
                            )

                            DetailStatView(
                                title: "Max Hiz",
                                value: String(format: "%.1f km/h", trip.maxSpeed),
                                icon: "gauge.high",
                                color: .orange
                            )
                        }

                        // Yakit
                        if trip.fuelUsed > 0 {
                            HStack(spacing: 20) {
                                DetailStatView(
                                    title: "Yakit",
                                    value: String(format: "%.1f L", trip.fuelUsed),
                                    icon: "fuelpump",
                                    color: .red
                                )

                                DetailStatView(
                                    title: "Maliyet",
                                    value: String(format: "%.0f TL", trip.fuelCost),
                                    icon: "turkishlirasign.circle",
                                    color: .red
                                )
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Pozisyon sayisi
                    Text("\(trip.positions.count) GPS noktasi kaydedildi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical)
            }
            .navigationTitle("Seyir Detayi")
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

// MARK: - Detail Stat View

struct DetailStatView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.headline)
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        TripHistoryView()
    }
    .modelContainer(for: [Trip.self], inMemory: true)
}
