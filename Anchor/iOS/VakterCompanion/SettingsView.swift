import SwiftUI

/// iPhone-side settings. Mostly info + diagnostic actions — the
/// authoritative config lives on the Mac (modes, sounds, hotkey,
/// trusted peers, defenses, auto-arm rules, cloud bucket creds).
struct SettingsView: View {

    @EnvironmentObject var store: CompanionStore
    @AppStorage("vakter.companion.darkMap") private var darkMap = false
    @AppStorage("vakter.companion.notifyOnAlarm") private var notifyOnAlarm = true
    @AppStorage("vakter.companion.notifyOnArm") private var notifyOnArm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    LabeledContent("Device",
                                   value: store.snapshot?.deviceName ?? "—")
                    LabeledContent("State",
                                   value: humanState)
                    LabeledContent("iCloud",
                                   value: store.iCloudAvailable ? "Connected" : "Not signed in")
                    if let err = store.lastSyncError {
                        LabeledContent("Last error",
                                       value: err)
                            .font(.footnote)
                    }
                }

                Section("Notifications") {
                    Toggle("Alarm triggers", isOn: $notifyOnAlarm)
                    Toggle("Arm / disarm changes", isOn: $notifyOnArm)
                    Text("Vakter posts a silent push when your Mac changes state. Toggle here which transitions raise a banner.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Appearance") {
                    Toggle("Dark map style", isOn: $darkMap)
                }

                Section {
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Label("Refresh now", systemImage: "arrow.clockwise")
                    }
                }

                Section("About") {
                    LabeledContent("App version",
                                   value: appVersion)
                    Link("vakter.app", destination: URL(string: "https://vakter.app")!)
                    Link("Privacy & Security", destination: URL(string: "https://vakter.app/security")!)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var humanState: String {
        switch store.snapshot?.state {
        case "armed":   return "On watch"
        case "grace":   return "Grace period"
        case "alarm":   return "Alarm engaged"
        case "unarmed": return "Off watch"
        default:        return "—"
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
