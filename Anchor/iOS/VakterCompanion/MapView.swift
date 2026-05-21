import SwiftUI
import MapKit

/// "Find my Vakter Mac" — drops pins for every event that carries a
/// location. The most recent event is highlighted so the user can spot
/// the latest known whereabouts at a glance.
struct MapView: View {

    @EnvironmentObject var store: CompanionStore

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Group {
                if locatedEvents.isEmpty {
                    ContentUnavailableView(
                        "No location yet",
                        systemImage: "map",
                        description: Text("As soon as your Mac captures a location during an event, it'll appear here.")
                    )
                } else {
                    Map(position: $position) {
                        ForEach(locatedEvents) { event in
                            Annotation(annotationLabel(event),
                                       coordinate: .init(latitude: event.locationLat!,
                                                         longitude: event.locationLon!)) {
                                pin(for: event)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .onAppear { recenter() }
                }
            }
            .navigationTitle("Map")
        }
    }

    private var locatedEvents: [CompanionEvent] {
        store.recentEvents.filter { $0.locationLat != nil && $0.locationLon != nil }
    }

    private func annotationLabel(_ event: CompanionEvent) -> String {
        event.timestamp.formatted(.relative(presentation: .named))
    }

    private func pin(for event: CompanionEvent) -> some View {
        let isLatest = event.id == locatedEvents.first?.id
        return ZStack {
            Circle()
                .fill(isLatest ? Color.red : Color.gray)
                .frame(width: isLatest ? 20 : 12,
                       height: isLatest ? 20 : 12)
            if isLatest {
                Circle()
                    .stroke(Color.red.opacity(0.4), lineWidth: 2)
                    .frame(width: 40, height: 40)
            }
        }
    }

    private func recenter() {
        guard let first = locatedEvents.first,
              let lat = first.locationLat, let lon = first.locationLon else { return }
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            latitudinalMeters: 1500,
            longitudinalMeters: 1500
        ))
    }
}
