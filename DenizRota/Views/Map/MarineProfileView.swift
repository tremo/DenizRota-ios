import SwiftUI
import CoreLocation

// MARK: - Marine Profile Sheet

/// OpenSeaMap'ten haritada seçilen noktadaki deniz işaretlerini gösteren bottom sheet
struct MarineProfileView: View {
    let coordinate: CLLocationCoordinate2D
    let onDismiss: () -> Void

    @State private var items: [SeamarkObject] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)

            // Başlık
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .foregroundStyle(.blue)
                    .font(.body)
                Text("Deniz Profili")
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.4f°N", coordinate.latitude))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.4f°E", coordinate.longitude))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            // İçerik
            Group {
                if isLoading {
                    loadingView
                } else if let error = loadError {
                    errorView(message: error)
                } else if items.isEmpty {
                    emptyView
                } else {
                    itemListView
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .task {
            await loadProfile()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Deniz işaretleri yükleniyor…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Tekrar Dene") {
                Task { await loadProfile() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Bu bölgede deniz işareti bulunamadı")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("600 metre yarıçap içinde OpenSeaMap verisi yok")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var itemListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Özet başlık
                HStack {
                    Text("\(items.count) deniz işareti bulundu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SeamarkRowView(item: item)
                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
        }
        .frame(maxHeight: 340)
    }

    // MARK: - Data Loading

    private func loadProfile() async {
        isLoading = true
        loadError = nil
        do {
            items = try await MarineProfileService.shared.fetchNearby(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            loadError = "Veri yüklenemedi. İnternet bağlantısını kontrol edin."
        }
        isLoading = false
    }
}

// MARK: - Seamark Row

struct SeamarkRowView: View {
    let item: SeamarkObject

    var iconColor: Color {
        switch item.symbolColorName {
        case "red": return .red
        case "yellow": return Color(red: 0.9, green: 0.7, blue: 0)
        case "blue": return .blue
        case "green": return .green
        default: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // İkon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: item.symbolName)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }

            // Bilgiler
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name ?? item.localizedType)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if item.name != nil {
                    Text(item.localizedType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lightChars = item.lightCharacteristics {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption2)
                        Text(lightChars)
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }

                if let vhf = item.vhfChannel {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption2)
                        Text("VHF Ch \(vhf)")
                            .font(.caption)
                    }
                    .foregroundStyle(.purple)
                }
            }

            Spacer()

            // Mesafe
            if let dist = item.distanceMeters {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatDistance(dist))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text("uzaklık")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0fm", meters)
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }
}
