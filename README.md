# DenizRota iOS - Başlangıç Dosyaları

Bu klasör, DenizRota iOS uygulaması için hazırlanmış Swift/SwiftUI başlangıç dosyalarını içerir.

## Kullanım

1. Xcode'da yeni iOS App projesi oluştur (SwiftUI + SwiftData)
2. Bu klasördeki dosyaları projeye kopyala
3. Info.plist ayarlarını ekle (aşağıda)
4. Background Modes capability ekle

## Dosya Yapısı

```
ios-starter/
├── App/
│   └── DenizRotaApp.swift          # Ana uygulama entry point
├── Models/
│   ├── Waypoint.swift              # Waypoint modeli
│   ├── Trip.swift                  # Seyir kaydı modeli
│   └── BoatSettings.swift          # Tekne ayarları
├── Views/
│   ├── ContentView.swift           # Tab bar ana görünüm
│   ├── MapView.swift               # Harita görünümü
│   └── SettingsView.swift          # Ayarlar görünümü
├── Services/
│   ├── LocationManager.swift       # GPS + Background Location
│   ├── NotificationManager.swift   # Bildirimler
│   └── WeatherService.swift        # Open-Meteo API
└── Utils/
    └── FetchCalculator.swift       # Kıyı fetch hesaplama
```

## Info.plist Ayarları

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

## Capabilities

Project → Targets → Signing & Capabilities → + Capability:
- **Background Modes** → Location updates

## Minimum Gereksinimler

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Özellikler

- [x] MapKit harita entegrasyonu
- [x] Background location tracking
- [x] Hedefe varış bildirimleri
- [x] Hız paneli
- [x] Open-Meteo API (hava durumu)
- [x] Fetch calculation (kıyı dalga ayarı)
- [x] SwiftData persistence
- [ ] Firebase entegrasyonu (eklenecek)
- [ ] Rüzgar/dalga overlay (eklenecek)
