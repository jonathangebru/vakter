import Foundation
import AppIntents
import VakterShared

// MARK: - Intents

/// Arms Vakter using the currently-selected mode. The most basic intent we
/// expose; everything else builds on it. The Shortcut form is:
///
///     Action: Arm Vakter
///
/// Returns nothing on success.
struct ArmVakterIntent: AppIntent {
    static let title: LocalizedStringResource = "Arm Vakter"
    static let description = IntentDescription(
        "Locks your Mac and arms Vakter using the current mode. Use this from a Shortcut tied to your 'Café' Focus, or any automation that should hand off to Vakter."
    )

    func perform() async throws -> some IntentResult {
        // TODO(week-3): once the menubar app talks XPC to the helper, this
        // intent should dispatch to the helper's arm pathway and await
        // confirmation. For the spike, we just log so we can verify the
        // intent fires.
        NSLog("[Intent] ArmVakterIntent.perform invoked")
        return .result()
    }
}

/// Switches Vakter's active mode.
struct SetVakterModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Vakter Mode"
    static let description = IntentDescription(
        "Switches Vakter between Normal, Travel, Library, and Loaner modes."
    )

    @Parameter(title: "Mode")
    var mode: VakterModeAppEnum

    func perform() async throws -> some IntentResult {
        NSLog("[Intent] SetVakterModeIntent → %@", mode.rawValue)
        return .result()
    }
}

// MARK: - App-enum bridge for VakterMode

/// AppIntents requires its own enum wrapper (it generates a metadata file
/// per case). We mirror VakterMode here. Conversion is trivial.
enum VakterModeAppEnum: String, AppEnum {
    case normal, travel, library, loaner, cafe

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mode"

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .normal:  "Normal",
        .travel:  "Travel",
        .library: "Library",
        .loaner:  "Loaner",
        .cafe:    "Cafe",
    ]

    /// Bridge into the shared model type.
    var asVakterMode: VakterMode {
        switch self {
        case .normal:  return .normal
        case .travel:  return .travel
        case .library: return .library
        case .loaner:  return .loaner
        case .cafe:    return .cafe
        }
    }
}

// MARK: - App Shortcuts provider

/// Surfaces our intents as App Shortcuts (pre-built Shortcut tiles that
/// users can drop into automations). Required for Spotlight + Shortcuts
/// auto-discovery on macOS 14+.
struct VakterShortcutsProvider: AppShortcutsProvider {

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ArmVakterIntent(),
            phrases: [
                "Arm \(.applicationName)",
                "Lock and arm \(.applicationName)",
            ],
            shortTitle: "Arm Vakter",
            systemImageName: "shield.fill"
        )

        AppShortcut(
            intent: SetVakterModeIntent(),
            phrases: [
                "Set \(.applicationName) mode",
            ],
            shortTitle: "Set Vakter Mode",
            systemImageName: "rectangle.stack"
        )
    }
}
