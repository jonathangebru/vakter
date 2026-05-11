import SwiftUI
import AnchorShared

/// Root of the Settings window. Tab-based layout matching design.md.
struct SettingsRoot: View {

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            ShortcutTab()
                .tabItem { Label("Shortcut", systemImage: "command") }

            ModesTab()
                .tabItem { Label("Modes", systemImage: "rectangle.stack") }

            SoundTab()
                .tabItem { Label("Sound", systemImage: "speaker.wave.3") }

            BluetoothTab()
                .tabItem { Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right") }

            DefensesTab()
                .tabItem { Label("Defenses", systemImage: "checkmark.shield") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding()
    }
}

// MARK: Per-tab stubs (each will get its own file as content grows)

private struct GeneralTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General").font(.title2.weight(.semibold))
            Toggle("Launch Anchor at login", isOn: .constant(true)).disabled(true)
            Text("More options coming soon.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding()
    }
}

private struct ShortcutTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Arming Shortcut").font(.title2.weight(.semibold))
            HStack {
                Text("Current:")
                Text(AnchorConstants.defaultHotkeyLabel).monospaced().bold()
            }
            Text("Press the combo anywhere on your Mac to lock and arm Anchor.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding()
    }
}

private struct ModesTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Modes").font(.title2.weight(.semibold))
            ForEach(AnchorMode.allCases, id: \.self) { mode in
                VStack(alignment: .leading) {
                    Text(mode.displayName).bold()
                    Text(mode.blurb).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }.padding()
    }
}

private struct SoundTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sound").font(.title2.weight(.semibold))
            Text("Voice cue and siren preview coming soon.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding()
    }
}

private struct BluetoothTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trusted Bluetooth Devices").font(.title2.weight(.semibold))
            Text("Pair 1–10 trusted peers. Anchor dampens false alarms while any of them are nearby.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding()
    }
}

private struct DefensesTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Mac's defenses").font(.title2.weight(.semibold))
            Text("FileVault, Find My Mac, login window message, automatic login, firmware password, screen auto-lock — score-and-fix UI coming soon.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding()
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.fill")
                .font(.system(size: 48)).foregroundStyle(.tint)
            Text("Anchor").font(.title2.weight(.semibold))
            Text("Watch over your Mac. Walk away in peace.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding()
    }
}
