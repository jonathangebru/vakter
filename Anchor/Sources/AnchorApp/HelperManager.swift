import Foundation
import ServiceManagement
import AnchorShared

/// Lifecycle manager for the embedded AnchorHelper LaunchAgent.
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
    private static let helperPlistName = "app.anchor.mac.helper.plist"

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
    /// **Why we unregister-then-register every call:**
    /// `SMAppService.register()` is idempotent in the happy case, but when
    /// the app binary has been re-signed since the last registration (e.g.
    /// after a Sparkle update, or during local dev), the recorded
    /// "Lightweight Code Requirement" (LWCR) no longer matches the new
    /// binary's signature. launchd then refuses to spawn the helper and
    /// returns `EX_CONFIG (78)`. The `properties` line shows
    /// "needs LWCR update" in `launchctl print`.
    /// Unregistering before registering clears the stale LWCR and forces
    /// launchd to record the new one. Microseconds of overhead per launch.
    @discardableResult
    func ensureRegistered() -> SMAppService.Status {
        // Refresh: drop the stale registration (if any) to clear an LWCR
        // recorded against a previous build's signature.
        try? service.unregister()

        do {
            try service.register()
            NSLog("[HelperManager] register() succeeded — status now: %@", statusLabel)
        } catch {
            // SMAppService returns SMAppServiceErrorDomain code=1 when the
            // status transitioned to .requiresApproval — that's actually a
            // normal first-launch path, not a hard error.
            let nsError = error as NSError
            if service.status == .requiresApproval {
                NSLog("[HelperManager] needs one-time approval in System Settings → Login Items")
            } else {
                NSLog("[HelperManager] register() FAILED: %@ (domain=%@ code=%ld) — final status: %@",
                      error.localizedDescription, nsError.domain, nsError.code, statusLabel)
            }
        }

        if service.status == .requiresApproval {
            NSLog("[HelperManager] requiresApproval — opening Login Items pane")
            openLoginItemsSettings()
        }

        return service.status
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
