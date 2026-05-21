import SwiftUI
import VakterShared

// Post-v1.4.3 consolidation (Issue #23): the Notifications and Privacy
// surfaces are no longer top-level Settings tabs. They live as sub-
// sections inside the consolidated tabs:
//
//   • `NotificationsSection`        → Settings → Alerts & Cloud
//   • `MenubarAppearanceSection`    → Settings → General
//   • `DiagnosticsSection`          → Settings → Alerts & Cloud
//
// We deliberately keep this file separate from SettingsRoot.swift even
// though both views are referenced from there — the file is small,
// self-contained, and history reads cleanly. Merging it back into
// SettingsRoot would just bloat that file.

// MARK: - Notifications section
//
// Where the user configures the iMessage recipient that gets the
// photo burst + Maps URL when an alarm fires. v0.9's headline UX
// addition — without this Vakter only "screams locally," with this
// the user's iPhone gets the evidence within ~10 s.
//
// Pre-v1.4.3 this was a standalone tab titled "When an alarm fires".
// Post-consolidation it lives inside Alerts & Cloud as the first
// section. The page-level title was dropped because the parent
// AlertsAndCloudTab labels the surface; the rest of the cards
// (recipient, test, disclosure) are unchanged.
struct NotificationsSection: View {

    @State private var handle: String = ""
    @State private var saveStatus: String? = nil
    @State private var testStatus: String? = nil
    @State private var testInFlight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingL) {

            // Sub-section header — sits inside the larger Alerts & Cloud
            // page. Uses the eyebrow + headline pattern from other cards
            // rather than a page title so the visual hierarchy stays:
            //   page title > section header > card title > card body.
            VStack(alignment: .leading, spacing: 4) {
                VakterEyebrow("Off-Mac evidence delivery")
                Text("iMessage recipient")
                    .font(.system(size: 18, weight: .semibold))
                Text("Vakter sends the first photos and the Mac's location to your iMessage so you have evidence on your phone — even if you can't get back to the Mac.")
                    .font(VakterDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            recipientCard
            testCard
            disclosureCard
        }
        .onAppear { reload() }
    }

    private var recipientCard: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingS) {
            Text("Recipient").font(.headline)
            Text("Phone number (E.164, e.g. +15551234567) or an Apple-ID email already registered with iMessage. Vakter only ever sends to this one handle.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("+15551234567 or you@example.com", text: $handle)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    save()
                }
                .disabled(handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let s = saveStatus {
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(VakterDesign.spacingL)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(VakterDesign.radiusL)
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingS) {
            Text("Test send").font(.headline)
            Text("Send a one-time test message to confirm Messages.app is connected. The first time you do this, macOS will ask for Automation consent — approve it once.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(testInFlight ? "Sending…" : "Send test") {
                    sendTest()
                }
                .disabled(testInFlight || EvidenceRecipientStore.load() == nil)
                if let s = testStatus {
                    Text(s).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(VakterDesign.spacingL)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(VakterDesign.radiusL)
    }

    private var disclosureCard: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingXS) {
            Label("Privacy", systemImage: "lock.shield.fill")
                .font(.caption.bold())
            Text("• Photos and location are sent only to this recipient — never to Vakter or any third party.\n• Location is fetched via Wi-Fi geolocation (accuracy 20 m – 5 km, depending on coverage).\n• If Location Services is off, Vakter sends the last successful fix from before arming, with an age stamp.\n• No recipient set = no off-Mac delivery (photos still save locally).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VakterDesign.spacingL)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(VakterDesign.radiusL)
    }

    private func reload() {
        handle = EvidenceRecipientStore.load()?.handle ?? ""
    }

    private func save() {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            EvidenceRecipientStore.save(nil)
            saveStatus = "Cleared."
        } else {
            EvidenceRecipientStore.save(EvidenceRecipient(handle: trimmed))
            saveStatus = "Saved."
        }
    }

    private func sendTest() {
        guard let recipient = EvidenceRecipientStore.load() else { return }
        testInFlight = true
        testStatus = nil
        Task {
            let delivery = iMessageEvidenceDelivery()
            let bundle = EvidenceBundle(
                reasonLine: "This is a Vakter test message. Your alarm channel is working.",
                mode: ActiveModeStore.load(),
                photoURLs: [],   // no photos for a test — just text
                location: nil,
                lastKnownLocation: nil,
                lastKnownLocationAge: nil,
                locale: .current
            )
            let result = await delivery.deliver(bundle, to: recipient)
            await MainActor.run {
                self.testInFlight = false
                switch result {
                case .success:
                    self.testStatus = "Sent. Check your phone."
                case .failure(let err):
                    self.testStatus = "Failed: \(err.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Menubar appearance section
//
// Pre-v1.4.3 this lived in the "Privacy" tab, which was misleading —
// the menubar appearance picker is more about *visibility* than
// data privacy. Post-consolidation it lives inside the General tab
// (where the user already configures the hotkey + alarm sound +
// stealth-overlay copy — all the "what does Vakter look/sound like"
// cosmetics in one place).
struct MenubarAppearanceSection: View {

    @State private var appearance: MenubarAppearance = .lighthouse
    @State private var saveStatus: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingL) {
            VStack(alignment: .leading, spacing: 4) {
                VakterEyebrow("Stealth")
                Text("Menubar appearance")
                    .font(.system(size: 18, weight: .semibold))
                Text("Pick how Vakter shows itself in the menubar. Hidden mode requires a working hotkey — set one up above first.")
                    .font(VakterDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(MenubarAppearance.allCases, id: \.self) { option in
                appearanceCard(option)
            }

            if let s = saveStatus {
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { appearance = MenubarAppearanceStore.load() }
    }

    private func appearanceCard(_ option: MenubarAppearance) -> some View {
        Button {
            select(option)
        } label: {
            HStack(alignment: .top, spacing: VakterDesign.spacingM) {
                Image(systemName: option == appearance ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(option == appearance ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: VakterDesign.spacingXS) {
                    Text(option.displayName).font(.headline)
                    Text(option.blurb).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(VakterDesign.spacingL)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(VakterDesign.radiusL)
        }
        .buttonStyle(.plain)
    }

    private func select(_ option: MenubarAppearance) {
        appearance = option
        MenubarAppearanceStore.save(option)
        NotificationCenter.default.post(
            name: .vakterMenubarAppearanceChanged,
            object: nil
        )
        saveStatus = "Saved."
    }
}

// MARK: - Diagnostics section
//
// Build a redacted zip of the last 7 days of events for support /
// legal / police. Pre-v1.4.3 this card sat at the bottom of the
// Privacy tab; post-consolidation it lives in Alerts & Cloud
// alongside the other evidence-delivery and cloud-backup surfaces
// (it's the same shape of feature — "package up the evidence").
struct DiagnosticsSection: View {

    @State private var saveStatus: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingS) {
            VStack(alignment: .leading, spacing: 4) {
                VakterEyebrow("Support")
                Text("Diagnostics export")
                    .font(.system(size: 18, weight: .semibold))
                Text("Build a redacted zip on your Desktop with the last 7 days of events, current defenses, and your Vakter config. No iMessage handle, no Apple-ID hash, no photos — safe to email to support, your lawyer, or police.")
                    .font(VakterDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Export to Desktop") {
                    exportDiagnostics()
                }
                if let s = saveStatus {
                    Text(s).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(VakterDesign.spacingL)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(VakterDesign.radiusL)
    }

    private func exportDiagnostics() {
        do {
            let url = try DiagnosticExport.build()
            saveStatus = "Exported: \(url.lastPathComponent)"
        } catch {
            saveStatus = "Failed: \(error.localizedDescription)"
        }
    }
}
