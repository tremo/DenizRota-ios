import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var routeToShowOnMap: Route?

    var body: some View {
        TabView(selection: $selectedTab) {
            MapTabView(routeToShow: $routeToShowOnMap)
                .tabItem {
                    Label("Harita", systemImage: "map")
                }
                .tag(0)

            RoutesTabView(onShowOnMap: { route in
                routeToShowOnMap = route
                selectedTab = 0
            })
                .tabItem {
                    Label("Rotalar", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .tag(1)

            TripsTabView()
                .tabItem {
                    Label("Seyirler", systemImage: "location.circle")
                }
                .tag(2)

            SettingsTabView()
                .tabItem {
                    Label("Ayarlar", systemImage: "gear")
                }
                .tag(3)
        }
        .tint(.blue)
    }
}

// MARK: - Tab Views

struct MapTabView: View {
    @Binding var routeToShow: Route?

    var body: some View {
        NavigationStack {
            MapView(routeToShow: $routeToShow)
                .navigationTitle("DenizRota")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }
}

struct RoutesTabView: View {
    var onShowOnMap: (Route) -> Void

    var body: some View {
        NavigationStack {
            RouteListView(onShowOnMap: onShowOnMap)
                .navigationTitle("Rotalar")
        }
    }
}

struct TripsTabView: View {
    var body: some View {
        NavigationStack {
            TripHistoryView()
                .navigationTitle("Seyirler")
        }
    }
}

struct SettingsTabView: View {
    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("Ayarlar")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager.shared)
        .modelContainer(for: [Route.self, Trip.self, BoatSettings.self], inMemory: true)
}
