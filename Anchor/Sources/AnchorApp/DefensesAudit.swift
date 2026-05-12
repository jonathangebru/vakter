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
        case .healthy:   return AnchorDesign.healthy
        case .warning:   return Color(red: 0.85, green: 0.60, blue: 0.20)  // amber
        case .attention: return AnchorDesign.alarm
        case .unknown:   return Color.secondary
        }
    }
}

/// Reads system posture without modifying anything. Lives entirely in
/// the menubar app (no helper round-trip needed — these are user-domain
/// queries).
enum DefensesAudit {

    static func run() -> [DefenseCheck] {
        return [
            checkFileVault(),
            checkFindMyMac(),
            checkAutoLogin(),
            checkScreenLockDelay(),
            checkLoginWindowMessage(),
            checkAnchorAppInLoginItems()
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

    private static func checkFindMyMac() -> DefenseCheck {
        // Find My Mac stores a flag in the MobileMe / iCloud config.
        // We check via `defaults` against the local iCloud account store.
        let out = shellOutput("/usr/bin/defaults read /Library/Preferences/com.apple.FindMyMac MMeFMMEnabled 2>/dev/null")
        let on = out.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        return DefenseCheck(
            id: "findmymac",
            title: "Find My Mac",
            detail: on
                ? "On. You can locate, lock, or erase your Mac remotely."
                : "Off (or could not read). Enable it under iCloud for remote recovery options.",
            status: on ? .healthy : .warning,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane?iCloud")
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

    private static func checkScreenLockDelay() -> DefenseCheck {
        // askForPasswordDelay (seconds). 0 = immediate. Larger = window of
        // free access after the display sleeps.
        let out = shellOutput("/usr/bin/defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null")
        let delay = Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let healthy = delay == 0
        return DefenseCheck(
            id: "lockdelay",
            title: "Require password immediately",
            detail: healthy
                ? "Locked instantly after the screen turns off — good."
                : "There's a \(delay)-second window after screen-off before a password is needed. Tighten to immediate.",
            status: healthy ? .healthy : .warning,
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

    private static func checkAnchorAppInLoginItems() -> DefenseCheck {
        // We're approved if our agent + daemon are enabled. We can't ask
        // launchctl in user-app context for daemon status easily, so use
        // a proxy: does the helper Mach service answer? Approximated by
        // checking the LaunchAgent loaded state via `launchctl list`.
        let out = shellOutput("/bin/launchctl list 2>/dev/null")
        let agent = out.contains("app.anchor.mac.helper")
        return DefenseCheck(
            id: "anchorlaunch",
            title: "Anchor itself launches at login",
            detail: agent
                ? "Anchor is approved and running."
                : "The Anchor helper isn't registered. Open Login Items and toggle it on so Anchor protects you on every boot.",
            status: agent ? .healthy : .warning,
            systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        )
    }

    // MARK: - Utility

    private static func shellOutput(_ command: String) -> String {
        let p = Process()
        p.launchPath = "/bin/sh"
        p.arguments = ["-c", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()  // discard stderr
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return ""
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                      encoding: .utf8) ?? ""
    }
}
