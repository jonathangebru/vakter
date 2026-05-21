import SwiftUI

/// Vakter for Apple Watch.
///
/// **What it does.** Single-screen "arm/disarm + status" tile. The
/// signature interaction is the wrist-flick + tap that arms the Mac
/// as the user stands up to leave a café — solves the #1 friction
/// ("I forgot to hit the hotkey"). Watch never speaks to the Mac
/// directly; it goes through the iPhone companion via
/// WatchConnectivity, which then writes the command to CloudKit.
///
/// **Why not direct CloudKit?** Apple Watch supports CloudKit, but
/// the iPhone is already paying that connection's overhead. Watch →
/// iPhone → CloudKit is one round-trip cheaper and conserves the
/// Watch's battery noticeably better than running CloudKit + Combine
/// directly on the Watch.
@main
struct VakterWatchApp: App {

    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
        }
    }
}

struct WatchRootView: View {

    @EnvironmentObject var store: WatchStore
    @State private var commandInFlight = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: glyphName)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(glyphTint)

            VStack(spacing: 2) {
                Text(humanState)
                    .font(.system(size: 16, weight: .semibold))
                Text(store.mode.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button(action: toggle) {
                if commandInFlight {
                    ProgressView()
                } else {
                    Text(buttonLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(buttonTint)
            .disabled(commandInFlight)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Derived

    private var humanState: String {
        switch store.state {
        case "armed":   return "On watch"
        case "grace":   return "Grace"
        case "alarm":   return "Alarm"
        case "unarmed": return "Off watch"
        default:        return "—"
        }
    }

    private var glyphName: String {
        switch store.state {
        case "alarm": return "shield.lefthalf.filled.badge.exclamationmark"
        case "grace": return "shield.fill"
        case "armed": return "shield.lefthalf.filled"
        default:      return "shield"
        }
    }

    private var glyphTint: Color {
        switch store.state {
        case "alarm": return .red
        case "grace": return .orange
        case "armed": return .green
        default:      return .secondary
        }
    }

    private var buttonLabel: String {
        store.state == "unarmed" ? "Arm" : "Disarm"
    }

    private var buttonTint: Color {
        store.state == "unarmed" ? .accentColor : .red
    }

    private func toggle() {
        Task {
            commandInFlight = true
            await store.send(action: store.state == "unarmed" ? "arm" : "disarm")
            commandInFlight = false
        }
    }
}
