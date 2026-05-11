import Foundation

/// The four selectable modes, defined in `design.md` § Modes.
///
/// Each mode is a *posture*, not a different code path. The state machine is
/// identical across modes — only the parameters (grace duration, audible/
/// haptic, camera cadence, and Loaner trust window) change.
public enum AnchorMode: String, Codable, Sendable, CaseIterable, Equatable {
    case normal
    case travel
    case library
    case loaner

    /// User-facing label.
    public var displayName: String {
        switch self {
        case .normal:  return "Normal"
        case .travel:  return "Travel"
        case .library: return "Library"
        case .loaner:  return "Loaner"
        }
    }

    /// Short one-line description shown in the mode picker.
    public var blurb: String {
        switch self {
        case .normal:  return "Café and daily use."
        case .travel:  return "Hotels, airports, conferences."
        case .library: return "Quiet zones (silent alarm with iPhone)."
        case .loaner:  return "Lend the Mac with a timed trust window."
        }
    }
}

/// All tuneable parameters for a mode, materialised at the moment the alarm
/// fires (or grace begins). Defaults come from `design.md`.
public struct ModeParameters: Codable, Sendable, Equatable {
    /// Grace window duration in seconds.
    public let graceSeconds: TimeInterval

    /// Whether the alarm produces audible siren + voice cue.
    public let audible: Bool

    /// Photo capture cadence pattern.
    public let photoCadence: PhotoCadence

    public static let normal = ModeParameters(
        graceSeconds: 8,
        audible: true,
        photoCadence: .normal
    )

    public static let travel = ModeParameters(
        graceSeconds: 5,
        audible: true,
        photoCadence: .burst
    )

    /// v1 Library mode (audible elevated chirp; no haptic until v1.5 iPhone).
    public static let library = ModeParameters(
        graceSeconds: 8,
        audible: false,
        photoCadence: .burst
    )

    public static let loaner = ModeParameters(
        graceSeconds: 8,
        audible: true,
        photoCadence: .normal
    )

    public static func parameters(for mode: AnchorMode) -> ModeParameters {
        switch mode {
        case .normal:  return .normal
        case .travel:  return .travel
        case .library: return .library
        case .loaner:  return .loaner
        }
    }
}

/// Photo capture pattern after alarm onset.
public enum PhotoCadence: String, Codable, Sendable, Equatable {
    /// Three frames at t=0, t=2, t=5 seconds. Used by Normal and Loaner.
    case normal
    /// Burst — frame at t=0, then every 5 seconds for the first minute,
    /// then every 30 seconds until disarmed. Used by Travel and Library.
    case burst
}

/// Loaner-mode-specific trust window options. The user picks one when
/// entering Loaner. Anchor is treated as Unarmed for this duration, then
/// auto-rearms to the previously-selected mode.
public enum LoanerTrustWindow: TimeInterval, Codable, Sendable, CaseIterable {
    case oneHour   = 3600
    case twoHours  = 7200
    case fourHours = 14400

    public var displayName: String {
        switch self {
        case .oneHour:   return "1 hour"
        case .twoHours:  return "2 hours"
        case .fourHours: return "4 hours"
        }
    }
}
