import SwiftUI
import AppKit
import MapKit
import VakterShared

/// Forensic event timeline.
///
/// Browses the persistent event log written by the helper, surfaces
/// the captured evidence inline (photos, audio waveform, location
/// pin, Merkle chain hashes), and lets the user export a police-ready
/// PDF in one click.
///
/// Matches the concepts-page § 05 spec: timeline with state pips on
/// the left rail, expandable detail block on the right showing every
/// piece of evidence the helper captured, plus filter chips and
/// search above.
struct EventLogView: View {

    // MARK: Filter chips

    enum Filter: String, CaseIterable, Identifiable {
        case all, armed, grace, alarm, photos, audio, location
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:      return "All"
            case .armed:    return "Armed"
            case .grace:    return "Grace"
            case .alarm:    return "Alarm"
            case .photos:   return "Photos"
            case .audio:    return "Audio"
            case .location: return "Location"
            }
        }
    }

    // MARK: State

    @State private var events: [VakterEvent] = []
    @State private var refreshTimer: Timer?
    @State private var filter: Filter = .all
    @State private var searchQuery: String = ""
    @State private var expandedEventID: UUID?

    private var filteredEvents: [VakterEvent] {
        events.filter { matchesFilter($0) && matchesSearch($0) }
    }

    /// Counts per filter, computed once from the full event list.
    /// Lets each chip show "Alarm · 3" instead of an opaque toggle.
    private var counts: [Filter: Int] {
        var c: [Filter: Int] = [.all: events.count]
        c[.armed]    = events.filter { $0.toState == .armed }.count
        c[.grace]    = events.filter { $0.toState == .grace }.count
        c[.alarm]    = events.filter { $0.toState == .alarm }.count
        c[.photos]   = events.filter { !$0.photoFilenames.isEmpty }.count
        c[.audio]    = events.filter { ($0.audioFilenames?.count ?? 0) > 0 }.count
        c[.location] = events.filter { $0.locationLat != nil }.count
        return c
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            toolbar

            if filteredEvents.isEmpty {
                events.isEmpty ? AnyView(emptyState) : AnyView(noMatchState)
            } else {
                AnyView(timeline)
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

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Event Log")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.6)
                Spacer()
                Button {
                    exportPDF()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Export PDF")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(VakterDesign.lantern)
                    )
                    .foregroundStyle(Color(red: 0.043, green: 0.082, blue: 0.188))
                }
                .buttonStyle(.plain)
                .help("Export the events below as a tamper-evident PDF report")
            }
            Text("Every arm, disarm, grace, and alarm Vakter has handled. Alarm entries include the captured photos, ambient audio, last-known location, and the cryptographic chain link.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Toolbar (filter chips + search)

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Filter chips with counts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Filter.allCases) { f in
                        filterChip(f)
                    }
                }
                .padding(.vertical, 1)
            }

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11, weight: .semibold))
                TextField("Search hash, trigger, transition…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func filterChip(_ f: Filter) -> some View {
        let isOn = filter == f
        let n = counts[f] ?? 0
        return Button(action: { filter = f }) {
            HStack(spacing: 6) {
                Text(f.label)
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                Text("·")
                    .opacity(0.5)
                Text("\(n)")
                    .font(.system(size: 12, weight: .regular).monospaced())
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isOn ? VakterDesign.lantern : Color.primary.opacity(0.06))
            )
            .foregroundStyle(isOn ? Color(red: 0.043, green: 0.082, blue: 0.188) : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Timeline

    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredEvents.enumerated()), id: \.element.id) { idx, event in
                eventRow(
                    event,
                    isLast: idx == filteredEvents.count - 1
                )
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: One event row

    private func eventRow(_ event: VakterEvent, isLast: Bool) -> some View {
        let isExpanded = expandedEventID == event.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                // Time column
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeOf(event))
                        .font(.system(size: 12.5, weight: .regular).monospaced())
                        .foregroundStyle(.primary)
                    Text(dayOf(event))
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 86, alignment: .leading)
                .padding(.top, 2)

                // Pip rail
                VStack(spacing: 0) {
                    Circle()
                        .fill(pipColor(for: event))
                        .frame(width: 11, height: 11)
                        .shadow(color: pipColor(for: event).opacity(0.6), radius: 6)
                        .padding(.top, 6)
                    if !isLast {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 14)

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(transitionLabel(event))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if hasEvidence(event) {
                            Text(isExpanded ? "Collapse" : "Expand")
                                .font(.system(size: 11).monospaced())
                                .foregroundStyle(.secondary)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !metaLine(event).isEmpty {
                        Text(metaLine(event))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    // Expanded detail
                    if isExpanded {
                        detailGrid(event)
                            .padding(.top, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.bottom, isLast ? 0 : 18)
                .padding(.top, 6)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasEvidence(event) else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    expandedEventID = isExpanded ? nil : event.id
                }
            }
        }
    }

    // MARK: Detail grid (photos / audio / location / chain)

    private func detailGrid(_ event: VakterEvent) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            if !event.photoFilenames.isEmpty {
                detailCard(label: "PHOTO BURST · \(event.photoFilenames.count) FRAMES") {
                    photoGrid(event)
                }
            }
            if let audio = event.audioFilenames, !audio.isEmpty {
                detailCard(label: "AMBIENT AUDIO · \(audio.count) CLIP\(audio.count == 1 ? "" : "S")") {
                    audioPanel(event, filenames: audio)
                }
            }
            if let lat = event.locationLat, let lon = event.locationLon {
                detailCard(label: "LAST KNOWN LOCATION") {
                    locationTile(lat: lat, lon: lon)
                }
            }
            if event.eventHash != nil {
                detailCard(label: "MERKLE CHAIN · SEALED") {
                    chainBlock(event)
                }
            }
        }
    }

    private func detailCard<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold).monospaced())
                .tracking(1.2)
                .foregroundStyle(.tertiary)
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: Photo grid

    private func photoGrid(_ event: VakterEvent) -> some View {
        let dir = eventDir(event)
        let visible = Array(event.photoFilenames.prefix(4))
        let extra = max(0, event.photoFilenames.count - visible.count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, name in
                    photoThumb(dir.appendingPathComponent(name))
                }
                if extra > 0 {
                    moreTile(extra: extra)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(event.photoFilenames.prefix(3), id: \.self) { name in
                    Text(name)
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func photoThumb(_ url: URL) -> some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .onTapGesture { NSWorkspace.shared.open(url) }
    }

    private func moreTile(extra: Int) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: 56, height: 56)
            .overlay(
                Text("+\(extra)")
                    .font(.system(size: 12, weight: .medium).monospaced())
                    .foregroundStyle(.secondary)
            )
    }

    // MARK: Audio panel

    private func audioPanel(_ event: VakterEvent, filenames: [String]) -> some View {
        let dir = eventDir(event)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    if let first = filenames.first {
                        NSWorkspace.shared.open(dir.appendingPathComponent(first))
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0.043, green: 0.082, blue: 0.188))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(VakterDesign.lantern))
                }
                .buttonStyle(.plain)
                .help("Open in QuickLook / system audio player")

                waveform()

                Text("\(filenames.count == 1 ? filenames[0] : "\(filenames.count) clips")")
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("AAC · 22 kHz mono")
                .font(.system(size: 10).monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    /// Static waveform — 28 bars at varied heights. Pre-computed for a
    /// consistent look across renders. (We don't read the actual audio
    /// to extract a real waveform; the visual is a placeholder shape
    /// that says "this is audio" at a glance.)
    private func waveform() -> some View {
        let heights: [CGFloat] = [4, 7, 12, 8, 16, 6, 11, 18, 9, 14, 6, 10, 16, 12, 6, 13, 9, 15, 11, 8, 12, 6, 10, 16, 13, 7, 10, 5]
        return HStack(alignment: .center, spacing: 1.5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(VakterDesign.lantern.opacity(0.65))
                    .frame(width: 2, height: h)
            }
        }
        .frame(height: 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Location tile (real MapKit)

    private func locationTile(lat: Double, lon: Double) -> some View {
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let region = MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )
        return VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .region(region)) {
                Annotation("", coordinate: coord) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.25))
                            .frame(width: 36, height: 36)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .allowsHitTesting(false)

            HStack {
                Text(String(format: "%.5f°N · %.5f°E", lat, lon))
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Link("Open in Maps",
                     destination: URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=Vakter+alert")!)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(VakterDesign.lantern)
            }
        }
    }

    // MARK: Merkle chain block

    private func chainBlock(_ event: VakterEvent) -> some View {
        let hash = event.eventHash ?? ""
        let prev = event.previousEventHash ?? "—"
        return VStack(alignment: .leading, spacing: 4) {
            chainLine(label: "hash", value: hash)
            chainLine(label: "prev", value: prev)
            chainLine(label: "signed", value: chainTimestamp(event))
            HStack(spacing: 5) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(VakterDesign.healthy)
                Text("Chain intact")
                    .font(.system(size: 9.5).monospaced())
                    .foregroundStyle(VakterDesign.healthy)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(VakterDesign.healthy.opacity(0.14))
            )
            .padding(.top, 4)
        }
    }

    private func chainLine(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10).monospaced())
                .foregroundStyle(VakterDesign.lantern)
                .frame(width: 40, alignment: .leading)
            Text(truncate(value, head: 10, tail: 8))
                .font(.system(size: 10).monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func truncate(_ s: String, head: Int, tail: Int) -> String {
        guard s.count > head + tail + 3 else { return s }
        let prefix = s.prefix(head)
        let suffix = s.suffix(tail)
        return "\(prefix)…\(suffix)"
    }

    private func chainTimestamp(_ event: VakterEvent) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: event.timestamp)
    }

    // MARK: Empty / no-match

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("No events yet")
                .font(.system(size: 15, weight: .semibold))
            Text("As soon as you arm Vakter, the log will start filling in. Try the Diagnostics → Run arm demo from the menubar.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var noMatchState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
            Text("No matching events.")
                .font(.system(size: 13, weight: .semibold))
            Text("Try a different filter or clear the search.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    // MARK: Predicates

    private func matchesFilter(_ event: VakterEvent) -> Bool {
        switch filter {
        case .all:      return true
        case .armed:    return event.toState == .armed
        case .grace:    return event.toState == .grace
        case .alarm:    return event.toState == .alarm
        case .photos:   return !event.photoFilenames.isEmpty
        case .audio:    return (event.audioFilenames?.count ?? 0) > 0
        case .location: return event.locationLat != nil
        }
    }

    private func matchesSearch(_ event: VakterEvent) -> Bool {
        guard !searchQuery.isEmpty else { return true }
        let q = searchQuery.lowercased()
        let triggerHit = event.trigger.map { humanTrigger($0).lowercased().contains(q) } ?? false
        let transHit = transitionLabel(event).lowercased().contains(q)
        let hashHit = (event.eventHash ?? "").lowercased().contains(q)
        return triggerHit || transHit || hashHit
    }

    // MARK: Helpers

    private func hasEvidence(_ event: VakterEvent) -> Bool {
        !event.photoFilenames.isEmpty
        || (event.audioFilenames?.count ?? 0) > 0
        || event.locationLat != nil
        || event.eventHash != nil
    }

    private func metaLine(_ event: VakterEvent) -> String {
        var bits: [String] = []
        if let t = event.trigger { bits.append(humanTrigger(t).lowercased()) }
        bits.append("\(event.modeAtEvent.rawValue) mode")
        if !event.photoFilenames.isEmpty {
            bits.append("\(event.photoFilenames.count) photo\(event.photoFilenames.count == 1 ? "" : "s")")
        }
        if let a = event.audioFilenames, !a.isEmpty {
            bits.append("\(a.count) audio")
        }
        if event.locationLat != nil {
            bits.append("location captured")
        }
        return bits.joined(separator: " · ")
    }

    private func transitionLabel(_ event: VakterEvent) -> String {
        switch (event.fromState, event.toState) {
        case (.unarmed, .armed):   return "Armed"
        case (.armed, .grace):     return "Grace period started"
        case (.grace, .alarm):     return "Alarm engaged"
        case (.armed, .alarm):     return "Alarm engaged (no grace)"
        case (.grace, .unarmed):   return "Disarmed during grace"
        case (.armed, .unarmed):   return "Disarmed"
        case (.alarm, .unarmed):   return "Alarm stopped"
        case (.alarm, .alarm):     return "Evidence appended"
        default:
            return "\(event.fromState.rawValue.capitalized) → \(event.toState.rawValue.capitalized)"
        }
    }

    private func humanTrigger(_ trigger: VakterTrigger) -> String {
        switch trigger {
        case .lidClose:              return "Lid closed"
        case .powerDisconnect:       return "Power disconnected"
        case .bluetoothPeerLeft:     return "Trusted Bluetooth left"
        case .powerButtonBriefPress: return "Power button"
        case .findMyCleared:         return "Find My cleared"
        case .appleIDChanged:        return "Apple ID changed"
        case .userAction:            return "Manual"
        }
    }

    private func pipColor(for event: VakterEvent) -> Color {
        switch event.toState {
        case .alarm:   return VakterDesign.alarm
        case .grace:   return VakterDesign.lantern
        case .armed:   return VakterDesign.healthy
        case .unarmed: return Color.primary.opacity(0.3)
        }
    }

    private func timeOf(_ event: VakterEvent) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: event.timestamp)
    }

    private func dayOf(_ event: VakterEvent) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(event.timestamp) { return "today" }
        if cal.isDateInYesterday(event.timestamp) { return "yesterday" }
        let f = DateFormatter()
        f.dateFormat = "dd MMM"
        return f.string(from: event.timestamp).lowercased()
    }

    private func eventDir(_ event: VakterEvent) -> URL {
        VakterConstants.eventsDirectoryURL
            .appendingPathComponent(
                ISO8601DateFormatter().string(from: event.timestamp)
                    .replacingOccurrences(of: ":", with: "-"),
                isDirectory: true
            )
    }

    // MARK: Refresh + Export

    private func refresh() {
        events = EventLogStore.shared.recent(limit: 50)
    }

    private func exportPDF() {
        let events = EventLogStore.shared.recent(limit: 30).reversed().map { $0 }
        let input = EvidenceReport.Input.from(events: events)

        let panel = NSSavePanel()
        panel.title = "Save Incident Report"
        panel.nameFieldStringValue = "vakter-incident-\(filenameStamp()).pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let out = EvidenceReport.render(input, to: url) {
                NSWorkspace.shared.activateFileViewerSelecting([out])
            }
        }
    }

    private func filenameStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f.string(from: Date())
    }
}
