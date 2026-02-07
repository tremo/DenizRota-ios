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

    var onTapCoordinate: ((CLLocationCoordinate2D) -> Void)?
    var onDeleteWaypoint: ((Waypoint) -> Void)?

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

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NauticalMapView?
        var lastRegionCenter = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        var lastRegionSpan = MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0)
        var isProgrammaticRegionChange = false

        // Callout management
        private var calloutContainer: UIView?
        private var calloutHosting: UIHostingController<AnyView>?
        private var selectedWaypointAnnotation: WaypointAnnotation?

        var isShowingCallout: Bool { calloutContainer != nil }

        // MARK: - Callout

        func showCallout(for annotation: WaypointAnnotation, in mapView: MKMapView) {
            removeCallout(animated: false)
            selectedWaypointAnnotation = annotation

            let waypoint = annotation.waypoint
            let calloutView = WaypointCalloutContent(
                waypoint: waypoint,
                onClose: { [weak self] in
                    self?.dismissCallout(in: mapView)
                },
                onDelete: { [weak self] in
                    self?.removeCallout(animated: false)
                    self?.parent?.onDeleteWaypoint?(waypoint)
                }
            )

            let hosting = UIHostingController(rootView: AnyView(calloutView))
            hosting.view.backgroundColor = .clear
            calloutHosting = hosting

            let fittingSize = hosting.sizeThatFits(in: CGSize(width: 220, height: 400))

            let container = UIView(frame: CGRect(origin: .zero, size: fittingSize))
            container.backgroundColor = .clear
            container.addSubview(hosting.view)
            hosting.view.frame = container.bounds

            mapView.addSubview(container)
            calloutContainer = container

            updateCalloutPosition(in: mapView)

            // Animate in
            container.alpha = 0
            container.transform = CGAffineTransform(scaleX: 0.85, y: 0.85).translatedBy(x: 0, y: 10)
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                container.alpha = 1
                container.transform = .identity
            }
        }

        func removeCallout(animated: Bool = true) {
            guard let container = calloutContainer else { return }

            if animated {
                UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn) {
                    container.alpha = 0
                    container.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                } completion: { _ in
                    container.removeFromSuperview()
                }
            } else {
                container.removeFromSuperview()
            }

            calloutContainer = nil
            calloutHosting = nil
            selectedWaypointAnnotation = nil
        }

        func dismissCallout(in mapView: MKMapView) {
            removeCallout()
            for annotation in mapView.selectedAnnotations {
                mapView.deselectAnnotation(annotation, animated: false)
            }
        }

        func updateCalloutPosition(in mapView: MKMapView) {
            guard let annotation = selectedWaypointAnnotation,
                  let container = calloutContainer else { return }

            let point = mapView.convert(annotation.coordinate, toPointTo: mapView)
            let size = container.bounds.size

            // Position above the pin (pin is 32x32 centered)
            var x = point.x - size.width / 2
            let y = point.y - size.height - 16

            // Keep within map bounds
            let margin: CGFloat = 8
            x = max(margin, min(x, mapView.bounds.width - size.width - margin))

            container.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        }

        // MARK: - Tap Handling

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let parent = parent,
                  let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)

            // Don't process if tap hit the callout
            if let callout = calloutContainer, callout.frame.contains(point) {
                return
            }

            // Don't process if tap hit an existing annotation
            for annotation in mapView.annotations {
                if let view = mapView.view(for: annotation) {
                    if view.frame.contains(point) {
                        return
                    }
                }
            }

            // If callout was showing, dismiss it without adding waypoint
            if isShowingCallout {
                dismissCallout(in: mapView)
                return
            }

            // Only add waypoint in route mode
            guard parent.isRouteMode else { return }

            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
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
