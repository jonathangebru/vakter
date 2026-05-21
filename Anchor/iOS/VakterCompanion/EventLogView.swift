import SwiftUI

/// Chronological event feed from the Mac. Newest first.
/// Tap a row for detail (photos, audio playback, location pin).
struct EventLogView: View {

    @EnvironmentObject var store: CompanionStore

    var body: some View {
        NavigationStack {
            Group {
                if store.recentEvents.isEmpty {
                    ContentUnavailableView(
                        "No events yet",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Events appear here when Vakter arms, disarms, or fires an alarm on your Mac.")
                    )
                } else {
                    List(store.recentEvents) { event in
                        NavigationLink {
                            EventDetailView(event: event)
                        } label: {
                            EventRow(event: event)
                        }
                    }
                    .refreshable { await store.refreshAll() }
                }
            }
            .navigationTitle("Events")
        }
    }
}

private struct EventRow: View {
    let event: CompanionEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(transition).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(event.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if !event.photoFilenames.isEmpty {
                    Label("\(event.photoFilenames.count)",
                          systemImage: "camera")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !event.audioFilenames.isEmpty {
                    Label("\(event.audioFilenames.count)",
                          systemImage: "mic")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if event.locationLat != nil {
                    Label("location",
                          systemImage: "location")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let trigger = event.trigger {
                    Text(trigger).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var transition: String {
        "\(event.fromState.capitalized) → \(event.toState.capitalized)"
    }

    private var tint: Color {
        switch event.toState {
        case "alarm":   return .red
        case "grace":   return .orange
        case "armed":   return .green
        case "unarmed": return .gray
        default:        return .secondary
        }
    }
}

private struct EventDetailView: View {
    let event: CompanionEvent

    var body: some View {
        Form {
            Section("When") {
                LabeledContent("Timestamp",
                    value: event.timestamp.formatted(date: .abbreviated, time: .standard))
            }
            Section("What") {
                LabeledContent("From", value: event.fromState.capitalized)
                LabeledContent("To", value: event.toState.capitalized)
                if let trigger = event.trigger {
                    LabeledContent("Trigger", value: trigger)
                }
            }
            if !event.photoFilenames.isEmpty || !event.audioFilenames.isEmpty {
                Section("Evidence") {
                    if !event.photoFilenames.isEmpty {
                        LabeledContent("Photos", value: "\(event.photoFilenames.count)")
                    }
                    if !event.audioFilenames.isEmpty {
                        LabeledContent("Audio clips", value: "\(event.audioFilenames.count)")
                    }
                    Text("Photo + audio payloads stream from your evidence bucket — open the dashboard URL the Mac emails you, or fetch them in Settings → Evidence Backup.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let lat = event.locationLat, let lon = event.locationLon {
                Section("Where") {
                    LabeledContent("Latitude", value: String(format: "%.5f", lat))
                    LabeledContent("Longitude", value: String(format: "%.5f", lon))
                    Link("Open in Maps",
                         destination: URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)")!)
                }
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
    }
}
