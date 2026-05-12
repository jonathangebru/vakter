import SwiftUI
import AppKit
import AnchorShared

/// Browses the persistent event log written by the helper.
///
/// Each ALARM event includes captured photos — shown inline as
/// thumbnails. Click a thumbnail to open the full-size image in the
/// system Preview app.
///
/// Empty state: a friendly card explaining that the log will fill in
/// as Anchor catches things (no alarming "you've been protected" copy).
struct EventLogView: View {

    @State private var events: [AnchorEvent] = []
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: AnchorDesign.spacingL) {
            HStack(alignment: .firstTextBaseline) {
                Text("Event Log")
                    .font(AnchorDesign.titleFont)
                Spacer()
                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            Text("Every arm, disarm, grace, and alarm Anchor has handled. Alarm entries include the photos captured at the moment.")
                .font(AnchorDesign.bodyFont)
                .foregroundStyle(.secondary)

            if events.isEmpty {
                emptyState
            } else {
                VStack(spacing: AnchorDesign.spacingS) {
                    ForEach(events) { event in
                        eventCard(event)
                    }
                }
            }
        }
        .onAppear {
            refresh()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                Task { @MainActor in refresh() }
            }
        }
        .onDisappear { refreshTimer?.invalidate() }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: AnchorDesign.spacingM) {
            ZStack {
                Circle()
                    .fill(AnchorDesign.anchor.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "clock")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(AnchorDesign.anchor)
            }
            Text("Nothing yet.")
                .font(.system(size: 18, weight: .semibold))
            Text("Once you've armed Anchor at least once, you'll see arm/disarm events here. Alarms (if any) will show their captured photos inline.")
                .font(AnchorDesign.bodyFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .padding(AnchorDesign.spacingXL)
        .background(
            RoundedRectangle(cornerRadius: AnchorDesign.radiusM, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: Event card

    private func eventCard(_ event: AnchorEvent) -> some View {
        VStack(alignment: .leading, spacing: AnchorDesign.spacingS) {
            HStack(spacing: AnchorDesign.spacingS) {
                tonePill(for: event)
                Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(transitionString(event))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let trigger = event.trigger {
                HStack(spacing: 6) {
                    Image(systemName: triggerIcon(trigger))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(humanTrigger(trigger))
                        .font(AnchorDesign.bodyFont)
                        .foregroundStyle(.primary)
                }
            }

            // Photo thumbnails for ALARM events.
            if event.toState == .alarm, !event.photoFilenames.isEmpty {
                let dirURL = AnchorConstants.eventsDirectoryURL
                    .appendingPathComponent(eventDirName(event), isDirectory: true)
                HStack(spacing: AnchorDesign.spacingS) {
                    ForEach(event.photoFilenames.prefix(6), id: \.self) { filename in
                        photoThumb(dirURL.appendingPathComponent(filename))
                    }
                    if event.photoFilenames.count > 6 {
                        Text("+\(event.photoFilenames.count - 6)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, height: 60)
                            .background(
                                RoundedRectangle(cornerRadius: AnchorDesign.radiusS)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    Spacer()
                }
                .padding(.top, AnchorDesign.spacingXS)
            }
        }
        .padding(AnchorDesign.spacingM)
        .background(
            RoundedRectangle(cornerRadius: AnchorDesign.radiusM, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AnchorDesign.radiusM, style: .continuous)
                .strokeBorder(borderColor(for: event), lineWidth: 1)
        )
    }

    private func photoThumb(_ url: URL) -> some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: AnchorDesign.radiusS, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AnchorDesign.radiusS, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .onTapGesture { NSWorkspace.shared.open(url) }
            } else {
                RoundedRectangle(cornerRadius: AnchorDesign.radiusS)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
    }

    // MARK: - Styling helpers

    private func tonePill(for event: AnchorEvent) -> some View {
        let (label, tone, icon): (String, AnchorStatusPill.Tone, String) = {
            switch event.toState {
            case .unarmed: return ("disarmed", .neutral,    "lock.open")
            case .armed:   return ("armed",    .watching,   "lock.fill")
            case .grace:   return ("grace",    .watching,   "hourglass")
            case .alarm:   return ("ALARM",    .attention,  "exclamationmark.triangle.fill")
            }
        }()
        return AnchorStatusPill(label, tone: tone, icon: icon)
    }

    private func borderColor(for event: AnchorEvent) -> Color {
        switch event.toState {
        case .alarm: return AnchorDesign.alarm.opacity(0.35)
        case .grace: return AnchorDesign.watch.opacity(0.30)
        default:     return Color.primary.opacity(0.08)
        }
    }

    private func transitionString(_ event: AnchorEvent) -> String {
        "\(event.fromState.rawValue) → \(event.toState.rawValue)"
    }

    private func triggerIcon(_ trigger: AnchorTrigger) -> String {
        switch trigger {
        case .lidClose:              return "rectangle.bottomhalf.inset.filled"
        case .powerDisconnect:       return "bolt.slash.fill"
        case .bluetoothPeerLeft:     return "antenna.radiowaves.left.and.right.slash"
        case .powerButtonBriefPress: return "power"
        case .userAction:            return "person.fill"
        }
    }

    private func humanTrigger(_ trigger: AnchorTrigger) -> String {
        switch trigger {
        case .lidClose:              return "Lid closed"
        case .powerDisconnect:       return "Power adapter disconnected"
        case .bluetoothPeerLeft:     return "Trusted Bluetooth device left range"
        case .powerButtonBriefPress: return "Power button pressed"
        case .userAction:            return "You took action (arm/disarm)"
        }
    }

    /// PhotoCapture writes into events/<ISO timestamp>/photo-NN.jpg.
    /// The directory name uses the same timestamp format we encode here.
    private func eventDirName(_ event: AnchorEvent) -> String {
        ISO8601DateFormatter().string(from: event.timestamp)
            .replacingOccurrences(of: ":", with: "-")
    }

    // MARK: - Data

    private func refresh() {
        events = EventLogStore.shared.recent(limit: 50)
    }
}
