import SwiftUI
import SwiftData

// MARK: - Theme Preference
enum ThemePreference: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "Sistem"
        case .light: return "Açık"
        case .dark: return "Koyu"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

@main
struct DenizRotaApp: App {
    @StateObject private var locationManager = LocationManager.shared
    @AppStorage("themePreference") private var themePreference: String = ThemePreference.system.rawValue

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Route.self,
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
            fatalError("ModelContainer olusturulamadi: \(error)")
        }
    }()

    init() {
        // Bildirim izni iste
        Task {
            await NotificationManager.shared.requestPermission()
        }
    }

    private var selectedTheme: ThemePreference {
        ThemePreference(rawValue: themePreference) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .preferredColorScheme(selectedTheme.colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
