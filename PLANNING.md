# DenizRota iOS - Proje Planı

## Genel Bakış

Native Swift/SwiftUI ile geliştirilecek iOS uygulaması. Mevcut web uygulamasının tüm özelliklerini içerecek, artı mobil-spesifik özellikler eklenecek.

## Temel Özellikler

### Faz 1: Çekirdek Özellikler (MVP)
- [ ] Harita görünümü (MapKit)
- [ ] Rota oluşturma ve waypoint yönetimi
- [ ] Hava durumu ve deniz verileri (Open-Meteo API)
- [ ] Rüzgar/dalga overlay görselleştirmesi
- [ ] Temel ayarlar (tekne bilgileri)

### Faz 2: Seyir Takibi
- [ ] GPS tabanlı trip tracking
- [ ] **Background Location** - ekran kapalıyken çalışma
- [ ] Hız göstergesi (anlık, ortalama, maksimum)
- [ ] Mesafe hesaplama
- [ ] Trip geçmişi

### Faz 3: Bildirimler
- [ ] **Hedefe varış bildirimi** - waypoint'e yaklaşınca
- [ ] Hava durumu uyarıları (rüzgar/dalga limitleri)
- [ ] Rota sapma uyarısı
- [ ] Sesli uyarılar (ekran kapalıyken)

### Faz 4: Cloud Sync
- [ ] Firebase Authentication
- [ ] Firestore ile data senkronizasyonu
- [ ] Web app ile ortak data

## Teknik Mimari

### Teknoloji Stack

| Bileşen | Teknoloji |
|---------|-----------|
| UI Framework | SwiftUI |
| Harita | MapKit |
| Networking | URLSession + async/await |
| Persistence | SwiftData / Core Data |
| Background Tasks | Core Location (Background Modes) |
| Notifications | UserNotifications + UNLocationNotificationTrigger |
| Cloud | Firebase iOS SDK |

### Minimum iOS Versiyonu
- **iOS 17.0** (SwiftUI güncel özellikler, SwiftData)

### Proje Yapısı

```
DenizRota-iOS/
├── DenizRota.xcodeproj
├── DenizRota/
│   ├── App/
│   │   ├── DenizRotaApp.swift          # Ana uygulama entry point
│   │   └── AppDelegate.swift           # Background handling
│   │
│   ├── Models/
│   │   ├── Waypoint.swift              # Waypoint modeli
│   │   ├── Route.swift                 # Rota modeli
│   │   ├── Trip.swift                  # Seyir kaydı modeli
│   │   ├── Weather.swift               # Hava durumu modeli
│   │   └── BoatSettings.swift          # Tekne ayarları
│   │
│   ├── Views/
│   │   ├── MainView.swift              # Ana görünüm (tab bar)
│   │   ├── Map/
│   │   │   ├── MapView.swift           # Harita görünümü
│   │   │   ├── MapOverlays.swift       # Rüzgar/dalga overlay
│   │   │   └── WaypointAnnotation.swift
│   │   ├── Route/
│   │   │   ├── RouteListView.swift     # Kayıtlı rotalar
│   │   │   ├── RouteDetailView.swift   # Rota detayı
│   │   │   └── WaypointRowView.swift
│   │   ├── Trip/
│   │   │   ├── TripTrackingView.swift  # Aktif seyir
│   │   │   ├── TripHistoryView.swift   # Geçmiş seyirler
│   │   │   └── SpeedPanelView.swift    # Hız göstergesi
│   │   └── Settings/
│   │       ├── SettingsView.swift
│   │       └── BoatSettingsView.swift
│   │
│   ├── Services/
│   │   ├── LocationManager.swift       # GPS + Background Location
│   │   ├── WeatherService.swift        # Open-Meteo API
│   │   ├── NotificationManager.swift   # Local notifications
│   │   ├── FetchCalculator.swift       # Kıyı fetch hesaplama
│   │   └── RouteCalculator.swift       # Mesafe/süre hesaplama
│   │
│   ├── Managers/
│   │   ├── TripManager.swift           # Seyir yönetimi
│   │   ├── RouteManager.swift          # Rota yönetimi
│   │   └── FirebaseManager.swift       # Cloud sync
│   │
│   ├── Utils/
│   │   ├── Constants.swift             # Sabitler
│   │   ├── Extensions.swift            # Swift extensions
│   │   └── CoastlineData.swift         # Türkiye kıyı verileri
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Localizable.strings         # Türkçe stringler
│       └── Info.plist
│
├── DenizRotaTests/
└── DenizRotaUITests/
```

## Background Location Implementasyonu

### Info.plist Gereksinimleri

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Rotanızı takip etmek için konum izni gerekiyor.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Ekran kapalıyken de seyrinizi takip edebilmek için sürekli konum izni gerekiyor.</string>

<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>processing</string>
</array>
```

### LocationManager.swift Temel Yapı

```swift
import CoreLocation
import Combine

@MainActor
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    private let locationManager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var currentSpeed: Double = 0 // km/h
    @Published var isTracking = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // Trip tracking
    private var tripPositions: [CLLocation] = []
    private var tripStartTime: Date?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 10 // 10 metre minimum hareket
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
    }

    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    func startTracking() {
        guard authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }

        isTracking = true
        tripStartTime = Date()
        tripPositions.removeAll()
        locationManager.startUpdatingLocation()
    }

    func stopTracking() -> Trip? {
        locationManager.stopUpdatingLocation()
        isTracking = false

        guard let startTime = tripStartTime else { return nil }

        // Trip oluştur ve döndür
        return createTrip(startTime: startTime, positions: tripPositions)
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Accuracy filtresi (50m üstü atla)
        guard location.horizontalAccuracy <= 50 else { return }

        // GPS noise filtresi (1km üstü atlama)
        if let lastPosition = tripPositions.last {
            let distance = location.distance(from: lastPosition)
            if distance > 1000 { return }
        }

        currentLocation = location
        currentSpeed = max(0, location.speed * 3.6) // m/s -> km/h

        if isTracking {
            tripPositions.append(location)
            checkWaypointProximity(location)
        }
    }

    private func checkWaypointProximity(_ location: CLLocation) {
        // Hedefe yaklaşma kontrolü - bildirim tetikle
        // NotificationManager ile entegre
    }
}
```

## Bildirim Sistemi

### NotificationManager.swift

```swift
import UserNotifications
import CoreLocation

class NotificationManager {
    static let shared = NotificationManager()

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // Hedefe varış bildirimi
    func scheduleArrivalNotification(waypoint: Waypoint, distance: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Hedefe Yaklaşıyorsunuz"
        content.body = "\(waypoint.name ?? "Waypoint")'a \(Int(distance))m kaldı"
        content.sound = .default

        // Hemen göster
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: "arrival-\(waypoint.id)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    // Hava durumu uyarısı
    func scheduleWeatherAlert(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Hava Durumu Uyarısı"
        content.body = message
        content.sound = .defaultCritical

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }
}
```

## Open-Meteo API Servisi

### WeatherService.swift

```swift
import Foundation

actor WeatherService {
    static let shared = WeatherService()

    private let weatherURL = "https://api.open-meteo.com/v1/forecast"
    private let marineURL = "https://marine-api.open-meteo.com/v1/marine"

    private var cache: [String: (data: WeatherData, timestamp: Date)] = [:]
    private let cacheExpiration: TimeInterval = 3600 // 1 saat

    func fetchWeather(lat: Double, lng: Double) async throws -> WeatherData {
        let cacheKey = "\(String(format: "%.2f", lat)),\(String(format: "%.2f", lng))"

        // Cache kontrolü
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheExpiration {
            return cached.data
        }

        // Paralel API çağrıları
        async let weatherTask = fetchWeatherData(lat: lat, lng: lng)
        async let marineTask = fetchMarineData(lat: lat, lng: lng)

        let (weather, marine) = try await (weatherTask, marineTask)

        let combinedData = WeatherData(
            windSpeed: weather.windSpeed,
            windDirection: weather.windDirection,
            windGusts: weather.windGusts,
            temperature: weather.temperature,
            waveHeight: marine?.waveHeight ?? 0,
            waveDirection: marine?.waveDirection ?? 0,
            wavePeriod: marine?.wavePeriod ?? 0
        )

        cache[cacheKey] = (combinedData, Date())
        return combinedData
    }

    private func fetchWeatherData(lat: Double, lng: Double) async throws -> WeatherResponse {
        var components = URLComponents(string: weatherURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lng)),
            URLQueryItem(name: "current", value: "temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(WeatherResponse.self, from: data)
    }

    private func fetchMarineData(lat: Double, lng: Double) async throws -> MarineResponse? {
        var components = URLComponents(string: marineURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lng)),
            URLQueryItem(name: "current", value: "wave_height,wave_direction,wave_period"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        do {
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            return try JSONDecoder().decode(MarineResponse.self, from: data)
        } catch {
            // Marine API opsiyonel
            return nil
        }
    }
}
```

## Xcode Proje Oluşturma Adımları

### 1. Yeni Proje
1. Xcode → File → New → Project
2. iOS → App seç
3. Product Name: `DenizRota`
4. Interface: **SwiftUI**
5. Language: **Swift**
6. Storage: **SwiftData**
7. "Include Tests" işaretle

### 2. Capabilities Ekle
1. Project → Targets → DenizRota → Signing & Capabilities
2. "+ Capability" tıkla:
   - **Background Modes** → Location updates işaretle
   - **Push Notifications** (ileride Firebase için)

### 3. Info.plist Düzenle
Location permission açıklamalarını ekle (yukarıdaki XML)

### 4. Paket Bağımlılıkları
File → Add Package Dependencies:
- Firebase iOS SDK: `https://github.com/firebase/firebase-ios-sdk`

## Firebase Entegrasyonu

### Mevcut Web App ile Ortak Kullanım

Aynı Firebase projesi kullanılacak:
1. Firebase Console → Project Settings → iOS app ekle
2. `GoogleService-Info.plist` indir
3. Xcode'a ekle

### Firestore Yapısı (Mevcut ile Uyumlu)

```
users/{userId}/
├── settings: { boatName, boatType, avgSpeed, fuelRate, ... }
├── trips/{tripId}/
│   └── { date, distance, duration, positions, ... }
└── routes/{routeId}/
    └── { name, waypoints, totalDistance, ... }
```

## Geliştirme Öncelikleri

### Sprint 1 (Hafta 1-2): Temel Yapı
- [ ] Xcode projesi kurulumu
- [ ] MapKit entegrasyonu
- [ ] Temel harita görünümü
- [ ] Waypoint ekleme/silme

### Sprint 2 (Hafta 3-4): Hava Durumu
- [ ] Open-Meteo API servisi
- [ ] Waypoint hava durumu gösterimi
- [ ] Risk seviyesi hesaplama
- [ ] Fetch calculation (kıyı)

### Sprint 3 (Hafta 5-6): Trip Tracking
- [ ] LocationManager implementasyonu
- [ ] Background location
- [ ] Hız paneli
- [ ] Trip kaydetme

### Sprint 4 (Hafta 7-8): Bildirimler
- [ ] NotificationManager
- [ ] Hedefe varış bildirimi
- [ ] Hava durumu uyarıları
- [ ] Sesli uyarılar

### Sprint 5 (Hafta 9-10): Cloud Sync
- [ ] Firebase Authentication
- [ ] Firestore entegrasyonu
- [ ] Web app ile senkronizasyon
- [ ] Offline destek

## Test Stratejisi

### Unit Tests
- WeatherService API parsing
- FetchCalculator hesaplamaları
- RouteCalculator mesafe/süre

### UI Tests
- Rota oluşturma flow
- Trip başlat/bitir flow
- Settings kaydetme

### Manual Tests
- Background location (gerçek cihazda)
- Bildirimler (gerçek cihazda)
- Pil tüketimi testi

---

## Hızlı Başlangıç Checklist

1. [ ] Xcode'da yeni proje oluştur
2. [ ] Bu dökümanı `PLANNING.md` olarak repoya ekle
3. [ ] Klasör yapısını oluştur
4. [ ] Info.plist permission'ları ekle
5. [ ] Background Modes capability ekle
6. [ ] İlk commit & push
7. [ ] MapView ile başla

---

**Sorular?** Her sprint için detaylı kod örnekleri hazırlayabilirim.
