# DenizRota iOS - Mimari ve Kod İncelemesi

Datca-Marmaris bolgesi, isimsiz koylara gunubirlik gezi senaryosu odakli inceleme.

## Oncelik Sirasi

### 1. KRITIK: FetchCalculator Kiyi Verisini Kullanmiyor

**Dosya:** `FetchCalculator.swift:114-136`

`Constants.swift` icinde Datca, Bozburun, Marmaris, Symi, Knidos icin detayli kiyi noktalari (`CoastlineData`) tanimlanmis, ancak `FetchCalculator.isNearCoastline()` bunlari kullanmiyor. Kendi icinde sadece 16 kaba kiyi noktasi var ve esik degeri ~11km (`threshold = 0.1` derece).

Datca yarimadasi en dar yerinde 1-2 km genisliginde. 11km cozunurluk ile yarimada govdesi algilanamaz. Sonuc: Korunakli bir koyda bile acik deniz dalgasi gosterebilir.

**Cozum:** `CoastlineData.allPoints` verisini kullanmali, threshold 0.01-0.02 dereceye dusurulmeli.

---

### 2. KRITIK: Harita Tipi Kiyi Navigasyonu Icin Yetersiz

**Dosya:** `MapView.swift:78` - `.mapStyle(.standard)`

Standard haritada koy girisleri, kayaliklar, sig alanlar gorunmuyor. Isimsiz koylari birbirinden ayirt etmek imkansiz. Demir atilacak noktayi degerlendirmek mumkun degil.

**Cozum:** Varsayilan `.hybrid` olmali veya harita tipi secici eklenmeli (standard/satellite/hybrid).

---

### 3. KRITIK: Ruzgar Siginagi Analizi Yok

Gunubirlik gezi planlayan bir denizcinin en temel sorusu: "Bugun hangi koy ruzgardan korunakli?" Uygulama ruzgar yonu/hizi ve kiyi verisine sahip ama bunlari birlestiremiyor.

**Cozum:** Koy agiz yonu vs ruzgar yonu karsilastirmasi, "bugun korunakli koylar" onerisi.

---

### 4. YUKSEK: Weather API Sadece Anlik Veri Cekiyor

**Dosya:** `WeatherService.swift:66` - `current=...` parametresi

DeparturePickerView gelecek saat planlamaya izin veriyor ama her zaman simdiki hava durumunu gosteriyor. Datca-Marmaris bolgesinde ogle sonrasi imbat 15-25 knot'a cikabilir.

**Cozum:** `hourly` parametresine gecis, kalkis saatine uygun veri gosterimi.

---

### 5. YUKSEK: RouteManager Derleme Hatalari

**Dosya:** `RouteManager.swift`

- Satir 42: `route.waypoints?.count` ama waypoints non-optional
- Satir 88: `fetchWeather(for:date:)` ama WeatherService date parametresi almiyor
- Satir 276: `fetchResult.fetchKm` ama calculateFetch() Double donduruyor

Ayrica MapView RouteManager'i kullanmiyor, kendi icinde dogrudan rota yonetimi yapiyor. Iki paralel sistem var.

---

### 6. YUKSEK: TripManager ile MapView Senkronize Degil

TripManager pause/resume, waypoint takibi, ilerleme gostergesi iceriyor. Ama MapView.stopTrip() TripManager'i kullanmiyor, dogrudan LocationManager'i cagiriyor. TripTrackingView'a gecis yok.

---

### 7. ORTA: Denizcilik Birimleri Kullanilmiyor

Her sey km/h ve km. Standart: knot ve deniz mili. En azindan ayarlarda birim tercihi olmali.

---

### 8. ORTA: Varsayilan Harita Merkezi Yanlis Bolgede

**Dosya:** `MapView.swift:16` - `(38.5, 27.0)` Izmir civari

Datca-Marmaris bolgesi ~36.75N, 28.2E civarinda.

---

### 9. ORTA: Yakit Hesabi BoatSettings'i Yok Sayiyor

**Dosya:** `MapView.swift:450` - `fuelRate: 20, fuelPrice: 45` hardcoded

Kullanici BoatSettings'te yakit tuketimini giriyor ama trip kaydedilirken bu degerler kullanilmiyor.

---

### 10. ORTA: Offline Calisma Destegi Yok

Datca-Marmaris kiyilarinda (Bozburun, Knidos, Symi) sinyal zayif. Harita tile cache yok, hava durumu offline erisilemez, "veri eski" uyarisi yok.

---

### 11. DUSUK: Risk Esikleri Tekne Tipine Gore Degismiyor

BoatSettings.boatType mevcut ama risk hesabinda kullanilmiyor.

---

### 12. DUSUK: Favori Nokta / Demir Atma Noktasi Kavrami Yok

Isimsiz koylara giden denizciler icin onceki ziyaretleri kaydetmek onemli. Mevcut model sadece rota waypoint'i destekliyor, yer isareti (bookmark/POI) kavrami yok.
