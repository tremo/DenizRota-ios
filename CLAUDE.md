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

## Devam Eden Geliştirmeler

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
- [ ] Dark mode desteği

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
