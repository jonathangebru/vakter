import SwiftUI
import CloudKit

/// Entry point for the Vakter iPhone companion.
///
/// **Architecture.** The app is read-mostly: it subscribes to the user's
/// private CloudKit database where the Mac publishes snapshots + events,
/// and renders them across four tabs (Status, Event Log, Map, Settings).
/// Remote arm/disarm round-trips through CloudKit too — the iPhone
/// writes a `VakterCommand` record that the Mac picks up on its next
/// CloudKit sync (typically <5 s thanks to the silent push delivered
/// via CloudKit subscriptions).
///
/// **Watch app.** The Apple Watch app is a peer of this iPhone app; it
/// connects via WatchConnectivity and mirrors the same state.
@main
struct VakterCompanionApp: App {

    @StateObject private var store = CompanionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task {
                    await store.bootstrap()
                }
        }
    }
}

struct RootView: View {

    @EnvironmentObject var store: CompanionStore

    var body: some View {
        TabView {
            StatusView()
                .tabItem { Label("Status", systemImage: "shield.lefthalf.filled") }

            EventLogView()
                .tabItem { Label("Events", systemImage: "list.bullet.clipboard") }

            MapView()
                .tabItem { Label("Map", systemImage: "map") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
