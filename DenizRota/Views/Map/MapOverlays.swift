import SwiftUI
import MapKit

// MARK: - Wind Overlay View
/// Windy-tarzi ruzgar partikul animasyonu overlay'i
/// 5 seviyeli renk skalasi: Yesil -> Sari -> Turuncu -> Kirmizi -> Koyu Kirmizi
struct WindOverlayView: View {
    let windData: [WindGridPoint]
    let mapRegion: MKCoordinateRegion
    let mapHeading: Double
    @State private var particles: [WindParticle] = []
    @State private var animationTimer: Timer?
    @State private var viewSize: CGSize = .zero
    // Timer closure struct'i yakalayinca let property'ler (windData, mapRegion,
    // mapHeading) eski kalir. @State ise SwiftUI storage uzerinden her zaman guncel
    // deger dondurur, bu yuzden timer'dan erisilenler @State kopyasina alinir.
    @State private var activeWindData: [WindGridPoint] = []
    @State private var activeMapRegion: MKCoordinateRegion = MKCoordinateRegion()
    @State private var activeHeading: Double = 0

    private let particleCount = 800

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawParticles(context: context, size: size)
            }
            .onAppear {
                viewSize = geometry.size
                activeWindData = windData
                activeMapRegion = mapRegion
                activeHeading = mapHeading
                initializeParticles(in: geometry.size)
                startAnimation()
            }
            .onDisappear {
                animationTimer?.invalidate()
                animationTimer = nil
            }
            .onChange(of: geometry.size) { _, newSize in
                viewSize = newSize
                initializeParticles(in: newSize)
            }
            .onChange(of: windData) { _, newData in
                activeWindData = newData
                activeMapRegion = mapRegion
                // Eski yondeki kuyruk izlerini temizle, yeni yone hemen gecis
                for i in particles.indices {
                    particles[i].trail = []
                }
            }
            .onChange(of: mapHeading) { _, newHeading in
                activeHeading = newHeading
                activeMapRegion = mapRegion
                // Harita dondurulunce eski yondeki kuyruk izlerini temizle
                for i in particles.indices {
                    particles[i].trail = []
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Rendering

    private func drawParticles(context: GraphicsContext, size: CGSize) {
        for particle in particles {
            guard particle.trail.count > 1 else { continue }
            guard let wind = getWindAtPoint(particle.position, in: size) else { continue }

            let color = windColor(for: wind.speed)
            let lifeRatio = particle.age / particle.maxAge
            let fadeAlpha = max(0, 1.0 - lifeRatio)

            // Trail: her segment icin ayrı opacity ile gradient efekti
            let trailPoints = particle.trail + [particle.position]
            let segmentCount = trailPoints.count - 1
            guard segmentCount > 0 else { continue }

            for s in 0..<segmentCount {
                // Trail basinda dusuk opacity, sonuna dogru artan
                let segmentRatio = Double(s) / Double(segmentCount)
                let segmentAlpha = segmentRatio * fadeAlpha * 0.85

                var segPath = Path()
                segPath.move(to: trailPoints[s])
                segPath.addLine(to: trailPoints[s + 1])

                // Ruzgar hizina gore cizgi kalinligi: 1.0 (hafif) - 2.5 (firtina)
                let lineWidth = max(1.0, min(2.5, wind.speed / 20.0 + 0.8))

                context.stroke(
                    segPath,
                    with: .color(color.opacity(segmentAlpha)),
                    lineWidth: lineWidth
                )
            }

            // Partikul basi - parlak nokta
            let headAlpha = fadeAlpha * 0.95
            let headSize = max(2.0, min(3.5, wind.speed / 20.0 + 1.5))
            let headRect = CGRect(
                x: particle.position.x - headSize / 2,
                y: particle.position.y - headSize / 2,
                width: headSize,
                height: headSize
            )
            context.fill(
                Path(ellipseIn: headRect),
                with: .color(color.opacity(headAlpha))
            )
        }
    }

    // MARK: - Particle System

    private func initializeParticles(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        particles = (0..<particleCount).map { _ in
            WindParticle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height)
                ),
                age: Double.random(in: 0...60),
                maxAge: Double.random(in: 40...100)
            )
        }
    }

    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            updateParticles()
        }
    }

    private func updateParticles() {
        let size = viewSize
        guard size.width > 0, size.height > 0 else { return }

        for i in particles.indices {
            guard let wind = getWindAtPoint(particles[i].position, in: size) else {
                resetParticle(&particles[i], in: size)
                continue
            }

            // Ruzgar yonu -> ekran-hizali hiz vektoru (harita heading'i duzeltmesi ile)
            let dirRad = ((wind.direction + 180 - activeHeading) * .pi) / 180.0

            // Ruzgar hizina orantili partikul hizi (Windy-tarzi: hizli ruzgar = hizli partikul)
            let speedFactor = max(0.5, wind.speed / 4.0)

            // Hamle (gust) varsa turbelans ekle
            let gustDiff = wind.gusts - wind.speed
            let turbulence: CGFloat = gustDiff > 8 ?
                CGFloat.random(in: -0.25...0.25) * (gustDiff / 30.0) : 0

            let dx = sin(dirRad + turbulence) * speedFactor
            let dy = -cos(dirRad + turbulence) * speedFactor

            // Trail guncelle - hizli ruzgarda daha uzun kuyruk
            let maxTrailLength = Int(max(6, min(16, wind.speed / 3.0)))
            particles[i].trail.append(particles[i].position)
            while particles[i].trail.count > maxTrailLength {
                particles[i].trail.removeFirst()
            }

            // Pozisyon guncelle
            particles[i].position.x += dx
            particles[i].position.y += dy
            particles[i].age += 1

            // Sinir disi veya omur dolmussa resetle
            let margin: CGFloat = 5
            if particles[i].age > particles[i].maxAge ||
               particles[i].position.x < -margin || particles[i].position.x > size.width + margin ||
               particles[i].position.y < -margin || particles[i].position.y > size.height + margin {
                resetParticle(&particles[i], in: size)
            }
        }
    }

    private func resetParticle(_ particle: inout WindParticle, in size: CGSize) {
        particle.position = CGPoint(
            x: CGFloat.random(in: 0...size.width),
            y: CGFloat.random(in: 0...size.height)
        )
        particle.age = 0
        particle.maxAge = Double.random(in: 40...100)
        particle.trail = []
    }

    // MARK: - Wind Interpolation (IDW)

    private func getWindAtPoint(_ point: CGPoint, in size: CGSize) -> WindGridPoint? {
        guard !activeWindData.isEmpty, size.width > 0, size.height > 0 else { return nil }

        // Ekran noktasini lat/lng'ye cevir (harita heading'i hesaba katarak)
        let region = activeMapRegion
        let nx = Double(point.x) / Double(size.width) - 0.5
        let ny = Double(point.y) / Double(size.height) - 0.5
        let headingRad = activeHeading * .pi / 180.0
        // Ekran ofsetini cografi eksenlere cevir (heading rotasyonunu geri al)
        let geoNx = nx * cos(headingRad) - ny * sin(headingRad)
        let geoNy = nx * sin(headingRad) + ny * cos(headingRad)
        let lng = region.center.longitude + geoNx * region.span.longitudeDelta
        let lat = region.center.latitude - geoNy * region.span.latitudeDelta

        // Deniz alaninda mi kontrol et
        guard SeaAreas.isInSea(lat: lat, lng: lng) else { return nil }

        // Inverse Distance Weighting (IDW) interpolasyonu
        var totalWeight = 0.0
        var speedSum = 0.0
        var gustSum = 0.0
        var dirXSum = 0.0
        var dirYSum = 0.0

        for point in activeWindData {
            let dist = sqrt(pow(lat - point.lat, 2) + pow(lng - point.lng, 2))
            if dist < 0.0001 {
                return point
            }
            let weight = 1.0 / (dist * dist)
            totalWeight += weight
            speedSum += point.speed * weight
            gustSum += point.gusts * weight
            let rad = point.direction * .pi / 180
            dirXSum += sin(rad) * weight
            dirYSum += cos(rad) * weight
        }

        guard totalWeight > 0 else { return nil }

        return WindGridPoint(
            lat: lat,
            lng: lng,
            speed: speedSum / totalWeight,
            direction: (atan2(dirXSum, dirYSum) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360),
            gusts: gustSum / totalWeight
        )
    }

    // MARK: - 5-Level Wind Color Scale
    /// Yesil (0-10) -> Sari (10-20) -> Turuncu (20-30) -> Kirmizi (30-40) -> Koyu Kirmizi (40+)
    /// Seviyeler arasi yumusak gecis (interpolasyon)

    private func windColor(for speed: Double) -> Color {
        // Tam esikler icin hizli donus
        if speed <= 0 { return Color(red: 0.20, green: 0.80, blue: 0.20) }
        if speed >= 50 { return Color(red: 0.55, green: 0.00, blue: 0.00) }

        // Gecis bolgelerinde interpolasyon (esik +/- 2 km/h)
        let transitionWidth = 2.0

        if speed < 10 - transitionWidth { return Color(red: 0.20, green: 0.80, blue: 0.20) }
        if speed < 10 + transitionWidth {
            let t = (speed - (10 - transitionWidth)) / (2 * transitionWidth)
            return interpolateColor(
                from: (0.20, 0.80, 0.20),
                to: (1.00, 0.90, 0.10),
                t: t
            )
        }
        if speed < 20 - transitionWidth { return Color(red: 1.00, green: 0.90, blue: 0.10) }
        if speed < 20 + transitionWidth {
            let t = (speed - (20 - transitionWidth)) / (2 * transitionWidth)
            return interpolateColor(
                from: (1.00, 0.90, 0.10),
                to: (1.00, 0.55, 0.00),
                t: t
            )
        }
        if speed < 30 - transitionWidth { return Color(red: 1.00, green: 0.55, blue: 0.00) }
        if speed < 30 + transitionWidth {
            let t = (speed - (30 - transitionWidth)) / (2 * transitionWidth)
            return interpolateColor(
                from: (1.00, 0.55, 0.00),
                to: (0.95, 0.15, 0.10),
                t: t
            )
        }
        if speed < 40 - transitionWidth { return Color(red: 0.95, green: 0.15, blue: 0.10) }
        if speed < 40 + transitionWidth {
            let t = (speed - (40 - transitionWidth)) / (2 * transitionWidth)
            return interpolateColor(
                from: (0.95, 0.15, 0.10),
                to: (0.55, 0.00, 0.00),
                t: t
            )
        }
        return Color(red: 0.55, green: 0.00, blue: 0.00)
    }

    private func interpolateColor(
        from: (r: Double, g: Double, b: Double),
        to: (r: Double, g: Double, b: Double),
        t: Double
    ) -> Color {
        let ct = max(0, min(1, t))
        return Color(
            red: from.r + (to.r - from.r) * ct,
            green: from.g + (to.g - from.g) * ct,
            blue: from.b + (to.b - from.b) * ct
        )
    }
}

// MARK: - Wave Overlay View
/// Dalga yuksekligi gorsellestirme overlay'i
struct WaveOverlayView: View {
    let waveData: [WaveGridPoint]
    let mapRegion: MKCoordinateRegion
    @State private var animationPhase: Double = 0

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let cellSize: CGFloat = 40
                let cols = Int(size.width / cellSize) + 1
                let rows = Int(size.height / cellSize) + 1

                for row in 0..<rows {
                    for col in 0..<cols {
                        let x = CGFloat(col) * cellSize + cellSize / 2
                        let y = CGFloat(row) * cellSize + cellSize / 2

                        guard let wave = getWaveAtPoint(CGPoint(x: x, y: y), in: size) else { continue }

                        let color = waveColor(for: wave.height)
                        let amplitude = wave.height * 5
                        let period = wave.period

                        // Draw wave symbol
                        var path = Path()
                        let waveWidth = cellSize * 0.6

                        // Wave shape based on period
                        let isSmooth = period > 8
                        let frequency: CGFloat = isSmooth ? 0.3 : 0.5

                        context.translateBy(x: x, y: y)
                        context.rotate(by: Angle(degrees: wave.direction))

                        for i in stride(from: -waveWidth/2, through: waveWidth/2, by: 2) {
                            let yOffset = sin((i * frequency + animationPhase) * 2) * amplitude
                            if i == -waveWidth/2 {
                                path.move(to: CGPoint(x: i, y: yOffset))
                            } else {
                                path.addLine(to: CGPoint(x: i, y: yOffset))
                            }
                        }

                        context.stroke(
                            path,
                            with: .color(color.opacity(0.6)),
                            lineWidth: 2
                        )

                        context.rotate(by: Angle(degrees: -wave.direction))
                        context.translateBy(x: -x, y: -y)
                    }
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    animationPhase = .pi * 2
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func getWaveAtPoint(_ point: CGPoint, in size: CGSize) -> WaveGridPoint? {
        guard !waveData.isEmpty else { return nil }

        let lng = mapRegion.center.longitude - mapRegion.span.longitudeDelta / 2 +
                  (Double(point.x) / Double(size.width)) * mapRegion.span.longitudeDelta
        let lat = mapRegion.center.latitude + mapRegion.span.latitudeDelta / 2 -
                  (Double(point.y) / Double(size.height)) * mapRegion.span.latitudeDelta

        guard SeaAreas.isInSea(lat: lat, lng: lng) else { return nil }

        // Interpolate wave data
        var totalWeight = 0.0
        var heightSum = 0.0
        var periodSum = 0.0
        var dirXSum = 0.0
        var dirYSum = 0.0

        for point in waveData {
            let dist = sqrt(pow(lat - point.lat, 2) + pow(lng - point.lng, 2))
            if dist < 0.0001 {
                return point
            }
            let weight = 1.0 / (dist * dist)
            totalWeight += weight
            heightSum += point.height * weight
            periodSum += point.period * weight
            let rad = point.direction * .pi / 180
            dirXSum += sin(rad) * weight
            dirYSum += cos(rad) * weight
        }

        guard totalWeight > 0 else { return nil }

        return WaveGridPoint(
            lat: lat,
            lng: lng,
            height: heightSum / totalWeight,
            direction: (atan2(dirXSum, dirYSum) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360),
            period: periodSum / totalWeight
        )
    }

    private func waveColor(for height: Double) -> Color {
        if height < 0.5 { return .green }
        if height < 1.0 { return .blue }
        if height < 1.5 { return .yellow }
        if height < 2.0 { return .orange }
        if height < 3.0 { return .red }
        return .purple
    }
}

// MARK: - Data Models
struct WindParticle {
    var position: CGPoint
    var age: Double
    var maxAge: Double
    var trail: [CGPoint] = []
}

struct WindGridPoint: Equatable {
    let lat: Double
    let lng: Double
    let speed: Double
    let direction: Double
    let gusts: Double
}

struct WaveGridPoint {
    let lat: Double
    let lng: Double
    let height: Double
    let direction: Double
    let period: Double
}

// MARK: - Wind Legend View
/// 5 seviyeli ruzgar renk skalasi lejanti
struct WindLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Ruzgar (km/h)")
                .font(.caption2)
                .fontWeight(.semibold)

            ForEach(windLevels, id: \.range) { level in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(level.color)
                        .frame(width: 14, height: 8)
                    Text(level.range)
                        .font(.system(size: 9))
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    private var windLevels: [(range: String, color: Color)] {
        [
            ("0-10", Color(red: 0.20, green: 0.80, blue: 0.20)),
            ("10-20", Color(red: 1.00, green: 0.90, blue: 0.10)),
            ("20-30", Color(red: 1.00, green: 0.55, blue: 0.00)),
            ("30-40", Color(red: 0.95, green: 0.15, blue: 0.10)),
            ("40+", Color(red: 0.55, green: 0.00, blue: 0.00))
        ]
    }
}

// MARK: - Wave Legend View
struct WaveLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dalga (m)")
                .font(.caption2)
                .fontWeight(.semibold)

            ForEach(waveLevels, id: \.range) { level in
                HStack(spacing: 4) {
                    Circle()
                        .fill(level.color)
                        .frame(width: 10, height: 10)
                    Text(level.range)
                        .font(.caption2)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    private var waveLevels: [(range: String, color: Color)] {
        [
            ("0-0.5", .green),
            ("0.5-1", .blue),
            ("1-1.5", .yellow),
            ("1.5-2", .orange),
            ("2-3", .red),
            ("3+", .purple)
        ]
    }
}

// MARK: - Weather Grid Loader
class WeatherGridLoader {
    static let shared = WeatherGridLoader()

    private let weatherService = WeatherService.shared

    func loadWindGrid(for region: MKCoordinateRegion, date: Date) async -> [WindGridPoint] {
        let gridSize = 6
        let latStep = region.span.latitudeDelta / Double(gridSize)
        let lngStep = region.span.longitudeDelta / Double(gridSize)

        var points: [WindGridPoint] = []

        await withTaskGroup(of: WindGridPoint?.self) { group in
            for i in 0...gridSize {
                for j in 0...gridSize {
                    let lat = region.center.latitude - region.span.latitudeDelta / 2 + Double(i) * latStep
                    let lng = region.center.longitude - region.span.longitudeDelta / 2 + Double(j) * lngStep

                    guard SeaAreas.isInSea(lat: lat, lng: lng) else { continue }

                    group.addTask {
                        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                        guard let weather = try? await self.weatherService.fetchWeather(for: coord, date: date) else {
                            return nil
                        }
                        return WindGridPoint(
                            lat: lat,
                            lng: lng,
                            speed: weather.windSpeed,
                            direction: weather.windDirection,
                            gusts: weather.windGusts
                        )
                    }
                }
            }

            for await point in group {
                if let point = point {
                    points.append(point)
                }
            }
        }

        return points
    }

    func loadWaveGrid(for region: MKCoordinateRegion, date: Date) async -> [WaveGridPoint] {
        let gridSize = 8
        let latStep = region.span.latitudeDelta / Double(gridSize)
        let lngStep = region.span.longitudeDelta / Double(gridSize)

        var points: [WaveGridPoint] = []

        await withTaskGroup(of: WaveGridPoint?.self) { group in
            for i in 0...gridSize {
                for j in 0...gridSize {
                    let lat = region.center.latitude - region.span.latitudeDelta / 2 + Double(i) * latStep
                    let lng = region.center.longitude - region.span.longitudeDelta / 2 + Double(j) * lngStep

                    guard SeaAreas.isInSea(lat: lat, lng: lng) else { continue }

                    group.addTask {
                        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                        guard let weather = try? await self.weatherService.fetchWeather(for: coord, date: date) else {
                            return nil
                        }
                        return WaveGridPoint(
                            lat: lat,
                            lng: lng,
                            height: weather.waveHeight,
                            direction: weather.waveDirection,
                            period: weather.wavePeriod
                        )
                    }
                }
            }

            for await point in group {
                if let point = point {
                    points.append(point)
                }
            }
        }

        return points
    }
}
