import Foundation
import SwiftData

// NOT: Firebase SDK'yı kullanmak için:
// 1. Xcode -> File -> Add Package Dependencies
// 2. URL: https://github.com/firebase/firebase-ios-sdk
// 3. FirebaseAuth ve FirebaseFirestore paketlerini seçin
// 4. GoogleService-Info.plist dosyasını projeye ekleyin

// Firebase SDK import edildiğinde bu satırları aktif edin:
// import FirebaseCore
// import FirebaseAuth
// import FirebaseFirestore

/// Firebase yönetimi servisi - Authentication ve Firestore işlemleri
@MainActor
class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    // MARK: - Published Properties
    @Published var isInitialized: Bool = false
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: FirebaseUser?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private Properties
    // private var db: Firestore?
    // private var auth: Auth?

    private init() {}

    // MARK: - Initialization

    /// Firebase'i başlat - AppDelegate veya App init'te çağrılmalı
    func initialize() {
        // Firebase SDK import edildiğinde:
        // FirebaseApp.configure()
        // auth = Auth.auth()
        // db = Firestore.firestore()

        isInitialized = true
        checkAuthState()
    }

    private func checkAuthState() {
        // Firebase SDK import edildiğinde:
        // if let user = auth?.currentUser {
        //     currentUser = FirebaseUser(from: user)
        //     isLoggedIn = true
        // }
    }

    // MARK: - Authentication

    /// Email ile kayıt ol
    func register(email: String, password: String, displayName: String) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Firebase SDK import edildiğinde:
        // let result = try await auth?.createUser(withEmail: email, password: password)
        // let changeRequest = result?.user.createProfileChangeRequest()
        // changeRequest?.displayName = displayName
        // try await changeRequest?.commitChanges()
        // currentUser = FirebaseUser(from: result?.user)
        // isLoggedIn = true

        // Placeholder - Firebase kurulunca kaldırılacak
        throw FirebaseError.notConfigured
    }

    /// Email ile giriş yap
    func login(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Firebase SDK import edildiğinde:
        // let result = try await auth?.signIn(withEmail: email, password: password)
        // currentUser = FirebaseUser(from: result?.user)
        // isLoggedIn = true

        throw FirebaseError.notConfigured
    }

    /// Google ile giriş yap
    func loginWithGoogle() async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Google Sign-In SDK gerekli
        throw FirebaseError.notConfigured
    }

    /// Çıkış yap
    func logout() throws {
        // Firebase SDK import edildiğinde:
        // try auth?.signOut()

        currentUser = nil
        isLoggedIn = false
    }

    /// Şifre sıfırlama emaili gönder
    func sendPasswordReset(email: String) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Firebase SDK import edildiğinde:
        // try await auth?.sendPasswordReset(withEmail: email)

        throw FirebaseError.notConfigured
    }

    // MARK: - Firestore - Settings

    /// Ayarları kaydet
    func saveSettings(_ settings: BoatSettings) async throws {
        guard isLoggedIn, currentUser != nil else {
            throw FirebaseError.notLoggedIn
        }

        // Firebase SDK import edildiğinde:
        // let data = settings.asDictionary
        // try await db?.collection("users").document(userId).collection("settings").document("boat").setData(data)

        throw FirebaseError.notConfigured
    }

    /// Ayarları yükle
    func loadSettings() async throws -> BoatSettings? {
        guard isLoggedIn, currentUser != nil else {
            throw FirebaseError.notLoggedIn
        }

        // Firebase SDK import edildiğinde:
        // let doc = try await db?.collection("users").document(userId).collection("settings").document("boat").getDocument()
        // if let data = doc?.data() {
        //     return BoatSettings(from: data)
        // }

        throw FirebaseError.notConfigured
    }

    // MARK: - Firestore - Routes

    /// Rotayı kaydet
    func saveRoute(_ route: Route) async throws {
        guard isLoggedIn, currentUser != nil else {
            throw FirebaseError.notLoggedIn
        }

        // Firebase SDK import edildiğinde:
        // let data = route.asDictionary
        // try await db?.collection("users").document(userId).collection("routes").document(route.id.uuidString).setData(data)

        throw FirebaseError.notConfigured
    }

    /// Rotaları yükle
    func loadRoutes() async throws -> [Route] {
        guard isLoggedIn, currentUser != nil else {
            throw FirebaseError.notLoggedIn
        }

        // Firebase SDK import edildiğinde:
        // let snapshot = try await db?.collection("users").document(userId).collection("routes").getDocuments()
        // return snapshot?.documents.compactMap { Route(from: $0.data()) } ?? []

        throw FirebaseError.notConfigured
    }

    /// Rotayı sil
    func deleteRoute(_ routeId: UUID) async throws {
        guard isLoggedIn, currentUser != nil else {
            throw FirebaseError.notLoggedIn
        }

        // Firebase SDK import edildiğinde:
        // try await db?.collection("users").document(userId).collection("routes").document(routeId.uuidString).delete()

        throw FirebaseError.notConfigured
    }

    // MARK: - Firestore - Trips

    /// Seyiri kaydet
    func saveTrip(_ trip: Trip) async throws {
        guard isLoggedIn, currentUser != nil else {
            throw FirebaseError.notLoggedIn
        }

        // Firebase SDK import edildiğinde:
        // let data = trip.asDictionary
        // try await db?.collection("users").document(userId).collection("trips").document(trip.id.uuidString).setData(data)

        throw FirebaseError.notConfigured
    }

    /// Seyirleri yükle
    func loadTrips() async throws -> [Trip] {
        guard isLoggedIn, currentUser != nil else {
            throw FirebaseError.notLoggedIn
        }

        // Firebase SDK import edildiğinde:
        // let snapshot = try await db?.collection("users").document(userId).collection("trips")
        //     .order(by: "startDate", descending: true)
        //     .getDocuments()
        // return snapshot?.documents.compactMap { Trip(from: $0.data()) } ?? []

        throw FirebaseError.notConfigured
    }

    /// Seyiri sil
    func deleteTrip(_ tripId: UUID) async throws {
        guard isLoggedIn, currentUser != nil else {
            throw FirebaseError.notLoggedIn
        }

        // Firebase SDK import edildiğinde:
        // try await db?.collection("users").document(userId).collection("trips").document(tripId.uuidString).delete()

        throw FirebaseError.notConfigured
    }

    // MARK: - Sync

    /// Tüm verileri senkronize et
    func syncAllData(context: ModelContext) async {
        guard isLoggedIn else { return }

        isLoading = true

        // Routes sync
        // do {
        //     let cloudRoutes = try await loadRoutes()
        //     // Merge logic...
        // } catch { }

        // Trips sync
        // do {
        //     let cloudTrips = try await loadTrips()
        //     // Merge logic...
        // } catch { }

        isLoading = false
    }
}

// MARK: - Firebase User Model
struct FirebaseUser {
    let id: String
    let email: String?
    let displayName: String?
    let photoURL: URL?

    var initials: String {
        guard let name = displayName, !name.isEmpty else {
            return email?.prefix(1).uppercased() ?? "U"
        }
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return name.prefix(1).uppercased()
    }

    // Firebase SDK import edildiğinde:
    // init(from user: User?) {
    //     self.id = user?.uid ?? ""
    //     self.email = user?.email
    //     self.displayName = user?.displayName
    //     self.photoURL = user?.photoURL
    // }
}

// MARK: - Firebase Errors
enum FirebaseError: LocalizedError {
    case notConfigured
    case notLoggedIn
    case networkError
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Firebase henüz yapılandırılmamış. Lütfen GoogleService-Info.plist dosyasını ekleyin."
        case .notLoggedIn:
            return "Bu işlem için giriş yapmanız gerekiyor."
        case .networkError:
            return "Ağ bağlantısı hatası. Lütfen internet bağlantınızı kontrol edin."
        case .unknownError(let message):
            return message
        }
    }
}

// MARK: - Firestore Dictionary Extensions
extension Trip {
    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "startDate": startDate.timeIntervalSince1970,
            "duration": duration,
            "distance": distance,
            "avgSpeed": avgSpeed,
            "maxSpeed": maxSpeed,
            "fuelUsed": fuelUsed,
            "fuelCost": fuelCost
        ]

        if let endDate = endDate {
            dict["endDate"] = endDate.timeIntervalSince1970
        }

        // Positions (simplified for storage)
        let positionData = positions.map { pos in
            [
                "lat": pos.latitude,
                "lng": pos.longitude,
                "ts": pos.timestamp.timeIntervalSince1970,
                "speed": pos.speed
            ]
        }
        dict["positions"] = positionData

        return dict
    }
}
