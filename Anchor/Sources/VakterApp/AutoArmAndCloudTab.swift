import SwiftUI
import CoreLocation
import VakterShared

/// Settings → Alerts & Cloud → "Auto-arm & Cloud" section.
///
/// Two cards rendered inside the consolidated Alerts & Cloud tab:
///   1. **Auto-arm rules** — list of rules + quick-add presets
///      (geofence, Wi-Fi-loss, idle, daily). Tapping "Add" creates a
///      sensible default the user can refine.
///   2. **Cloud evidence backup** — Backblaze B2 credentials or a
///      pre-signed URL template. Survives a wipe; explainer copy
///      points out that this is what makes the evidence
///      thief-proof.
///
/// Pre-v1.4.3 (Issue #23) this was its own top-level tab titled
/// "Auto-arm & Cloud". Post-consolidation it lives as a section
/// inside Alerts & Cloud — the rendered header was downgraded from
/// a page title to a sub-section eyebrow + headline so the visual
/// hierarchy reads cleanly under the parent tab title.
struct AutoArmAndCloudTab: View {

    @State private var rules: [AutoArmRule] = []
    @State private var cloudConfig = LiveCloudConfig()
    @State private var cloudFeedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingL) {
            sectionHeader
            autoArmCard
            cloudCard
        }
        .onAppear {
            rules = AutoArmRuleStore.load()
            cloudConfig.reload()
        }
    }

    // MARK: Header

    private var sectionHeader: some View {
        // Sub-section header inside Alerts & Cloud. Eyebrow + headline
        // rather than `font(size: 22)` because the parent tab already
        // owns the page title — using the same big type here would
        // produce two stacked titles.
        VStack(alignment: .leading, spacing: 4) {
            VakterEyebrow("Auto-arm & off-Mac backup")
            Text("Rules and bucket")
                .font(.system(size: 18, weight: .semibold))
            Text("Make Vakter arm itself when you forget, and back up evidence to a bucket you control so it survives even if your Mac is wiped.")
                .font(VakterDesign.bodyFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Auto-arm card

    private var autoArmCard: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingM) {
            HStack {
                Text("Auto-arm rules").font(.system(size: 15, weight: .semibold))
                Spacer()
                Menu("Add rule") {
                    Button("Idle for 5 minutes") { addRule(.idleForSeconds(seconds: 300)) }
                    Button("Idle for 15 minutes") { addRule(.idleForSeconds(seconds: 900)) }
                    Button("Off home Wi-Fi…") { addRule(.wifiDisconnect(ssids: ["HomeWiFi"])) }
                    Button("Daily at 6:00 PM") { addRule(.dailyAt(hour: 18, minute: 0)) }
                    Button("Leaving current location") {
                        // For v1.4 we seed with a placeholder; in v1.5
                        // we'll add a "Use my current location" picker
                        // that does a one-shot CLLocationManager probe.
                        addRule(.geofenceExit(latitude: 0, longitude: 0, radiusMeters: 100))
                    }
                }
                .menuStyle(.borderlessButton)
            }
            if rules.isEmpty {
                Text("No rules yet. Vakter only arms when you press the hotkey or click \u{2018}Arm\u{2019} in the menubar.")
                    .font(VakterDesign.captionFont)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, VakterDesign.spacingS)
            } else {
                ForEach(rules) { rule in
                    ruleRow(rule)
                    if rule.id != rules.last?.id {
                        Divider().padding(.leading, 38)
                    }
                }
            }
        }
        .padding(VakterDesign.spacingM)
        .background(
            RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func ruleRow(_ rule: AutoArmRule) -> some View {
        HStack(spacing: VakterDesign.spacingM) {
            Image(systemName: iconFor(rule.trigger))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(VakterDesign.accent)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.name).font(.system(size: 13, weight: .medium))
                Text(humanDescription(rule.trigger))
                    .font(VakterDesign.captionFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: binding(forEnabledOf: rule))
                .labelsHidden()
            Button {
                deleteRule(rule)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func iconFor(_ trigger: AutoArmRule.Trigger) -> String {
        switch trigger {
        case .geofenceExit:    return "location.fill"
        case .wifiDisconnect:  return "wifi.slash"
        case .idleForSeconds:  return "moon.zzz.fill"
        case .dailyAt:         return "clock.fill"
        }
    }

    private func humanDescription(_ trigger: AutoArmRule.Trigger) -> String {
        switch trigger {
        case .geofenceExit(let lat, let lon, let radius):
            return String(format: "Leaving %.4f, %.4f (r=%.0f m)", lat, lon, radius)
        case .wifiDisconnect(let ssids):
            return "Off Wi-Fi: \(ssids.joined(separator: ", "))"
        case .idleForSeconds(let s):
            return "Idle for \(Int(s / 60)) min"
        case .dailyAt(let h, let m):
            return String(format: "Daily at %02d:%02d", h, m)
        }
    }

    // MARK: Cloud card

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingM) {
            HStack {
                Text("Cloud evidence backup").font(.system(size: 15, weight: .semibold))
                Spacer()
                Picker("", selection: $cloudConfig.provider) {
                    Text("Off").tag("off")
                    Text("Backblaze B2").tag(CloudEvidenceUpload.Provider.backblazeB2.rawValue)
                    Text("Pre-signed URL").tag(CloudEvidenceUpload.Provider.presignedURL.rawValue)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            Text("On alarm, evidence (photos, audio, location, event log) is uploaded to a bucket you own. Even if the thief wipes the Mac, the evidence is already in the cloud.")
                .font(VakterDesign.captionFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if cloudConfig.provider == CloudEvidenceUpload.Provider.backblazeB2.rawValue {
                Form {
                    TextField("Key ID", text: $cloudConfig.keyID)
                    SecureField("Application key", text: $cloudConfig.secret)
                    TextField("Bucket ID", text: $cloudConfig.bucket)
                }
                .formStyle(.columns)
            } else if cloudConfig.provider == CloudEvidenceUpload.Provider.presignedURL.rawValue {
                Form {
                    TextField("URL template", text: $cloudConfig.secret,
                              prompt: Text("https://bucket.s3.amazonaws.com/{filename}?sig=..."))
                    Text("`{filename}` will be replaced with the per-file path on upload.")
                        .font(VakterDesign.captionFont)
                        .foregroundStyle(.secondary)
                }
                .formStyle(.columns)
            }

            HStack {
                Button("Save") { saveCloud() }
                    .keyboardShortcut(.defaultAction)
                if cloudConfig.provider != "off" {
                    Button("Clear", role: .destructive) {
                        CloudEvidenceConfig.clear()
                        cloudConfig.reload()
                        cloudFeedback = "Cleared"
                    }
                }
                Spacer()
                if let msg = cloudFeedback {
                    Text(msg).font(VakterDesign.captionFont).foregroundStyle(.secondary)
                }
            }
        }
        .padding(VakterDesign.spacingM)
        .background(
            RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: Mutations

    private func addRule(_ trigger: AutoArmRule.Trigger) {
        let rule = AutoArmRule(name: defaultName(for: trigger), trigger: trigger)
        rules.append(rule)
        _ = AutoArmRuleStore.save(rules)
        // Helper picks up the new rules on next launch. v1.5 polish:
        // post a notification the helper observes for live reload.
    }

    private func defaultName(for trigger: AutoArmRule.Trigger) -> String {
        switch trigger {
        case .geofenceExit:    return "Leaving location"
        case .wifiDisconnect:  return "Off home Wi-Fi"
        case .idleForSeconds:  return "Idle"
        case .dailyAt:         return "Daily"
        }
    }

    private func binding(forEnabledOf rule: AutoArmRule) -> Binding<Bool> {
        Binding(
            get: { rules.first(where: { $0.id == rule.id })?.enabled ?? false },
            set: { newValue in
                if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
                    rules[idx].enabled = newValue
                    _ = AutoArmRuleStore.save(rules)
                }
            }
        )
    }

    private func deleteRule(_ rule: AutoArmRule) {
        rules.removeAll { $0.id == rule.id }
        _ = AutoArmRuleStore.save(rules)
    }

    private func saveCloud() {
        if cloudConfig.provider == "off" {
            CloudEvidenceConfig.clear()
            cloudFeedback = "Off"
            return
        }
        guard let provider = CloudEvidenceUpload.Provider(rawValue: cloudConfig.provider) else {
            cloudFeedback = "Bad provider"
            return
        }
        let saved = CloudEvidenceConfig.save(.init(
            provider: provider,
            keyID: cloudConfig.keyID.isEmpty ? nil : cloudConfig.keyID,
            secret: cloudConfig.secret.isEmpty ? nil : cloudConfig.secret,
            bucket: cloudConfig.bucket
        ))
        cloudFeedback = saved ? "Saved" : "Couldn\u{2019}t save"
    }
}

/// Mutable view-model for the cloud card. Reads from
/// `CloudEvidenceConfig` (UserDefaults + Keychain) and writes back on Save.
@Observable
private final class LiveCloudConfig {
    var provider: String = "off"
    var keyID: String = ""
    var secret: String = ""
    var bucket: String = ""

    init() { reload() }

    func reload() {
        if let cfg = CloudEvidenceConfig.load() {
            provider = cfg.provider.rawValue
            keyID = cfg.keyID ?? ""
            secret = cfg.secret ?? ""
            bucket = cfg.bucket
        } else {
            provider = "off"
            keyID = ""; secret = ""; bucket = ""
        }
    }
}
