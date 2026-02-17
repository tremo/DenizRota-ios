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

    // Ruzgar partikul overlay (Windy-tarzi)
    @State private var showWindOverlay = false
    @State private var windGridData: [WindGridPoint] = []
    @State private var isLoadingWindGrid = false
    @State private var currentMapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 38.5, longitude: 27.0),
        span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
    )
    @State private var windGridLoadTask: Task<Void, Never>?
    @State private var routeWeatherLoadTask: Task<Void, Never>?

    // Demir alarmi
    @StateObject private var anchorAlarmManager = AnchorAlarmManager.shared

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
                anchorAlarmState: anchorAlarmManager.state,
                anchorCenter: anchorAlarmManager.anchorCenter,
                anchorRadius: anchorAlarmManager.radius,
                isAlarmTriggered: anchorAlarmManager.isAlarmTriggered,
                showWindOverlay: showWindOverlay,
                windData: windGridData,
                onTapCoordinate: { coordinate in
                    addWaypoint(at: coordinate)
                },
                onDeleteWaypoint: { waypoint in
                    deleteWaypoint(waypoint)
                },
                onRegionChanged: { region in
                    currentMapRegion = region
                    scheduleWindGridReload()
                },
                onWaypointMoved: { waypoint, coordinate in
                    moveWaypoint(waypoint, to: coordinate)
                },
                onInsertWaypoint: { coordinate, index in
                    insertWaypoint(at: coordinate, atIndex: index)
                },
                onAnchorCenterChanged: { coordinate in
                    anchorAlarmManager.updateCenter(coordinate)
                },
                onAnchorRadiusChanged: { newRadius in
                    anchorAlarmManager.updateRadius(newRadius)
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

                    // Ruzgar overlay toggle - Sag ust
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showWindOverlay.toggle()
                        }
                        if showWindOverlay {
                            Task { await loadWindGrid() }
                        }
                    } label: {
                        Image(systemName: "wind")
                            .font(.title3)
                            .padding(10)
                            .background(showWindOverlay ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.ultraThinMaterial))
                            .foregroundStyle(showWindOverlay ? .white : .primary)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                            .overlay {
                                if isLoadingWindGrid {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .tint(showWindOverlay ? .white : .blue)
                                }
                            }
                    }

                    // Demir alarmi butonu - Sag ust
                    Button {
                        handleAnchorButtonTap()
                    } label: {
                        Group {
                            if anchorAlarmManager.state == .active {
                                Image(systemName: "stop.fill")
                                    .font(.title3)
                            } else {
                                Text("⚓")
                                    .font(.system(size: 18, weight: .bold))
                            }
                        }
                            .frame(width: 22, height: 22)
                            .padding(10)
                            .background(anchorButtonBackground)
                            .foregroundStyle(anchorButtonForeground)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                            .overlay {
                                if anchorAlarmManager.isAlarmTriggered {
                                    Circle()
                                        .stroke(Color.red, lineWidth: 2)
                                        .scaleEffect(1.3)
                                        .opacity(anchorAlarmManager.isAlarmTriggered ? 1 : 0)
                                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: anchorAlarmManager.isAlarmTriggered)
                                }
                            }
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

                // Demir alarmi tetiklenmis uyarisi
                if anchorAlarmManager.isAlarmTriggered {
                    AnchorAlarmBanner(drift: anchorAlarmManager.currentDrift)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Ruzgar renk skalasi lejanti (sol alt)
                if showWindOverlay && !windGridData.isEmpty {
                    HStack {
                        WindLegendView()
                            .padding(.leading, 16)
                            .transition(.opacity)
                        Spacer()
                    }
                }

                // Demir alarmi aktif durum bilgisi
                if anchorAlarmManager.state == .active {
                    AnchorActiveInfoBar(
                        radius: anchorAlarmManager.radius,
                        drift: anchorAlarmManager.currentDrift
                    )
                    .padding(.horizontal, 16)
                }

                // Demir alarmi draft kontrolleri
                if anchorAlarmManager.state == .drafting {
                    AnchorDraftControlsBar(
                        radius: $anchorAlarmManager.radius,
                        onConfirm: {
                            anchorAlarmManager.activateAlarm()
                            locationManager.startLocationUpdates()
                        },
                        onCancel: {
                            anchorAlarmManager.cancelDrafting()
                            locationManager.stopLocationUpdatesIfNeeded()
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
                    .disabled((activeRoute?.waypoints.isEmpty ?? true) && !locationManager.isTracking)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, showTimelineBar ? 8 : 30)

                // Zaman cubugu (tab bar'in hemen ustunde)
                if showTimelineBar {
                    TimelineBarView(
                        selectedDate: $selectedForecastDate,
                        onDateChanged: { date in
                            onForecastDateChanged(date)
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
        // Otomatik hava durumu guncelleme (15 dakikada bir)
        .onReceive(weatherRefreshTimer) { _ in
            autoRefreshWeather()
        }
        .onAppear {
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

        // Hava durumu verisi yoksa otomatik yukle
        if !route.waypoints.isEmpty {
            let hasWeatherData = route.waypoints.contains { $0.windSpeed != nil }
            if !hasWeatherData {
                Task { await loadWeatherForRoute() }
            }
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

        // Otomatik hava durumu yukle
        Task { await loadWeatherForWaypoint(waypoint) }
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

    private func moveWaypoint(_ waypoint: Waypoint, to coordinate: CLLocationCoordinate2D) {
        waypoint.latitude = coordinate.latitude
        waypoint.longitude = coordinate.longitude

        // Konum degistigi icin hava durumu verisini temizle
        waypoint.windSpeed = nil
        waypoint.windDirection = nil
        waypoint.windGusts = nil
        waypoint.temperature = nil
        waypoint.waveHeight = nil
        waypoint.waveDirection = nil
        waypoint.wavePeriod = nil
        waypoint.riskLevel = .unknown

        activeRoute?.updatedAt = Date()

        // Yeni konum icin otomatik hava durumu yukle
        Task { await loadWeatherForWaypoint(waypoint) }
    }

    private func insertWaypoint(at coordinate: CLLocationCoordinate2D, atIndex index: Int) {
        guard let route = activeRoute else { return }

        // Mevcut waypoint'lerin orderIndex'lerini kaydir
        for waypoint in route.waypoints where waypoint.orderIndex >= index {
            waypoint.orderIndex += 1
        }

        let waypoint = Waypoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            orderIndex: index,
            name: "Nokta \(index + 1)"
        )

        route.waypoints.append(waypoint)
        route.reorderWaypoints()

        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // Otomatik hava durumu yukle
        Task { await loadWeatherForWaypoint(waypoint) }
    }

    // MARK: - Weather

    /// Otomatik hava durumu guncelleme
    /// Aktif rota varsa ve waypoint'ler varsa hava durumunu gunceller
    private func autoRefreshWeather() {
        // Aktif rota varsa ve waypoint'ler varsa guncelle (rota modu veya gosterilen rota)
        guard let route = activeRoute,
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

    /// Tek bir waypoint icin hava durumu yukle (ekleme/tasima sonrasi)
    private func loadWeatherForWaypoint(_ waypoint: Waypoint) async {
        let forecastDate = selectedForecastDate

        waypoint.isLoading = true

        do {
            let weather = try await WeatherService.shared.fetchWeather(for: waypoint.coordinate, date: forecastDate)

            guard !Task.isCancelled else {
                waypoint.isLoading = false
                return
            }

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
            guard !Task.isCancelled else { return }
            await MainActor.run {
                waypoint.isLoading = false
                waypoint.riskLevel = .unknown
            }
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
            // Iptal edildiyse erken cik (race condition onlemi)
            guard !Task.isCancelled else { break }

            do {
                let weather = try await WeatherService.shared.fetchWeather(for: waypoint.coordinate, date: forecastDate)

                // Iptal edildiyse sonucu yazma (eski veri ustune yazmayı onle)
                guard !Task.isCancelled else { break }

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
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    waypoint.isLoading = false
                    waypoint.riskLevel = .unknown
                }
            }
        }

        isLoadingWeather = false
        lastWeatherUpdate = Date()
    }

    /// Zaman cubugu degistiginde cagirilir - hava durumunu gunceller
    private func onForecastDateChanged(_ date: Date) {
        // Aktif rota varsa hava durumunu guncelle (onceki istegi iptal et)
        if let route = activeRoute, !route.waypoints.isEmpty {
            routeWeatherLoadTask?.cancel()
            routeWeatherLoadTask = Task { await loadWeatherForRoute() }
        }

        // Ruzgar overlay aktifse grid verisini de guncelle
        if showWindOverlay {
            Task { await loadWindGrid() }
        }
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

    // MARK: - Anchor Alarm

    private var anchorButtonBackground: AnyShapeStyle {
        switch anchorAlarmManager.state {
        case .idle:
            return AnyShapeStyle(.ultraThinMaterial)
        case .drafting:
            return AnyShapeStyle(Color.orange)
        case .active:
            return anchorAlarmManager.isAlarmTriggered
                ? AnyShapeStyle(Color.red)
                : AnyShapeStyle(Color.green)
        }
    }

    private var anchorButtonForeground: Color {
        anchorAlarmManager.state == .idle ? .primary : .white
    }

    private func handleAnchorButtonTap() {
        switch anchorAlarmManager.state {
        case .idle:
            // Draft modunu baslat - mevcut konumu merkez al
            guard let location = locationManager.currentLocation else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                anchorAlarmManager.startDrafting(at: location.coordinate)
            }
            locationManager.startLocationUpdates()

        case .drafting:
            // Draft modundayken tekrar basilirsa iptal et
            withAnimation(.easeInOut(duration: 0.25)) {
                anchorAlarmManager.cancelDrafting()
            }
            locationManager.stopLocationUpdatesIfNeeded()

        case .active:
            // Aktif alarmi durdur
            withAnimation(.easeInOut(duration: 0.25)) {
                anchorAlarmManager.deactivateAlarm()
            }
            locationManager.stopLocationUpdatesIfNeeded()
        }
    }

    // MARK: - Wind Grid

    /// Ruzgar grid verisini yukle (Windy-tarzi animasyon icin)
    private func loadWindGrid() async {
        // Zaten yukleme varsa bekle (scheduleWindGridReload iptal mekanizmasini kullanir)
        guard !isLoadingWindGrid else { return }
        isLoadingWindGrid = true

        let region = currentMapRegion
        let date = selectedForecastDate

        let data = await WeatherGridLoader.shared.loadWindGrid(
            for: region,
            date: date
        )

        // Iptal edildiyse sonucu yazma
        guard !Task.isCancelled else {
            isLoadingWindGrid = false
            return
        }

        await MainActor.run {
            windGridData = data
            isLoadingWindGrid = false
        }
    }

    /// Harita bolge degisikliklerinde debounce ile grid yeniden yukle
    private func scheduleWindGridReload() {
        guard showWindOverlay else { return }

        windGridLoadTask?.cancel()
        isLoadingWindGrid = false // Onceki yuklemeyi sifirla, yenisi baslasin
        windGridLoadTask = Task {
            // 1.5 saniye bekle (gereksiz API cagrilarini onle)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await loadWindGrid()
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

// MARK: - Anchor Alarm Banner (tetiklenmis uyari)

struct AnchorAlarmBanner: View {
    let drift: Double

    @State private var isFlashing = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("DEMIR TARAMA!")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("Tekne \(Int(drift))m uzaklasti")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.red)
                .opacity(isFlashing ? 1.0 : 0.7)
        )
        .shadow(color: .red.opacity(0.4), radius: 8, y: 2)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                isFlashing = true
            }
        }
    }
}

// MARK: - Anchor Active Info Bar

struct AnchorActiveInfoBar: View {
    let radius: Double
    let drift: Double

    var body: some View {
        HStack(spacing: 12) {
            Text("⚓")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.green)

            Text("Demir Alarmi Aktif")
                .font(.subheadline.bold())

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Yaricap: \(Int(radius))m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Sapma: \(Int(drift))m")
                    .font(.caption)
                    .foregroundStyle(drift > radius * 0.7 ? .orange : .secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Anchor Draft Controls Bar

struct AnchorDraftControlsBar: View {
    @Binding var radius: Double

    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Yaricap slider
            HStack(spacing: 12) {
                Image(systemName: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(value: $radius, in: 10...500, step: 5)
                    .tint(.blue)

                Text("\(Int(radius))m")
                    .font(.subheadline.bold())
                    .frame(width: 50, alignment: .trailing)
            }

            // Butonlar
            HStack(spacing: 16) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onCancel()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                        Text("Vazgec")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onConfirm()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("Alarmi Kur")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .clipShape(Capsule())
                    .shadow(radius: 2)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    MapView(routeToShow: .constant(nil))
        .environmentObject(LocationManager.shared)
        .modelContainer(for: [Route.self, Trip.self, BoatSettings.self], inMemory: true)
}
