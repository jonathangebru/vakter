import Foundation

/// Which siren the alarm subsystem plays. The actual waveform synthesis
/// lives in `AudioController.startSiren()` — this enum is the contract
/// the Settings UI uses to let the user pick.
public enum AlarmSound: String, Codable, Sendable, CaseIterable, Equatable {

    /// Default. Continuous 880 Hz sine. Calm-protector brand voice.
    case classicSiren
    /// Sweeping frequency, 600 → 1200 Hz, 1 Hz/sec — more dramatic.
    case sweepKlaxon
    /// Two alternating tones (1000 Hz / 1300 Hz) at 4 Hz — phone-alert energy.
    case dualTone
    /// Single softer 660 Hz tone with slow LFO amplitude wobble — gentler
    /// for libraries, lecture halls, quiet hotel hallways. Still loud
    /// (forced to internal speakers at max volume) but less aggressive.
    case calmChime
    /// Japanese-style emergency two-tone, 1300 / 1700 Hz alternating
    /// at 2 Hz. Reads as "Japanese ambulance / police siren" — locals
    /// in JP recognise it instantly as "this is an emergency, not a
    /// novelty ringtone." Bystanders elsewhere just read it as urgent.
    case japaneseTwoTone
    /// European-style nee-naw, 660 / 990 Hz alternating at 1 Hz. The
    /// cadence Brits, Germans, and French read as "ambulance / police."
    /// Same logic as the JP variant — locale-recognisable urgency.
    case europeanNeeNaw

    // — Sample-backed sounds (Sonniss GDC 2026 — Federico Soler) ——————
    //
    // Three professionally-recorded alarm patterns shipped as bundled
    // AAC under `Resources/sounds/`. Audibly richer than the synth
    // waveforms (harmonics, body, depth) — the v1.1 quality upgrade.
    //
    /// Long sustained alarm tones with rising tension. Sample-backed,
    /// recommended default. Replaces the pre-v1.1 pure-sine classicSiren.
    case pulseAlarm
    /// Medium-rhythm pulsing klaxon. Halfway between continuous and
    /// staccato — strong attention without being frantic.
    case rhythmicKlaxon
    /// Fast urgent staccato pulses. Highest threat-perception, use
    /// for the alarming-mid-grace scenario.
    case urgentBeacon

    /// True if this sound plays back from a bundled audio file rather
    /// than being synthesised at runtime. `AudioController` uses this
    /// to pick the right playback path.
    public var isSampleBacked: Bool {
        switch self {
        case .pulseAlarm, .rhythmicKlaxon, .urgentBeacon: return true
        default: return false
        }
    }

    /// Resource name (no extension) for sample-backed sounds. nil for
    /// synth sounds.
    public var sampleResourceName: String? {
        switch self {
        case .pulseAlarm:     return "pulseAlarm"
        case .rhythmicKlaxon: return "rhythmicKlaxon"
        case .urgentBeacon:   return "urgentBeacon"
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .classicSiren:    return "Classic siren"
        case .sweepKlaxon:     return "Sweeping klaxon"
        case .dualTone:        return "Dual-tone alert"
        case .calmChime:       return "Calm chime"
        case .japaneseTwoTone: return "Japanese two-tone"
        case .europeanNeeNaw:  return "European nee-naw"
        case .pulseAlarm:      return "Pulse alarm"
        case .rhythmicKlaxon:  return "Rhythmic klaxon"
        case .urgentBeacon:    return "Urgent beacon"
        }
    }

    public var blurb: String {
        switch self {
        case .classicSiren:    return "Steady 880 Hz tone. Synth — clean, ungimmicky."
        case .sweepKlaxon:     return "Frequency sweeps up and down. The most attention-grabbing."
        case .dualTone:        return "Two alternating tones at 4 Hz. Reads as \u{201C}phone alert.\u{201D}"
        case .calmChime:       return "Slower, lower-pitched. Loud but less aggressive — for libraries."
        case .japaneseTwoTone: return "1300 / 1700 Hz two-tone. Reads as a Japanese emergency vehicle."
        case .europeanNeeNaw:  return "660 / 990 Hz nee-naw. Reads as a European ambulance / police siren."
        case .pulseAlarm:      return "Long sustained pulses with rising tension. The recommended default."
        case .rhythmicKlaxon:  return "Medium-rhythm pulsing klaxon. Confident, persistent."
        case .urgentBeacon:    return "Fast staccato bursts. Maximum urgency — use sparingly."
        }
    }

    public var icon: String {
        switch self {
        case .classicSiren:    return "speaker.wave.3.fill"
        case .sweepKlaxon:     return "waveform.path"
        case .dualTone:        return "waveform"
        case .calmChime:       return "bell.fill"
        case .japaneseTwoTone: return "waveform.badge.exclamationmark"
        case .europeanNeeNaw:  return "cross.case.fill"
        case .pulseAlarm:      return "alarm.fill"
        case .rhythmicKlaxon:  return "speaker.wave.2.bubble.fill"
        case .urgentBeacon:    return "exclamationmark.octagon.fill"
        }
    }
}

public enum AlarmSoundStore {

    private static var url: URL {
        VakterConstants.supportDirectoryURL.appendingPathComponent("alarm-sound.json")
    }

    public static func load() -> AlarmSound {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(AlarmSound.self, from: data) else {
            return .classicSiren
        }
        return s
    }

    public static func save(_ sound: AlarmSound) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(sound)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[AlarmSoundStore] save failed: %@", error.localizedDescription)
        }
    }
}
