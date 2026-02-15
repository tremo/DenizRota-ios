import SwiftUI
import MapKit
import AudioToolbox

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
    @objc dynamic var coordinate: CLLocationCoordinate2D

    var title: String? {
        waypoint.name
    }

    init(waypoint: Waypoint, number: Int) {
        self.waypoint = waypoint
        self.number = number
        self.coordinate = waypoint.coordinate
    }
}

class UserLocationAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

// MARK: - Anchor Alarm Annotations

class AnchorCenterAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

class AnchorRadiusHandleAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

class AnchorRadiusLabelAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var radius: Double = 50

    init(coordinate: CLLocationCoordinate2D, radius: Double) {
        self.coordinate = coordinate
        self.radius = radius
    }
}

// MARK: - Anchor Circle Overlay

class AnchorCircleOverlay: MKCircle {}

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

    // Anchor alarm
    var anchorAlarmState: AnchorAlarmState = .idle
    var anchorCenter: CLLocationCoordinate2D?
    var anchorRadius: Double = 50
    var isAlarmTriggered: Bool = false

    // Ruzgar partikul overlay
    var showWindOverlay: Bool = false
    var windData: [WindGridPoint] = []

    var onTapCoordinate: ((CLLocationCoordinate2D) -> Void)?
    var onDeleteWaypoint: ((Waypoint) -> Void)?
    var onRegionChanged: ((MKCoordinateRegion) -> Void)?
    var onWaypointMoved: ((Waypoint, CLLocationCoordinate2D) -> Void)?
    var onInsertWaypoint: ((CLLocationCoordinate2D, Int) -> Void)?
    var onAnchorCenterChanged: ((CLLocationCoordinate2D) -> Void)?
    var onAnchorRadiusChanged: ((Double) -> Void)?

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

        // Long press gesture: rota cizgisi uzerinde 3 sn basinca araya waypoint ekle
        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 3.0
        longPressGesture.allowableMovement = 10
        longPressGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(longPressGesture)
        context.coordinator.longPressGesture = longPressGesture

        if showOpenSeaMap {
            addOpenSeaMapOverlay(to: mapView)
        }

        // Ruzgar partikul view'i MKMapView'in subview'i olarak ekle
        let particleView = WindParticleView(frame: mapView.bounds)
        particleView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        particleView.mapView = mapView
        mapView.addSubview(particleView)
        context.coordinator.windParticleView = particleView

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        if mapView.mapType != mapStyle.mapType {
            mapView.mapType = mapStyle.mapType
        }

        updateOpenSeaMapOverlay(mapView)
        updateRegion(mapView, context: context)
        if !context.coordinator.isDraggingWaypoint {
            updateAnnotations(mapView)
            updateRouteOverlay(mapView)
        }
        updateAnchorOverlay(mapView, context: context)
        updateWindOverlay(context: context)
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
                    view.isDraggable = isRouteMode

                    // Pulsating animasyon: yukleniyor ise ekle, degilse kaldir
                    if waypoint.isLoading {
                        Self.addPulseAnimation(to: view)
                    } else {
                        Self.removePulseAnimation(from: view)
                    }
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

    // MARK: - Anchor Overlay

    private func updateAnchorOverlay(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        if anchorAlarmState == .idle {
            // Tum anchor elemanlarini temizle
            removeAnchorElements(from: mapView, coordinator: coordinator)
            return
        }

        guard let center = anchorCenter else {
            removeAnchorElements(from: mapView, coordinator: coordinator)
            return
        }

        // --- Circle Overlay ---
        // Sadece center veya radius degismisse guncelle (flicker onlemi)
        let existingCircle = mapView.overlays.compactMap { $0 as? AnchorCircleOverlay }.first
        let needsCircleUpdate = existingCircle == nil ||
            abs(existingCircle!.coordinate.latitude - center.latitude) > 0.00001 ||
            abs(existingCircle!.coordinate.longitude - center.longitude) > 0.00001 ||
            abs(existingCircle!.radius - anchorRadius) > 0.1

        if needsCircleUpdate {
            for overlay in mapView.overlays where overlay is AnchorCircleOverlay {
                mapView.removeOverlay(overlay)
            }
            let circle = AnchorCircleOverlay(center: center, radius: anchorRadius)
            mapView.addOverlay(circle, level: .aboveRoads)
        }

        // --- Center Annotation ---
        let existingCenters = mapView.annotations.compactMap { $0 as? AnchorCenterAnnotation }
        if let existing = existingCenters.first {
            UIView.animate(withDuration: 0.2) {
                existing.coordinate = center
            }
        } else {
            let annotation = AnchorCenterAnnotation(coordinate: center)
            mapView.addAnnotation(annotation)
        }

        // --- Radius Handle (sadece drafting modunda) ---
        let existingHandles = mapView.annotations.compactMap { $0 as? AnchorRadiusHandleAnnotation }
        if anchorAlarmState == .drafting {
            let handleCoord = coordinateFromCenter(center, distanceMeters: anchorRadius, bearing: 90)
            if let existing = existingHandles.first {
                UIView.animate(withDuration: 0.2) {
                    existing.coordinate = handleCoord
                }
            } else {
                let handle = AnchorRadiusHandleAnnotation(coordinate: handleCoord)
                mapView.addAnnotation(handle)
            }
        } else {
            existingHandles.forEach { mapView.removeAnnotation($0) }
        }

        // --- Radius Label ---
        let existingLabels = mapView.annotations.compactMap { $0 as? AnchorRadiusLabelAnnotation }
        let labelCoord = coordinateFromCenter(center, distanceMeters: anchorRadius, bearing: 0)
        if let existing = existingLabels.first {
            existing.radius = anchorRadius
            UIView.animate(withDuration: 0.2) {
                existing.coordinate = labelCoord
            }
            // Label guncelle
            if let view = mapView.view(for: existing) {
                view.image = Self.renderRadiusLabel(radius: anchorRadius)
            }
        } else {
            let label = AnchorRadiusLabelAnnotation(coordinate: labelCoord, radius: anchorRadius)
            mapView.addAnnotation(label)
        }

        // Drag gesture'lari ayarla (sadece drafting modunda)
        coordinator.setupAnchorGestures(mapView: mapView, isDrafting: anchorAlarmState == .drafting)
    }

    private func removeAnchorElements(from mapView: MKMapView, coordinator: Coordinator) {
        for overlay in mapView.overlays where overlay is AnchorCircleOverlay {
            mapView.removeOverlay(overlay)
        }
        mapView.annotations.compactMap { $0 as? AnchorCenterAnnotation }.forEach {
            mapView.removeAnnotation($0)
        }
        mapView.annotations.compactMap { $0 as? AnchorRadiusHandleAnnotation }.forEach {
            mapView.removeAnnotation($0)
        }
        mapView.annotations.compactMap { $0 as? AnchorRadiusLabelAnnotation }.forEach {
            mapView.removeAnnotation($0)
        }
        coordinator.removeAnchorGestures(from: mapView)
    }

    /// Merkez koordinattan belirli mesafe ve yon ile yeni koordinat hesapla
    private func coordinateFromCenter(
        _ center: CLLocationCoordinate2D,
        distanceMeters: Double,
        bearing: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0 // metre
        let angularDistance = distanceMeters / earthRadius
        let bearingRad = bearing * .pi / 180.0
        let lat1 = center.latitude * .pi / 180.0
        let lng1 = center.longitude * .pi / 180.0

        let lat2 = asin(
            sin(lat1) * cos(angularDistance) +
            cos(lat1) * sin(angularDistance) * cos(bearingRad)
        )
        let lng2 = lng1 + atan2(
            sin(bearingRad) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(
            latitude: lat2 * 180.0 / .pi,
            longitude: lng2 * 180.0 / .pi
        )
    }

    // MARK: - Wind Overlay

    private func updateWindOverlay(context: Context) {
        guard let particleView = context.coordinator.windParticleView else { return }
        particleView.windData = windData
        if showWindOverlay && !particleView.isAnimating {
            particleView.startAnimation()
        } else if !showWindOverlay && particleView.isAnimating {
            particleView.stopAnimation()
        }
    }

    // MARK: - Rendering Helpers

    static func renderWaypointImage(number: Int, riskLevel: RiskLevel, isLoading: Bool) -> UIImage {
        let size: CGFloat = 32
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let color: UIColor
            if isLoading {
                color = .systemGray
            } else {
                switch riskLevel {
                case .green: color = .systemGreen
                case .yellow: color = .systemOrange
                case .red: color = .systemRed
                case .unknown: color = .systemGray
                }
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

    // MARK: - Pulse Animation

    private static let pulseAnimationKey = "waypointPulse"

    static func addPulseAnimation(to view: MKAnnotationView) {
        guard view.layer.animation(forKey: pulseAnimationKey) == nil else { return }

        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 1.0
        opacityAnim.toValue = 0.35

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 1.0
        scaleAnim.toValue = 0.85

        let group = CAAnimationGroup()
        group.animations = [opacityAnim, scaleAnim]
        group.duration = 0.8
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        view.layer.add(group, forKey: pulseAnimationKey)
    }

    static func removePulseAnimation(from view: MKAnnotationView) {
        guard view.layer.animation(forKey: pulseAnimationKey) != nil else { return }
        view.layer.removeAnimation(forKey: pulseAnimationKey)
        view.layer.opacity = 1.0
        view.layer.transform = CATransform3DIdentity
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

    // MARK: - Anchor Rendering Helpers

    static func renderAnchorCenterImage(isTriggered: Bool) -> UIImage {
        let size: CGFloat = 44
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let bgColor: UIColor = isTriggered ? .systemRed : .systemBlue
            bgColor.withAlphaComponent(0.15).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))

            bgColor.setFill()
            let innerSize: CGFloat = 28
            let innerOrigin = (size - innerSize) / 2
            ctx.cgContext.fillEllipse(in: CGRect(x: innerOrigin, y: innerOrigin, width: innerSize, height: innerSize))

            UIColor.white.setStroke()
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.strokeEllipse(in: CGRect(x: innerOrigin, y: innerOrigin, width: innerSize, height: innerSize))

            // Capa ikonu (basit)
            let iconAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let icon = "⚓"
            let iconSize = icon.size(withAttributes: iconAttrs)
            let iconPoint = CGPoint(
                x: (size - iconSize.width) / 2,
                y: (size - iconSize.height) / 2
            )
            icon.draw(at: iconPoint, withAttributes: iconAttrs)
        }
    }

    static func renderRadiusHandleImage() -> UIImage {
        let size: CGFloat = 28
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                                   color: UIColor.black.withAlphaComponent(0.3).cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: size - 4, height: size - 4))

            ctx.cgContext.setShadow(offset: .zero, blur: 0)
            UIColor.systemBlue.setFill()
            let dotSize: CGFloat = 10
            let dotOrigin = (size - dotSize) / 2
            ctx.cgContext.fillEllipse(in: CGRect(x: dotOrigin, y: dotOrigin, width: dotSize, height: dotSize))
        }
    }

    static func renderRadiusLabel(radius: Double) -> UIImage {
        let text = "\(Int(radius))m"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        let padding: CGFloat = 8
        let size = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 2,
                                   color: UIColor.black.withAlphaComponent(0.3).cgColor)
            UIColor.systemBlue.withAlphaComponent(0.85).setFill()
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6)
            path.fill()

            ctx.cgContext.setShadow(offset: .zero, blur: 0)
            let textPoint = CGPoint(x: padding, y: padding / 2)
            text.draw(at: textPoint, withAttributes: attrs)
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
        var windParticleView: WindParticleView?

        // Waypoint drag state
        var isDraggingWaypoint = false
        var longPressGesture: UILongPressGestureRecognizer?

        // Anchor alarm gesture state
        private var anchorPanGesture: UIPanGestureRecognizer?
        private var isDraggingAnchorCenter = false
        private var isDraggingRadiusHandle = false
        private var dragStartCoordinate: CLLocationCoordinate2D?

        // MARK: - Anchor Gesture Setup

        func setupAnchorGestures(mapView: MKMapView, isDrafting: Bool) {
            if isDrafting && anchorPanGesture == nil {
                let pan = UIPanGestureRecognizer(target: self, action: #selector(handleAnchorPan(_:)))
                pan.delegate = self
                mapView.addGestureRecognizer(pan)
                anchorPanGesture = pan
            } else if !isDrafting {
                removeAnchorGestures(from: mapView)
            }
        }

        func removeAnchorGestures(from mapView: MKMapView) {
            if let gesture = anchorPanGesture {
                mapView.removeGestureRecognizer(gesture)
                anchorPanGesture = nil
            }
            isDraggingAnchorCenter = false
            isDraggingRadiusHandle = false
        }

        @objc func handleAnchorPan(_ gesture: UIPanGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

            switch gesture.state {
            case .began:
                // Hangi elemani surukledigimizi belirle
                if let handleAnnotation = mapView.annotations.first(where: { $0 is AnchorRadiusHandleAnnotation }),
                   let handleView = mapView.view(for: handleAnnotation) {
                    let handlePoint = gesture.location(in: handleView)
                    let hitArea = handleView.bounds.insetBy(dx: -20, dy: -20)
                    if hitArea.contains(handlePoint) {
                        isDraggingRadiusHandle = true
                        mapView.isScrollEnabled = false
                        return
                    }
                }

                if let centerAnnotation = mapView.annotations.first(where: { $0 is AnchorCenterAnnotation }),
                   let centerView = mapView.view(for: centerAnnotation) {
                    let centerPoint = gesture.location(in: centerView)
                    let hitArea = centerView.bounds.insetBy(dx: -20, dy: -20)
                    if hitArea.contains(centerPoint) {
                        isDraggingAnchorCenter = true
                        mapView.isScrollEnabled = false
                        return
                    }
                }

            case .changed:
                if isDraggingAnchorCenter {
                    parent?.onAnchorCenterChanged?(coordinate)
                } else if isDraggingRadiusHandle {
                    guard let center = parent?.anchorCenter else { return }
                    let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
                    let handleLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    let newRadius = centerLocation.distance(from: handleLocation)
                    parent?.onAnchorRadiusChanged?(newRadius)
                }

            case .ended, .cancelled:
                isDraggingAnchorCenter = false
                isDraggingRadiusHandle = false
                mapView.isScrollEnabled = true

            default:
                break
            }
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Anchor pan gesture: sadece anchor/handle uzerindeyse basla
            if gestureRecognizer === anchorPanGesture {
                guard let mapView = gestureRecognizer.view as? MKMapView else { return false }
                let point = gestureRecognizer.location(in: mapView)

                // Handle uzerinde mi?
                if let handleAnnotation = mapView.annotations.first(where: { $0 is AnchorRadiusHandleAnnotation }),
                   let handleView = mapView.view(for: handleAnnotation) {
                    let handlePoint = gestureRecognizer.location(in: handleView)
                    if handleView.bounds.insetBy(dx: -20, dy: -20).contains(handlePoint) {
                        return true
                    }
                }

                // Center uzerinde mi?
                if let centerAnnotation = mapView.annotations.first(where: { $0 is AnchorCenterAnnotation }),
                   let centerView = mapView.view(for: centerAnnotation) {
                    let centerPoint = gestureRecognizer.location(in: centerView)
                    if centerView.bounds.insetBy(dx: -20, dy: -20).contains(centerPoint) {
                        return true
                    }
                }

                return false
            }

            // Long press gesture: rota modunda polyline yakininda
            if gestureRecognizer === longPressGesture {
                guard let parent = parent, parent.isRouteMode,
                      let mapView = gestureRecognizer.view as? MKMapView,
                      let route = parent.activeRoute,
                      route.waypoints.count > 1 else { return false }

                let point = gestureRecognizer.location(in: mapView)
                let sortedWaypoints = route.sortedWaypoints
                for i in 0..<(sortedWaypoints.count - 1) {
                    let startPoint = mapView.convert(sortedWaypoints[i].coordinate, toPointTo: mapView)
                    let endPoint = mapView.convert(sortedWaypoints[i + 1].coordinate, toPointTo: mapView)
                    if distanceFromPoint(point, toSegmentFrom: startPoint, to: endPoint) < 44 {
                        return true
                    }
                }
                return false
            }

            // Tap gesture: rota modu icin
            guard let parent = parent, parent.isRouteMode,
                  let mapView = gestureRecognizer.view as? MKMapView else {
                return false
            }

            let point = gestureRecognizer.location(in: mapView)

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

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Anchor pan ile harita scroll ayni anda calismasin
            if gestureRecognizer === anchorPanGesture || otherGestureRecognizer === anchorPanGesture {
                return false
            }
            // Long press ile diger gesture'lar ayni anda calismasin
            if gestureRecognizer === longPressGesture || otherGestureRecognizer === longPressGesture {
                return false
            }
            return false
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let parent = parent,
                  let mapView = gesture.view as? MKMapView else { return }

            let coordinate = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            parent.onTapCoordinate?(coordinate)
        }

        // MARK: - Long Press (Araya Waypoint Ekleme)

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let parent = parent,
                  parent.isRouteMode,
                  let mapView = gesture.view as? MKMapView,
                  let route = parent.activeRoute,
                  route.waypoints.count > 1 else { return }

            let touchPoint = gesture.location(in: mapView)
            let sortedWaypoints = route.sortedWaypoints

            var closestSegmentIndex = -1
            var closestDistance: CGFloat = .greatestFiniteMagnitude

            for i in 0..<(sortedWaypoints.count - 1) {
                let startPoint = mapView.convert(sortedWaypoints[i].coordinate, toPointTo: mapView)
                let endPoint = mapView.convert(sortedWaypoints[i + 1].coordinate, toPointTo: mapView)
                let distance = distanceFromPoint(touchPoint, toSegmentFrom: startPoint, to: endPoint)

                if distance < closestDistance {
                    closestDistance = distance
                    closestSegmentIndex = i
                }
            }

            guard closestDistance < 44, closestSegmentIndex >= 0 else { return }

            let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
            parent.onInsertWaypoint?(coordinate, closestSegmentIndex + 1)

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }

        /// Nokta ile dogru parcasi arasindaki en kisa mesafe (ekran koordinatlarinda)
        private func distanceFromPoint(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy

            if lengthSquared == 0 { return hypot(point.x - start.x, point.y - start.y) }

            var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
            t = max(0, min(1, t))

            let projX = start.x + t * dx
            let projY = start.y + t * dy

            return hypot(point.x - projX, point.y - projY)
        }

        // MARK: - Waypoint Drag

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard let waypointAnnotation = view.annotation as? WaypointAnnotation else { return }

            switch newState {
            case .starting:
                isDraggingWaypoint = true
                removeCallout()

            case .dragging:
                updateRoutePolylineDuringDrag(mapView)

            case .ending:
                let newCoordinate = waypointAnnotation.coordinate
                parent?.onWaypointMoved?(waypointAnnotation.waypoint, newCoordinate)
                view.dragState = .none
                isDraggingWaypoint = false
                updateRoutePolylineDuringDrag(mapView)
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

            case .canceling:
                waypointAnnotation.coordinate = waypointAnnotation.waypoint.coordinate
                view.dragState = .none
                isDraggingWaypoint = false
                updateRoutePolylineDuringDrag(mapView)

            default:
                break
            }
        }

        /// Drag sirasinda polyline'i annotation'larin guncel konumlarindan yeniden ciz
        private func updateRoutePolylineDuringDrag(_ mapView: MKMapView) {
            for overlay in mapView.overlays where overlay is MKPolyline {
                mapView.removeOverlay(overlay)
            }

            let waypointAnnotations = mapView.annotations
                .compactMap { $0 as? WaypointAnnotation }
                .sorted { $0.number < $1.number }

            guard waypointAnnotations.count > 1 else { return }

            var coordinates = waypointAnnotations.map(\.coordinate)
            let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
            mapView.addOverlay(polyline, level: .aboveRoads)
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(overlay: tileOverlay)
            }

            if let anchorCircle = overlay as? AnchorCircleOverlay {
                let renderer = MKCircleRenderer(circle: anchorCircle)
                let isTriggered = parent?.isAlarmTriggered ?? false
                let isActive = parent?.anchorAlarmState == .active
                renderer.strokeColor = isTriggered ? .systemRed : .systemBlue
                renderer.fillColor = isTriggered
                    ? UIColor.systemRed.withAlphaComponent(0.08)
                    : UIColor.systemBlue.withAlphaComponent(0.08)
                renderer.lineWidth = isActive ? 3 : 2
                renderer.lineDashPattern = isActive ? nil : [8, 6]
                return renderer
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
                view.isDraggable = parent?.isRouteMode ?? false

                // Yukleniyor ise pulsating animasyon ekle
                if waypointAnnotation.waypoint.isLoading {
                    NauticalMapView.addPulseAnimation(to: view)
                }

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

            if annotation is AnchorCenterAnnotation {
                let identifier = "AnchorCenter"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ??
                    MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

                view.annotation = annotation
                view.canShowCallout = false
                let isTriggered = parent?.isAlarmTriggered ?? false
                view.image = NauticalMapView.renderAnchorCenterImage(isTriggered: isTriggered)
                view.centerOffset = CGPoint(x: 0, y: 0)
                view.isDraggable = false
                view.zPriority = .max

                return view
            }

            if annotation is AnchorRadiusHandleAnnotation {
                let identifier = "AnchorHandle"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ??
                    MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

                view.annotation = annotation
                view.canShowCallout = false
                view.image = NauticalMapView.renderRadiusHandleImage()
                view.centerOffset = CGPoint(x: 0, y: 0)
                view.isDraggable = false

                return view
            }

            if let labelAnnotation = annotation as? AnchorRadiusLabelAnnotation {
                let identifier = "AnchorLabel"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ??
                    MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

                view.annotation = annotation
                view.canShowCallout = false
                view.image = NauticalMapView.renderRadiusLabel(radius: labelAnnotation.radius)
                view.centerOffset = CGPoint(x: 0, y: -10)

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
            parent?.onRegionChanged?(mapView.region)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isProgrammaticRegionChange {
                isProgrammaticRegionChange = false
            }
            updateCalloutPosition(in: mapView)
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
