import SwiftUI
import SwiftData

@main
struct DenizRotaApp: App {
    @StateObject private var locationManager = LocationManager.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Waypoint.self,
            Trip.self,
            TripPosition.self,
            BoatSettings.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("ModelContainer oluşturulamadı: \(error)")
        }
    }()

    init() {
        // Bildirim izni iste
        Task {
            await NotificationManager.shared.requestPermission()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
        }
        .modelContainer(sharedModelContainer)
    }
}
