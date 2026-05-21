import Foundation
import AppKit
import SwiftUI

/// One item in the defense audit: a system-level security setting and its
/// status. The score is a roll-up of items.
struct DefenseCheck: Identifiable {
    enum Status { case healthy, warning, attention, unknown }

    let id: String
    let title: String
    let detail: String
    let status: Status
    let systemSettingsURL: URL?

    var icon: String {
        switch status {
        case .healthy:   return "checkmark.circle.fill"
        case .warning:   return "exclamationmark.triangle.fill"
        case .attention: return "exclamationmark.octagon.fill"
        case .unknown:   return "questionmark.circle"
        }
    }

    var tint: Color {
        switch status {
        case .healthy:   return VakterDesign.healthy
        case .warning:   return Color(red: 0.85, green: 0.60, blue: 0.20)  // amber
        case .attention: return VakterDesign.alarm
        case .unknown:   return Color.secondary
        }
    }
}

/// Reads macOS system posture without modifying anything. Vakter's
/// Defenses page surfaces these as a roll-up score — the user fixes
/// each issue by clicking through to System Settings.
///
/// All checks run via shell commands (defaults, fdesetup, spctl,
/// csrutil, socketfilterfw, bioutil, nvram, launchctl, softwareupdate)
/// because the equivalent Swift APIs are either deprecated, private,
/// or sandboxed away.
enum DefensesAudit {

    static func run() -> [DefenseCheck] {
        return [
            checkFileVault(),
            checkFindMyMac(),
            checkFirewall(),
            checkStealthMode(),
            checkGatekeeper(),
            checkSIP(),
            checkTouchIDEnrollment(),
            checkAutoLogin(),
            checkScreenLockDelay(),
            checkLoginWindowMessage(),
            checkSoftwareUpdates(),
            checkVakterAppInLoginItems(),
            // v1.4.2 — 8 new checks added per Feature #21, bringing the
            // audit total from 12 → 20. Order is load-bearing: existing
            // 12 keep their array index so `DefensesScoreHistory` (which
            // is keyed only by total score, not per-check) stays stable
            // across the upgrade.
            //
            // Categorisation (against the Pareto buckets in
            // `DefenseCategory`): the five "sharing" probes
            // (AirDrop / AirPlay / File / Media / Printer) and the two
            // remote-access probes (SSH / ARD) all belong to Firewall &
            // Sharing; boot security policy belongs to System Integrity.
            // `DefensesAudit` itself doesn't carry a category tag — the
            // category modelling lives in `DefenseChecklist.swift` and is
            // already wired through `DefensesProbe.runAll()`.
            checkAirDropDiscoverableMode(),
            checkAirPlayReceiver(),
            checkFileSharing(),
            checkMediaSharing(),
            checkPrinterSharing(),
            checkRemoteLogin(),
            checkRemoteManagement(),
            checkBootSecurityPolicy()
        ]
    }

    /// Roll-up score: percentage of "healthy" checks (0–100).
    static func score(_ checks: [DefenseCheck]) -> Int {
        guard !checks.isEmpty else { return 0 }
        let good = checks.filter { $0.status == .healthy }.count
        return (good * 100) / checks.count
    }

    // MARK: - Individual checks

    private static func checkFileVault() -> DefenseCheck {
        let out = shellOutput("/usr/bin/fdesetup status")
        let on = out.contains("FileVault is On")
        return DefenseCheck(
            id: "filevault",
            title: "FileVault disk encryption",
            detail: on
                ? "Your disk is encrypted. A thief can't read your files."
                : "Off. A thief who pulls your drive can read everything.",
            status: on ? .healthy : .attention,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FDE")
        )
    }

    /// Find My Mac. Old code looked at `MMeFMMEnabled` in a Preferences
    /// plist that no longer reliably exists on modern macOS — which is
    /// why this check was reporting "off" even when FMM was on. The
    /// reliable detection is the firmware-level `fmm-mobileme-token-FMM`
    /// variable in NVRAM, which is non-empty iff Find My Mac is enabled.
    private static func checkFindMyMac() -> DefenseCheck {
        // Try three detection methods in order — Find My state lives in
        // different places depending on macOS version + Apple Silicon vs
        // Intel + whether NVRAM is accessible to the user (it isn't
        // reliably on Sonoma+).
        //
        //   1. `nvram -p` (dump all) and grep for fmm-mobileme-token-FMM
        //      — works on Apple Silicon Sonoma+ where the specific-var
        //      lookup returns "data not found" even when the var exists.
        //   2. Specific `nvram fmm-mobileme-token-FMM` lookup — fallback
        //      for older macOS.
        //   3. MobileMeAccounts plist `DeviceLocator` service entry —
        //      most reliable but slowest.
        //
        // ANY of these succeeding marks Find My as on.
        var on = false

        // 1. nvram -p dump
        let allNvram = shellOutput("/usr/sbin/nvram -p")
        if allNvram.contains("fmm-mobileme-token-FMM") {
            // Look for the actual token line, not the BridgeHasAccount
            // companion var. Token line has a tab + a value after it.
            for line in allNvram.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1)
                if parts.count == 2,
                   parts[0] == "fmm-mobileme-token-FMM",
                   !parts[1].trimmingCharacters(in: .whitespaces).isEmpty {
                    on = true
                    break
                }
            }
        }

        // 2. Fallback to specific lookup if dump didn't show it
        if !on {
            let specific = shellOutput("/usr/sbin/nvram fmm-mobileme-token-FMM 2>/dev/null")
            let parts = specific.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let token = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                on = !token.isEmpty
            }
        }

        // 3. Last fallback: MobileMeAccounts plist
        if !on {
            let plistDump = shellOutput("/usr/bin/defaults read MobileMeAccounts 2>/dev/null")
            // The DeviceLocator service is what "Find My Mac" maps to.
            // Look for both the service name and its active status nearby.
            if plistDump.contains("Dataclass.DeviceLocator")
               || plistDump.contains("DataclassDeviceLocator") {
                on = true
            }
        }

        return DefenseCheck(
            id: "findmymac",
            title: "Find My Mac",
            detail: on
                ? "On. If this Mac is stolen, you can locate, lock, or remotely erase it from iCloud."
                : "Off. Turn it on under iCloud so you can locate or wipe a stolen Mac.",
            status: on ? .healthy : .attention,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane?iCloud")
        )
    }

    /// Application Firewall. `socketfilterfw --getglobalstate` returns
    /// "Firewall is enabled" or "Firewall is disabled". Note that in
    /// macOS 15+ the firewall settings no longer live in a plist —
    /// socketfilterfw is the only supported read path.
    private static func checkFirewall() -> DefenseCheck {
        let out = shellOutput("/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null")
        let on = out.lowercased().contains("enabled")
        return DefenseCheck(
            id: "firewall",
            title: "Application Firewall",
            detail: on
                ? "Enabled. Inbound connections from unfamiliar apps are blocked by default."
                : "Off. Any incoming network connection is allowed. Turn the firewall on for cafe and airport networks.",
            status: on ? .healthy : .warning,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Firewall")
        )
    }

    /// Stealth mode (firewall hides from probes/pings). Useful on public Wi-Fi.
    private static func checkStealthMode() -> DefenseCheck {
        let out = shellOutput("/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null")
        let on = out.lowercased().contains("enabled")
        return DefenseCheck(
            id: "stealth",
            title: "Firewall stealth mode",
            detail: on
                ? "On. Your Mac stays invisible to network scanners on public Wi-Fi."
                : "Off. Your Mac responds to unsolicited network probes — fine at home, less ideal on cafe Wi-Fi.",
            status: on ? .healthy : .warning,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Firewall")
        )
    }

    /// Gatekeeper. `spctl --status` returns "assessments enabled".
    private static func checkGatekeeper() -> DefenseCheck {
        let out = shellOutput("/usr/sbin/spctl --status 2>/dev/null")
        let on = out.contains("assessments enabled")
        return DefenseCheck(
            id: "gatekeeper",
            title: "Gatekeeper app verification",
            detail: on
                ? "On. macOS verifies signatures and notarisation before running new apps."
                : "Off. macOS will launch unsigned or tampered apps without warning. Re-enable in Privacy & Security.",
            status: on ? .healthy : .attention,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security")
        )
    }

    /// System Integrity Protection. `csrutil status` is the canonical
    /// check. Three states matter:
    ///   • "enabled."             → healthy
    ///   • "partially enabled."   → warning (custom config in Recovery)
    ///   • "disabled."            → attention (rare; dev machines only)
    ///
    /// Pre-fix the parser substring-matched "enabled" which also
    /// matched the "partially enabled" string, silently hiding the
    /// custom-config warning.
    private static func checkSIP() -> DefenseCheck {
        let out = shellOutput("/usr/bin/csrutil status 2>/dev/null").lowercased()
        let partial = out.contains("partially enabled")
        let fullyOn = !partial && out.contains("enabled")

        let status: DefenseCheck.Status
        let detail: String
        if fullyOn {
            status = .healthy
            detail = "Enabled. Even root processes can't touch protected system files. Standard macOS posture."
        } else if partial {
            status = .warning
            detail = "Partially enabled — you have a custom config from Recovery Mode. Some SIP protections are off. Run `csrutil status` in Terminal for the full breakdown."
        } else {
            status = .attention
            detail = "Disabled. SIP is normally only off on developer machines. Re-enable from Recovery Mode if this wasn't intentional."
        }

        return DefenseCheck(
            id: "sip",
            title: "System Integrity Protection",
            detail: detail,
            status: status,
            // SIP can only be toggled in Recovery Mode — no settings URL.
            systemSettingsURL: nil
        )
    }

    /// Touch ID enrolment. `bioutil -c -s` (system scope) needs sudo;
    /// `bioutil -r` user scope reads without sudo. Returns lines like
    /// "Effective biometric functionality: 1". We check whether any
    /// fingerprint exists by looking at the lower-cost user query.
    private static func checkTouchIDEnrollment() -> DefenseCheck {
        let out = shellOutput("/usr/bin/bioutil -r 2>/dev/null")
        let lower = out.lowercased()
        // macOS naming has shifted over the years:
        //   • pre-Sonoma:   "Touch ID for unlock: 1"
        //   • Sonoma+:      "Biometrics for unlock: 1"
        //     (since Apple Silicon Macs without a Touch ID sensor can
        //     still unlock biometrically via paired Apple Watch).
        // Plus the "Effective …" variants which represent the user-set
        // value after MDM / Screen Time policy has been applied.
        let unlockOn =
            lower.contains("biometrics for unlock: 1") ||
            lower.contains("effective biometrics for unlock: 1") ||
            lower.contains("touch id for unlock: 1") ||
            lower.contains("effective touch id for unlock: 1")
        return DefenseCheck(
            id: "touchid",
            title: "Touch ID for unlock",
            detail: unlockOn
                ? "Enrolled. You can disarm Vakter at the lock screen with a single fingertip."
                : "Not set up. Enrol a fingerprint so disarming Vakter takes one tap, not a typed password.",
            status: unlockOn ? .healthy : .warning,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.preferences.password")
        )
    }

    private static func checkAutoLogin() -> DefenseCheck {
        let out = shellOutput("/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null")
        let isAutoLogin = !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return DefenseCheck(
            id: "autologin",
            title: "Automatic login",
            detail: isAutoLogin
                ? "On. A thief who reboots your Mac will be logged straight in. Turn this off."
                : "Off. A reboot lands at the login screen — good.",
            status: isAutoLogin ? .attention : .healthy,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension")
        )
    }

    /// Screen lock posture has TWO settings, both important:
    ///   • `askForPassword`     — defaults to 1 (on). If 0, the lock
    ///                            screen *never* asks for a password.
    ///   • `askForPasswordDelay`— defaults to 0 (immediate). Larger
    ///                            values create a free-access window
    ///                            after the screen sleeps.
    ///
    /// We need both to be healthy. Pre-fix only the delay was checked,
    /// so a user with `askForPassword=0` would show ✅ when their lock
    /// screen actually demanded nothing.
    private static func checkScreenLockDelay() -> DefenseCheck {
        let askRaw = shellOutput("/usr/bin/defaults read com.apple.screensaver askForPassword 2>/dev/null")
        let delayRaw = shellOutput("/usr/bin/defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null")

        // Defaults: askForPassword = 1, askForPasswordDelay = 0
        // (an empty/missing read returns "" → fall back to the default).
        let askForPassword = Int(askRaw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
        let delay = Int(delayRaw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let passwordOn = askForPassword != 0
        let delayHealthy = delay == 0

        let healthy = passwordOn && delayHealthy

        let detail: String
        if !passwordOn {
            detail = "Off. Your lock screen doesn't actually require a password. Anyone who wakes the Mac can use it."
        } else if !delayHealthy {
            detail = "There's a \(delay)-second window after screen-off before a password is needed. Tighten to immediate."
        } else {
            detail = "Locked instantly after the screen turns off — good."
        }

        return DefenseCheck(
            id: "lockdelay",
            title: "Require password immediately",
            detail: detail,
            // !passwordOn is critical (.attention); delay-only is warning.
            status: healthy ? .healthy : (!passwordOn ? .attention : .warning),
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?General")
        )
    }

    private static func checkLoginWindowMessage() -> DefenseCheck {
        let out = shellOutput("/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow LoginwindowText 2>/dev/null")
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMessage = !trimmed.isEmpty
        return DefenseCheck(
            id: "loginmessage",
            title: "Lock-screen \u{201C}if found\u{201D} message",
            detail: hasMessage
                ? "A message is set — your contact info is visible on the lock screen."
                : "No message set. Add one so a good Samaritan can return a found Mac.",
            status: hasMessage ? .healthy : .warning,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?General")
        )
    }

    /// Pending macOS updates. Pre-fix this ran `softwareupdate -l`
    /// which hits Apple's servers and takes 10–30 s — guaranteed to
    /// time out under shellOutput's 6 s guard and report "updates
    /// available" even when there are none.
    ///
    /// Modern fix: read the cached scan result that macOS's own
    /// `softwareupdated` daemon writes to
    /// `/Library/Preferences/com.apple.SoftwareUpdate.plist`. The
    /// system refreshes that file in the background; it's instant
    /// to read.
    ///
    /// Keys we look at:
    ///   • `LastUpdatesAvailable` — Int count of pending updates
    ///     (0 = up to date)
    ///   • `LastFullSuccessfulDate` — Date of the last successful scan
    ///     (so we can flag "haven't checked in a long time")
    private static func checkSoftwareUpdates() -> DefenseCheck {
        let availRaw = shellOutput(
            "/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate LastUpdatesAvailable 2>/dev/null"
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let count = Int(availRaw)

        let status: DefenseCheck.Status
        let detail: String
        switch count {
        case .none:
            // Cache hasn't been populated yet (fresh install, or system
            // hasn't run softwareupdated). We don't know — surface that
            // honestly rather than guessing.
            status = .warning
            detail = "Couldn't read the update cache. Open System Settings → General → Software Update once to populate it."
        case .some(let n) where n == 0:
            status = .healthy
            detail = "No pending updates. Your security patches are current."
        case .some(let n):
            status = .warning
            detail = "\(n) update\(n == 1 ? "" : "s") pending. Security patches are usually included — install them when convenient."
        }

        return DefenseCheck(
            id: "swupdate",
            title: "macOS up to date",
            detail: detail,
            status: status,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.preferences.softwareupdate")
        )
    }

    /// Is Vakter itself approved + running as a Login Item? The helper
    /// LaunchAgent presence in `launchctl list` is the proxy.
    private static func checkVakterAppInLoginItems() -> DefenseCheck {
        let out = shellOutput("/bin/launchctl list 2>/dev/null")
        let agent = out.contains("app.vakter.mac.helper") ||
                    // Legacy fallback — pre-rebrand installs.
                    out.contains("app.anchor.mac.helper")
        return DefenseCheck(
            id: "vakter-launch",
            title: "Vakter launches at login",
            detail: agent
                ? "Vakter is approved and on watch."
                : "Vakter's background helper isn't registered. Open Login Items and toggle it on so Vakter watches your Mac on every boot.",
            status: agent ? .healthy : .warning,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        )
    }

    // MARK: - v1.4.2 additions (Feature #21)
    //
    // The 8 checks below cover the most common "wait, I left that on"
    // sharing footguns on a modern Mac plus Apple Silicon boot security.
    //
    // They follow the same shape as the original 12:
    //   • shell-out via `shellOutput()` (timeout-bounded, stderr-silent)
    //   • map the textual result into one of four `DefenseCheck.Status`
    //     values: .healthy / .warning / .attention / .unknown
    //   • surface a deep-link into System Settings where possible
    //
    // Heuristics deliberately err toward `.warning`, not `.attention`,
    // for sharing services because the "fix" is usually a single toggle
    // the user knowingly enabled (e.g. Printer Sharing at the office).
    // `.attention` is reserved for posture flips that genuinely undermine
    // theft response — e.g. Remote Login is ON, or boot security is
    // reduced from Full Security on Apple Silicon.

    /// AirDrop discoverability scope. Healthy when set to "Off" or
    /// "Contacts Only". "Everyone" is a warning — at a coffee shop your
    /// Mac becomes a target for random AirDrop spam / phishing prompts.
    ///
    /// Probe: `defaults read com.apple.sharingd DiscoverableMode`. The
    /// expected values are the three System Settings options surfaced as
    /// "Off" / "Contacts Only" / "Everyone". The key is only present
    /// once the user has explicitly opened the AirDrop pane and picked a
    /// scope — on a fresh install the key is missing, which we treat as
    /// the default Contacts Only (healthy) per Apple's documented
    /// default behaviour.
    private static func checkAirDropDiscoverableMode() -> DefenseCheck {
        let raw = shellOutput("/usr/bin/defaults read com.apple.sharingd DiscoverableMode 2>/dev/null")
        let val = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let status: DefenseCheck.Status
        let detail: String
        if val.contains("everyone") {
            status = .warning
            detail = "AirDrop is set to Everyone — strangers on cafe Wi-Fi can target you with AirDrop prompts. Switch to Contacts Only."
        } else if val.contains("contacts only") {
            status = .healthy
            detail = "Set to Contacts Only — only people in your iCloud contacts can see you."
        } else if val.contains("off") || val == "" {
            // Empty = key missing (key isn't written until the user
            // changes it from the macOS-default Contacts Only).
            status = .healthy
            detail = val.isEmpty
                ? "Using the macOS default (Contacts Only)."
                : "AirDrop visibility is off."
        } else {
            status = .unknown
            detail = "Couldn't read AirDrop visibility (got: \(val))."
        }

        return DefenseCheck(
            id: "airdrop-discoverable",
            title: "AirDrop discovery scope",
            detail: detail,
            status: status,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension")
        )
    }

    /// AirPlay Receiver — lets other Apple devices send their screen
    /// to your Mac. Reasonable for a home Mac mini wired to a TV;
    /// undesirable for a laptop in public.
    ///
    /// Probe: `launchctl list | grep com.apple.AirPlayXPCHelper`.
    /// `AirPlayXPCHelper` is the receiver-side helper that launchd
    /// only loads when the AirPlay Receiver toggle is on. The
    /// `AirPlayUIAgent` peer is always present (UI-only) — checking
    /// for the helper rather than the agent is what avoids the
    /// false-positive Pareto reported pre-v0.10.1. Same probe shape
    /// is already used in `DefensesProbe.itemAirPlayReceiver()`.
    private static func checkAirPlayReceiver() -> DefenseCheck {
        let out = shellOutput("/bin/launchctl list 2>/dev/null")
        let on = out.contains("com.apple.AirPlayXPCHelper")
        return DefenseCheck(
            id: "airplay-receiver",
            title: "AirPlay Receiver",
            detail: on
                ? "On. Anyone nearby on the same network can send their screen to your Mac. Off is the safe default for laptops."
                : "Off. Your Mac won't accept incoming AirPlay sessions.",
            status: on ? .warning : .healthy,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension")
        )
    }

    /// SMB File Sharing. `smbd` is loaded by launchd only while File
    /// Sharing is on in System Settings → Sharing. Two SMB-adjacent
    /// daemons exist:
    ///   • `com.apple.smbd`        — the SMB server itself
    ///   • `com.apple.smb.preferences` — a passive helper, ignored
    ///
    /// We grep for the server. Healthy = absent (sharing is off).
    /// Warn (not attention) because users at home often deliberately
    /// enable it to share their Public folder with a partner's Mac.
    private static func checkFileSharing() -> DefenseCheck {
        let out = shellOutput("/bin/launchctl list 2>/dev/null")
        let on = out.contains("com.apple.smbd")
        return DefenseCheck(
            id: "file-sharing",
            title: "File Sharing (SMB)",
            detail: on
                ? "On. Other devices on this network can browse your shared folders. Turn off in cafes / airports."
                : "Off. No SMB shares are exposed.",
            status: on ? .warning : .healthy,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")
        )
    }

    /// Media Sharing (Music library + Home Sharing). The launchd label
    /// is `com.apple.mediasharingd`. Same shape as File Sharing — warn
    /// when on, healthy when off, because there's a legitimate "share
    /// my Music library with the family iPad" use case.
    private static func checkMediaSharing() -> DefenseCheck {
        let out = shellOutput("/bin/launchctl list 2>/dev/null")
        let on = out.contains("com.apple.mediasharingd")
        return DefenseCheck(
            id: "media-sharing",
            title: "Media Sharing",
            detail: on
                ? "On. Your Music library is reachable over the network. Off is the safe default in public."
                : "Off. Your Music library isn't exposed.",
            status: on ? .warning : .healthy,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")
        )
    }

    /// Printer Sharing. `cupsctl` prints "_share_printers=0" or
    /// "_share_printers=1". The binary lives at `/usr/sbin/cupsctl`
    /// and is present on every macOS install (CUPS ships with the
    /// system). On Apple Silicon under macOS 15+ the binary requires
    /// no privilege escalation for a status read.
    ///
    /// We tolerate the binary being missing (would be weird, but on
    /// some kiosk/SOE builds it's deleted) by falling through to
    /// `.unknown` rather than asserting OFF.
    private static func checkPrinterSharing() -> DefenseCheck {
        let out = shellOutput("/usr/sbin/cupsctl 2>/dev/null")
        if out.isEmpty {
            return DefenseCheck(
                id: "printer-sharing",
                title: "Printer Sharing",
                detail: "Couldn't read CUPS status. Check System Settings → General → Sharing → Printer Sharing manually.",
                status: .unknown,
                systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")
            )
        }
        let on = out.contains("_share_printers=1")
        return DefenseCheck(
            id: "printer-sharing",
            title: "Printer Sharing",
            detail: on
                ? "On. Other devices on this network can print through your Mac. Off is the safe default for laptops."
                : "Off. Connected printers stay private to this Mac.",
            status: on ? .warning : .healthy,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")
        )
    }

    /// Remote Login (SSH). The launchd label for the SSH server is
    /// `com.openssh.sshd`. `launchctl list <label>` is the cleanest
    /// probe — it returns a job description plist if the service is
    /// loaded, or "Could not find service" otherwise. This sidesteps
    /// `systemsetup -getremotelogin` which requires admin privilege
    /// (and returns a misleading "You need administrator access"
    /// string for non-root callers — see DefensesProbe.itemRemoteLogin
    /// for the multi-fallback story we landed on in v0.10.1).
    ///
    /// On a healthy Mac SSH is off — flagged `.attention` (not just
    /// `.warning`) because an attacker with the user's password (or a
    /// pwned SSH key) gets full shell access to the Mac, which
    /// dramatically widens the blast radius of any other compromise.
    private static func checkRemoteLogin() -> DefenseCheck {
        let out = shellOutput("/bin/launchctl list com.openssh.sshd 2>/dev/null")
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        // launchctl prints a multi-line plist-like blob when the
        // service is loaded. When absent, it either prints "Could not
        // find service" or returns no output at all (depending on the
        // macOS version). Treat empty output as "absent" = healthy.
        if trimmed.isEmpty || trimmed.localizedCaseInsensitiveContains("could not find") {
            return DefenseCheck(
                id: "remote-login",
                title: "Remote Login (SSH)",
                detail: "Off. SSH access from other machines is disabled.",
                status: .healthy,
                systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")
            )
        }
        return DefenseCheck(
            id: "remote-login",
            title: "Remote Login (SSH)",
            detail: "On. SSH is accepting connections. Turn off when not actively in use — it's the most-attacked surface on a Mac.",
            status: .attention,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")
        )
    }

    /// Remote Management (Apple Remote Desktop / ARD). Listens for
    /// inbound VNC / ARD-protocol sessions. Disabled by default.
    ///
    /// Probe: `launchctl list com.apple.RemoteManagement`. Like SSH,
    /// flagged `.attention` when on because ARD is a full-control
    /// remote desktop protocol — the historical "Apple Remote Desktop
    /// Root" advisories made unprotected ARD a notorious foothold for
    /// post-exploitation.
    private static func checkRemoteManagement() -> DefenseCheck {
        let out = shellOutput("/bin/launchctl list com.apple.RemoteManagement 2>/dev/null")
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.localizedCaseInsensitiveContains("could not find") {
            return DefenseCheck(
                id: "remote-management",
                title: "Remote Management (ARD)",
                detail: "Off. Apple Remote Desktop isn't accepting inbound sessions.",
                status: .healthy,
                systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")
            )
        }
        return DefenseCheck(
            id: "remote-management",
            title: "Remote Management (ARD)",
            detail: "On. Apple Remote Desktop is reachable. Turn off unless you actually use ARD — it grants screen-and-control to authenticated callers.",
            status: .attention,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")
        )
    }

    /// Boot security policy on Apple Silicon. `bputil -d` dumps the
    /// current LocalPolicy. Healthy posture is "Full Security" — the
    /// default and only mode that prevents an attacker with physical
    /// access from booting an arbitrary OS or extracted kernel.
    ///
    /// Two reduced-security flavours exist:
    ///   • Reduced Security  — allows older macOS versions and kexts
    ///   • Permissive Security — same, plus disabled signature checks
    ///
    /// On Intel Macs `bputil` doesn't exist at all and there's no
    /// directly-comparable concept (the equivalent — Secure Boot on
    /// T2 Macs — is read via different tooling we'd need to wire
    /// separately). We gate this check via
    /// `sysctl hw.optional.arm64` and emit `.unknown` on Intel rather
    /// than misreport. The Intel population at v1.4.2 is small but
    /// nonzero (mostly 2019/2020 Intel MacBook Pros), and pretending
    /// the check passed would lower the score's signal value.
    ///
    /// Note: `bputil -d` requires no privilege escalation on macOS 15+
    /// when invoked by a regular user (read-only LocalPolicy dump).
    /// If a future macOS tightens that and returns "Operation not
    /// permitted", we fall through to `.unknown`.
    private static func checkBootSecurityPolicy() -> DefenseCheck {
        // Gate on Apple Silicon. `sysctl -n hw.optional.arm64` prints
        // "1" on Apple Silicon and "0" (or errors) on Intel.
        let arch = shellOutput("/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard arch == "1" else {
            return DefenseCheck(
                id: "boot-security",
                title: "Boot security policy",
                detail: "Not applicable on Intel Macs (the LocalPolicy boot model is Apple Silicon only).",
                status: .unknown,
                systemSettingsURL: nil
            )
        }

        let out = shellOutput("/usr/bin/bputil -d 2>/dev/null").lowercased()
        if out.isEmpty {
            return DefenseCheck(
                id: "boot-security",
                title: "Boot security policy",
                detail: "Couldn't read the LocalPolicy. Open Startup Security Utility in Recovery Mode to verify Full Security.",
                status: .unknown,
                systemSettingsURL: nil
            )
        }

        // `bputil -d` output keys we care about:
        //   "OS environment:" → "one true recoveryOS"   (uninteresting)
        //   "Local policy nonce hash" → opaque hash      (uninteresting)
        //   "Policy:" / "Security mode:" lines whose value embeds one
        //                       of "full", "reduced", "permissive".
        // We do a phrase-level lowercase scan rather than line parsing
        // so changes in Apple's exact key labels don't silently break
        // the probe.
        if out.contains("full security") {
            return DefenseCheck(
                id: "boot-security",
                title: "Boot security policy",
                detail: "Full Security. Only the OS this Mac shipped with (and Apple-signed updates) can boot.",
                status: .healthy,
                systemSettingsURL: nil
            )
        }
        if out.contains("permissive security") {
            return DefenseCheck(
                id: "boot-security",
                title: "Boot security policy",
                detail: "Permissive Security. Boot signature checks are disabled — only enable if you actively run kernel extensions.",
                status: .attention,
                systemSettingsURL: nil
            )
        }
        if out.contains("reduced security") {
            return DefenseCheck(
                id: "boot-security",
                title: "Boot security policy",
                detail: "Reduced Security. The Mac can boot older macOS / third-party kexts. Return to Full Security via Startup Security Utility if you don't need that flexibility.",
                status: .warning,
                systemSettingsURL: nil
            )
        }
        return DefenseCheck(
            id: "boot-security",
            title: "Boot security policy",
            detail: "LocalPolicy didn't include a recognisable security mode. Run `bputil -d` in Terminal for the full dump.",
            status: .unknown,
            systemSettingsURL: nil
        )
    }

    // MARK: - Utility

    /// Run a shell command and capture stdout. Stderr is discarded.
    ///
    /// A timeout protects against hangs — `softwareupdate -l` in
    /// particular can sit on Apple's servers for tens of seconds, and
    /// even after wake from sleep, the audit page mustn't freeze. If
    /// the timeout fires we SIGTERM the process and return whatever
    /// stdout we already have (empty most of the time).
    private static func shellOutput(_ command: String, timeout: TimeInterval = 6.0) -> String {
        let p = Process()
        p.launchPath = "/bin/sh"
        p.arguments = ["-c", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
        } catch {
            return ""
        }

        // Race the process against the timeout. We can't await
        // p.waitUntilExit() with a deadline, so use a dispatch group +
        // a kill timer.
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            p.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            // Terminate the process. We may have partial stdout already.
            p.terminate()
            // Give it a beat to flush, then SIGKILL if still hanging.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) {
                if p.isRunning {
                    kill(p.processIdentifier, SIGKILL)
                }
            }
            // Read whatever was already in the pipe — don't read the
            // full pipe (that would block).
            let fd = pipe.fileHandleForReading.fileDescriptor
            var flags = fcntl(fd, F_GETFL)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            let partial = pipe.fileHandleForReading.availableData
            flags = fcntl(fd, F_GETFL)
            _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
            return String(data: partial, encoding: .utf8) ?? ""
        }

        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                      encoding: .utf8) ?? ""
    }
}
