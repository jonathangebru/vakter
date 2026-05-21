import SwiftUI

/// The home tab. Shows the Mac's current armed/unarmed/grace/alarm
/// state in big calm type, plus the primary arm/disarm action.
///
/// The visual language mirrors the macOS app's arming overlay so the
/// two experiences feel like one product across devices.
struct StatusView: View {

    @EnvironmentObject var store: CompanionStore
    @State private var commandInFlight = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Lighthouse glyph (placeholder until we share the
                // LighthouseGlyph Shape across targets).
                Image(systemName: glyphName)
                    .font(.system(size: 96, weight: .light))
                    .foregroundStyle(glyphTint)

                VStack(spacing: 8) {
                    Text(humanState).font(.system(size: 28, weight: .semibold))
                    Text(modeAndDevice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: toggle) {
                    HStack(spacing: 8) {
                        if commandInFlight { ProgressView() }
                        Text(buttonLabel).font(.system(size: 17, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(buttonTint)
                .disabled(commandInFlight || store.snapshot == nil)
                .padding(.horizontal)

                if !store.iCloudAvailable {
                    Label("iCloud not signed in — sign in to sync with your Mac.",
                          systemImage: "exclamationmark.icloud")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer().frame(height: 16)
            }
            .navigationTitle("Vakter")
            .refreshable { await store.refreshAll() }
        }
    }

    // MARK: - Derived

    private var snapshot: CompanionSnapshot? { store.snapshot }

    private var humanState: String {
        switch snapshot?.state {
        case "armed":   return "On watch"
        case "grace":   return "Grace period"
        case "alarm":   return "Alarm engaged"
        case "unarmed": return "Off watch"
        default:        return "Connecting\u{2026}"
        }
    }

    private var modeAndDevice: String {
        guard let snap = snapshot else { return "" }
        return "\(snap.deviceName) • \(snap.mode.capitalized) mode"
    }

    private var glyphName: String {
        switch snapshot?.state {
        case "alarm": return "shield.lefthalf.filled.badge.exclamationmark"
        case "grace": return "shield.fill"
        case "armed": return "shield.lefthalf.filled"
        default:      return "shield"
        }
    }

    private var glyphTint: Color {
        switch snapshot?.state {
        case "alarm": return .red
        case "grace": return .orange
        case "armed": return .green
        default:      return .secondary
        }
    }

    private var buttonLabel: String {
        snapshot?.state == "unarmed" ? "Arm Mac" : "Disarm"
    }

    private var buttonTint: Color {
        snapshot?.state == "unarmed" ? .accentColor : .red
    }

    // MARK: - Actions

    private func toggle() {
        Task {
            commandInFlight = true
            if snapshot?.state == "unarmed" {
                await store.sendArm()
            } else {
                await store.sendDisarm()
            }
            await store.refreshAll()
            commandInFlight = false
        }
    }
}
