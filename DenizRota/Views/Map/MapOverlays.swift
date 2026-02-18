import SwiftUI
import MapKit

// MARK: - Wind Particle View (UIView - MKMapView subview)
/// Windy-tarzi ruzgar partikul animasyonu.
/// MKMapView'in subview'i olarak calisir, mapView.convert() ile
/// heading/zoom/pan otomatik olarak dogru hesaplanir.
class WindParticleView: UIView {

    weak var mapView: MKMapView?

    var windData: [WindGridPoint] = [] {
        didSet {
            // Yeni ruzgar verisi geldiginde kuyruk izlerini temizle
            for i in particles.indices {
                particles[i].trail = []
            }
        }
    }

    private(set) var isAnimating = false
    private var particles: [GeoParticle] = []
    private var displayLink: CADisplayLink?
    private let particleCount = 800
    private var projection = ScreenProjection()

    // Partikul: cografi koordinatlarda yasar, harita ile birlikte hareket eder
    private struct GeoParticle {
        var lat: Double
        var lng: Double
        var age: Double
        var maxAge: Double
        var trail: [(lat: Double, lng: Double)]
    }

    // Frame basina 3 convert cagrisiyla hesaplanan projeksiyon matrisi.
    // Tum partikul/trail noktalarini basit aritmetikle ekrana cevirir.
    private struct ScreenProjection {
        var refLat: Double = 0
        var refLng: Double = 0
        var refScreen: CGPoint = .zero
        // Ekran koordinati degisimi / derece degisimi
        var dLatX: CGFloat = 0
        var dLatY: CGFloat = 0
        var dLngX: CGFloat = 0
        var dLngY: CGFloat = 0

        mutating func update(mapView: MKMapView, view: UIView) {
            let center = mapView.region.center
            refLat = center.latitude
            refLng = center.longitude
            refScreen = mapView.convert(center, toPointTo: view)

            let delta = 0.01
            let pLat = mapView.convert(
                CLLocationCoordinate2D(latitude: center.latitude + delta, longitude: center.longitude),
                toPointTo: view
            )
            let pLng = mapView.convert(
                CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude + delta),
                toPointTo: view
            )

            dLatX = (pLat.x - refScreen.x) / delta
            dLatY = (pLat.y - refScreen.y) / delta
            dLngX = (pLng.x - refScreen.x) / delta
            dLngY = (pLng.y - refScreen.y) / delta
        }

        func toScreen(lat: Double, lng: Double) -> CGPoint {
            let dl = lat - refLat
            let dn = lng - refLng
            return CGPoint(
                x: refScreen.x + CGFloat(dl) * dLatX + CGFloat(dn) * dLngX,
                y: refScreen.y + CGFloat(dl) * dLatY + CGFloat(dn) * dLngY
            )
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Animation Lifecycle

    func startAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        initializeParticles()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
        displayLink?.add(to: .main, forMode: .common)
    }

    func stopAnimation() {
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        particles = []
        setNeedsDisplay()
    }

    @objc private func tick() {
        guard let mapView = mapView else { return }
        projection.update(mapView: mapView, view: self)
        updateParticles()
        setNeedsDisplay()
    }

    // MARK: - Particle Initialization

    private func initializeParticles() {
        guard let mapView = mapView else { return }
        let region = mapView.region

        particles = (0..<particleCount).map { _ in
            GeoParticle(
                lat: region.center.latitude + Double.random(in: -0.5...0.5) * region.span.latitudeDelta,
                lng: region.center.longitude + Double.random(in: -0.5...0.5) * region.span.longitudeDelta,
                age: Double.random(in: 0...60),
                maxAge: Double.random(in: 40...100),
                trail: []
            )
        }
    }

    // MARK: - Particle Update (cografi koordinatlarda)

    private func updateParticles() {
        guard let mapView = mapView else { return }
        let viewBounds = bounds
        guard viewBounds.width > 0, viewBounds.height > 0 else { return }

        // Metre/piksel orani - zoom seviyesine gore partikul hizini kalibre eder
        let metersPerPoint = mapView.region.span.latitudeDelta * 111_000 / Double(viewBounds.height)
        let proj = projection

        for i in particles.indices {
            let coord = CLLocationCoordinate2D(latitude: particles[i].lat, longitude: particles[i].lng)
            guard let wind = getWindAtCoordinate(coord) else {
                resetParticle(&particles[i], in: mapView)
                continue
            }

            // Ruzgar yonu -> cografi hareket vektoru
            let toAngleRad = (wind.direction + 180) * .pi / 180.0
            let speedFactor = max(0.5, wind.speed / 4.0)

            // Hamle (gust) varsa turbelans ekle
            let gustDiff = wind.gusts - wind.speed
            let turbulence: Double = gustDiff > 8 ?
                Double.random(in: -0.25...0.25) * (gustDiff / 30.0) : 0
            let angle = toAngleRad + turbulence

            // Cografi koordinatlarda hareket (metre -> derece)
            let metersPerFrame = speedFactor * metersPerPoint
            let dLat = cos(angle) * metersPerFrame / 111_000
            let cosLat = cos(particles[i].lat * .pi / 180)
            let dLng = sin(angle) * metersPerFrame / (111_000 * max(cosLat, 0.01))

            // Trail guncelle
            let maxTrailLength = Int(max(6, min(16, wind.speed / 3.0)))
            particles[i].trail.append((lat: particles[i].lat, lng: particles[i].lng))
            while particles[i].trail.count > maxTrailLength {
                particles[i].trail.removeFirst()
            }

            // Cografi pozisyon guncelle
            particles[i].lat += dLat
            particles[i].lng += dLng
            particles[i].age += 1

            // Ekran disina ciktiysa veya omru dolduysa resetle (projeksiyon cache ile)
            let screenPoint = proj.toScreen(lat: particles[i].lat, lng: particles[i].lng)
            let margin: CGFloat = 20
            if particles[i].age > particles[i].maxAge ||
               screenPoint.x < -margin || screenPoint.x > viewBounds.width + margin ||
               screenPoint.y < -margin || screenPoint.y > viewBounds.height + margin {
                resetParticle(&particles[i], in: mapView)
            }
        }
    }

    private func resetParticle(_ particle: inout GeoParticle, in mapView: MKMapView) {
        let region = mapView.region
        particle.lat = region.center.latitude + Double.random(in: -0.5...0.5) * region.span.latitudeDelta
        particle.lng = region.center.longitude + Double.random(in: -0.5...0.5) * region.span.longitudeDelta
        particle.age = 0
        particle.maxAge = Double.random(in: 40...100)
        particle.trail = []
    }

    // MARK: - Drawing (Core Graphics)

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let proj = projection
        context.setLineCap(.round)

        for particle in particles {
            guard particle.trail.count > 1 else { continue }
            let coord = CLLocationCoordinate2D(latitude: particle.lat, longitude: particle.lng)
            guard let wind = getWindAtCoordinate(coord) else { continue }

            let color = windColor(for: wind.speed)
            let lifeRatio = particle.age / particle.maxAge
            let fadeAlpha = CGFloat(max(0, 1.0 - lifeRatio))

            // Trail koordinatlarini ekran noktasina cevir (projeksiyon cache ile - frame basina 3 convert)
            var screenPoints: [CGPoint] = particle.trail.map { p in
                proj.toScreen(lat: p.lat, lng: p.lng)
            }
            screenPoints.append(proj.toScreen(lat: particle.lat, lng: particle.lng))

            let segmentCount = screenPoints.count - 1
            guard segmentCount > 0 else { continue }

            let lineWidth = max(1.0, min(2.5, wind.speed / 20.0 + 0.8))
            context.setLineWidth(lineWidth)

            // Trail: gradient efekti (bastan sona artan opacity)
            for s in 0..<segmentCount {
                let segmentRatio = CGFloat(s) / CGFloat(segmentCount)
                let segmentAlpha = segmentRatio * fadeAlpha * 0.85

                context.setStrokeColor(color.withAlphaComponent(segmentAlpha).cgColor)
                context.move(to: screenPoints[s])
                context.addLine(to: screenPoints[s + 1])
                context.strokePath()
            }

            // Partikul basi - parlak nokta
            let headAlpha = fadeAlpha * 0.95
            let headSize = max(2.0, min(3.5, wind.speed / 20.0 + 1.5))
            let headPoint = screenPoints.last!
            context.setFillColor(color.withAlphaComponent(headAlpha).cgColor)
            context.fillEllipse(in: CGRect(
                x: headPoint.x - headSize / 2,
                y: headPoint.y - headSize / 2,
                width: headSize,
                height: headSize
            ))
        }
    }

    // MARK: - Wind Interpolation (IDW)

    private func getWindAtCoordinate(_ coordinate: CLLocationCoordinate2D) -> WindGridPoint? {
        guard !windData.isEmpty else { return nil }

        let lat = coordinate.latitude
        let lng = coordinate.longitude

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

    // MARK: - 5-Level Wind Color Scale
    /// Yesil (0-10) -> Sari (10-20) -> Turuncu (20-30) -> Kirmizi (30-40) -> Koyu Kirmizi (40+)

    private func windColor(for speed: Double) -> UIColor {
        if speed <= 0 { return UIColor(red: 0.20, green: 0.80, blue: 0.20, alpha: 1) }
        if speed >= 50 { return UIColor(red: 0.55, green: 0.00, blue: 0.00, alpha: 1) }

        let tw = 2.0
        if speed < 10 - tw { return UIColor(red: 0.20, green: 0.80, blue: 0.20, alpha: 1) }
        if speed < 10 + tw {
            let t = CGFloat((speed - (10 - tw)) / (2 * tw))
            return lerpColor(from: (0.20, 0.80, 0.20), to: (1.00, 0.90, 0.10), t: t)
        }
        if speed < 20 - tw { return UIColor(red: 1.00, green: 0.90, blue: 0.10, alpha: 1) }
        if speed < 20 + tw {
            let t = CGFloat((speed - (20 - tw)) / (2 * tw))
            return lerpColor(from: (1.00, 0.90, 0.10), to: (1.00, 0.55, 0.00), t: t)
        }
        if speed < 30 - tw { return UIColor(red: 1.00, green: 0.55, blue: 0.00, alpha: 1) }
        if speed < 30 + tw {
            let t = CGFloat((speed - (30 - tw)) / (2 * tw))
            return lerpColor(from: (1.00, 0.55, 0.00), to: (0.95, 0.15, 0.10), t: t)
        }
        if speed < 40 - tw { return UIColor(red: 0.95, green: 0.15, blue: 0.10, alpha: 1) }
        if speed < 40 + tw {
            let t = CGFloat((speed - (40 - tw)) / (2 * tw))
            return lerpColor(from: (0.95, 0.15, 0.10), to: (0.55, 0.00, 0.00), t: t)
        }
        return UIColor(red: 0.55, green: 0.00, blue: 0.00, alpha: 1)
    }

    private func lerpColor(from: (CGFloat, CGFloat, CGFloat), to: (CGFloat, CGFloat, CGFloat), t: CGFloat) -> UIColor {
        let ct = max(0, min(1, t))
        return UIColor(
            red: from.0 + (to.0 - from.0) * ct,
            green: from.1 + (to.1 - from.1) * ct,
            blue: from.2 + (to.2 - from.2) * ct,
            alpha: 1
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
