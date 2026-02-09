# DenizRota iOS - Claude.md

Bu dosya Claude Code'un projeyi anlaması için referans dokümantasyonudur.

## İçindekiler

1. [Proje Özeti](#proje-özeti)
2. [Hızlı Referans](#hızlı-referans)
3. [Teknoloji Stack](#teknoloji-stack)
4. [Veri Modelleri](#veri-modelleri-swiftdata)
5. [Proje Yapısı](#proje-yapısı)
6. [Mimari Kararlar](#mimari-kararlar)
7. [Servisler ve Yöneticiler](#servisler-ve-yöneticiler)
8. [API Endpoints](#api-endpoints)
9. [Önemli Sabitler](#önemli-sabitler-constantsswift)
10. [Geliştirme İş Akışı](#geliştirme-iş-akışı-ve-kurallar)
11. [Sık Yapılan İşlemler](#sık-yapılan-işlemler)
12. [Tamamlanan Özellikler](#tamamlanan-özellikler)
13. [TODO Listesi](#todo-listesi-oncelik-sirasina-gore)
14. [Öncelikli Geliştirme Yol Haritası](#öncelikli-geliştirme-yol-haritası)
15. [Test Senaryoları](#test-senaryoları)
16. [Sık Karşılaşılan Sorunlar](#sık-karşılaşılan-sorunlar-ve-çözümleri)
17. [Performans ve En İyi Uygulamalar](#performans-ve-en-i̇yi-uygulamalar)
18. [Komutlar](#komutlar)
19. [Önemli Notlar](#önemli-notlar)

---

## Proje Özeti

DenizRota, amatör denizciler için tekne rota planlama ve seyir takibi uygulamasıdır. Web uygulaması (https://github.com/tremo/DenizRota) ile senkronize çalışır.

## Hızlı Referans

### Temel Bilgiler
- **Platform**: iOS 17.0+
- **Dil**: Swift 5.9+ / SwiftUI
- **Ana Özellikler**: Rota planlama, GPS tracking, saatlik hava tahmini, OpenSeaMap, Windy-tarzı rüzgar animasyonu
- **Lokasyon**: Datça-Marmaris-Bozburun bölgesi için optimize edilmiş
- **Toplam Kod**: ~6,376 satır Swift (24 dosya)

### Sık Kullanılan Dosyalar
| Dosya | Amaç | Satır |
|-------|------|-------|
| `MapView.swift` | Ana harita UI, rota yönetimi, rüzgar overlay | 716 |
| `NauticalMapView.swift` | UIKit harita wrapper, OpenSeaMap | 631 |
| `MapOverlays.swift` | Windy-tarzı rüzgar partikül animasyonu, dalga overlay, grid loader | 577 |
| `TripTrackingView.swift` | Aktif seyir takip UI | 499 |
| `TimelineBarView.swift` | Windy-tarzı zaman çubuğu | 201 |
| `WeatherService.swift` | Open-Meteo API (saatlik tahmin) | 282 |
| `LocationManager.swift` | GPS + background tracking | 211 |
| `FetchCalculator.swift` | Kıyı fetch hesaplama | 106 |
| `Constants.swift` | Sabitler, deniz alanları, kıyı verileri | 258 |
| `DenizRotaApp.swift` | App entry point, SwiftData schema | 81 |

### Önemli State Management
```swift
// MapView ana state'leri
@EnvironmentObject var locationManager: LocationManager
@Query(sort: \Route.updatedAt, order: .reverse) private var routes: [Route]
@Environment(\.modelContext) private var modelContext
@State private var mapStyle: MapStyleOption = .hybrid
@State private var showOpenSeaMap = true
@State private var showTimelineBar = false
@State private var selectedForecastDate = Date()
@State private var showWindOverlay = false
@State private var windGridData: [WindGridPoint] = []
```

### Koordinatlar (Test İçin)
- Datça merkez: `36.78, 28.25`
- Marmaris: `36.85, 28.27`
- Bozburun: `36.70, 27.90`
- Knidos antik liman: `36.68, 27.37`

## Teknoloji Stack

- **UI Framework**: SwiftUI
- **Harita**: MapKit (UIViewRepresentable wrapper)
- **Veri Saklama**: SwiftData (@Model macro)
- **Networking**: URLSession + async/await
- **GPS**: Core Location (Background Modes)
- **Bildirimler**: UserNotifications
- **Cloud**: Firebase (hazırlanıyor)

## Veri Modelleri (SwiftData)

### Route (@Model)
Ana rota modeli - waypoint'leri organize eder
```swift
- id: UUID
- name: String
- createdAt: Date
- updatedAt: Date
- waypoints: [Waypoint] (@Relationship, cascade delete)
- totalDistance: Double (computed)
- estimatedDuration: Double (computed)
```

### Waypoint (@Model)
Rota üzerindeki noktalar - hava durumu verisi taşır
```swift
- id: UUID
- name: String?
- latitude: Double
- longitude: Double
- order: Int
- route: Route? (@Relationship)
- windSpeed: Double?
- windDirection: Double?
- waveHeight: Double?
- temperature: Double?
- riskLevel: RiskLevel (computed: .green/.yellow/.red/.unknown)
- isLoading: Bool (hava durumu yüklenirken)
```

### Trip (@Model)
Tamamlanmış veya aktif seyir kaydı
```swift
- id: UUID
- startDate: Date
- endDate: Date?
- duration: TimeInterval
- distance: Double (km)
- avgSpeed: Double (km/h)
- maxSpeed: Double (km/h)
- fuelUsed: Double (liters)
- fuelCost: Double (TRY)
- positions: [TripPosition] (@Relationship, cascade delete)
```

### TripPosition (@Model)
Seyir sırasında kaydedilen GPS noktaları
```swift
- id: UUID
- latitude: Double
- longitude: Double
- timestamp: Date
- speed: Double (km/h)
- accuracy: Double (meters)
```

### BoatSettings (@Model)
Kullanıcının tekne bilgileri
```swift
- id: UUID
- boatName: String
- boatType: BoatType (.motorlu, .yelkenli, .surat, .gulet, .katamaran)
- avgSpeed: Double (km/h)
- fuelRate: Double (L/h)
- fuelPrice: Double (TRY/L)
- maxWindSpeed: Double? (km/h)
- maxWaveHeight: Double? (m)
```

### İlişkiler
```
Route 1──────▶ * Waypoint (cascade delete)
Trip 1──────▶ * TripPosition (cascade delete)
```

**Not**: Route ve Trip arasında doğrudan ilişki yok. Trip bağımsız tracking kaydı.

## Proje Yapısı

```
DenizRota/
├── App/
│   └── DenizRotaApp.swift       # Uygulama entry point
│
├── Models/
│   ├── Route.swift              # Rota modeli (@Model)
│   ├── Waypoint.swift           # Waypoint modeli (@Model)
│   ├── Trip.swift               # Seyir kaydı (@Model) + TripPosition (@Model)
│   └── BoatSettings.swift       # Tekne ayarları (@Model)
│
├── Views/
│   ├── ContentView.swift        # Tab bar ana görünüm
│   ├── Map/
│   │   ├── MapView.swift        # Ana harita görünümü (716 satır)
│   │   ├── NauticalMapView.swift # UIViewRepresentable harita wrapper (631 satır)
│   │   ├── MapOverlays.swift    # Windy-tarzı rüzgar partikül animasyonu + dalga overlay (577 satır)
│   │   └── TimelineBarView.swift # Windy-tarzı zaman çubuğu (201 satır)
│   ├── Route/
│   │   └── RouteListView.swift  # Kayıtlı rotalar listesi
│   ├── Trip/
│   │   ├── TripHistoryView.swift    # Seyir geçmişi
│   │   ├── TripTrackingView.swift   # Aktif seyir takibi
│   │   └── DeparturePickerView.swift # Seyir zamanı seçici
│   └── Settings/
│       └── SettingsView.swift   # Ayarlar
│
├── Services/
│   ├── LocationManager.swift    # GPS + Background location
│   ├── WeatherService.swift     # Open-Meteo API
│   └── NotificationManager.swift # Bildirim sistemi
│
├── Managers/
│   ├── RouteManager.swift       # Rota yönetimi
│   ├── TripManager.swift        # Seyir yönetimi
│   └── FirebaseManager.swift    # Cloud sync (SDK kurulumu gerekli)
│
└── Utils/
    ├── Constants.swift          # Sabitler, deniz alanları, kıyı verileri
    ├── Extensions.swift         # Date, CLLocation, Color uzantıları
    └── FetchCalculator.swift    # Kıyı fetch hesaplama
```

## Mimari Kararlar

### SwiftUI + SwiftData
- **Neden SwiftUI**: Modern, deklaratif UI, iOS 17+ özellikler
- **Neden SwiftData**: Basit persistence, Core Data'nın modern alternatifi, `@Model` macro
- **Trade-off**: iOS 17+ minimum gereksinim

### UIKit Hybrid Yaklaşımı (NauticalMapView)
- **Neden**: SwiftUI Map view OpenSeaMap tile overlay desteklemiyor
- **Çözüm**: UIViewRepresentable ile MKMapView wrapper
- **Avantaj**: MKTileOverlay, custom annotation rendering, gelişmiş gesture handling
- **Maliyet**: UIKit/SwiftUI bridge, biraz daha karmaşık kod

### Actor-based Services
- **Neden**: Thread-safe, modern concurrency
- **Uygulama**: WeatherService actor olarak tanımlı
- **Avantaj**: Race condition yok, cache güvenli

### Singleton Managers
- **LocationManager.shared**: Global GPS state, background tracking
- **NotificationManager.shared**: Bildirim sistemi
- **WeatherService.shared**: API cache ve istek yönetimi
- **TripManager.shared**: Aktif seyir state
- **Justification**: Bu servisler app-wide state taşıyor, tek instance yeterli

### Koordinat Sistemi
- Tüm mesafeler: km (kullanıcı arayüzünde knot'a çevrilebilir - TODO-7)
- Tüm hızlar: km/h (GPS m/s'den çevriliyor)
- Koordinatlar: WGS84 decimal degrees (CLLocationCoordinate2D)

## Servisler ve Yöneticiler

### LocationManager (@MainActor, ObservableObject)
**Dosya**: `Services/LocationManager.swift`
**Amaç**: GPS tracking, background location, kullanıcı konumu
**Singleton**: `LocationManager.shared`

**Önemli Property'ler**:
```swift
@Published var currentLocation: CLLocation?
@Published var currentSpeed: Double  // km/h
@Published var isTracking: Bool
@Published var authorizationStatus: CLAuthorizationStatus
```

**Önemli Metodlar**:
- `requestPermission()` - Konum izni iste
- `startTracking()` - GPS tracking başlat (background)
- `stopTracking()` - GPS tracking durdur
- `locationManager(_:didUpdateLocations:)` - GPS güncelleme callback

**Filtreler**:
- Accuracy: < 50m
- Jump detection: > 1000m
- Distance filter: 10m minimum

### WeatherService (actor)
**Dosya**: `Services/WeatherService.swift` (282 satır)
**Amaç**: Open-Meteo API entegrasyonu, saatlik hava durumu ve dalga verileri
**Singleton**: `WeatherService.shared`

**Önemli Metodlar**:
```swift
func fetchWeather(for coordinate: CLLocationCoordinate2D, date: Date = Date()) async throws -> WeatherData
func clearCache()
```

**Cache**: 1 saat in-memory cache (actor ile thread-safe), cache key: `"lat,lng,day,hour"` formatı

**API'ler**:
1. Weather API: `https://api.open-meteo.com/v1/forecast` (hourly, forecast_days=3)
2. Marine API: `https://marine-api.open-meteo.com/v1/marine` (hourly, forecast_days=3)

**Özellikler**:
- Saatlik tahmin: `date` parametresi ile belirli saat için veri döndürür
- Exponential backoff retry (3 deneme)
- Marine API opsiyonel (kıyı dışında veri döndürmeyebilir)
- `WeatherData` struct: windSpeed, windDirection, windGusts, temperature, waveHeight, waveDirection, wavePeriod, fetchDistance, riskLevel (computed)

### NotificationManager
**Dosya**: `Services/NotificationManager.swift`
**Amaç**: Local bildirimler, hedefe varış, hava durumu uyarıları
**Singleton**: `NotificationManager.shared`

**Önemli Metodlar**:
```swift
func requestPermission() async -> Bool
func scheduleArrivalNotification(waypoint: Waypoint, distance: Double)
func scheduleWeatherAlert(message: String)
func cancelAllNotifications()
```

### TripManager (@MainActor, ObservableObject)
**Dosya**: `Managers/TripManager.swift`
**Amaç**: Aktif seyir yönetimi, waypoint progress tracking
**Singleton**: `TripManager.shared`

**Durum**: ⚠️ Oluşturulmuş ama MapView tarafından kullanılmıyor (TODO-6)

**Önemli Metodlar**:
```swift
func startTrip(waypoints: [Waypoint])
func pauseTrip()
func resumeTrip()
func stopTrip() -> Trip?
func handleLocationUpdate(_ location: CLLocation)
```

### RouteManager (@MainActor, ObservableObject)
**Dosya**: `Managers/RouteManager.swift`
**Amaç**: Rota yönetimi, hava durumu yükleme, risk hesaplama
**Singleton**: `RouteManager.shared`

**Durum**: ⚠️ Derleme hataları var, MapView kendi rota yönetimini yapıyor (TODO-5)

**Önemli Metodlar**:
```swift
func loadWeather(for route: Route, departureDate: Date) async
func calculateRisk(for route: Route) -> RiskLevel
func saveRoute(_ route: Route)
```

### FetchCalculator
**Dosya**: `Utils/FetchCalculator.swift`
**Amaç**: Kıyı fetch hesaplama, dalga yüksekliği ayarlama
**Singleton**: `FetchCalculator.shared`

**Önemli Metodlar**:
```swift
func calculateFetch(lat: Double, lng: Double, windDirection: Double) -> Double
func adjustWaveHeight(_ waveHeight: Double, fetchKm: Double) -> Double
```

**Algoritma**:
1. Rüzgar yönünde 0.5 km adımlarla ilerle
2. Karaya çarpana kadar devam (max 100 km)
3. Fetch mesafesine göre dalga düşürme faktörü uygula
4. CoastlineData.allPoints ile detaylı kıyı kontrolü

### WeatherGridLoader
**Dosya**: `Views/Map/MapOverlays.swift` (satır 491-577)
**Amaç**: Harita bölgesi için grid bazlı rüzgar/dalga verisi yükleme
**Singleton**: `WeatherGridLoader.shared`

**Önemli Metodlar**:
```swift
func loadWindGrid(for region: MKCoordinateRegion, date: Date) async -> [WindGridPoint]
func loadWaveGrid(for region: MKCoordinateRegion, date: Date) async -> [WaveGridPoint]
```

**Algoritma**:
- Harita bölgesini 6x6 (rüzgar) veya 8x8 (dalga) grid'e böler
- Her grid noktası için paralel API çağrısı (`withTaskGroup`)
- `SeaAreas.isInSea()` ile kara noktalarını atlar

### WindOverlayView (Windy-tarzı Rüzgar Animasyonu)
**Dosya**: `Views/Map/MapOverlays.swift` (satır 1-250)
**Amaç**: 800 partikül ile Windy benzeri rüzgar akış animasyonu

**Teknik Detaylar**:
- SwiftUI `Canvas` ile GPU-hızlandırılmış çizim
- 800 partikül, her biri gradient trail ile çizilir
- 5 seviyeli renk skalası: Yeşil (0-10) → Sarı (10-20) → Turuncu (20-30) → Kırmızı (30-40) → Koyu Kırmızı (40+)
- Partikül yaşam döngüsü: doğum → rüzgar yönünde hareket → ölüm → yeniden doğum
- IDW (Inverse Distance Weighting) ile grid noktaları arasında interpolasyon
- Timer-based animasyon (~30 FPS)

### TimelineBarView
**Dosya**: `Views/Map/TimelineBarView.swift` (201 satır)
**Amaç**: Windy-tarzı ince zaman çubuğu, saat/gün seçimi
**Binding**: `@Binding var selectedDate: Date`

**Özellikler**:
- Yatay scroll ile saatlik seçim (48 saat - bugün + yarın)
- "Şimdi" etiketi mevcut saat için
- Gece saatleri koyu arka plan ile ayırt edilir
- `onDateChanged` callback ile hava durumu güncelleme tetiklenir

## API Endpoints

### Open-Meteo Weather API
```
GET https://api.open-meteo.com/v1/forecast
Params: latitude, longitude, hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,temperature_2m
```

### Open-Meteo Marine API
```
GET https://marine-api.open-meteo.com/v1/marine
Params: latitude, longitude, hourly=wave_height,wave_direction,wave_period
```

## Önemli Sabitler (Constants.swift)

- **GPS Accuracy Threshold**: 50m
- **GPS Jump Threshold**: 1000m
- **Waypoint Proximity**: 100m (hedefe varış bildirimi)
- **Wind Speed Yellow**: >= 15 km/h
- **Wind Speed Red**: >= 30 km/h
- **Wave Height Yellow**: >= 0.5m
- **Wave Height Red**: >= 1.5m
- **Weather Cache**: 1 saat

## Geliştirme İş Akışı ve Kurallar

### Branch Stratejisi
- **main**: Kararlı üretim kodu
- **claude/[feature-name]-[sessionId]**: Claude tarafından oluşturulan özellik branch'leri
- Her PR main'e merge edilmeden önce review yapılır

### Commit Mesajları
- Türkçe, net ve açıklayıcı yazılmalı
- Format: "[Ne yapıldı]: [Kısa açıklama]"
- Örnekler:
  - "Harita tipini hybrid yap, OpenSeaMap tile overlay ekle (TODO-2)"
  - "FetchCalculator: CoastlineData.allPoints kullan, threshold düşür"
  - "Waypoint popup'i kompakt overlay kart tasarımına geçir"

### Kod Stili ve Kurallar
1. **SwiftUI Lifecycle**: `@main` struct ile başlangıç, `App` protocol
2. **State Management**:
   - `@State` view-local state için
   - `@StateObject` singleton manager'lar için (LocationManager, TripManager)
   - `@EnvironmentObject` paylaşılan objeler için
   - `@Query` SwiftData sorguları için
3. **Naming Conventions**:
   - Türkçe değişken/fonksiyon isimleri kullanmayın - sadece comment'ler Türkçe
   - camelCase - değişkenler, fonksiyonlar
   - PascalCase - tipler, struct'lar, class'lar
4. **Async/Await**: Modern concurrency kullan, completion handler'lar yok
5. **Error Handling**: `do-catch` veya optional handling, force unwrap kullanma
6. **SwiftData**:
   - `@Model` macro ile model tanımlama
   - `@Relationship(deleteRule: .cascade)` ile ilişkiler
   - `modelContext` ile insert/delete işlemleri

### Sık Kullanılan Patterns

#### Location Manager Pattern
```swift
@StateObject private var locationManager = LocationManager.shared
@EnvironmentObject var locationManager: LocationManager
```

#### SwiftData Query Pattern
```swift
@Query(sort: \Route.updatedAt, order: .reverse) private var routes: [Route]
@Environment(\.modelContext) private var modelContext
```

#### Weather Service Pattern
```swift
let weather = try await WeatherService.shared.fetchWeather(for: coordinate, date: selectedDate)
```

#### Notification Pattern
```swift
await NotificationManager.shared.requestPermission()
NotificationManager.shared.scheduleArrivalNotification(waypoint: waypoint, distance: distance)
```

### Test Etme
- Gerçek cihazda test gerekli: GPS, background location, bildirimler
- Simulator'da çalışmayan özellikler: Background location, bazı bildirimler
- Test lokasyonları: Datça (36.78, 28.25), Marmaris (36.85, 28.27), Bozburun (36.70, 27.90)

### Bilinen Kısıtlamalar
1. **Marine API**: Açık denizde veri döndürmeyebilir (kıyı yakını için tasarlanmış)
2. **Background Location**: "Always" izni gerekli, iOS Settings'ten manuel aktive edilmeli
3. **Weather Cache**: 1 saat, offline durumlar için stale data gösterilebilir
4. **Fetch Calculation**: Türkiye Ege/Akdeniz kıyıları için optimize edilmiş

### Hata Ayıklama İpuçları
1. **Derleme Hataları**: Optional chaining vs non-optional properties - Model tanımlarını kontrol et
2. **MapView Sorunları**: NauticalMapView UIViewRepresentable - coordinator pattern kullanıyor
3. **Weather API Hataları**: Network bağlantısı ve cache kontrol et
4. **GPS Doğruluk**: `horizontalAccuracy <= 50m` filtresi var, düşük sinyal = veri yok

## Tamamlanan Özellikler

### Faz 1: Çekirdek (MVP) ✅
- [x] MapKit harita görünümü
- [x] Rota oluşturma ve waypoint yönetimi
- [x] Open-Meteo hava durumu entegrasyonu
- [x] Fetch-adjusted dalga hesaplaması
- [x] Risk seviyesi sistemi (yeşil/sarı/kırmızı)
- [x] Tekne ayarları

### Faz 2: Seyir Takibi ✅
- [x] GPS tabanlı trip tracking
- [x] Background location desteği
- [x] Hız göstergesi (anlık, ortalama, maksimum)
- [x] Mesafe hesaplama
- [x] Trip geçmişi ve istatistikler

### Faz 3: Bildirimler ✅
- [x] Hedefe varış bildirimi
- [x] Hava durumu uyarıları
- [x] Sesli uyarılar

### Backend Servisleri ✅
- [x] RouteManager - rota yönetimi
- [x] TripManager - seyir yönetimi
- [x] Constants - sabitler ve kıyı verileri
- [x] Extensions - yardımcı uzantılar
- [x] MapOverlays - rüzgar/dalga görselleştirme

### Faz 4: Gelişmiş Harita Özellikleri ✅
- [x] NauticalMapView - UIKit/MapKit wrapper
- [x] OpenSeaMap tile overlay (deniz işaretleri)
- [x] Harita tipi seçici (standard/hybrid/satellite)
- [x] Detaylı kıyı fetch hesaplama (CoastlineData)
- [x] Waypoint risk seviyesi görselleştirmesi
- [x] Kompakt waypoint detay kartları
- [x] Uyarlanabilir tema desteği (açık/koyu/sistem)

### Faz 5: Windy-tarzı Görselleştirme ✅
- [x] Saatlik hava durumu tahmini (3 günlük, hourly API)
- [x] Windy-tarzı zaman çubuğu (TimelineBarView) - saat/gün seçimi
- [x] Rüzgar partikül animasyonu overlay'ı (800 partikül, gradient trail)
- [x] 5 seviyeli renk skalası (yeşil→sarı→turuncu→kırmızı→koyu kırmızı)
- [x] Rüzgar lejantı (WindLegendView)
- [x] WeatherGridLoader - harita bölgesi için grid bazlı hava verisi
- [x] Debounce ile harita bölge değişikliklerinde otomatik grid yükleme
- [x] Zaman değişikliğinde hem waypoint hem grid verisini güncelleme

### Kaldırılan Özellikler
- ~~Korunaklı koylar (Protected Coves)~~ - Overpass API ile eklendi, sonra karmaşıklık sebebiyle tamamen kaldırıldı (PR #24)
- ~~ShelterAnalyzer~~ - Rüzgar sığınağı analizi eklendi (PR #19), sonra kaldırıldı (PR #24)

## Sık Yapılan İşlemler

### Yeni Model Ekleme
1. `Models/` klasöründe yeni Swift dosyası oluştur
2. `@Model` macro ile class tanımla
3. `DenizRotaApp.swift`'te Schema'ya ekle: `Schema([..., YeniModel.self])`
4. İlişkiler için `@Relationship(deleteRule: .cascade)` kullan

### Yeni View Ekleme
1. İlgili klasöre ekle (`Map/`, `Trip/`, `Route/`, `Settings/`)
2. `@Environment(\.modelContext)` ve `@Query` ile veri oku
3. `@EnvironmentObject var locationManager` ile GPS verisi al
4. `@State` ile view-local state yönet

### API Servisi Ekleme
1. `Services/` klasöründe `actor` olarak tanımla (thread-safe)
2. Cache mekanizması ekle (WeatherService örneği)
3. `async throws` fonksiyonlar kullan
4. Error handling ile optional return

### Harita Üzerine Özellik Ekleme
1. `NauticalMapView.swift` - MKMapView delegate metodları
2. Yeni annotation için: `MKAnnotation` protocol implement et
3. Overlay için: `MKOverlay` ve `MKOverlayRenderer` kullan
4. `updateUIView` metodunda state değişikliklerine göre güncelle

### Background İşlem Ekleme
1. `Info.plist` → Background Modes ekle
2. `LocationManager` veya yeni manager oluştur
3. `CLLocationManager.allowsBackgroundLocationUpdates = true`
4. Battery-efficient kod yaz (düşük frekans, akıllı filtreler)

## TODO Listesi (Oncelik Sirasina Gore)

Asagidaki maddeler "todo N'i yap" seklinde referans verilebilir.
Her madde bagimsiz olarak uygulanabilir.

---

### TODO-1: FetchCalculator'i CoastlineData ile Duzelt [KRITIK] ✅
**Durum:** TAMAMLANDI (PR #7)
**Dosyalar:** `Utils/FetchCalculator.swift`, `Utils/Constants.swift`
**Yapilan:**
1. ✅ `FetchCalculator.isNearCoastline()` metodu `CoastlineData.allPoints` verisini kullaniyor (satir 94-105)
2. ✅ Threshold 0.015 dereceye (~1.5km) düşürüldü (satir 95)
3. ✅ `isPointOnLand()` metodu `SeaAreas.isInSea()` ile entegre edildi (satir 72-91)
4. ✅ Fetch hesaplama artık detaylı kıyı verileriyle çalışıyor

---

### TODO-2: Harita Tipini Hybrid Yap + OpenSeaMap Tile Overlay Ekle [KRITIK] ✅
**Durum:** TAMAMLANDI (PR #8-16)
**Dosyalar:** `Views/Map/MapView.swift`, `Views/Map/NauticalMapView.swift`
**Yapilan:**
1. ✅ `NauticalMapView.swift` UIViewRepresentable wrapper oluşturuldu (631 satır)
2. ✅ OpenSeaMap tile overlay entegrasyonu tamamlandı (`https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png`)
3. ✅ `MapStyleOption` enum ile harita tipi seçici eklendi (standard/hybrid/satellite)
4. ✅ Varsayılan harita tipi `.hybrid` olarak ayarlandı (MapView.swift satır 20)
5. ✅ OpenSeaMap toggle eklendi (MapView.swift satır 92-94)
6. ✅ Sağ üst köşede harita tipi menüsü eklendi (MapView.swift satır 81-99)
7. ✅ Waypoint annotation rendering, route polyline, user location gösterimi implementasyonu
8. ✅ Tap gesture handling ile waypoint ekleme ve seçme özellikleri

**Teknik Detaylar:**
- `OpenSeaMapOverlay` MKTileOverlay subclass olarak tanımlı
- Tile overlay `.aboveLabels` seviyesinde gösteriliyor
- Zoom level: 6-18 arası
- Waypoint'ler risk seviyesine göre renklendirilmiş pinler (yeşil/sarı/kırmızı)
- Kompakt overlay kart tasarımı ile waypoint detay gösterimi
- `onRegionChanged` callback ile harita bölge değişikliklerinde rüzgar grid'i yenilenir
- `onDeleteWaypoint` callback ile waypoint silme desteği

---

### TODO-3: Ruzgar Siginagi Analizi [ORTA] ❌ KALDIRILDI
**Durum:** TAMAMLANDI (PR #19) sonra KALDIRILDI (PR #24)
**Dosyalar:** `Utils/ShelterAnalyzer.swift` (silindi), `Services/OverpassService.swift` (silindi)
**Aciklama:** Korunakli koylar ve ruzgar siginagi analizi ozelligi eklendi (Overpass API ile dinamik koy yukleme), ancak karmasiklik ve performans sorunlari nedeniyle tamamen kaldirildi.

---

### TODO-4: Weather API'yi Saatlik Tahmine Gecir [YUKSEK] ✅
**Durum:** TAMAMLANDI
**Dosyalar:** `Services/WeatherService.swift`, `Views/Map/MapView.swift`, `Views/Map/TimelineBarView.swift`
**Yapilan:**
1. ✅ `WeatherService.fetchWeather` metoduna `date: Date = Date()` parametresi eklendi (satir 15)
2. ✅ API `hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,temperature_2m` kullaniyor (satir 70)
3. ✅ `forecast_days=3` eklendi (bugun + 2 gun) (satir 71)
4. ✅ Marine API ayni: `hourly=wave_height,wave_direction,wave_period` (satir 83)
5. ✅ `WeatherAPIResponse` ve `MarineAPIResponse` `hourly` formatina guncellendi, `valuesForDate()` ile hedef saate en yakin deger seciliyor
6. ✅ Cache key: `"\(lat),\(lng),\(day),\(hour)"` formati (satir 117-124)
7. ✅ Windy-tarzi `TimelineBarView` ile saat/gun secimi entegre edildi
8. ✅ `loadWeatherForRoute()` secilen `selectedForecastDate`'i kullaniyor (satir 447)
9. ✅ Exponential backoff retry mekanizmasi eklendi (3 deneme)

---

### TODO-5: RouteManager Derleme Hatalarini Duzelt [YUKSEK]
**Durum:** Yapilmadi
**Dosyalar:** `Managers/RouteManager.swift`
**Sorun:** 3 derleme hatasi var + MapView RouteManager'i kullanmiyor (iki paralel sistem).
**Yapilacak:**
1. Satir 42: `route.waypoints?.count ?? 0` -> `route.waypoints.count` (waypoints non-optional)
2. Satir 59: `route.waypoints` optional chain kaldir (ayni sorun)
3. Satir 72: `route.waypoints?.forEach` -> `route.waypoints.forEach`
4. Satir 80: `route.waypoints` optional chain kaldir
5. Satir 88: `fetchWeather(for: waypoint.coordinate, date: departureDate)` -> WeatherService'in imzasina uydur. TODO-4 tamamlandi, `date` parametresi mevcut: `WeatherService.shared.fetchWeather(for: coordinate, date: date)`
6. Satir 141: `route.waypoints?.count ?? 0` -> `route.waypoints.count`
7. `Waypoint.updateWeather(from:)` extension'indaki (satir 270-283) `data.waveHeight` optional chain ve `fetchResult.fetchKm` hatasini duzelt:
   - `calculateFetch()` Double dondurur, `.fetchKm` property'si yok
   - `FetchCalculator.shared.adjustWaveHeight(waveHeight, fetchKm: fetchResult)` olmali (`fetchResult` zaten Double)
8. **Karar noktasi:** MapView'in kendi rota yonetimini RouteManager'a tasimak buyuk bir refactor. Simdilik RouteManager'i derlenir hale getirmek yeterli, ileride MapView refactor edilebilir.

---

### TODO-6: TripManager'i MapView'a Entegre Et [YUKSEK]
**Durum:** Yapilmadi
**Dosyalar:** `Views/Map/MapView.swift`, `Managers/TripManager.swift`, `Views/Trip/TripTrackingView.swift`
**Sorun:** MapView.stopTrip() (satir 436-456) TripManager'i kullanmiyor, dogrudan LocationManager cagiriyor. TripTrackingView'a gecis yok. Pause/resume, waypoint ilerleme gostergesi, detayli varis bildirimi gibi ozellikler kullanilmiyor.
**Yapilacak:**
1. `MapView`'a `@StateObject private var tripManager = TripManager.shared` ekle
2. `startTrip()`: `locationManager.startTracking()` yerine `tripManager.startTrip(waypoints:)` cagir
3. `stopTrip()`: `locationManager.stopTracking()` yerine `tripManager.stopTrip()` kullan, donusu kaydet
4. Seyir aktifken `TripTrackingView`'i fullscreen sheet veya NavigationLink ile goster
5. `TripTrackingView` zaten pause/resume, waypoint progress, varis tespiti iceriyor - bunlar otomatik calisacak
6. Trip kaydetme: `trip.calculateStats(fuelRate: 20, fuelPrice: 45)` hardcoded degerleri BoatSettings'ten al (modelContext'ten Query ile)
7. `TripPosition` init'ini kontrol et - `TripManager.handleLocationUpdate()` `TripPosition(latitude:longitude:timestamp:speed:accuracy:)` kullaniyorken `Trip.swift`'teki init `TripPosition(location: CLLocation)` - bunlari uyumlastir

---

### TODO-7: Denizcilik Birimleri (Knot/Mil) Destegi Ekle [ORTA]
**Durum:** Yapilmadi
**Dosyalar:** `Models/BoatSettings.swift`, `Utils/Extensions.swift`, `Views/Settings/SettingsView.swift`, tum View dosyalari
**Sorun:** Her sey km/h ve km. Denizcilik standardi knot ve deniz mili.
**Yapilacak:**
1. `BoatSettings`'e `useNauticalUnits: Bool = false` property ekle
2. `Extensions.swift`'e donusum fonksiyonlari ekle:
   - `Double.toKnots` (km/h * 0.539957)
   - `Double.toNauticalMiles` (km * 0.539957)
   - `Double.speedDisplay(nautical: Bool)` -> "15.5 km/h" veya "8.4 kn"
   - `Double.distanceDisplay(nautical: Bool)` -> "12.3 km" veya "6.6 nm"
3. `SettingsView`'da birim tercihi toggle'i ekle
4. Tum view'larda hiz ve mesafe gosterimini bu tercihe gore degistir:
   - `MapView` SpeedPanelView
   - `RouteInfoBar` mesafe/sure
   - `TripTrackingView` hiz/mesafe
   - `TripHistoryView` istatistikler
   - `WaypointDetailSheet` ruzgar hizi

---

### TODO-8: Varsayilan Harita Merkezini Datca-Marmaris'e Tasi [ORTA]
**Durum:** Yapilmadi
**Dosyalar:** `Views/Map/MapView.swift`, `Utils/Constants.swift`
**Sorun:** Varsayilan merkez (38.5, 27.0) Izmir civari. Datca-Marmaris bolgesi ~36.75, 28.2.
**Yapilacak:**
1. `Constants.swift` satir 14: `defaultMapCenter` koordinatini `(36.78, 28.25)` yap (Datca merkez)
2. `MapView.swift` satir 16: Ayni koordinati guncelle
3. `MapView.swift` satir 18: Span'i `(2, 2)`'den `(0.8, 0.8)`'e dusur - Datca-Marmaris bolgesi gorunsun, tum Ege degil
4. Ideal: Kullanicinin son baktigi bolgeyi UserDefaults'a kaydedip sonraki acilista oradan basla

---

### TODO-9: Yakit Hesabini BoatSettings'ten Al [ORTA]
**Durum:** Yapilmadi
**Dosyalar:** `Views/Map/MapView.swift`
**Sorun:** `stopTrip()` (satir 450) `fuelRate: 20, fuelPrice: 45` hardcoded deger kullaniyor. BoatSettings'i yok sayiyor.
**Yapilacak:**
1. `MapView`'a BoatSettings query ekle: `@Query private var boatSettings: [BoatSettings]`
2. `stopTrip()` icinde: `let settings = boatSettings.first`
3. `trip.calculateStats(fuelRate: settings?.fuelRate ?? 20, fuelPrice: settings?.fuelPrice ?? 45)` seklinde guncelle
4. Ayni sorun `Route.estimatedFuel()` ve `Route.estimatedDuration()` icin de gecerli - bunlar da default 20 L/h ve 15 km/h kullaniyor, BoatSettings'ten alinmali

---

### TODO-10: Offline Harita ve Hava Durumu Cache'i [ORTA]
**Durum:** Yapilmadi
**Dosyalar:** `Services/WeatherService.swift`, `Views/Map/MapView.swift`
**Sorun:** Datca-Marmaris kiyilarinda (Bozburun, Knidos, Symi) sinyal zayif/yok. Harita tile cache yok, hava durumu offline erisilemez, "veri eski" uyarisi yok.
**Yapilacak:**
1. `WeatherService` cache'ini bellekten diske tasi (UserDefaults veya JSON dosya)
2. Cache suresi dolsa bile eski veriyi "stale" olarak dondur, UI'da "son guncelleme: 2 saat once" goster
3. `MapView`'a bir uyari banner'i ekle: "Hava durumu verisi eski (son guncelleme: X)" - kirmizi/turuncu renkle
4. Harita icin: `MKTileOverlay` kullanildiginda (TODO-2) URLSession cache policy'yi `.returnCacheDataElseLoad` yap
5. Gelecekte: Kalkis oncesi bolge tile'larini indirme butonu (offline map download)

---

### TODO-11: Risk Esiklerini Tekne Tipine Gore Ayarla [DUSUK]
**Durum:** Yapilmadi
**Dosyalar:** `Models/Waypoint.swift` (RiskLevel.calculate), `Models/BoatSettings.swift`
**Sorun:** Ayni ruzgarda surat teknesi rahatken kucuk fiber tekne sikintida olabilir. BoatType mevcut ama risk hesabinda kullanilmiyor.
**Yapilacak:**
1. `RiskLevel.calculate()` metoduna `boatType: BoatType = .motorlu` parametresi ekle
2. Tekne tipine gore esik degerleri:
   - `.surat`: wind yellow 25, red 40 / wave yellow 1.0, red 2.0 (daha dayanikli)
   - `.motorlu`: wind yellow 15, red 30 / wave yellow 0.5, red 1.5 (mevcut degerler)
   - `.yelkenli`: wind yellow 20, red 35 / wave yellow 0.7, red 1.5 (ruzgar avantaj)
   - `.gulet`: wind yellow 20, red 35 / wave yellow 0.8, red 2.0 (buyuk tekne)
   - `.katamaran`: wind yellow 20, red 35 / wave yellow 0.8, red 2.0 (stabil)
3. Hava durumu yuklenirken BoatSettings'ten tip bilgisini al ve risk hesabina gecirir

---

### TODO-12: Favori Nokta / Demir Atma Noktasi Sistemi [DUSUK]
**Durum:** Yapilmadi
**Dosyalar:** Yeni model `Models/Bookmark.swift`, yeni view, `Views/Map/MapView.swift`
**Sorun:** Isimsiz koylara giden denizciler onceki ziyaretlerini kaydetmek istiyor.
**Yapilacak:**
1. Yeni `Bookmark` SwiftData modeli olustur:
   - `id: UUID`, `latitude: Double`, `longitude: Double`
   - `name: String` (kullanici girer veya "Isimsiz Koy" default)
   - `category: BookmarkCategory` enum: `.anchorage`, `.restaurant`, `.swim`, `.danger`, `.fuel`, `.other`
   - `notes: String?` (serbest not)
   - `rating: Int?` (1-5 yildiz)
   - `createdAt: Date`, `lastVisited: Date?`
   - `photos: [Data]?` (kucuk thumbnail'lar, opsiyonel)
2. `MapView`'da uzun basma (long press) ile "Yer Isareti Ekle" secenegi
3. Haritada bookmark'lari kategori ikonlariyla goster (capa, restoran, yuzme, tehlike)
4. Bookmark listesi view'i (Tab bar'a 5. tab veya Route tab'inin altinda)
5. `DenizRotaApp.swift` schema'ya `Bookmark.self` ekle

---

## Öncelikli Geliştirme Yol Haritası

### Kısa Vadeli (1-2 Hafta)
1. ~~**TODO-4**: Saatlik hava tahmini~~ ✅ TAMAMLANDI
2. **TODO-5**: RouteManager derleme hataları - Teknik borç temizliği

### Orta Vadeli (3-4 Hafta)
4. **TODO-6**: TripManager entegrasyonu - Mevcut kod kullanılmıyor
5. **TODO-7**: Nautical units - Denizci kullanıcılar için kritik
6. **TODO-8**: Harita merkezi Datça-Marmaris - UX iyileştirmesi

### Uzun Vadeli (1-2 Ay)
7. **TODO-9**: BoatSettings fuel hesabı - Hardcoded değerler temizliği
8. **TODO-10**: Offline cache - Kıyı bölgelerinde sinyal zayıf
9. **TODO-11**: Risk eşikleri tekne tipine göre - Gelişmiş özellik
10. **TODO-12**: Bookmark sistemi - Community istek

### Teknik Borç
- RouteManager ve MapView arasında kod tekrarı (iki paralel sistem)
- TripManager kullanılmıyor, doğrudan LocationManager çağrılıyor
- Hardcoded fuel/speed değerleri (BoatSettings var ama kullanılmıyor)
- ~~Weather API hourly tahmin desteklemiyor~~ ✅ ÇÖZÜLDÜ
- RouteManager derleme hataları (optional chaining sorunları)

### Firebase Entegrasyonu (Gelecek)
- Şu an SDK kurulu değil, FirebaseManager placeholder
- Web app ile sync için gerekli
- Auth, Firestore, Cloud Functions hazırlanacak

---

## Eski Gelistirme Plani

### Faz 4: Cloud Sync (Hazırlanıyor)
- [ ] Firebase SDK kurulumu
- [ ] GoogleService-Info.plist ekleme
- [ ] Authentication entegrasyonu
- [ ] Firestore senkronizasyon
- [ ] Web app ile ortak data

### UI İyileştirmeleri
- [x] Seyir tarihi/saati seçici → Windy-tarzı zaman çubuğuna dönüştürüldü
- [x] Otomatik hava durumu güncelleme (15 dk)
- [x] Windy-tarzı rüzgar partikül animasyonu
- [x] Saatlik hava tahmini (3 günlük)
- [ ] Kayıtlı rotalar görünümünü geliştir
- [x] Dark mode desteği

### Testler
- [ ] Unit tests (WeatherService, FetchCalculator)
- [ ] UI tests (rota oluşturma, seyir flow)

## Test Senaryoları

### Manuel Test Checklist

#### Rota Oluşturma
1. ✅ Haritada waypoint ekle (tap)
2. ✅ Waypoint detaylarını gör
3. ✅ Waypoint sil
4. ✅ Waypoint sırasını değiştir (drag)
5. ✅ Hava durumu yükle
6. ✅ Risk seviyesi gösterimi (yeşil/sarı/kırmızı)
7. ✅ Rotayı kaydet

#### GPS Tracking
1. ✅ Location permission iste
2. ✅ Tracking başlat
3. ✅ Hız panelini gör
4. ✅ Background'da çalışmasını test et (uygulamayı kapat)
5. ✅ Tracking durdur
6. ✅ Trip history'de görüntüle

#### Harita Özellikleri
1. ✅ Harita tipi değiştir (standard/hybrid/satellite)
2. ✅ OpenSeaMap overlay toggle
3. ✅ Zoom in/out
4. ✅ Pan (kaydır)
5. ✅ User location gösterimi
6. ✅ Rüzgar partikül animasyonu toggle
7. ✅ Zaman çubuğu ile saat/gün seçimi
8. ✅ Rüzgar renk skalası lejantı

#### Bildirimler
1. ✅ Notification permission iste
2. ✅ Hedefe varış bildirimi test et (waypoint'e yaklaş)
3. ✅ Hava durumu uyarısı test et

### Otomatik Test (Gelecek)
- [ ] Unit tests: WeatherService, FetchCalculator
- [ ] UI tests: Rota oluşturma flow
- [ ] Integration tests: GPS tracking

### Test Verileri
**Datça-Marmaris Test Rotası**:
1. Datça merkez: 36.78, 28.25
2. Knidos: 36.68, 27.37
3. Bozburun: 36.70, 27.90
4. Marmaris: 36.85, 28.27

**Beklenen Mesafe**: ~60 km
**Beklenen Süre**: ~4 saat (15 km/h)

## Firebase Kurulum Adımları

1. Xcode → File → Add Package Dependencies
2. URL: `https://github.com/firebase/firebase-ios-sdk`
3. Paketler: FirebaseAuth, FirebaseFirestore
4. Firebase Console'dan `GoogleService-Info.plist` indir
5. Dosyayı Xcode projesine ekle
6. `FirebaseManager.swift`'teki import satırlarını aktif et

## Sık Karşılaşılan Sorunlar ve Çözümleri

### "Value of optional type 'X?' must be unwrapped"
- **Sebep**: SwiftData model'de optional olarak işaretlenmemiş property optional olarak kullanılıyor
- **Çözüm**: Model tanımını kontrol et, `?` ekle veya kaldır
- **Örnek**: `route.waypoints` optional değil, `route.waypoints?.count` yerine `route.waypoints.count`

### MapView'da Annotation'lar Görünmüyor
- **Sebep**: `updateAnnotations()` metodu doğru çağrılmıyor veya coordinator doğru ayarlanmamış
- **Çözüm**: `NauticalMapView.updateUIView` içinde `updateAnnotations(mapView)` çağrısını kontrol et
- **Debug**: `print("Annotations count: \(mapView.annotations.count)")` ile debug et

### Weather API Hep Aynı Veriyi Döndürüyor
- **Sebep**: Cache 1 saat süreyle aktif, cache key saat bilgisi içeriyor (`lat,lng,day,hour`)
- **Çözüm**: Test için `WeatherService.shared.clearCache()` çağır
- **Not**: Farklı saat seçildiğinde farklı cache key kullanılır, dolayısıyla yeni API çağrısı yapılır

### GPS Noktaları Kaydedilmiyor
- **Sebep**: Accuracy threshold (50m) veya jump threshold (1000m) filtresi
- **Çözüm**: `LocationManager.swift` içindeki `horizontalAccuracy` ve `distance` kontrollerini incele
- **Debug**: `print("Accuracy: \(location.horizontalAccuracy)m")` ile kontrol et

### Background Location Çalışmıyor
1. ✅ Info.plist'te "Always" permission tanımlı mı?
2. ✅ Background Modes → Location updates capability aktif mi?
3. ✅ Gerçek cihazda test ediliyor mu? (Simulator'da çalışmaz)
4. ✅ Ayarlar → DenizRota → Konum → "Her Zaman" seçilmiş mi?
5. ✅ `allowsBackgroundLocationUpdates = true` ayarlı mı?

### Xcode Projesine Dosya Eklenmiş Ama Görünmüyor
- **Sebep**: Dosya sadece file system'e kopyalanmış, Xcode projesine eklenmemiş
- **Çözüm**: Xcode Project Navigator → sağ tık → "Add Files to DenizRota" → dosyayı seç
- **Kontrol**: Build Phases → Compile Sources altında dosya var mı?

### Derleme Hatası: "Cannot find type 'X' in scope"
- **Sebep**: Import eksik veya dosya target'a eklenmemiş
- **Çözüm**:
  1. İlgili import'u ekle (örn: `import MapKit`)
  2. File Inspector → Target Membership → DenizRota checkbox'ını işaretle

## Performans ve En İyi Uygulamalar

### GPS Tracking Optimizasyonu
- ✅ `distanceFilter = 10m`: 10 metreden az hareket = güncelleme yok
- ✅ Accuracy filtresi (50m): Düşük doğruluklu noktaları atla
- ✅ Jump detection (1000m): GPS noise'ı filtrele
- 🔄 TODO: Hız bazlı adaptive filtering (durduğunda daha az update)

### Weather API Cache Stratejisi
- ✅ 1 saat cache süresi
- ✅ In-memory cache (actor ile thread-safe)
- 🔄 TODO: Disk cache (offline destek - TODO-10)
- 🔄 TODO: Stale-while-revalidate pattern

### Map Rendering
- ✅ Annotation reuse (dequeueReusableAnnotationView)
- ✅ Programmatic vs user region change ayırımı (isProgrammaticRegionChange)
- ✅ Selective update (sadece değişen annotation'ları güncelle)
- ✅ Wind grid debounce: 1.5s bekleme ile gereksiz API çağrılarını önleme
- ✅ SwiftUI Canvas ile GPU-hızlandırılmış partikül çizimi
- ⚠️ Dikkat: OpenSeaMap tile'ları ağ üzerinden yükleniyor, yavaş bağlantıda gecikebilir
- ⚠️ Dikkat: Rüzgar overlay aktifken 6x6=36+ API çağrısı yapılır (grid noktaları)

### Battery Optimization
- ✅ Background location sadece tracking aktifken
- ✅ `pausesLocationUpdatesAutomatically = false` - manuel kontrol
- ✅ `activityType = .otherNavigation` - deniz seyri için optimize
- 🔄 TODO: Hız < 1 km/h ise update frekansını düşür

### Memory Management
- ✅ SwiftData cascade delete: Trip silinince TripPosition'lar otomatik silinir
- ✅ Weak references coordinator pattern'inde (parent reference)
- ⚠️ Dikkat: Uzun trip'lerde binlerce TripPosition birikebilir - limit koy (örn: 10000 nokta)

### Threading
- ✅ @MainActor - LocationManager, tüm UI güncellemeleri
- ✅ actor - WeatherService (thread-safe cache)
- ✅ Task/async-await - network işlemleri
- ⚠️ Dikkat: SwiftData modelContext işlemleri main thread'de

## Komutlar

```bash
# Xcode'da aç
open DenizRota.xcodeproj

# SwiftLint (kurulu ise)
swiftlint

# Proje temizle ve yeniden derle
xcodebuild clean build -project DenizRota.xcodeproj -scheme DenizRota

# Git
git status
git add .
git commit -m "mesaj"
git push origin <branch>

# Branch oluştur
git checkout -b claude/feature-name-12345

# Son commit'leri gör
git log --oneline --max-count=10
```

## Önemli Notlar

### Genel
- **Minimum iOS**: 17.0+ (SwiftUI ve SwiftData gereksinimleri)
- **Test Cihaz**: Background location ve bildirimler için gerçek cihaz gerekli
- **Lokalizasyon**: Şu an sadece Türkçe, ileride İngilizce eklenebilir
- **Web App**: https://github.com/tremo/DenizRota - Firebase ile senkronize olacak

### Teknik Sınırlamalar
- **Marine API**: Açık denizde (kıyıdan 50+ km) veri döndürmeyebilir - bu normal
- **Background Location**: iOS "Always" izni elle verilmeli (Settings → DenizRota → Konum)
- **Weather Cache**: 1 saat cache süresi, offline'da stale data gösterilebilir (TODO-10)
- **Fetch Calculation**: Türkiye Ege/Akdeniz kıyıları için optimize, diğer bölgelerde test edilmedi

### Geliştirme Notları
- **SwiftData**: Core Data'nın modern hali, `@Model` macro ile basit
- **Actor**: WeatherService thread-safe olması için actor
- **UIViewRepresentable**: NauticalMapView, MKMapView için gerekli (OpenSeaMap tile overlay)
- **Singleton Pattern**: Manager'lar app-wide state taşıdığı için singleton

### Bilinen Problemler
1. RouteManager derleme hataları (TODO-5)
2. TripManager kullanılmıyor (TODO-6)
3. Hardcoded fuel/speed değerleri (TODO-9)
4. ~~Weather API sadece current data~~ ✅ ÇÖZÜLDÜ (TODO-4)
5. Harita merkezi Ege genel (TODO-8)

### Gelecek Özellikler
- Firebase sync (web app ile)
- Offline harita cache (TODO-10)
- Nautical units (knot/nm) (TODO-7)
- Bookmark system (TODO-12)
