import Foundation
import ServiceManagement
import VakterShared

/// Lifecycle manager for the embedded VakterHelper LaunchAgent.
///
/// macOS 13+ requires LaunchAgents bundled inside applications to be
/// registered through `SMAppService.agent(plistName:)`. The first time
/// `register()` is called, macOS marks the agent as "requires approval"
/// and the user must enable it in System Settings → Login Items & Extensions
/// → Allow in Background. After that, the agent boots on every login and
/// survives app restarts.
///
/// We register lazily on app launch. Idempotent — safe to call repeatedly.
@MainActor
final class HelperManager {

    /// Filename of the embedded LaunchAgent plist (relative to
    /// `Contents/Library/LaunchAgents/` inside the app bundle).
    private static let helperPlistName = "app.vakter.mac.helper.plist"

    private let service: SMAppService

    init() {
        self.service = SMAppService.agent(plistName: HelperManager.helperPlistName)
    }

    /// Current registration status.
    var status: SMAppService.Status { service.status }

    /// Human-readable representation of the helper's status, for menubar
    /// display and logs.
    var statusLabel: String {
        switch service.status {
        case .notRegistered:    return "not registered"
        case .enabled:          return "enabled (running)"
        case .requiresApproval: return "needs approval in System Settings"
        case .notFound:         return "plist missing from bundle"
        @unknown default:       return "unknown"
        }
    }

    /// Register the helper LaunchAgent. Returns the resulting status.
    ///
    /// **State-aware:** we only re-register when the status isn't already
    /// `.enabled`. Unconditionally calling `unregister()` blows away the
    /// user's Login Items approval every launch — which then forces them
    /// back to System Settings every time we relaunch or rebuild.
    /// The recorded code requirement is identity-based (Developer ID
    /// Application + Team ID), so a re-signed-but-same-identity rebuild
    /// continues to satisfy the existing registration without an LWCR
    /// refresh. If LWCR mismatch ever does happen (e.g. major macOS
    /// upgrade), launchd reports `EX_CONFIG` and we recover via the
    /// `notRegistered` branch below.
    @discardableResult
    func ensureRegistered() -> SMAppService.Status {
        switch service.status {
        case .enabled:
            // Apple thinks it's enabled — but launchd may secretly be
            // refusing the spawn with EX_CONFIG (78) because the binary
            // was rebuilt and the launch-constraint predicate no longer
            // matches the cached code requirement. Probe launchctl
            // directly; if the helper isn't actually running (or is
            // showing exit 78), force a refresh.
            if !isHelperHealthy() {
                NSLog("[HelperManager] status=enabled but helper not running — auto force-refresh")
                forceRefreshRegistration()
                return service.status
            }
            return .enabled

        case .requiresApproval:
            NSLog("[HelperManager] needs one-time approval in System Settings → Login Items")
            openLoginItemsSettings()
            return .requiresApproval

        case .notRegistered, .notFound:
            do {
                try service.register()
                NSLog("[HelperManager] register() succeeded — status now: %@", statusLabel)
            } catch {
                let nsError = error as NSError
                if service.status == .requiresApproval {
                    NSLog("[HelperManager] needs one-time approval in System Settings → Login Items")
                } else {
                    NSLog("[HelperManager] register() FAILED: %@ (domain=%@ code=%ld) — final status: %@",
                          error.localizedDescription, nsError.domain, nsError.code, statusLabel)
                }
            }
            if service.status == .requiresApproval {
                openLoginItemsSettings()
            }
            return service.status

        @unknown default:
            return service.status
        }
    }

    /// Force a full re-registration cycle. Used when status reports
    /// `.enabled` but launchd actually can't launch the binary because
    /// the LWCR signature changed after a rebuild (manifests as
    /// `EX_CONFIG`, exit code 78, in `launchctl list`). Unregister blows
    /// away the prior approval; we re-register and macOS surfaces the
    /// re-approval prompt automatically.
    ///
    /// Only call this when you've detected the helper is unreachable
    /// over XPC despite `service.status == .enabled` — otherwise you'll
    /// destroy a perfectly good user approval for nothing.
    func forceRefreshRegistration() {
        NSLog("[HelperManager] forcing refresh of LaunchAgent registration")
        do {
            try service.unregister()
        } catch {
            NSLog("[HelperManager] unregister() failed during refresh: %@",
                  error.localizedDescription)
        }
        do {
            try service.register()
            NSLog("[HelperManager] refresh: re-registered — status now: %@", statusLabel)
        } catch {
            NSLog("[HelperManager] refresh: register() FAILED: %@",
                  error.localizedDescription)
        }
        // Always open Login Items so the user can re-approve in one tap.
        openLoginItemsSettings()
    }

    /// Shell out to `launchctl print` and check whether the helper is
    /// actually running (or at least not stuck on a non-zero exit code).
    /// Detects the "Apple says enabled, launchd disagrees" state that
    /// `SMAppService.Status` cannot see.
    ///
    /// Returns true when:
    ///   - `launchctl print gui/$UID/app.vakter.mac.helper` succeeds, AND
    ///   - the printout shows a running PID OR a recent exit code of 0.
    /// False otherwise — which is the cue for `forceRefreshRegistration()`.
    private func isHelperHealthy() -> Bool {
        let target = "gui/\(getuid())/app.vakter.mac.helper"
        let (text, status) = Shell.runDetailed("/bin/launchctl", ["print", target])
        if status != 0 { return false }
        // Reject anything containing "last exit code = 78" (LWCR mismatch)
        // or "EX_CONFIG" or "no such service."
        if text.contains("last exit code = 78") { return false }
        if text.contains("EX_CONFIG")           { return false }
        if text.range(of: #"pid = [0-9]+"#, options: .regularExpression) != nil {
            return true
        }
        if text.contains("last exit code = 0")  { return true }
        // Default: not healthy.
        return false
    }

    /// Unregister the helper LaunchAgent. Used during uninstall / debugging.
    func unregister() {
        do {
            try service.unregister()
            NSLog("[HelperManager] unregistered — status now: %@", statusLabel)
        } catch {
            NSLog("[HelperManager] unregister() FAILED: %@", error.localizedDescription)
        }
    }

    /// Convenience: open the macOS Login Items pane so the user can flip
    /// the approval toggle. Used the first time the helper is registered.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
