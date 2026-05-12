import Foundation
import ServiceManagement
import AnchorShared

/// Lifecycle manager for the embedded `AnchorPrivilegedDaemon` LaunchDaemon.
///
/// The daemon runs as root and exposes a single XPC method
/// (`AnchorPrivilegedProtocol.setSleepDisabled`) so the user-level helper
/// can toggle `pmset disablesleep` without prompting for admin each time.
///
/// Registration:
///   - On first launch, `register()` adds the daemon to the system's
///     Login Items. macOS shows the user a notification: "Anchor added a
///     Login Item." The user can view/control it in System Settings →
///     General → Login Items & Extensions → Allow in Background.
///   - The user must approve it ONCE. Subsequent launches use the
///     already-approved daemon silently.
///   - Like `HelperManager`, we proactively unregister+register on every
///     launch so the recorded code requirement (LWCR) refreshes when
///     the app binary is re-signed (e.g. via Sparkle update).
@MainActor
final class PrivilegedDaemonManager {

    private static let daemonPlistName = "app.anchor.mac.privileged-helper.plist"

    private let service: SMAppService

    init() {
        self.service = SMAppService.daemon(plistName: PrivilegedDaemonManager.daemonPlistName)
    }

    var status: SMAppService.Status { service.status }

    var statusLabel: String {
        switch service.status {
        case .notRegistered:    return "not registered"
        case .enabled:          return "enabled (root daemon ready)"
        case .requiresApproval: return "needs approval in System Settings"
        case .notFound:         return "plist missing from bundle"
        @unknown default:       return "unknown"
        }
    }

    /// Register the daemon. Pops a one-time system Login Items prompt the
    /// first time. After approval, the daemon is launchable on-demand via
    /// its Mach service.
    @discardableResult
    func ensureRegistered() -> SMAppService.Status {
        // Refresh: drop any stale registration so the recorded code
        // requirement matches the freshly-signed binary.
        try? service.unregister()

        do {
            try service.register()
            NSLog("[PrivilegedDaemonManager] register() succeeded — status: %@", statusLabel)
        } catch {
            // SMAppService returns SMAppServiceErrorDomain code=1
            // ("Operation not permitted") when the status transitioned to
            // .requiresApproval — that's actually a normal first-launch
            // path, not a real error. Only log a loud failure when the
            // status didn't reach a usable state.
            let nsError = error as NSError
            if service.status == .requiresApproval {
                NSLog("[PrivilegedDaemonManager] needs one-time approval in System Settings → Login Items")
            } else {
                NSLog("[PrivilegedDaemonManager] register() FAILED: %@ (domain=%@ code=%ld) — final status: %@",
                      error.localizedDescription, nsError.domain, nsError.code, statusLabel)
            }
        }

        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        return service.status
    }

    func unregister() {
        do { try service.unregister() } catch {
            NSLog("[PrivilegedDaemonManager] unregister failed: %@", error.localizedDescription)
        }
    }
}
