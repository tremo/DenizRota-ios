import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [BoatSettings]

    @State private var boatName = "Teknem"
    @State private var selectedBoatType: BoatType = .motorlu
    @State private var avgSpeed: Double = 15
    @State private var fuelRate: Double = 20
    @State private var tankCapacity: Double = 200
    @State private var fuelPrice: Double = 45

    @State private var showingSaveAlert = false

    private var settings: BoatSettings? {
        settingsList.first
    }

    var body: some View {
        Form {
            // Tekne Bilgileri
            Section("Tekne Bilgileri") {
                TextField("Tekne Adı", text: $boatName)

                Picker("Tekne Tipi", selection: $selectedBoatType) {
                    ForEach(BoatType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }

            // Performans
            Section("Performans") {
                HStack {
                    Text("Ortalama Hız")
                    Spacer()
                    TextField("", value: $avgSpeed, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("km/h")
                        .foregroundStyle(.secondary)
                }
            }

            // Yakıt
            Section("Yakıt") {
                HStack {
                    Text("Yakıt Tüketimi")
                    Spacer()
                    TextField("", value: $fuelRate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("L/saat")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Depo Kapasitesi")
                    Spacer()
                    TextField("", value: $tankCapacity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("L")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Yakıt Fiyatı")
                    Spacer()
                    TextField("", value: $fuelPrice, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("₺/L")
                        .foregroundStyle(.secondary)
                }
            }

            // Konum İzinleri
            Section("Konum") {
                NavigationLink {
                    LocationPermissionView()
                } label: {
                    HStack {
                        Text("Konum İzinleri")
                        Spacer()
                        Text(permissionStatus)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Kaydet
            Section {
                Button("Ayarları Kaydet") {
                    saveSettings()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            loadSettings()
        }
        .alert("Kaydedildi", isPresented: $showingSaveAlert) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text("Ayarlarınız başarıyla kaydedildi.")
        }
    }

    private var permissionStatus: String {
        switch LocationManager.shared.authorizationStatus {
        case .authorizedAlways: return "Her Zaman"
        case .authorizedWhenInUse: return "Kullanırken"
        case .denied: return "Reddedildi"
        case .restricted: return "Kısıtlı"
        case .notDetermined: return "Belirlenmedi"
        @unknown default: return "Bilinmiyor"
        }
    }

    private func loadSettings() {
        guard let settings = settings else { return }
        boatName = settings.boatName
        selectedBoatType = settings.boatType
        avgSpeed = settings.avgSpeed
        fuelRate = settings.fuelRate
        tankCapacity = settings.tankCapacity
        fuelPrice = settings.fuelPrice
    }

    private func saveSettings() {
        if let existing = settings {
            existing.boatName = boatName
            existing.boatType = selectedBoatType
            existing.avgSpeed = avgSpeed
            existing.fuelRate = fuelRate
            existing.tankCapacity = tankCapacity
            existing.fuelPrice = fuelPrice
        } else {
            let newSettings = BoatSettings()
            newSettings.boatName = boatName
            newSettings.boatType = selectedBoatType
            newSettings.avgSpeed = avgSpeed
            newSettings.fuelRate = fuelRate
            newSettings.tankCapacity = tankCapacity
            newSettings.fuelPrice = fuelPrice
            modelContext.insert(newSettings)
        }

        showingSaveAlert = true
    }
}

// MARK: - Location Permission View

struct LocationPermissionView: View {
    @EnvironmentObject var locationManager: LocationManager

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text("Ekran kapalıyken seyir takibi")
                    } icon: {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                    }

                    Label {
                        Text("Hedefe varış bildirimleri")
                    } icon: {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.orange)
                    }

                    Label {
                        Text("Rota sapma uyarıları")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Sürekli konum izni şunlar için gerekli:")
            }

            Section {
                HStack {
                    Text("Mevcut Durum")
                    Spacer()
                    Text(statusText)
                        .foregroundStyle(statusColor)
                }

                if !locationManager.hasAlwaysPermission {
                    Button("Ayarları Aç") {
                        openSettings()
                    }
                }
            } header: {
                Text("İzin Durumu")
            } footer: {
                Text("'Her Zaman' seçeneğini seçmeniz önerilir. Ayarlar > DenizRota > Konum bölümünden değiştirebilirsiniz.")
            }
        }
        .navigationTitle("Konum İzinleri")
    }

    private var statusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return "Her Zaman ✓"
        case .authorizedWhenInUse: return "Sadece Kullanırken"
        case .denied: return "Reddedildi"
        case .restricted: return "Kısıtlı"
        case .notDetermined: return "Belirlenmedi"
        @unknown default: return "Bilinmiyor"
        }
    }

    private var statusColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return .green
        case .authorizedWhenInUse: return .orange
        default: return .red
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: BoatSettings.self, inMemory: true)
    .environmentObject(LocationManager.shared)
}
