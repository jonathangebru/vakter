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
            // Already approved + registered. Leave the user's approval alone.
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
