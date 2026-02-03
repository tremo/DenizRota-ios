import Foundation
import CoreLocation
import SwiftUI

// MARK: - Date Extensions
extension Date {
    /// ISO 8601 formatında string (saat hassasiyeti)
    var iso8601Hour: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let str = formatter.string(from: self)
        // "2024-01-15T14:30:00Z" -> "2024-01-15T14:00"
        return String(str.prefix(13)) + ":00"
    }

    /// Türkçe kısa tarih formatı (15 Oca)
    var shortDateTR: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: self)
    }

    /// Türkçe uzun tarih formatı (15 Ocak 2024)
    var longDateTR: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: self)
    }

    /// Saat formatı (14:30)
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    /// Tarih ve saat (15 Oca 14:30)
    var dateTimeStringTR: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM HH:mm"
        return formatter.string(from: self)
    }

    /// Göreceli zaman (2 saat önce, 3 gün önce)
    var relativeTimeTR: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Bugünün başlangıcı
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// Saat ekle
    func addingHours(_ hours: Double) -> Date {
        addingTimeInterval(hours * 3600)
    }

    /// Dakika ekle
    func addingMinutes(_ minutes: Double) -> Date {
        addingTimeInterval(minutes * 60)
    }
}

// MARK: - TimeInterval Extensions
extension TimeInterval {
    /// Saniyeden formatlanmış süre (1:30:45 veya 45 dk)
    var formattedDuration: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if minutes > 0 {
            return "\(minutes) dk \(seconds) sn"
        } else {
            return "\(seconds) sn"
        }
    }

    /// Kısa süre formatı (1:30 veya 45dk)
    var shortDuration: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60

        if hours > 0 {
            if minutes > 0 {
                return String(format: "%d:%02d", hours, minutes)
            }
            return "\(hours) saat"
        }
        return "\(minutes) dk"
    }

    /// Saatten formatlanmış süre
    static func fromHours(_ hours: Double) -> TimeInterval {
        hours * 3600
    }
}

// MARK: - Double Extensions
extension Double {
    /// Koordinat formatı (4 ondalık)
    var coordinateString: String {
        String(format: "%.4f", self)
    }

    /// Mesafe formatı (1.5 km veya 500 m)
    var distanceString: String {
        if self >= 1.0 {
            return String(format: "%.1f km", self)
        } else {
            return String(format: "%.0f m", self * 1000)
        }
    }

    /// Hız formatı (15.5 km/h)
    var speedString: String {
        String(format: "%.1f km/h", self)
    }

    /// Yüzde formatı (%85)
    var percentString: String {
        String(format: "%%%.0f", self * 100)
    }

    /// Para formatı (₺1,234)
    var currencyTRY: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "TRY"
        formatter.currencySymbol = "₺"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "₺\(Int(self))"
    }

    /// Derece to radyan
    var radians: Double {
        self * .pi / 180.0
    }

    /// Radyan to derece
    var degrees: Double {
        self * 180.0 / .pi
    }
}

// MARK: - CLLocationCoordinate2D Extensions
extension CLLocationCoordinate2D {
    /// İki koordinat arası mesafe (km)
    func distance(to other: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: latitude, longitude: longitude)
        let location2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return location1.distance(from: location2) / 1000.0
    }

    /// Koordinat string'i
    var displayString: String {
        String(format: "%.4f°, %.4f°", latitude, longitude)
    }

    /// Deniz alanında mı?
    var isInSea: Bool {
        SeaAreas.isInSea(lat: latitude, lng: longitude)
    }

    /// CLLocation'a dönüştür
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

// MARK: - CLLocation Extensions
extension CLLocation {
    /// Hız km/h cinsinden
    var speedKmh: Double {
        max(0, speed * 3.6)
    }

    /// Koordinat kısayolu
    var coord: CLLocationCoordinate2D {
        coordinate
    }
}

// MARK: - Array Extensions
extension Array where Element == CLLocationCoordinate2D {
    /// Koordinat dizisinin toplam mesafesi (km)
    var totalDistance: Double {
        guard count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<count {
            total += self[i - 1].distance(to: self[i])
        }
        return total
    }

    /// Merkez nokta
    var center: CLLocationCoordinate2D? {
        guard !isEmpty else { return nil }
        let totalLat = reduce(0.0) { $0 + $1.latitude }
        let totalLng = reduce(0.0) { $0 + $1.longitude }
        return CLLocationCoordinate2D(latitude: totalLat / Double(count), longitude: totalLng / Double(count))
    }
}

// MARK: - Color Extensions
extension Color {
    /// Risk seviyesi renkleri
    static let riskGreen = Color.green
    static let riskYellow = Color.yellow
    static let riskRed = Color.red
    static let riskGray = Color.gray

    /// Wind speed renkleri
    static func windColor(for speed: Double) -> Color {
        if speed < 10 { return .green }
        if speed < 20 { return .yellow }
        if speed < 30 { return .orange }
        if speed < 40 { return .red }
        return .purple
    }

    /// Wave height renkleri
    static func waveColor(for height: Double) -> Color {
        if height < 0.5 { return .green }
        if height < 1.0 { return .blue }
        if height < 1.5 { return .yellow }
        if height < 2.0 { return .orange }
        if height < 3.0 { return .red }
        return .purple
    }
}

// MARK: - View Extensions
extension View {
    /// Koşullu modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Gizleme modifier
    @ViewBuilder
    func hidden(_ isHidden: Bool) -> some View {
        if isHidden {
            self.hidden()
        } else {
            self
        }
    }
}

// MARK: - String Extensions
extension String {
    /// Boş veya whitespace kontrolü
    var isBlankOrEmpty: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// İlk harfi büyük
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

// MARK: - Optional Extensions
extension Optional where Wrapped == Double {
    /// Nil ise varsayılan değer döndür
    func orDefault(_ defaultValue: Double) -> Double {
        self ?? defaultValue
    }
}

extension Optional where Wrapped == String {
    /// Nil veya boş ise varsayılan değer döndür
    func orDefault(_ defaultValue: String) -> String {
        guard let value = self, !value.isBlankOrEmpty else {
            return defaultValue
        }
        return value
    }
}
