import Foundation

/// XPC protocol exposed by `VakterPrivilegedDaemon` (the LaunchDaemon
/// that runs as root) to the user-level `VakterHelper`.
///
/// One method only — toggling `pmset disablesleep`. The user authorises
/// the daemon ONCE in System Settings → Login Items after the app calls
/// `SMAppService.daemon(...).register()`. Afterwards arming and disarming
/// happens silently — no per-arm Touch ID prompt.
///
/// Security note: the daemon validates that the connecting peer's code
/// signature matches our team ID + bundle ID before honouring any call.
/// Without that, any process could connect and disable sleep.
@objc public protocol VakterPrivilegedProtocol {

    /// Toggle the global `disablesleep` setting via `pmset -a disablesleep <0|1>`.
    /// Reply is `true` on success.
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool) -> Void)
}
