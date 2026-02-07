import SwiftUI
import MapKit

// MARK: - Wind Overlay View
/// Rüzgar partikül animasyonu overlay'i
struct WindOverlayView: View {
    let windData: [WindGridPoint]
    let mapRegion: MKCoordinateRegion
    @State private var particles: [WindParticle] = []
    @State private var animationTimer: Timer?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for particle in particles {
                    guard let wind = getWindAtPoint(particle.position, in: size) else { continue }

                    let color = windColor(for: wind.speed)
                    let alpha = 1.0 - (particle.age / particle.maxAge)

                    // Draw trail
                    if particle.trail.count > 1 {
                        var path = Path()
                        path.move(to: particle.trail[0])
                        for point in particle.trail.dropFirst() {
                            path.addLine(to: point)
                        }
                        path.addLine(to: particle.position)

                        context.stroke(
                            path,
                            with: .color(color.opacity(alpha * 0.8)),
                            lineWidth: 1.5
                        )
                    }
                }
            }
            .onAppear {
                initializeParticles(in: geometry.size)
                startAnimation(in: geometry.size)
            }
            .onDisappear {
                animationTimer?.invalidate()
            }
            .onChange(of: geometry.size) { _, newSize in
                initializeParticles(in: newSize)
            }
        }
        .allowsHitTesting(false)
    }

    private func initializeParticles(in size: CGSize) {
        particles = (0..<500).map { _ in
            WindParticle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height)
                ),
                age: Double.random(in: 0...50),
                maxAge: Double.random(in: 50...100)
            )
        }
    }

    private func startAnimation(in size: CGSize) {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            updateParticles(in: size)
        }
    }

    private func updateParticles(in size: CGSize) {
        for i in particles.indices {
            guard let wind = getWindAtPoint(particles[i].position, in: size) else {
                resetParticle(&particles[i], in: size)
                continue
            }

            // Calculate direction
            let dirRad = ((wind.direction + 180) * .pi) / 180.0
            let speed = wind.speed / 5.0

            // Add turbulence for gusts
            let turbulence = wind.gusts > wind.speed + 10 ?
                CGFloat.random(in: -0.3...0.3) : 0

            let dx = sin(dirRad + turbulence) * speed
            let dy = -cos(dirRad + turbulence) * speed

            // Update position
            particles[i].trail.append(particles[i].position)
            if particles[i].trail.count > 10 {
                particles[i].trail.removeFirst()
            }

            particles[i].position.x += dx
            particles[i].position.y += dy
            particles[i].age += 1

            // Reset if out of bounds or too old
            if particles[i].age > particles[i].maxAge ||
               particles[i].position.x < 0 || particles[i].position.x > size.width ||
               particles[i].position.y < 0 || particles[i].position.y > size.height {
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
        particle.maxAge = Double.random(in: 50...100)
        particle.trail = []
    }

    private func getWindAtPoint(_ point: CGPoint, in size: CGSize) -> WindGridPoint? {
        guard !windData.isEmpty else { return nil }

        // Convert screen point to lat/lng
        let lng = mapRegion.center.longitude - mapRegion.span.longitudeDelta / 2 +
                  (Double(point.x) / Double(size.width)) * mapRegion.span.longitudeDelta
        let lat = mapRegion.center.latitude + mapRegion.span.latitudeDelta / 2 -
                  (Double(point.y) / Double(size.height)) * mapRegion.span.latitudeDelta

        // Check if in sea
        guard SeaAreas.isInSea(lat: lat, lng: lng) else { return nil }

        // Interpolate wind data
        var totalWeight = 0.0
        var speedSum = 0.0
        var gustSum = 0.0
        var dirXSum = 0.0
        var dirYSum = 0.0

        for point in windData {
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

    private func windColor(for speed: Double) -> Color {
        if speed < 10 { return .green }
        if speed < 20 { return .yellow }
        if speed < 30 { return .orange }
        if speed < 40 { return .red }
        return .purple
    }
}

// MARK: - Wave Overlay View
/// Dalga yüksekliği görselleştirme overlay'i
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

struct WindGridPoint {
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
struct WindLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ruzgar (km/h)")
                .font(.caption2)
                .fontWeight(.semibold)

            ForEach(windLevels, id: \.range) { level in
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

    private var windLevels: [(range: String, color: Color)] {
        [
            ("0-10", .green),
            ("10-20", .yellow),
            ("20-30", .orange),
            ("30-40", .red),
            ("40+", .purple)
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

// MARK: - Overlay Toggle Buttons
struct WeatherOverlayButtons: View {
    @Binding var showWindOverlay: Bool
    @Binding var showWaveOverlay: Bool
    var onLoadWeather: () async -> Void

    @State private var isLoading = false

    var body: some View {
        HStack(spacing: 8) {
            // Wind toggle
            Button {
                Task {
                    if !showWindOverlay {
                        isLoading = true
                        await onLoadWeather()
                        isLoading = false
                    }
                    showWindOverlay.toggle()
                }
            } label: {
                Image(systemName: "wind")
                    .foregroundStyle(showWindOverlay ? .white : .blue)
                    .frame(width: 36, height: 36)
                    .background(showWindOverlay ? Color.blue : Color.white)
                    .clipShape(Circle())
                    .shadow(radius: 2)
            }

            // Wave toggle
            Button {
                Task {
                    if !showWaveOverlay {
                        isLoading = true
                        await onLoadWeather()
                        isLoading = false
                    }
                    showWaveOverlay.toggle()
                }
            } label: {
                Image(systemName: "water.waves")
                    .foregroundStyle(showWaveOverlay ? .white : .blue)
                    .frame(width: 36, height: 36)
                    .background(showWaveOverlay ? Color.blue : Color.white)
                    .clipShape(Circle())
                    .shadow(radius: 2)
            }

            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
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
                        guard let weather = try? await self.weatherService.fetchWeather(for: coord) else {
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
                        guard let weather = try? await self.weatherService.fetchWeather(for: coord) else {
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
