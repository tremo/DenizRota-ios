import SwiftUI
import MapKit

// MARK: - Map Style Option

enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case hybrid = "Hybrid"
    case satellite = "Uydu"

    var id: String { rawValue }

    var mapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .hybrid: return .hybrid
        case .satellite: return .satellite
        }
    }

    var icon: String {
        switch self {
        case .standard: return "map"
        case .hybrid: return "map.fill"
        case .satellite: return "globe.americas.fill"
        }
    }
}

// MARK: - Custom Annotations

class WaypointAnnotation: NSObject, MKAnnotation {
    let waypoint: Waypoint
    let number: Int

    var coordinate: CLLocationCoordinate2D {
        waypoint.coordinate
    }

    var title: String? {
        waypoint.name
    }

    init(waypoint: Waypoint, number: Int) {
        self.waypoint = waypoint
        self.number = number
    }
}

class CoveAnnotation: NSObject, MKAnnotation {
    let cove: Cove
    let shelterLevel: ShelterLevel

    var coordinate: CLLocationCoordinate2D {
        cove.coordinate
    }

    var title: String? {
        cove.name
    }

    var subtitle: String? {
        shelterLevel.shortDescription
    }

    init(cove: Cove, shelterLevel: ShelterLevel) {
        self.cove = cove
        self.shelterLevel = shelterLevel
    }
}

class UserLocationAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

// MARK: - OpenSeaMap Tile Overlay

class OpenSeaMapOverlay: MKTileOverlay {}

// MARK: - Nautical Map View

struct NauticalMapView: UIViewRepresentable {
    var region: MKCoordinateRegion
    var mapStyle: MapStyleOption
    var showOpenSeaMap: Bool

    var userLocation: CLLocation?
    var activeRoute: Route?
    var isRouteMode: Bool
    var shelterResults: [CoveShelterResult]

    var onTapCoordinate: ((CLLocationCoordinate2D) -> Void)?
    var onDeleteWaypoint: ((Waypoint) -> Void)?
    var onRegionChanged: ((MKCoordinateRegion) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.parent = self

        mapView.mapType = mapStyle.mapType
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = false
        mapView.pointOfInterestFilter = .includingAll

        mapView.setRegion(region, animated: false)
        context.coordinator.lastRegionCenter = region.center
        context.coordinator.lastRegionSpan = region.span

        // Tap gesture for adding waypoints
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapGesture.numberOfTapsRequired = 1
        tapGesture.delegate = context.coordinator
        // Don't interfere with double-tap zoom
        for gesture in mapView.gestureRecognizers ?? [] {
            if let doubleTap = gesture as? UITapGestureRecognizer,
               doubleTap.numberOfTapsRequired == 2 {
                tapGesture.require(toFail: doubleTap)
            }
        }
        mapView.addGestureRecognizer(tapGesture)

        if showOpenSeaMap {
            addOpenSeaMapOverlay(to: mapView)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        if mapView.mapType != mapStyle.mapType {
            mapView.mapType = mapStyle.mapType
        }

        updateOpenSeaMapOverlay(mapView)
        updateRegion(mapView, context: context)
        updateAnnotations(mapView)
        updateCoveAnnotations(mapView)
        updateRouteOverlay(mapView)
    }

    // MARK: - OpenSeaMap

    private func addOpenSeaMapOverlay(to mapView: MKMapView) {
        let template = "https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png"
        let overlay = OpenSeaMapOverlay(urlTemplate: template)
        overlay.canReplaceMapContent = false
        overlay.maximumZ = 18
        overlay.minimumZ = 6
        mapView.addOverlay(overlay, level: .aboveLabels)
    }

    private func updateOpenSeaMapOverlay(_ mapView: MKMapView) {
        let hasOverlay = mapView.overlays.contains { $0 is OpenSeaMapOverlay }
        if showOpenSeaMap && !hasOverlay {
            addOpenSeaMapOverlay(to: mapView)
        } else if !showOpenSeaMap && hasOverlay {
            for overlay in mapView.overlays where overlay is OpenSeaMapOverlay {
                mapView.removeOverlay(overlay)
            }
        }
    }

    // MARK: - Region

    private func updateRegion(_ mapView: MKMapView, context: Context) {
        let lastCenter = context.coordinator.lastRegionCenter
        let lastSpan = context.coordinator.lastRegionSpan
        let newCenter = region.center
        let newSpan = region.span

        let centerChanged = abs(lastCenter.latitude - newCenter.latitude) > 0.001 ||
                            abs(lastCenter.longitude - newCenter.longitude) > 0.001
        let spanChanged = abs(lastSpan.latitudeDelta - newSpan.latitudeDelta) > 0.01

        if centerChanged || spanChanged {
            context.coordinator.lastRegionCenter = newCenter
            context.coordinator.lastRegionSpan = newSpan
            context.coordinator.isProgrammaticRegionChange = true
            mapView.setRegion(region, animated: true)
        }
    }

    // MARK: - Annotations

    private func updateAnnotations(_ mapView: MKMapView) {
        // --- User Location ---
        let existingUserAnnotations = mapView.annotations.compactMap { $0 as? UserLocationAnnotation }

        if let location = userLocation {
            if let existing = existingUserAnnotations.first {
                UIView.animate(withDuration: 0.3) {
                    existing.coordinate = location.coordinate
                }
            } else {
                mapView.addAnnotation(UserLocationAnnotation(coordinate: location.coordinate))
            }
        } else {
            existingUserAnnotations.forEach { mapView.removeAnnotation($0) }
        }

        // --- Waypoints ---
        let existingWaypointAnnotations = mapView.annotations.compactMap { $0 as? WaypointAnnotation }
        let currentWaypoints = activeRoute?.sortedWaypoints ?? []
        let existingByID = Dictionary(uniqueKeysWithValues: existingWaypointAnnotations.map { ($0.waypoint.id, $0) })
        let currentIDs = Set(currentWaypoints.map(\.id))

        // Remove annotations for waypoints that no longer exist
        for annotation in existingWaypointAnnotations {
            if !currentIDs.contains(annotation.waypoint.id) {
                mapView.removeAnnotation(annotation)
            }
        }

        // Add or update annotations for current waypoints
        for (index, waypoint) in currentWaypoints.enumerated() {
            let number = index + 1
            if let existing = existingByID[waypoint.id] {
                // Re-create if number changed
                if existing.number != number {
                    mapView.removeAnnotation(existing)
                    mapView.addAnnotation(WaypointAnnotation(waypoint: waypoint, number: number))
                } else if let view = mapView.view(for: existing) {
                    // Refresh appearance for risk level changes
                    view.image = Self.renderWaypointImage(
                        number: number,
                        riskLevel: waypoint.riskLevel,
                        isLoading: waypoint.isLoading
                    )
                }
            } else {
                mapView.addAnnotation(WaypointAnnotation(waypoint: waypoint, number: number))
            }
        }
    }

    // MARK: - Cove Annotations

    private func updateCoveAnnotations(_ mapView: MKMapView) {
        let existingCoveAnnotations = mapView.annotations.compactMap { $0 as? CoveAnnotation }

        if shelterResults.isEmpty {
            // Koy analizi kapalı, tüm cove annotation'larını kaldır
            existingCoveAnnotations.forEach { mapView.removeAnnotation($0) }
            return
        }

        let existingByKey = Dictionary(uniqueKeysWithValues: existingCoveAnnotations.map { ($0.cove.stableId, $0) })
        let currentKeys = Set(shelterResults.map(\.cove.stableId))

        // Artik olmayan annotation'lari kaldir
        for annotation in existingCoveAnnotations {
            if !currentKeys.contains(annotation.cove.stableId) {
                mapView.removeAnnotation(annotation)
            }
        }

        // Yeni annotation ekle veya guncelle
        for result in shelterResults {
            if let existing = existingByKey[result.cove.stableId] {
                // Shelter level degismisse yeniden olustur
                if existing.shelterLevel != result.shelterLevel {
                    mapView.removeAnnotation(existing)
                    mapView.addAnnotation(CoveAnnotation(cove: result.cove, shelterLevel: result.shelterLevel))
                } else if let view = mapView.view(for: existing) {
                    view.image = Self.renderCoveImage(shelterLevel: result.shelterLevel)
                }
            } else {
                mapView.addAnnotation(CoveAnnotation(cove: result.cove, shelterLevel: result.shelterLevel))
            }
        }
    }

    // MARK: - Route Overlay

    private func updateRouteOverlay(_ mapView: MKMapView) {
        for overlay in mapView.overlays where overlay is MKPolyline {
            mapView.removeOverlay(overlay)
        }

        guard let route = activeRoute, route.waypoints.count > 1 else { return }

        var coordinates = route.sortedWaypoints.map(\.coordinate)
        let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
        mapView.addOverlay(polyline, level: .aboveRoads)
    }

    // MARK: - Rendering Helpers

    static func renderWaypointImage(number: Int, riskLevel: RiskLevel, isLoading: Bool) -> UIImage {
        let size: CGFloat = 32
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let color: UIColor
            switch riskLevel {
            case .green: color = .systemGreen
            case .yellow: color = .systemOrange
            case .red: color = .systemRed
            case .unknown: color = .systemGray
            }

            ctx.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 2,
                color: UIColor.black.withAlphaComponent(0.3).cgColor
            )

            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))

            ctx.cgContext.setShadow(offset: .zero, blur: 0)

            if !isLoading {
                let text = "\(number)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 13),
                    .foregroundColor: UIColor.white
                ]
                let textSize = text.size(withAttributes: attrs)
                let textPoint = CGPoint(
                    x: (size - textSize.width) / 2,
                    y: (size - textSize.height) / 2
                )
                text.draw(at: textPoint, withAttributes: attrs)
            }
        }
    }

    static func renderCoveImage(shelterLevel: ShelterLevel) -> UIImage {
        let size: CGFloat = 28
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let color: UIColor
            switch shelterLevel {
            case .excellent: color = .systemGreen
            case .good: color = .systemBlue
            case .moderate: color = .systemOrange
            case .poor: color = .systemRed
            }

            // Dış çember
            ctx.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 2,
                color: UIColor.black.withAlphaComponent(0.3).cgColor
            )
            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))

            ctx.cgContext.setShadow(offset: .zero, blur: 0)

            // Çapa ikonu (basit anchor şekli)
            UIColor.white.setFill()
            let centerX = size / 2
            let centerY = size / 2
            // Dikey çizgi
            let barWidth: CGFloat = 2.5
            let barHeight: CGFloat = 12
            ctx.cgContext.fill(CGRect(x: centerX - barWidth / 2, y: centerY - barHeight / 2, width: barWidth, height: barHeight))
            // Yatay çizgi (üst)
            let crossWidth: CGFloat = 10
            ctx.cgContext.fill(CGRect(x: centerX - crossWidth / 2, y: centerY - barHeight / 2, width: crossWidth, height: barWidth))
            // Alt yarım daire
            let arcRadius: CGFloat = 5
            UIColor.white.setStroke()
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.addArc(center: CGPoint(x: centerX, y: centerY + barHeight / 2 - arcRadius), radius: arcRadius, startAngle: 0, endAngle: .pi, clockwise: false)
            ctx.cgContext.strokePath()
        }
    }

    static func renderUserLocationImage() -> UIImage {
        let size: CGFloat = 60
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            UIColor.systemBlue.withAlphaComponent(0.2).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))

            let dotSize: CGFloat = 16
            let dotOrigin = (size - dotSize) / 2
            UIColor.systemBlue.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: dotOrigin, y: dotOrigin, width: dotSize, height: dotSize))

            UIColor.white.setStroke()
            ctx.cgContext.setLineWidth(3)
            ctx.cgContext.strokeEllipse(in: CGRect(x: dotOrigin, y: dotOrigin, width: dotSize, height: dotSize))
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: NauticalMapView?
        var lastRegionCenter = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        var lastRegionSpan = MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0)
        var isProgrammaticRegionChange = false
        var calloutHostingController: UIHostingController<WaypointCalloutContent>?
        var selectedWaypointAnnotation: WaypointAnnotation?

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let parent = parent, parent.isRouteMode,
                  let mapView = gestureRecognizer.view as? MKMapView else {
                // Not in route mode - let MKMapView handle taps (annotation selection etc.)
                return false
            }

            let point = gestureRecognizer.location(in: mapView)

            // Don't recognize if tap is on an existing annotation
            // Let MKMapView handle it so didSelect fires
            for annotation in mapView.annotations {
                if let view = mapView.view(for: annotation) {
                    let pointInView = view.convert(point, from: mapView)
                    if view.point(inside: pointInView, with: nil) {
                        return false
                    }
                }
            }

            return true
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let parent = parent,
                  let mapView = gesture.view as? MKMapView else { return }

            let coordinate = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            parent.onTapCoordinate?(coordinate)
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(overlay: tileOverlay)
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 3
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let waypointAnnotation = annotation as? WaypointAnnotation {
                let identifier = "WaypointPin"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ??
                    MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

                view.annotation = annotation
                view.canShowCallout = false

                view.image = NauticalMapView.renderWaypointImage(
                    number: waypointAnnotation.number,
                    riskLevel: waypointAnnotation.waypoint.riskLevel,
                    isLoading: waypointAnnotation.waypoint.isLoading
                )
                view.centerOffset = CGPoint(x: 0, y: 0)

                return view
            }

            if let coveAnnotation = annotation as? CoveAnnotation {
                let identifier = "CovePin"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ??
                    MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

                view.annotation = annotation
                view.canShowCallout = true
                view.image = NauticalMapView.renderCoveImage(shelterLevel: coveAnnotation.shelterLevel)
                view.centerOffset = CGPoint(x: 0, y: 0)

                return view
            }

            if annotation is UserLocationAnnotation {
                let identifier = "UserPin"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ??
                    MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

                view.annotation = annotation
                view.canShowCallout = false
                view.image = NauticalMapView.renderUserLocationImage()
                view.centerOffset = CGPoint(x: 0, y: 0)

                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let waypointAnnotation = annotation as? WaypointAnnotation {
                showCallout(for: waypointAnnotation, in: mapView)
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {
            if annotation is WaypointAnnotation {
                removeCallout()
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            updateCalloutPosition(in: mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isProgrammaticRegionChange {
                isProgrammaticRegionChange = false
            }
            updateCalloutPosition(in: mapView)
            parent?.onRegionChanged?(mapView.region)
        }

        // MARK: - Callout Management

        func showCallout(for annotation: WaypointAnnotation, in mapView: MKMapView) {
            removeCallout()
            selectedWaypointAnnotation = annotation

            let content = WaypointCalloutContent(
                waypoint: annotation.waypoint,
                onClose: { [weak self] in
                    guard let self = self else { return }
                    mapView.deselectAnnotation(annotation, animated: true)
                    self.removeCallout()
                },
                onDelete: { [weak self] in
                    guard let self = self else { return }
                    self.removeCallout()
                    self.parent?.onDeleteWaypoint?(annotation.waypoint)
                }
            )

            let hostingController = UIHostingController(rootView: content)
            hostingController.view.backgroundColor = .clear
            hostingController.view.translatesAutoresizingMaskIntoConstraints = true

            let fittingSize = hostingController.view.intrinsicContentSize
            hostingController.view.frame.size = fittingSize

            mapView.addSubview(hostingController.view)
            calloutHostingController = hostingController

            updateCalloutPosition(in: mapView)
        }

        func removeCallout() {
            calloutHostingController?.view.removeFromSuperview()
            calloutHostingController = nil
            selectedWaypointAnnotation = nil
        }

        func updateCalloutPosition(in mapView: MKMapView) {
            guard let annotation = selectedWaypointAnnotation,
                  let calloutView = calloutHostingController?.view else { return }

            let point = mapView.convert(annotation.coordinate, toPointTo: mapView)
            let calloutSize = calloutView.intrinsicContentSize
            calloutView.frame = CGRect(
                x: point.x - calloutSize.width / 2,
                y: point.y - calloutSize.height - 20,
                width: calloutSize.width,
                height: calloutSize.height
            )
        }
    }
}

// MARK: - Callout Bubble Shape

struct CalloutBubbleShape: Shape {
    var cornerRadius: CGFloat = 10
    var triangleHeight: CGFloat = 8
    var triangleWidth: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let cardBottom = rect.height - triangleHeight
        var path = Path()

        path.move(to: CGPoint(x: 0, y: cornerRadius))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0),
                     tangent2End: CGPoint(x: cornerRadius, y: 0),
                     radius: cornerRadius)
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: 0))
        path.addArc(tangent1End: CGPoint(x: rect.width, y: 0),
                     tangent2End: CGPoint(x: rect.width, y: cornerRadius),
                     radius: cornerRadius)
        path.addLine(to: CGPoint(x: rect.width, y: cardBottom - cornerRadius))
        path.addArc(tangent1End: CGPoint(x: rect.width, y: cardBottom),
                     tangent2End: CGPoint(x: rect.width - cornerRadius, y: cardBottom),
                     radius: cornerRadius)
        path.addLine(to: CGPoint(x: rect.midX + triangleWidth / 2, y: cardBottom))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height))
        path.addLine(to: CGPoint(x: rect.midX - triangleWidth / 2, y: cardBottom))
        path.addLine(to: CGPoint(x: cornerRadius, y: cardBottom))
        path.addArc(tangent1End: CGPoint(x: 0, y: cardBottom),
                     tangent2End: CGPoint(x: 0, y: cardBottom - cornerRadius),
                     radius: cornerRadius)
        path.closeSubpath()

        return path
    }
}

// MARK: - Waypoint Callout Content

struct WaypointCalloutContent: View {
    let waypoint: Waypoint
    let onClose: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                // Header: risk dot, name, buttons
                HStack(spacing: 6) {
                    Circle()
                        .fill(riskColor)
                        .frame(width: 8, height: 8)
                    Text(waypoint.name ?? "Nokta \(waypoint.orderIndex + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                }

                if waypoint.windSpeed != nil {
                    Divider()

                    // Row 1: Wind + Temperature
                    HStack(spacing: 0) {
                        weatherItem(
                            icon: "wind",
                            value: String(format: "%.0f", waypoint.windSpeed ?? 0),
                            unit: "km/h",
                            extra: waypoint.windDirection?.windDirectionText,
                            tint: Color.windColor(for: waypoint.windSpeed ?? 0)
                        )
                        weatherItem(
                            icon: "thermometer.medium",
                            value: waypoint.temperature.map { "\(Int($0))" } ?? "-",
                            unit: "°C",
                            extra: nil,
                            tint: .orange
                        )
                    }

                    // Row 2: Wave + Period
                    HStack(spacing: 0) {
                        weatherItem(
                            icon: "water.waves",
                            value: waypoint.waveHeight.map { String(format: "%.1f", $0) } ?? "-",
                            unit: "m",
                            extra: nil,
                            tint: Color.waveColor(for: waypoint.waveHeight ?? 0)
                        )
                        weatherItem(
                            icon: "timer",
                            value: (waypoint.wavePeriod ?? 0) > 0
                                ? String(format: "%.1f", waypoint.wavePeriod!) : "-",
                            unit: "sn",
                            extra: nil,
                            tint: .cyan
                        )
                    }
                } else if waypoint.isLoading {
                    Divider()
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.5)
                        Text("Yukleniyor...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 24)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // Space for triangle
            Spacer().frame(height: 8)
        }
        .frame(width: 200)
        .background(.regularMaterial)
        .clipShape(CalloutBubbleShape())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    @ViewBuilder
    private func weatherItem(icon: String, value: String, unit: String, extra: String?, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            if let extra = extra {
                Text(extra)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
