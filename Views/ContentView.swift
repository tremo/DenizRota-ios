import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MapTabView()
                .tabItem {
                    Label("Harita", systemImage: "map")
                }
                .tag(0)

            RoutesTabView()
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
    var body: some View {
        NavigationStack {
            MapView()
                .navigationTitle("DenizRota")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct RoutesTabView: View {
    var body: some View {
        NavigationStack {
            Text("Kayıtlı Rotalar")
                .navigationTitle("Rotalar")
        }
    }
}

struct TripsTabView: View {
    var body: some View {
        NavigationStack {
            Text("Seyir Geçmişi")
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
}
