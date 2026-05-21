import Foundation

/// Locks the user's screen.
///
/// macOS doesn't expose a clean public API for this. The historically-
/// reliable path is to load the private framework `login` and invoke
/// `SACLockScreenImmediate()`. We do that via `dlopen` so we don't have
/// to link against the private framework at build time and trip up
/// the App Store reviewer (we're not shipping there anyway, but it's
/// good hygiene to keep our public symbol surface clean).
///
/// Fallback: invoke `pmset displaysleepnow` via Process. This puts the
/// display to sleep, which under default macOS settings locks the screen
/// immediately. Less reliable than `SACLockScreenImmediate` but works
/// without dlopen if the private symbol isn't available.
enum ScreenLocker {

    typealias LockFn = @convention(c) () -> Int32

    /// Lock the screen after an optional delay. The delay gives the
    /// menubar app a window to render its "On watch" arming overlay
    /// (signature 0.6 s fade) before the lock takes the foreground.
    static func lockScreen(after delaySeconds: TimeInterval = 0) {
        if delaySeconds <= 0 {
            performLock()
            return
        }
        NSLog("[ScreenLocker] screen lock scheduled in %.2f s", delaySeconds)
        DispatchQueue.global().asyncAfter(deadline: .now() + delaySeconds) {
            performLock()
        }
    }

    private static func performLock() {
        NSLog("[ScreenLocker] requesting screen lock")
        if !lockViaPrivateAPI() {
            NSLog("[ScreenLocker] private API unavailable; falling back to pmset displaysleepnow")
            lockViaPMSet()
        }
    }

    /// Try the private `login.framework` symbol. Returns true on success.
    private static func lockViaPrivateAPI() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY) else {
            return false
        }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "SACLockScreenImmediate") else {
            return false
        }
        let lockFn = unsafeBitCast(sym, to: LockFn.self)
        _ = lockFn()
        return true
    }

    /// Fallback: invoke `pmset displaysleepnow`. Locks if user has
    /// "Require password immediately after sleep" enabled (default on Macs
    /// with FileVault). We surface this requirement in the Defenses panel.
    private static func lockViaPMSet() {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["displaysleepnow"]
        do {
            try task.run()
        } catch {
            NSLog("[ScreenLocker] pmset launch failed: %@", error.localizedDescription)
        }
    }
}
