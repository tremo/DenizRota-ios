import Foundation
import UserNotifications
import AVFoundation
import AudioToolbox

final class NotificationManager {
    static let shared = NotificationManager()

    private var audioPlayer: AVAudioPlayer?

    private init() {
        configureAudioSession()
    }

    // MARK: - Setup

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
        } catch {
            print("Audio session error: \(error)")
        }
    }

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge, .criticalAlert]
            )
            print("Notification permission: \(granted)")
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    // MARK: - Arrival Notification

    func sendArrivalNotification(waypointName: String?, distance: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Hedefe Yaklaşıyorsunuz!"

        if let name = waypointName {
            content.body = "\(name) noktasına \(Int(distance)) metre kaldı"
        } else {
            content.body = "Bir sonraki noktaya \(Int(distance)) metre kaldı"
        }

        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)

        let request = UNNotificationRequest(
            identifier: "arrival-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }

        // Sesli uyarı (ekran kapalıyken de duyulsun)
        playAlertSound()
    }

    // MARK: - Weather Alert

    func sendWeatherAlert(title: String, message: String, critical: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = critical ? .defaultCritical : .default

        if critical {
            content.interruptionLevel = .critical
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)

        let request = UNNotificationRequest(
            identifier: "weather-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)

        if critical {
            playAlertSound()
        }
    }

    // MARK: - Speed Alert

    func sendSpeedAlert(currentSpeed: Double, limit: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Hız Uyarısı"
        content.body = String(format: "Mevcut hız: %.1f km/h (Limit: %.0f km/h)", currentSpeed, limit)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)

        let request = UNNotificationRequest(
            identifier: "speed-alert",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Route Deviation Alert

    func sendRouteDeviationAlert(distance: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Rotadan Sapma"
        content.body = String(format: "Rotanızdan %.0f metre uzaklaştınız", distance)
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)

        let request = UNNotificationRequest(
            identifier: "deviation-alert",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)

        playAlertSound()
    }

    // MARK: - Anchor Drag Alarm

    func sendAnchorDragAlarm(drift: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Demir Tarama Alarmi!"
        content.body = String(format: "Tekne demir noktasindan %dm uzaklasti!", Int(drift))
        content.sound = .defaultCritical
        content.interruptionLevel = .critical

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)

        let request = UNNotificationRequest(
            identifier: "anchor-drag-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Anchor alarm notification error: \(error)")
            }
        }

        // Kritik alarm sesi - sessiz modda bile duyulsun
        playCriticalAlertSound()
    }

    // MARK: - Audio

    private func playCriticalAlertSound() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            // Tekrarlayan alarm sesi (3 kez)
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8) {
                    AudioServicesPlaySystemSound(1005)
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        } catch {
            print("Critical audio error: \(error)")
        }
    }

    private func playAlertSound() {
        // Sistem sesi çal - ekran kapalıyken de çalışır
        do {
            try AVAudioSession.sharedInstance().setActive(true)

            // Sistem alert sesi
            AudioServicesPlaySystemSound(1005) // SMS tone

            // Veya custom ses dosyası:
            // if let soundURL = Bundle.main.url(forResource: "alert", withExtension: "wav") {
            //     audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            //     audioPlayer?.play()
            // }
        } catch {
            print("Audio playback error: \(error)")
        }
    }

    // MARK: - Clear

    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
