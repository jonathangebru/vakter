import Foundation
import AnchorShared

/// Listens to macOS distributed notifications for screen-lock state.
///
/// We emit `.screenUnlocked` whenever the user successfully unlocks the
/// system — that's our cue to disarm (or cancel an alarm), because macOS
/// has already authenticated the user. Skipping a second prompt is the
/// whole UX point of the design.
///
/// Notifications are posted by the loginwindow process:
///   - `com.apple.screenIsLocked`
///   - `com.apple.screenIsUnlocked`
/// They're delivered through `DistributedNotificationCenter.default()`
/// and arrive on the main thread.
final class ScreenLockObserver: AnchorSignalObserver, @unchecked Sendable {

    private var observerToken: NSObjectProtocol?
    private var emit: ((AnchorSignal) -> Void)?

    func start(_ emit: @escaping (AnchorSignal) -> Void) {
        self.emit = emit

        // Only the unlock notification is interesting for v1. (Future:
        // we may also use `.screenIsLocked` to confirm our own arm-induced
        // lock actually took effect.)
        observerToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            NSLog("[ScreenLockObserver] screen unlocked → emitting .screenUnlocked")
            self?.emit?(.screenUnlocked)
        }
        NSLog("[ScreenLockObserver] watching com.apple.screenIsUnlocked")
    }

    deinit {
        if let observerToken = observerToken {
            DistributedNotificationCenter.default().removeObserver(observerToken)
        }
    }
}
