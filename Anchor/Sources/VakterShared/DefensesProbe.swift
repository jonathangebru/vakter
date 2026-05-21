import Foundation

/// Lightweight, helper-callable snapshot of the user's core macOS
/// defenses at alarm time. Embedded inside the Evidence Bundle as
/// `defenses.json` so the recipient (and the user's later self) can
/// see the security posture *at the moment of the alarm* — useful
/// for police reports, insurance claims, and "did we lose anything
/// the thief could exploit" forensics.
///
/// Why a separate probe instead of reusing `DefensesAudit` from
/// VakterApp?
///   - `DefensesAudit` lives in VakterApp and pulls in SwiftUI types
///     for its UI render.
///   - The helper (which runs as a CLI LaunchAgent) cannot import
///     VakterApp.
///   - The Evidence Bundle needs only a Codable snapshot, not the UI
///     rows.
/// So this is a deliberately minimal re-implementation of the most
/// forensically-relevant shell probes.
public struct DefensesSnapshot: Codable, Sendable {
    public let capturedAt: Date
    public let fileVaultEnabled: Bool
    public let findMyTokenPresent: Bool
    public let firewallEnabled: Bool
    public let stealthModeEnabled: Bool
    public let gatekeeperEnabled: Bool
    public let sipEnabled: Bool
    public let autoLoginEnabled: Bool

    public init(capturedAt: Date,
                fileVaultEnabled: Bool,
                findMyTokenPresent: Bool,
                firewallEnabled: Bool,
                stealthModeEnabled: Bool,
                gatekeeperEnabled: Bool,
                sipEnabled: Bool,
                autoLoginEnabled: Bool) {
        self.capturedAt = capturedAt
        self.fileVaultEnabled = fileVaultEnabled
        self.findMyTokenPresent = findMyTokenPresent
        self.firewallEnabled = firewallEnabled
        self.stealthModeEnabled = stealthModeEnabled
        self.gatekeeperEnabled = gatekeeperEnabled
        self.sipEnabled = sipEnabled
        self.autoLoginEnabled = autoLoginEnabled
    }
}

public enum DefensesProbe {

    /// Run all probes synchronously. Should be called off the main
    /// thread because it shells out to ~6 binaries. Total wall-clock
    /// ~150 ms in practice.
    public static func snapshot() -> DefensesSnapshot {
        DefensesSnapshot(
            capturedAt: Date(),
            fileVaultEnabled:    probeFileVault(),
            findMyTokenPresent:  probeFindMyToken(),
            firewallEnabled:     probeFirewall(),
            stealthModeEnabled:  probeStealthMode(),
            gatekeeperEnabled:   probeGatekeeper(),
            sipEnabled:          probeSIP(),
            autoLoginEnabled:    probeAutoLogin()
        )
    }

    /// Pareto-style full checklist across all 5 categories. Used by
    /// the menubar dropdown ("Access Security › Firewall & Sharing ›
    /// macOS Updates › Software Updates › System Integrity").
    ///
    /// Probes are deliberately independent (each function can fail
    /// without affecting others) and silent on errors — a missing
    /// binary just yields `.unknown` for that one item, the rest
    /// keep running.
    ///
    /// Total wall-clock ~250–400 ms because of the slower probes
    /// (`softwareupdate -l`, SSH dir scan). Call off-main-thread.
    public static func runAll() -> DefenseChecklist {
        let items: [DefenseItem] = [
            // ── Access Security ────────────────────────────────────
            itemAutoLogin(),
            itemPasswordAfterSleep(),
            itemScreensaverDelay(),
            itemTouchIDEnrolled(),
            itemSSHKeysPassphrase(),
            itemFileVault(),
            // ── Firewall & Sharing ─────────────────────────────────
            itemFirewall(),
            itemStealthMode(),
            itemRemoteLogin(),
            itemRemoteManagement(),
            itemFileSharing(),
            itemMediaSharing(),
            itemPrinterSharing(),
            itemAirPlayReceiver(),
            // ── macOS Updates ──────────────────────────────────────
            itemMacOSAutoUpdate(),
            // ── Software Updates ───────────────────────────────────
            itemSoftwareUpdatesAvailable(),
            itemAppStoreAutoUpdate(),
            // ── System Integrity ───────────────────────────────────
            itemSIP(),
            itemGatekeeper(),
            itemFindMy(),
        ]
        return DefenseChecklist(runAt: Date(), items: items)
    }

    /// Same NVRAM token read used by `FindMyTokenWatcher` — exposed
    /// here so the alarm-time snapshot is consistent with the watcher's
    /// reality.
    public static func findMyTokenValue() -> String? {
        let out = runProcess("/usr/sbin/nvram", ["fmm-mobileme-token-FMM"])
        // Format on success: "fmm-mobileme-token-FMM\t<token>"
        // On absence: stderr "nvram: Error getting variable - 'fmm-mobileme-token-FMM': (iokit/common) data was not found"
        guard !out.isEmpty, out.contains("fmm-mobileme-token-FMM") else { return nil }
        return out
    }

    // MARK: - Individual probes

    private static func probeFileVault() -> Bool {
        runProcess("/usr/bin/fdesetup", ["status"])
            .lowercased()
            .contains("on")
    }

    private static func probeFindMyToken() -> Bool {
        findMyTokenValue() != nil
    }

    private static func probeFirewall() -> Bool {
        let out = runProcess(
            "/usr/libexec/ApplicationFirewall/socketfilterfw",
            ["--getglobalstate"]).lowercased()
        return out.contains("enabled")
    }

    private static func probeStealthMode() -> Bool {
        let out = runProcess(
            "/usr/libexec/ApplicationFirewall/socketfilterfw",
            ["--getstealthmode"]).lowercased()
        return out.contains("enabled")
    }

    private static func probeGatekeeper() -> Bool {
        runProcess("/usr/sbin/spctl", ["--status"]).contains("enabled")
    }

    private static func probeSIP() -> Bool {
        runProcess("/usr/bin/csrutil", ["status"]).contains("enabled")
    }

    private static func probeAutoLogin() -> Bool {
        // Auto-login is configured at /Library/Preferences/com.apple.loginwindow
        let out = runProcess("/usr/bin/defaults",
                             ["read", "/Library/Preferences/com.apple.loginwindow",
                              "autoLoginUser"])
        // If the key exists and isn't empty/error, auto-login is ON.
        return !out.contains("does not exist") && !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Pareto-style checklist items
    //
    // One function per `DefenseItem`. Naming convention `item<Thing>()`
    // distinguishes from the lower-level `probe<Thing>()` helpers above.
    // Each item is independent — a single broken probe just yields
    // `.unknown` for its one row, never affects the others.
    //
    // The `remediationURLString` deep-links into System Settings where
    // possible. Format reference:
    //   x-apple.systempreferences:com.apple.<pane-id>
    // The pane IDs were lifted from Apple's "Open System Settings" doc.

    // ── Access Security ─────────────────────────────────────────────

    private static func itemAutoLogin() -> DefenseItem {
        let on = probeAutoLogin()
        return DefenseItem(
            id: "access.autoLogin",
            category: .accessSecurity,
            title: on ? "Automatic login is ON" : "Automatic login is off",
            detail: "Auto-login lets anyone with physical access bypass the password screen. Keep it off.",
            status: on ? .fail : .pass,
            remediationURLString: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
        )
    }

    private static func itemPasswordAfterSleep() -> DefenseItem {
        // `defaults read com.apple.screensaver askForPassword`:
        //   - returns "1" when explicitly enabled
        //   - returns "0" when explicitly disabled
        //   - "does not exist" error when the user hasn't touched it
        //
        // On modern macOS (13+) "Require password" is ON by default and
        // managed via the Lock Screen pane; the `askForPassword` key is
        // only written when the user CHANGES from the default. So missing
        // key = the macOS default (ON), not OFF. We treat missing-key as
        // .pass to avoid the false-negative "Password after sleep is OFF"
        // bug v0.10.0 shipped with.
        let raw = runProcess("/usr/bin/defaults",
                             ["read", "com.apple.screensaver", "askForPassword"])
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitlyOff = trimmed == "0"
        return DefenseItem(
            id: "access.passwordAfterSleep",
            category: .accessSecurity,
            title: explicitlyOff
                ? "Password after sleep is OFF"
                : "Password after sleep is on",
            detail: "A thief who closes the lid and reopens it shouldn't get straight back in.",
            status: explicitlyOff ? .fail : .pass,
            remediationURLString: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"
        )
    }

    private static func itemScreensaverDelay() -> DefenseItem {
        // idleTime semantics:
        //   N (positive int)   → screensaver starts after N seconds
        //   0                  → explicitly disabled
        //   key missing        → using macOS default (20 min on Sonoma)
        //
        // We only flag .fail when the user has explicitly set 0 (disabled
        // entirely). Missing-key falls into the "20 min default" bucket
        // which is .warn (not bad but >15 min Pareto threshold).
        let raw = runProcess("/usr/bin/defaults", ["-currentHost", "read",
                                                    "com.apple.screensaver", "idleTime"])
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyMissing = trimmed.contains("does not exist")
        let idle: Int = keyMissing ? 1200 /* 20-min macOS default */
                                   : (Int(trimmed) ?? 1200)
        let status: DefenseStatus
        let title: String
        if !keyMissing && idle == 0 {
            status = .fail
            title = "Screensaver is disabled"
        } else if idle <= 900 {
            status = .pass
            title = "Screensaver shows in under 15 min"
        } else {
            status = .warn
            let mins = idle / 60
            title = keyMissing
                ? "Screensaver starts after ~\(mins) min (default)"
                : "Screensaver starts after \(mins) min"
        }
        return DefenseItem(
            id: "access.screensaverDelay",
            category: .accessSecurity,
            title: title,
            detail: "An idle Mac should lock itself quickly. Set the screensaver to start in 15 minutes or less under System Settings → Lock Screen → \"Start Screen Saver when inactive.\"",
            status: status,
            remediationURLString: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"
        )
    }

    private static func itemTouchIDEnrolled() -> DefenseItem {
        // `bioutil -r` output (Sonoma+):
        //   User Touch ID configuration:
        //     Biometrics for unlock: 1
        //     Effective biometrics for unlock: 1
        //
        // The pre-v0.10.1 probe looked for "template count: N" which
        // doesn't appear in any output I've seen — false-negative for
        // users with fingerprints enrolled. Correct signal:
        // "Effective biometrics for unlock: 1" means the user has at
        // least one fingerprint set up and the system honours it.
        let out = runProcess("/usr/bin/bioutil", ["-r"]).lowercased()

        if out.isEmpty || out.contains("is not available") {
            return DefenseItem(
                id: "access.touchID",
                category: .accessSecurity,
                title: "Touch ID not available",
                detail: "This Mac doesn't have a Touch ID sensor.",
                status: .unknown
            )
        }
        let enrolled = out.contains("effective biometrics for unlock: 1")
        return DefenseItem(
            id: "access.touchID",
            category: .accessSecurity,
            title: enrolled ? "Touch ID is enrolled" : "Touch ID is not enrolled",
            detail: "Enrolling a fingerprint lets you disarm Vakter with a tap instead of a password.",
            status: enrolled ? .pass : .warn,
            remediationURLString: "x-apple.systempreferences:com.apple.Touch-ID-Settings.extension"
        )
    }

    private static func itemSSHKeysPassphrase() -> DefenseItem {
        // Walk ~/.ssh/*.pub-paired keys; if any private key file has no
        // `Proc-Type: 4,ENCRYPTED` header (legacy) AND no encrypted
        // PEM marker, it's probably passphrase-less.
        let sshDir = ("~/.ssh" as NSString).expandingTildeInPath
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: sshDir) else {
            return DefenseItem(
                id: "access.sshKeys",
                category: .accessSecurity,
                title: "No SSH keys found",
                detail: "Nothing to protect — you don't have SSH keys on this Mac.",
                status: .pass
            )
        }
        var passphraseless = 0
        var total = 0
        for name in entries where name.hasPrefix("id_") && !name.hasSuffix(".pub") {
            total += 1
            let path = "\(sshDir)/\(name)"
            guard let header = try? String(contentsOfFile: path, encoding: .utf8).prefix(400)
            else { continue }
            let h = String(header)
            // Modern OpenSSH format (`-----BEGIN OPENSSH PRIVATE KEY-----`)
            // doesn't expose encryption in the header; we can only check
            // legacy PEM. For OpenSSH-format keys we treat them as
            // "unknown encryption" but lean .pass (most people who
            // generated keys recently used a passphrase).
            if h.contains("BEGIN RSA PRIVATE KEY") || h.contains("BEGIN DSA PRIVATE KEY") {
                if !h.contains("Proc-Type: 4,ENCRYPTED") {
                    passphraseless += 1
                }
            }
        }
        if total == 0 {
            return DefenseItem(
                id: "access.sshKeys",
                category: .accessSecurity,
                title: "No SSH keys found",
                detail: "Nothing to protect — you don't have SSH keys on this Mac.",
                status: .pass
            )
        }
        return DefenseItem(
            id: "access.sshKeys",
            category: .accessSecurity,
            title: passphraseless == 0
                ? "SSH keys require a passphrase"
                : "\(passphraseless) of \(total) SSH key\(total == 1 ? "" : "s") has no passphrase",
            detail: "A stolen Mac shouldn't grant access to your servers without an extra password.",
            status: passphraseless == 0 ? .pass : .fail
        )
    }

    private static func itemFileVault() -> DefenseItem {
        let on = probeFileVault()
        return DefenseItem(
            id: "access.fileVault",
            category: .accessSecurity,
            title: on ? "FileVault is on" : "FileVault is OFF",
            detail: "Disk encryption — a thief with the drive can't read your files.",
            status: on ? .pass : .fail,
            remediationURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_FDE"
        )
    }

    // ── Firewall & Sharing ──────────────────────────────────────────

    private static func itemFirewall() -> DefenseItem {
        let on = probeFirewall()
        return DefenseItem(
            id: "firewall.firewall",
            category: .firewallSharing,
            title: on ? "Firewall is on" : "Firewall is OFF",
            detail: "Blocks unsolicited incoming connections on hotel/cafe Wi-Fi.",
            status: on ? .pass : .fail,
            remediationURLString: "x-apple.systempreferences:com.apple.Network-Settings.extension"
        )
    }

    private static func itemStealthMode() -> DefenseItem {
        let on = probeStealthMode()
        return DefenseItem(
            id: "firewall.stealth",
            category: .firewallSharing,
            title: on ? "Firewall stealth mode is enabled" : "Firewall stealth mode is disabled",
            detail: "Stealth mode makes your Mac invisible to network scanners on public Wi-Fi.",
            status: on ? .pass : .warn,
            remediationURLString: "x-apple.systempreferences:com.apple.Network-Settings.extension"
        )
    }

    private static func itemRemoteLogin() -> DefenseItem {
        // Two-step probe:
        //   1. `launchctl list com.openssh.sshd` — works as user.
        //      `sshd-keygen-wrapper` is the actual launchd label.
        //   2. fallback: `systemsetup -getremotelogin` (requires admin
        //      → returns "You need administrator access" string from
        //      a non-root caller, which is most of our users).
        //
        // Pre-v0.10.1 we only tried (2) and misread the admin-required
        // error string as "on=false → off=pass" — false positive that
        // claimed Remote Login was off when really we couldn't tell.
        let lcOut = runProcess("/bin/launchctl",
                               ["list", "com.openssh.sshd"])
        let lcMissing = lcOut.contains("Could not find service")
        if !lcOut.isEmpty && !lcMissing {
            // launchctl returned a job description → sshd is loaded.
            return DefenseItem(
                id: "firewall.remoteLogin",
                category: .firewallSharing,
                title: "Remote Login is ON",
                detail: "SSH access from other Macs. Off by default — turn on only when you need it.",
                status: .fail,
                remediationURLString: "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
            )
        }
        if lcMissing {
            return DefenseItem(
                id: "firewall.remoteLogin",
                category: .firewallSharing,
                title: "Remote Login is off",
                detail: "SSH access from other Macs. Off by default — turn on only when you need it.",
                status: .pass,
                remediationURLString: "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
            )
        }
        // launchctl gave us nothing useful — try the systemsetup probe
        // and honestly degrade to .unknown if it asks for admin.
        let sysOut = runProcess("/usr/sbin/systemsetup",
                                ["-getremotelogin"]).lowercased()
        if sysOut.contains("administrator access") {
            return DefenseItem(
                id: "firewall.remoteLogin",
                category: .firewallSharing,
                title: "Remote Login: status unavailable",
                detail: "Vakter can't read this setting without admin privileges. Check System Settings → General → Sharing → Remote Login.",
                status: .unknown,
                remediationURLString: "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
            )
        }
        let on = sysOut.contains(": on")
        return DefenseItem(
            id: "firewall.remoteLogin",
            category: .firewallSharing,
            title: on ? "Remote Login is ON" : "Remote Login is off",
            detail: "SSH access from other Macs. Off by default — turn on only when you need it.",
            status: on ? .fail : .pass,
            remediationURLString: "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
        )
    }

    private static func itemRemoteManagement() -> DefenseItem {
        // ARDAgent ("Apple Remote Desktop") agent is launchd-managed:
        // com.apple.RemoteManagement → enabled or disabled.
        let out = runProcess("/bin/launchctl",
                             ["list", "com.apple.RemoteManagement"])
        let on = out.contains("\"Label\" = \"com.apple.RemoteManagement\"")
        return DefenseItem(
            id: "firewall.remoteManagement",
            category: .firewallSharing,
            title: on ? "Remote Management is ON" : "Remote Management is off",
            detail: "Apple Remote Desktop access. Strong attack surface; keep off unless you actually use ARD.",
            status: on ? .fail : .pass,
            remediationURLString: "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
        )
    }

    private static func itemFileSharing() -> DefenseItem {
        // smbd is the SMB sharing daemon; launchctl list shows it when
        // file sharing is on.
        let out = runProcess("/bin/launchctl", ["list", "com.apple.smbd"])
        let on = out.contains("\"Label\" = \"com.apple.smbd\"")
        return DefenseItem(
            id: "firewall.fileSharing",
            category: .firewallSharing,
            title: on ? "File Sharing is ON" : "File Sharing is off",
            detail: "Exposes your Documents and Public folder over SMB. Off is the safe default.",
            status: on ? .fail : .pass,
            remediationURLString: "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
        )
    }

    private static func itemMediaSharing() -> DefenseItem {
        let out = runProcess("/bin/launchctl",
                             ["list", "com.apple.mediasharingd"])
        let on = out.contains("\"Label\" = \"com.apple.mediasharingd\"")
        return DefenseItem(
            id: "firewall.mediaSharing",
            category: .firewallSharing,
            title: on ? "Media Sharing is ON" : "Media Sharing is off",
            detail: "Shares your Music library over the network. Off is the safe default.",
            status: on ? .warn : .pass,
            remediationURLString: "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
        )
    }

    private static func itemPrinterSharing() -> DefenseItem {
        let out = runProcess("/usr/sbin/cupsctl", [])
        // cupsctl prints "_share_printers=1" when sharing is on.
        let on = out.contains("_share_printers=1")
        return DefenseItem(
            id: "firewall.printerSharing",
            category: .firewallSharing,
            title: on ? "Printer Sharing is ON" : "Printer Sharing is off",
            detail: "Lets other Macs use your USB printer. Off is the safe default.",
            status: on ? .warn : .pass,
            remediationURLString: "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
        )
    }

    private static func itemAirPlayReceiver() -> DefenseItem {
        // The AirPlay-receiver toggle is a system-wide service that
        // launchd manages as `com.apple.AirPlayXPCHelper` / the
        // newer `com.apple.controlcenter.airplay-receiver`. Reading
        // `defaults com.apple.controlcenter AirplayReceiverEnabled`
        // returns "does not exist" on most installs because the key
        // is only written when the user toggles. The actual signal:
        //
        //   - `pmset -g | grep tcpkeepalive` (off on most installs)
        //   - `launchctl list | grep -i airplay`
        //
        // launchctl is the most reliable. On installs where AirPlay
        // receiver is on, you see one of:
        //   com.apple.AirPlayXPCHelper
        //   com.apple.AirPlayUIAgent  (UI-only, always present)
        let listOut = runProcess("/bin/launchctl", ["list"])
        let airPlayHelperRunning = listOut.contains("com.apple.AirPlayXPCHelper")
        return DefenseItem(
            id: "firewall.airplayReceiver",
            category: .firewallSharing,
            title: airPlayHelperRunning
                ? "AirPlay receiver is ON"
                : "AirPlay receiver is off",
            detail: "Lets other Apple devices send their screen to your Mac. Off is the safe default.",
            status: airPlayHelperRunning ? .warn : .pass,
            remediationURLString: "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension"
        )
    }

    // ── macOS Updates ───────────────────────────────────────────────

    private static func itemMacOSAutoUpdate() -> DefenseItem {
        // System-wide automatic OS-update preference.
        // Default on macOS 14+ for `AutomaticallyInstallMacOSUpdates` is OFF
        // (Apple still asks before installing major OS updates), so a
        // missing key → .warn rather than masquerading as ON.
        let raw = runProcess("/usr/bin/defaults",
                             ["read",
                              "/Library/Preferences/com.apple.SoftwareUpdate.plist",
                              "AutomaticallyInstallMacOSUpdates"])
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let on = trimmed == "1"
        return DefenseItem(
            id: "macos.autoUpdate",
            category: .macOSUpdates,
            title: on ? "macOS auto-updates are on" : "macOS auto-updates are off",
            detail: "Critical-security patches get installed without you having to remember.",
            status: on ? .pass : .warn,
            remediationURLString: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
        )
    }

    // ── Software Updates ────────────────────────────────────────────

    private static func itemSoftwareUpdatesAvailable() -> DefenseItem {
        // `softwareupdate -l` lists pending updates. "No new software
        // available." means we're current. Anything else is a list of
        // labels.
        let out = runProcess("/usr/sbin/softwareupdate", ["-l"])
        let current = out.contains("No new software available")
                   || out.contains("No updates are available")
        return DefenseItem(
            id: "software.updatesAvailable",
            category: .softwareUpdates,
            title: current ? "macOS is up to date" : "macOS updates are pending",
            detail: "Click here to open Software Update and install pending patches.",
            status: current ? .pass : .warn,
            remediationURLString: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
        )
    }

    private static func itemAppStoreAutoUpdate() -> DefenseItem {
        // App Store autoUpdate is in com.apple.commerce.plist.
        // Default on modern macOS is ON, and Apple writes the value
        // lazily — so a missing key means "default (on)", not off.
        // The pre-v0.10.1 probe wrongly flagged this as .warn even
        // when auto-update was actually enabled.
        let raw = runProcess("/usr/bin/defaults",
                             ["read", "com.apple.commerce", "AutoUpdate"])
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitlyOff = trimmed == "0"
        return DefenseItem(
            id: "software.appStoreAutoUpdate",
            category: .softwareUpdates,
            title: explicitlyOff
                ? "App Store doesn't auto-update apps"
                : "App Store auto-updates apps",
            detail: "Apps you install from the App Store get patched automatically.",
            status: explicitlyOff ? .warn : .pass,
            remediationURLString: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
        )
    }

    // ── System Integrity ────────────────────────────────────────────

    private static func itemSIP() -> DefenseItem {
        let on = probeSIP()
        return DefenseItem(
            id: "integrity.sip",
            category: .systemIntegrity,
            title: on ? "System Integrity Protection is on" : "SIP is OFF",
            detail: "Prevents even root from modifying protected system files. Should always be on.",
            status: on ? .pass : .fail
        )
    }

    private static func itemGatekeeper() -> DefenseItem {
        let on = probeGatekeeper()
        return DefenseItem(
            id: "integrity.gatekeeper",
            category: .systemIntegrity,
            title: on ? "Gatekeeper is on" : "Gatekeeper is OFF",
            detail: "Blocks unsigned / untrusted apps. Should always be on.",
            status: on ? .pass : .fail
        )
    }

    private static func itemFindMy() -> DefenseItem {
        let token = findMyTokenValue() != nil
        return DefenseItem(
            id: "integrity.findMy",
            category: .systemIntegrity,
            title: token ? "Find My is on" : "Find My is OFF",
            detail: "Lets you locate or remote-wipe a stolen Mac. Pair with Vakter's alarm for full coverage.",
            status: token ? .pass : .fail,
            remediationURLString: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane"
        )
    }

    // MARK: - Shell helper

    /// Thin shim over the shared `Shell.run` helper. Kept as a
    /// private name to minimise call-site churn during the v0.9.3
    /// simplification refactor.
    private static func runProcess(_ binary: String, _ args: [String]) -> String {
        Shell.run(binary, args)
    }
}
