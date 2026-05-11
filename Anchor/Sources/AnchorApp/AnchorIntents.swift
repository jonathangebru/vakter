import Foundation
import AppIntents
import AnchorShared

// MARK: - Intents

/// Arms Anchor using the currently-selected mode. The most basic intent we
/// expose; everything else builds on it. The Shortcut form is:
///
///     Action: Arm Anchor
///
/// Returns nothing on success.
struct ArmAnchorIntent: AppIntent {
    static let title: LocalizedStringResource = "Arm Anchor"
    static let description = IntentDescription(
        "Locks your Mac and arms Anchor using the current mode. Use this from a Shortcut tied to your 'Café' Focus, or any automation that should hand off to Anchor."
    )

    func perform() async throws -> some IntentResult {
        // TODO(week-3): once the menubar app talks XPC to the helper, this
        // intent should dispatch to the helper's arm pathway and await
        // confirmation. For the spike, we just log so we can verify the
        // intent fires.
        NSLog("[Intent] ArmAnchorIntent.perform invoked")
        return .result()
    }
}

/// Switches Anchor's active mode.
struct SetAnchorModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Anchor Mode"
    static let description = IntentDescription(
        "Switches Anchor between Normal, Travel, Library, and Loaner modes."
    )

    @Parameter(title: "Mode")
    var mode: AnchorModeAppEnum

    func perform() async throws -> some IntentResult {
        NSLog("[Intent] SetAnchorModeIntent → %@", mode.rawValue)
        return .result()
    }
}

// MARK: - App-enum bridge for AnchorMode

/// AppIntents requires its own enum wrapper (it generates a metadata file
/// per case). We mirror AnchorMode here. Conversion is trivial.
enum AnchorModeAppEnum: String, AppEnum {
    case normal, travel, library, loaner

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mode"

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .normal:  "Normal",
        .travel:  "Travel",
        .library: "Library",
        .loaner:  "Loaner",
    ]

    /// Bridge into the shared model type.
    var asAnchorMode: AnchorMode {
        switch self {
        case .normal:  return .normal
        case .travel:  return .travel
        case .library: return .library
        case .loaner:  return .loaner
        }
    }
}

// MARK: - App Shortcuts provider

/// Surfaces our intents as App Shortcuts (pre-built Shortcut tiles that
/// users can drop into automations). Required for Spotlight + Shortcuts
/// auto-discovery on macOS 14+.
struct AnchorShortcutsProvider: AppShortcutsProvider {

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ArmAnchorIntent(),
            phrases: [
                "Arm \(.applicationName)",
                "Lock and arm \(.applicationName)",
            ],
            shortTitle: "Arm Anchor",
            systemImageName: "shield.fill"
        )

        AppShortcut(
            intent: SetAnchorModeIntent(),
            phrases: [
                "Set \(.applicationName) mode",
            ],
            shortTitle: "Set Anchor Mode",
            systemImageName: "rectangle.stack"
        )
    }
}
