import SwiftUI
import MapKit
import SwiftData
import Combine

struct MapView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var locationManager: LocationManager
    @Query(sort: \Route.updatedAt, order: .reverse) private var routes: [Route]

    // Dışarıdan gelen rota (kayıtlı rotalardan seçilen)
    @Binding var routeToShow: Route?

    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 38.5, longitude: 27.0), // Ege
        span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
    )

    // Harita tipi
    @State private var mapStyle: MapStyleOption = .hybrid
    @State private var showOpenSeaMap = true

    @State private var isRouteMode = false
    @State private var activeRoute: Route?
    @State private var showingSaveRouteAlert = false
    @State private var newRouteName = ""

    // Zaman cubugu (Windy-tarzi)
    @State private var showTimelineBar = false
    @State private var selectedForecastDate = Date()

    // Hava durumu
    @State private var isLoadingWeather = false
    @State private var lastWeatherUpdate: Date?

    // Korunakli koy analizi
    @State private var shelterResults: [CoveShelterResult] = []
    @State private var showingShelterSheet = false
    @State private var isShelterModeActive = false

    // Otomatik hava durumu guncelleme timer'i (15 dakika)
    private let weatherRefreshTimer = Timer.publish(
        every: AppConstants.weatherAutoRefreshInterval,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        ZStack {
            // Harita
            NauticalMapView(
                region: mapRegion,
                mapStyle: mapStyle,
                showOpenSeaMap: showOpenSeaMap,
                userLocation: locationManager.currentLocation,
                activeRoute: activeRoute,
                isRouteMode: isRouteMode,
                shelterResults: isShelterModeActive ? shelterResults : [],
                onTapCoordinate: { coordinate in
                    addWaypoint(at: coordinate)
                },
                onDeleteWaypoint: { waypoint in
                    deleteWaypoint(waypoint)
                }
            )
            .ignoresSafeArea(edges: .top)

            // UI Overlay
            VStack {
                // Ust bilgi paneli
                HStack(alignment: .top) {
                    // Hiz paneli (seyir aktifken) - Sol ust
                    if locationManager.isTracking {
                        SpeedPanelView(speed: locationManager.currentSpeed)
                            .padding(.leading, 16)
                            .padding(.top, 8)
                    }

                    Spacer()

                    VStack(spacing: 8) {
                    // Harita tipi secici - Sag ust
                    Menu {
                        ForEach(MapStyleOption.allCases) { style in
                            Button {
                                mapStyle = style
                            } label: {
                                Label(style.rawValue, systemImage: style.icon)
                            }
                        }

                        Divider()

                        Toggle(isOn: $showOpenSeaMap) {
                            Label("Deniz Haritasi", systemImage: "water.waves")
                        }
                    } label: {
                        Image(systemName: "map.fill")
                            .font(.title3)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                    // Zaman cubugu toggle - Sag ust
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showTimelineBar.toggle()
                        }
                    } label: {
                        Image(systemName: showTimelineBar ? "calendar.circle.fill" : "calendar.circle")
                            .font(.title3)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }

                // Rota bilgi cubugu
                if let route = activeRoute {
                    RouteInfoBar(route: route, isSaved: route.name != "Yeni Rota")
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                Spacer()

                // Zaman cubugu (Windy-tarzi)
                if showTimelineBar {
                    TimelineBarView(
                        selectedDate: $selectedForecastDate,
                        onDateChanged: { date in
                            onForecastDateChanged(date)
                        }
                    )
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Alt butonlar
                HStack(spacing: 16) {
                    // Rota modu toggle
                    Button {
                        toggleRouteMode()
                    } label: {
                        Image(systemName: isRouteMode ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.title2)
                            .padding(12)
                            .background(isRouteMode ? .blue : Color(.systemBackground))
                            .foregroundStyle(isRouteMode ? .white : .blue)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }

                    // Hava durumu yukle (aktif rota varsa)
                    if let route = activeRoute, !route.waypoints.isEmpty {
                        Button {
                            Task { await loadWeatherForRoute() }
                        } label: {
                            Image(systemName: isLoadingWeather ? "arrow.clockwise" : "cloud.sun")
                                .font(.title2)
                                .padding(12)
                                .background(Color(.systemBackground))
                                .foregroundStyle(.orange)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                                .rotationEffect(.degrees(isLoadingWeather ? 360 : 0))
                                .animation(isLoadingWeather ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoadingWeather)
                        }
                        .disabled(isLoadingWeather)
                    }

                    // Korunakli koylar butonu
                    Button {
                        toggleShelterMode()
                    } label: {
                        Image(systemName: "shield.checkered")
                            .font(.title2)
                            .padding(12)
                            .background(isShelterModeActive ? .green : Color(.systemBackground))
                            .foregroundStyle(isShelterModeActive ? .white : .teal)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }

                    // Korunakli koylar listesi (aktifken)
                    if isShelterModeActive && !shelterResults.isEmpty {
                        Button {
                            showingShelterSheet = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.title2)
                                .padding(12)
                                .background(Color(.systemBackground))
                                .foregroundStyle(.teal)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                    }

                    // Rota kaydet (sadece kaydedilmemis rotalar icin)
                    if let route = activeRoute, !route.waypoints.isEmpty, route.name == "Yeni Rota" {
                        Button {
                            showingSaveRouteAlert = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                                .padding(12)
                                .background(Color(.systemBackground))
                                .foregroundStyle(.green)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                    }

                    // Son waypoint'i sil (rota modunda)
                    if isRouteMode, let route = activeRoute, !route.waypoints.isEmpty {
                        Button {
                            undoLastWaypoint()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.title2)
                                .padding(12)
                                .background(Color(.systemBackground))
                                .foregroundStyle(.red)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                    }

                    // Rotayi temizle/kapat
                    if activeRoute != nil && !isRouteMode {
                        Button {
                            clearActiveRoute()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .padding(12)
                                .background(Color(.systemBackground))
                                .foregroundStyle(.gray)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                    }

                    Spacer()

                    // Seyir baslat/bitir
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
                    .disabled(activeRoute?.waypoints.isEmpty ?? true && !locationManager.isTracking)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }

            // Konum izni uyarisi
            if !locationManager.hasAnyPermission {
                PermissionOverlay()
            }
        }
        .alert("Rotayi Kaydet", isPresented: $showingSaveRouteAlert) {
            TextField("Rota Adi", text: $newRouteName)
            Button("Kaydet") {
                saveRoute()
            }
            Button("Iptal", role: .cancel) {
                newRouteName = ""
            }
        } message: {
            Text("Rotaniz icin bir isim girin")
        }
        .sheet(isPresented: $showingShelterSheet) {
            ShelterListSheet(results: shelterResults)
                .presentationDetents([.medium, .large])
        }
        // Otomatik hava durumu guncelleme (15 dakikada bir)
        .onReceive(weatherRefreshTimer) { _ in
            autoRefreshWeather()
        }
        .onAppear {
            // Ilk yuklemede hava durumunu kontrol et
            autoRefreshWeather()
        }
        // Kayitli rotadan secilen rotayi haritada goster
        .onChange(of: routeToShow) { oldValue, newValue in
            if let route = newValue {
                showRouteOnMap(route)
            }
        }
    }

    /// Secilen rotayi haritada goster ve kamerayi ayarla
    private func showRouteOnMap(_ route: Route) {
        activeRoute = route
        isRouteMode = false

        // Kamerayi rotaya odakla
        if let firstWaypoint = route.sortedWaypoints.first {
            mapRegion = MKCoordinateRegion(
                center: firstWaypoint.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }
    }

    // MARK: - Route Mode

    private func toggleRouteMode() {
        isRouteMode.toggle()

        if isRouteMode && activeRoute == nil {
            // Yeni rota olustur
            let route = Route(name: "Yeni Rota")
            modelContext.insert(route)
            activeRoute = route
        }

        if !isRouteMode {
            // Rota modu kapatildiginda bos rotayi sil, ama waypoint varsa rotayi koru
            if let route = activeRoute, route.waypoints.isEmpty {
                modelContext.delete(route)
                activeRoute = nil
            }
            // Waypoint'li rota haritada kalmaya devam eder
        }
    }

    /// Aktif rotayi haritadan kaldir
    private func clearActiveRoute() {
        if let route = activeRoute {
            // Kaydedilmemis rotayi sil
            if route.name == "Yeni Rota" {
                modelContext.delete(route)
            }
        }
        activeRoute = nil
        routeToShow = nil
    }

    // MARK: - Waypoint Management

    private func addWaypoint(at coordinate: CLLocationCoordinate2D) {
        guard let route = activeRoute else { return }

        let waypoint = Waypoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            orderIndex: route.waypoints.count,
            name: "Nokta \(route.waypoints.count + 1)"
        )

        route.waypoints.append(waypoint)
        route.updatedAt = Date()

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func deleteWaypoint(_ waypoint: Waypoint) {
        guard let route = activeRoute else { return }
        route.removeWaypoint(waypoint)
        modelContext.delete(waypoint)
    }

    private func undoLastWaypoint() {
        guard let route = activeRoute,
              let lastWaypoint = route.sortedWaypoints.last else { return }

        deleteWaypoint(lastWaypoint)
    }

    // MARK: - Weather

    /// Otomatik hava durumu guncelleme
    /// Aktif rota varsa ve waypoint'ler varsa hava durumunu gunceller
    private func autoRefreshWeather() {
        // Sadece rota modu aktifken ve waypoint varsa guncelle
        guard isRouteMode,
              let route = activeRoute,
              !route.waypoints.isEmpty,
              !isLoadingWeather else { return }

        // Son guncellemeden bu yana yeterli sure gectiyse guncelle
        if let lastUpdate = lastWeatherUpdate {
            let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
            // En az 5 dakika gecmis olmali (gereksiz cagrilari onle)
            guard timeSinceLastUpdate >= 300 else { return }
        }

        Task {
            await loadWeatherForRoute()
        }
    }

    private func loadWeatherForRoute() async {
        guard let route = activeRoute else { return }

        isLoadingWeather = true
        let forecastDate = selectedForecastDate

        for waypoint in route.waypoints {
            waypoint.isLoading = true
        }

        // Her waypoint icin hava durumu (secilen tarihe gore)
        for waypoint in route.waypoints {
            do {
                let weather = try await WeatherService.shared.fetchWeather(for: waypoint.coordinate, date: forecastDate)

                await MainActor.run {
                    waypoint.windSpeed = weather.windSpeed
                    waypoint.windDirection = weather.windDirection
                    waypoint.windGusts = weather.windGusts
                    waypoint.temperature = weather.temperature
                    waypoint.waveHeight = weather.waveHeight
                    waypoint.waveDirection = weather.waveDirection
                    waypoint.wavePeriod = weather.wavePeriod
                    waypoint.riskLevel = weather.riskLevel
                    waypoint.isLoading = false
                }
            } catch {
                await MainActor.run {
                    waypoint.isLoading = false
                    waypoint.riskLevel = .unknown
                }
            }
        }

        isLoadingWeather = false
        lastWeatherUpdate = Date()
    }

    /// Zaman cubugu degistiginde cagirilir - hava durumu ve korunak analizini gunceller
    private func onForecastDateChanged(_ date: Date) {
        // Aktif rota varsa hava durumunu guncelle
        if let route = activeRoute, !route.waypoints.isEmpty {
            Task { await loadWeatherForRoute() }
        }

        // Korunak modu aktifse yeniden analiz et
        if isShelterModeActive {
            refreshShelterAnalysis()
        }
    }

    // MARK: - Shelter Analysis

    private func toggleShelterMode() {
        if isShelterModeActive {
            // Kapat
            isShelterModeActive = false
            shelterResults = []
            return
        }

        refreshShelterAnalysis()
    }

    /// Korunak analizini secilen tarihe gore yeniden calistir
    private func refreshShelterAnalysis() {
        // Rüzgar verisini al - aktif rotadaki waypoint'lerden veya mevcut konumdan
        var windDirection: Double?
        var windSpeed: Double?

        // Önce aktif rotadaki waypoint'lerden rüzgar verisini dene
        if let route = activeRoute {
            for wp in route.waypoints {
                if let dir = wp.windDirection, let spd = wp.windSpeed {
                    windDirection = dir
                    windSpeed = spd
                    break
                }
            }
        }

        // Rüzgar verisi yoksa API'den çek (secilen tarih ile)
        if windDirection == nil {
            Task {
                do {
                    let coordinate = locationManager.currentLocation?.coordinate ??
                        CLLocationCoordinate2D(latitude: mapRegion.center.latitude, longitude: mapRegion.center.longitude)
                    let weather = try await WeatherService.shared.fetchWeather(for: coordinate, date: selectedForecastDate)
                    await MainActor.run {
                        shelterResults = ShelterAnalyzer.shared.analyzeAllCoves(
                            windDirection: weather.windDirection,
                            windSpeed: weather.windSpeed
                        )
                        isShelterModeActive = true
                    }
                } catch {
                    await MainActor.run {
                        shelterResults = ShelterAnalyzer.shared.analyzeAllCoves(
                            windDirection: 0,
                            windSpeed: 15
                        )
                        isShelterModeActive = true
                    }
                }
            }
            return
        }

        // Rüzgar verisi varsa doğrudan analiz et
        shelterResults = ShelterAnalyzer.shared.analyzeAllCoves(
            windDirection: windDirection!,
            windSpeed: windSpeed!
        )
        isShelterModeActive = true
    }

    // MARK: - Trip

    private func startTrip() {
        guard let route = activeRoute else { return }
        let waypoints = route.sortedWaypoints
        locationManager.startTracking(waypoints: waypoints)
    }

    private func stopTrip() {
        if let result = locationManager.stopTracking() {
            // Trip kaydet
            let trip = Trip(startDate: result.startTime)
            trip.endDate = result.endTime
            trip.maxSpeed = result.maxSpeed

            // Pozisyonlari ekle
            for location in result.positions {
                let position = TripPosition(location: location)
                trip.positions.append(position)
            }

            // Istatistikleri hesapla
            trip.calculateStats(fuelRate: 20, fuelPrice: 45)

            modelContext.insert(trip)

            print("Trip saved: \(trip.distance) km, \(trip.positions.count) positions")
        }
    }

    // MARK: - Save Route

    private func saveRoute() {
        guard let route = activeRoute else { return }

        if !newRouteName.isEmpty {
            route.name = newRouteName
        }

        route.updatedAt = Date()
        newRouteName = ""

        // Rota modunu kapat, rota haritada kalmaya devam etsin
        isRouteMode = false
        // activeRoute korunuyor, haritada goruntuleniyor
    }
}

// MARK: - User Location Marker

struct UserLocationMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.blue.opacity(0.2))
                .frame(width: 60, height: 60)

            Circle()
                .fill(.blue)
                .frame(width: 16, height: 16)

            Circle()
                .stroke(.white, lineWidth: 3)
                .frame(width: 16, height: 16)
        }
    }
}

// MARK: - Route Info Bar

struct RouteInfoBar: View {
    let route: Route
    var isSaved: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            // Rota adi (kayitliysa)
            if isSaved {
                Text(route.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }

            // Nokta sayisi
            Label("\(route.waypoints.count)", systemImage: "mappin")
                .font(.subheadline.bold())

            // Mesafe
            Label(String(format: "%.1f km", route.totalDistance), systemImage: "arrow.left.and.right")
                .font(.subheadline.bold())

            // Sure
            let duration = route.estimatedDuration()
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            Label("\(hours)s \(minutes)d", systemImage: "clock")
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Waypoint Marker

struct WaypointMarkerView: View {
    let number: Int
    let riskLevel: RiskLevel
    var isLoading: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(riskColor)
                .frame(width: 32, height: 32)
                .shadow(radius: 2)

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.7)
            } else {
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
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

            Text("Konum Izni Gerekli")
                .font(.title2.bold())

            Text("Seyir takibi ve rota olusturma icin konum erismine izin vermeniz gerekiyor.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Izin Ver") {
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

// MARK: - Shelter List Sheet

struct ShelterListSheet: View {
    let results: [CoveShelterResult]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let first = results.first {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "wind")
                                .foregroundStyle(.blue)
                            Text("Rüzgar: \(Int(first.windSpeed)) km/h \(first.windDirection.windDirectionText)")
                                .font(.subheadline)
                        }
                    }
                }

                ForEach(ShelterLevel.allCases, id: \.self) { level in
                    let filtered = results.filter { $0.shelterLevel == level }
                    if !filtered.isEmpty {
                        Section(header: shelterSectionHeader(level: level, count: filtered.count)) {
                            ForEach(filtered) { result in
                                ShelterCoveRow(result: result)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Korunaklı Koylar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    private func shelterSectionHeader(level: ShelterLevel, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: level.icon)
                .foregroundStyle(level.color)
            Text("\(level.rawValue) (\(count))")
                .foregroundStyle(level.color)
        }
    }
}

struct ShelterCoveRow: View {
    let result: CoveShelterResult

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(result.shelterLevel.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.cove.name)
                    .font(.subheadline.bold())
                Text(result.shelterLevel.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Koy ağız yönü
            VStack(alignment: .trailing, spacing: 2) {
                Text("Ağız: \(result.cove.mouthDirection.windDirectionText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.4f, %.4f", result.cove.latitude, result.cove.longitude))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    MapView(routeToShow: .constant(nil))
        .environmentObject(LocationManager.shared)
        .modelContainer(for: [Route.self, Trip.self, BoatSettings.self], inMemory: true)
}
