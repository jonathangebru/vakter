import Foundation
import VakterShared

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
final class ScreenLockObserver: VakterSignalObserver, @unchecked Sendable {

    private var unlockToken: NSObjectProtocol?
    private var lockToken: NSObjectProtocol?
    private var emit: ((VakterSignal) -> Void)?

    /// Bug fix (v1.4 audit): macOS fires
    /// `com.apple.screenIsUnlocked` spuriously when other subsystems
    /// touch the lock-screen state (e.g. AVFoundation engaging audio
    /// to override system mute during an alarm). Pre-fix, those
    /// phantom notifications immediately disarmed any active alarm.
    ///
    /// We track the lock state ourselves now: an unlock notification
    /// is only authoritative if we previously observed the screen go
    /// *locked*. Otherwise we ignore it as noise.
    ///
    /// Marked `@unchecked Sendable`-safe because we only mutate
    /// `screenIsLocked` from the main thread (the notification queue
    /// is `.main`).
    private var screenIsLocked: Bool = false

    func start(_ emit: @escaping (VakterSignal) -> Void) {
        self.emit = emit

        lockToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screenIsLocked = true
            NSLog("[ScreenLockObserver] screen LOCKED")
        }

        unlockToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            guard self.screenIsLocked else {
                // Spurious notification while the screen was never
                // locked — ignore.
                NSLog("[ScreenLockObserver] spurious unlock notification ignored (screen was not locked)")
                return
            }
            self.screenIsLocked = false
            NSLog("[ScreenLockObserver] screen unlocked → emitting .screenUnlocked")
            self.emit?(.screenUnlocked)
        }
        NSLog("[ScreenLockObserver] watching com.apple.screenIsLocked + com.apple.screenIsUnlocked")
    }

    deinit {
        if let lockToken = lockToken {
            DistributedNotificationCenter.default().removeObserver(lockToken)
        }
        if let unlockToken = unlockToken {
            DistributedNotificationCenter.default().removeObserver(unlockToken)
        }
    }
}
