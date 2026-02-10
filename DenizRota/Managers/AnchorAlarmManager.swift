import Foundation
import CoreLocation
import Combine

enum AnchorAlarmState: Equatable {
    case idle
    case drafting
    case active
}

@MainActor
final class AnchorAlarmManager: ObservableObject {
    static let shared = AnchorAlarmManager()

    // MARK: - Published State

    @Published var state: AnchorAlarmState = .idle
    @Published var anchorCenter: CLLocationCoordinate2D?
    @Published var radius: Double = 50 // metre
    @Published var isAlarmTriggered = false
    @Published var currentDrift: Double = 0 // metre

    // MARK: - Anti-Drift Filter

    /// Ust uste daire disinda kalan konum sayisi
    private var consecutiveOutsideCount = 0
    private let requiredConsecutiveCount = 3

    // MARK: - UserDefaults

    private let radiusKey = "anchorAlarmLastRadius"

    // MARK: - Init

    private init() {
        // Son kullanilan yaricapi yukle
        let savedRadius = UserDefaults.standard.double(forKey: radiusKey)
        if savedRadius > 0 {
            radius = savedRadius
        }
    }

    // MARK: - Draft Mode

    /// Draft modunu baslat - mevcut konum merkez olur
    func startDrafting(at coordinate: CLLocationCoordinate2D) {
        anchorCenter = coordinate
        isAlarmTriggered = false
        consecutiveOutsideCount = 0
        currentDrift = 0
        state = .drafting
    }

    /// Draft modunu iptal et
    func cancelDrafting() {
        state = .idle
        anchorCenter = nil
        isAlarmTriggered = false
        consecutiveOutsideCount = 0
        currentDrift = 0
    }

    // MARK: - Alarm Activation

    /// Alarmi aktif et (draft'tan gecis)
    func activateAlarm() {
        guard state == .drafting, anchorCenter != nil else { return }
        state = .active
        consecutiveOutsideCount = 0
        isAlarmTriggered = false

        // Yaricapi kaydet
        UserDefaults.standard.set(radius, forKey: radiusKey)
    }

    /// Alarmi durdur
    func deactivateAlarm() {
        state = .idle
        anchorCenter = nil
        isAlarmTriggered = false
        consecutiveOutsideCount = 0
        currentDrift = 0
    }

    // MARK: - Location Check

    /// Yeni konum verisi geldiginde cagrilir
    func checkLocation(_ location: CLLocation) {
        guard state == .active, let center = anchorCenter else { return }

        let centerLocation = CLLocation(
            latitude: center.latitude,
            longitude: center.longitude
        )
        let distance = location.distance(from: centerLocation) // metre

        currentDrift = distance

        if distance > radius {
            consecutiveOutsideCount += 1

            if consecutiveOutsideCount >= requiredConsecutiveCount && !isAlarmTriggered {
                triggerAlarm(drift: distance)
            }
        } else {
            // Daire icine dondu - sayaci sifirla
            consecutiveOutsideCount = 0

            if isAlarmTriggered {
                // Tekne geri dondu, alarmi sustur
                isAlarmTriggered = false
            }
        }
    }

    // MARK: - Alarm Trigger

    private func triggerAlarm(drift: Double) {
        isAlarmTriggered = true

        NotificationManager.shared.sendAnchorDragAlarm(drift: drift)

        print("ANCHOR ALARM: Tekne \(Int(drift))m sapmis!")
    }

    // MARK: - Radius Adjustment

    func updateRadius(_ newRadius: Double) {
        radius = max(10, min(500, newRadius)) // 10m - 500m arasi
    }

    func updateCenter(_ newCenter: CLLocationCoordinate2D) {
        guard state == .drafting else { return }
        anchorCenter = newCenter
    }
}
