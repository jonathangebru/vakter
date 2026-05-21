import Foundation

/// The five selectable Vakter modes.
///
/// Each mode is a *posture*, not a different code path. The state machine is
/// identical across modes — only the parameters (grace duration, audible/
/// haptic, camera cadence, alarm-cap seconds, and default alarm sound)
/// change.
///
/// **Important — persistence contract.** The rawValues here ("normal",
/// "travel", "library", "loaner", "cafe") are written to disk by
/// `ActiveModeStore` (~/Library/Application Support/Vakter/active-mode.json).
/// Never change the rawValue of an existing case — that would silently
/// reset every user's mode to the default. Adding new cases is fine.
public enum VakterMode: String, Codable, Sendable, CaseIterable, Equatable {
    case normal
    case travel
    case library
    case loaner
    /// Public-space-tuned: longer grace (settled, you're sitting down),
    /// silent siren default (don't disturb the cafe), normal photo
    /// cadence (less obnoxious than burst), 30 s alarm cap (don't be
    /// the one whose laptop screams for 5 minutes in a Blue Bottle).
    case cafe

    /// User-facing label.
    public var displayName: String {
        switch self {
        case .normal:  return "Normal"
        case .travel:  return "Travel"
        case .library: return "Library"
        case .loaner:  return "Loaner"
        case .cafe:    return "Cafe"
        }
    }

    /// Short one-line description shown in the mode picker.
    public var blurb: String {
        switch self {
        case .normal:  return "Desk + daily use."
        case .travel:  return "Hotels, airports, conferences."
        case .library: return "Quiet zones (silent alarm with iPhone)."
        case .loaner:  return "Lend the Mac with a timed trust window."
        case .cafe:    return "Public spaces — discreet siren, short cap."
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

    /// Maximum alarm duration in seconds, or nil to run until disarmed.
    /// Used by `.cafe` to cap the public-space siren at 30 s so we don't
    /// turn a snatch into a community noise complaint.
    public let alarmCapSeconds: TimeInterval?

    /// Per-mode default `AlarmSound` *suggestion*. The user's globally-
    /// picked alarm sound (via `AlarmSoundStore`) always wins; this is
    /// only the preview / first-launch default. nil = no preference.
    public let defaultAlarmSound: AlarmSound?

    public init(
        graceSeconds: TimeInterval,
        audible: Bool,
        photoCadence: PhotoCadence,
        alarmCapSeconds: TimeInterval? = nil,
        defaultAlarmSound: AlarmSound? = nil
    ) {
        self.graceSeconds = graceSeconds
        self.audible = audible
        self.photoCadence = photoCadence
        self.alarmCapSeconds = alarmCapSeconds
        self.defaultAlarmSound = defaultAlarmSound
    }

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

    /// v1 Library mode (silent alarm; will pair with iPhone push in v1.0).
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

    /// Cafe — longer grace (you're settled), silent siren default so a
    /// false-positive doesn't disturb the room, normal photo cadence,
    /// 30 s alarm cap, soothing chime as the default sound.
    public static let cafe = ModeParameters(
        graceSeconds: 12,
        audible: false,
        photoCadence: .normal,
        alarmCapSeconds: 30,
        defaultAlarmSound: .calmChime
    )

    public static func parameters(for mode: VakterMode) -> ModeParameters {
        switch mode {
        case .normal:  return .normal
        case .travel:  return .travel
        case .library: return .library
        case .loaner:  return .loaner
        case .cafe:    return .cafe
        }
    }
}

/// Photo capture pattern after alarm onset.
public enum PhotoCadence: String, Codable, Sendable, Equatable {
    /// Three frames at t=0, t=2, t=5 seconds. Used by Normal, Loaner, Cafe.
    case normal
    /// Burst — frame at t=0, then every 5 seconds for the first minute,
    /// then every 30 seconds until disarmed. Used by Travel and Library.
    case burst
}

/// Loaner-mode-specific trust window options. The user picks one when
/// entering Loaner. Vakter is treated as Unarmed for this duration, then
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
