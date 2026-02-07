# DenizRota iOS - Claude.md

Bu dosya Claude Code'un projeyi anlaması için referans dokümantasyonudur.

## Proje Özeti

DenizRota, amatör denizciler için tekne rota planlama ve seyir takibi uygulamasıdır. Web uygulaması (https://github.com/tremo/DenizRota) ile senkronize çalışır.

## Teknoloji Stack

- **UI Framework**: SwiftUI
- **Harita**: MapKit
- **Veri Saklama**: SwiftData
- **Networking**: URLSession + async/await
- **GPS**: Core Location (Background Modes)
- **Bildirimler**: UserNotifications
- **Cloud**: Firebase (hazırlanıyor)

## Proje Yapısı

```
DenizRota/
├── App/
│   └── DenizRotaApp.swift       # Uygulama entry point
│
├── Models/
│   ├── Route.swift              # Rota modeli (@Model)
│   ├── Waypoint.swift           # Waypoint modeli (@Model)
│   ├── Trip.swift               # Seyir kaydı (@Model)
│   ├── TripPosition.swift       # GPS noktası (@Model)
│   └── BoatSettings.swift       # Tekne ayarları (@Model)
│
├── Views/
│   ├── ContentView.swift        # Tab bar ana görünüm
│   ├── Map/
│   │   ├── MapView.swift        # Ana harita görünümü
│   │   └── MapOverlays.swift    # Rüzgar/dalga overlay
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

## TODO Listesi (Oncelik Sirasina Gore)

Asagidaki maddeler "todo N'i yap" seklinde referans verilebilir.
Her madde bagimsiz olarak uygulanabilir.

---

### TODO-1: FetchCalculator'i CoastlineData ile Duzelt [KRITIK]
**Durum:** Yapilmadi
**Dosyalar:** `Utils/FetchCalculator.swift`, `Utils/Constants.swift`
**Sorun:** `FetchCalculator.isNearCoastline()` (satir 114-136) kendi icinde sadece 16 kaba kiyi noktasi kullaniyor. Threshold 0.1 derece (~11km). Ama `Constants.swift` icinde `CoastlineData` enum'unda Datca, Bozburun, Marmaris, Symi, Knidos vs. icin cok daha detayli kiyi noktalari zaten tanimli. FetchCalculator bunlari hic kullanmiyor.
**Yapilacak:**
1. `FetchCalculator.isNearCoastline()` metodunu `CoastlineData.allPoints` verisini kullanacak sekilde degistir
2. Threshold'u 0.1'den 0.015 dereceye (~1.5km) dusur
3. `isPointOnLand()` metodunda deniz alanlari kontrolunu `SeaAreas.isInSea()` ile degistir (kod tekrarini onle)
4. Test: Datca kuzey kiyisinda (36.76, 28.20) guney ruzgarinda fetch ~2km olmali (yarimada genisligi). Simdi muhtemelen 50-100km cikar.

---

### TODO-2: Harita Tipini Hybrid Yap + OpenSeaMap Tile Overlay Ekle [KRITIK]
**Durum:** Yapilmadi
**Dosyalar:** `Views/Map/MapView.swift`
**Sorun:** `.mapStyle(.standard)` (satir 78) kiyi navigasyonu icin yetersiz. Koylar, kayaliklar, sig alanlar gorunmuyor. Isimsiz koylari ayirt etmek imkansiz.
**Yapilacak:**
1. SwiftUI `Map` view'i `.mapStyle(.standard)` yerine `.mapStyle(.hybrid)` yap - bu en basit adim
2. Harita tipi secici ekle: Sag ust kosede kucuk bir buton ile `.standard` / `.hybrid` / `.imagery` arasinda gecis
3. OpenSeaMap entegrasyonu icin `UIViewRepresentable` ile `MKMapView` wrapper olustur (`Views/Map/NauticalMapView.swift` yeni dosya):
   - `MKTileOverlay` ile OpenSeaMap tile'larini yukle: `https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png`
   - Base map olarak `.satelliteFlyover` veya `.hybridFlyover` kullan
   - OpenSeaMap katmani deniz isaretlerini (samandira, fener, derinlik, demirleme alani) gosterir
   - Mevcut annotation/polyline/overlay mantigi aynen tasasin
   - `MapView.swift`'teki `Map(...)` blogu yerine `NauticalMapView(...)` kullanilsin
4. Harita tipi state'i: `@State private var mapStyle: MapStyleOption = .hybrid` enum ile yonet
5. OpenSeaMap tile'lari seffaf PNG oldugu icin uydu goruntusu ustune bindirilir - ek bir ayar gerekmez
**Not:** OpenSeaMap tile URL'si: `https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png` - ucretsiz, API key gerektirmez. Tile'lar sadece deniz isaret ve derinliklerini gosterir, altindaki harita Apple Maps'ten gelir.

---

### TODO-3: Ruzgar Siginagi Analizi Ekle [KRITIK]
**Durum:** Yapilmadi
**Dosyalar:** Yeni dosya `Services/ShelterAnalyzer.swift`, `Utils/Constants.swift`, `Views/Map/MapView.swift`
**Sorun:** Gunubirlik gezi planlayan denizcinin temel sorusu "bugun hangi koy korunakli?" ama uygulama bunu cevaplayamiyor.
**Yapilacak:**
1. `Constants.swift`'e bilinen koy/demirleme noktalari ekle - her biri icin:
   - Koordinat (lat, lng)
   - Isim (varsa, yoksa "Datca GB Koyu" gibi yonsel isim)
   - Agiz yonu (derece, kuzey=0): koyun denize acildigi yon
   - Ornegin: Knidos koyu agiz yonu ~270 (batiya bakiyor), Bozburun koyu ~180 (guneye bakiyor)
2. Yeni `ShelterAnalyzer.swift` olustur:
   - `func analyzeShelter(cove: Cove, windDirection: Double, windSpeed: Double) -> ShelterLevel`
   - ShelterLevel: `.excellent` (ruzgar koy arkasinda), `.good` (capraz), `.moderate` (kapali ama acili), `.poor` (ruzgar agizdan giriyor)
   - Mantik: ruzgar yonu ile koy agiz yonu arasindaki aci farki
     - 150-210 derece fark = excellent (ruzgar tam tersten)
     - 90-150 veya 210-270 = good (capraz)
     - 45-90 veya 270-315 = moderate
     - 0-45 veya 315-360 = poor (ruzgar agizdan)
3. `MapView.swift`'e "Korunakli Koylar" butonu ekle (kalkan ikonu):
   - Tiklaninca mevcut ruzgar yonunu al
   - Tum koylari analiz et
   - Haritada koylariyesil/sari/kirmizi ile isaretle
   - Liste olarak da gosterilebilir (sheet)

---

### TODO-4: Weather API'yi Saatlik Tahmine Gecir [YUKSEK]
**Durum:** Yapilmadi
**Dosyalar:** `Services/WeatherService.swift`
**Sorun:** API `current=...` parametresi kullaniyor (satir 66). Hep simdiki hava durumunu dondurur. DeparturePickerView gelecek saat secmeye izin veriyor ama hava durumu her zaman "simdi". Datca-Marmaris'te ogle sonrasi imbat 15-25 knot cikar, sabah ruzgarsiz olur.
**Yapilacak:**
1. `WeatherService.fetchWeather` metoduna `date: Date = Date()` parametresi ekle
2. API cagrisini degistir:
   - `current=...` yerine `hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,temperature_2m`
   - `forecast_days=2` ekle (bugun + yarin)
   - Response'ta `hourly.time[]` dizisinden hedef saate en yakin degeri sec
3. Marine API icin ayni: `hourly=wave_height,wave_direction,wave_period`
4. Response parsing: `WeatherAPIResponse` ve `MarineAPIResponse` struct'larini `hourly` formatina guncelle
5. `MapView.loadWeatherForRoute()` ve `DeparturePickerView` entegre et - secilen kalkis saatindeki hava durumunu gostersin
6. Cache key'e saat bilgisini ekle: `"\(lat),\(lng),\(hour)"` formati

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
5. Satir 88: `fetchWeather(for: waypoint.coordinate, date: departureDate)` -> WeatherService'in imzasina uydur. Eger TODO-4 yapildiysa `date` parametresi olacak, yapilmadiysa `date` parametresini kaldir
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

## Eski Gelistirme Plani

### Faz 4: Cloud Sync (Hazırlanıyor)
- [ ] Firebase SDK kurulumu
- [ ] GoogleService-Info.plist ekleme
- [ ] Authentication entegrasyonu
- [ ] Firestore senkronizasyon
- [ ] Web app ile ortak data

### UI İyileştirmeleri
- [x] Seyir tarihi/saati seçici (departure picker)
- [x] Otomatik hava durumu güncelleme (15 dk)
- [ ] Kayıtlı rotalar görünümünü geliştir
- [x] Dark mode desteği

### Testler
- [ ] Unit tests (WeatherService, FetchCalculator)
- [ ] UI tests (rota oluşturma, seyir flow)

## Firebase Kurulum Adımları

1. Xcode → File → Add Package Dependencies
2. URL: `https://github.com/firebase/firebase-ios-sdk`
3. Paketler: FirebaseAuth, FirebaseFirestore
4. Firebase Console'dan `GoogleService-Info.plist` indir
5. Dosyayı Xcode projesine ekle
6. `FirebaseManager.swift`'teki import satırlarını aktif et

## Komutlar

```bash
# Xcode'da aç
open DenizRota.xcodeproj

# SwiftLint (kurulu ise)
swiftlint

# Git
git status
git add .
git commit -m "mesaj"
git push origin <branch>
```

## Notlar

- Minimum iOS: 17.0
- SwiftData kullanılıyor (Core Data değil)
- Background location için "Always" izni gerekli
- Marine API bazı açık deniz noktalarında veri döndürmeyebilir
- Fetch hesaplaması kıyı çizgisi verilerine bağlı
