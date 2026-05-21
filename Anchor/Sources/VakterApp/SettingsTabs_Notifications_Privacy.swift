import SwiftUI
import VakterShared

// MARK: - Notifications tab

/// Where the user configures the iMessage recipient that gets the
/// photo burst + Maps URL when an alarm fires. v0.9's headline UX
/// addition — without this Vakter only "screams locally," with this
/// the user's iPhone gets the evidence within ~10 s.
struct NotificationsTab: View {

    @State private var handle: String = ""
    @State private var saveStatus: String? = nil
    @State private var testStatus: String? = nil
    @State private var testInFlight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingL) {

            VakterEyebrow("Off-Mac evidence delivery")
            Text("When an alarm fires")
                .font(VakterDesign.displayLarge)
            Text("Vakter sends the first photos and the Mac's location to your iMessage so you have evidence on your phone — even if you can't get back to the Mac.")
                .font(VakterDesign.bodyFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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

// MARK: - Privacy tab

/// Stealth-menubar picker + future privacy toggles.
struct PrivacyTab: View {

    @State private var appearance: MenubarAppearance = .lighthouse
    @State private var saveStatus: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingL) {
            VakterEyebrow("Stealth")
            Text("Menubar appearance")
                .font(VakterDesign.displayLarge)
            Text("Pick how Vakter shows itself in the menubar. Hidden mode requires a working hotkey — set one up under Shortcut first.")
                .font(VakterDesign.bodyFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(MenubarAppearance.allCases, id: \.self) { option in
                appearanceCard(option)
            }

            diagnosticsCard

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

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingS) {
            Text("Diagnostics export").font(.headline)
            Text("Build a redacted zip on your Desktop with the last 7 days of events, current defenses, and your Vakter config. No iMessage handle, no Apple-ID hash, no photos — safe to email to support, your lawyer, or police.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    private func select(_ option: MenubarAppearance) {
        appearance = option
        MenubarAppearanceStore.save(option)
        NotificationCenter.default.post(
            name: .vakterMenubarAppearanceChanged,
            object: nil
        )
        saveStatus = "Saved."
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
