import Foundation
import AnchorShared

/// The authoritative Anchor state machine.
///
/// Single source of truth. Driven by:
///   - external `AnchorSignal` values from observers (lid, power, BT, hotkey)
///   - explicit control calls from the menubar app over XPC (arm, disarm, setMode)
///   - timer expirations (grace timeout → alarm; loaner expiry → re-arm)
///
/// Side effects (audio start/stop, photo capture, event log writes,
/// snapshot publish) are dispatched from `transition(to:trigger:)`.
final class StateMachine {

    // MARK: State

    private(set) var state: AnchorState = .unarmed
    private(set) var mode: AnchorMode = .normal
    private(set) var loanerExpiresAt: Date?

    private var graceTimer: DispatchSourceTimer?
    private var loanerTimer: DispatchSourceTimer?

    private let lock = NSLock()

    // Wiring (constructor-injected once we have real implementations).
    private let audio: AudioControlling
    private let photos: PhotoCapturing
    private let log: EventLogStore
    private let sleepGuard: SleepGuard

    /// Subscribers (typically the menubar app) that want a callback every
    /// time the snapshot changes. The XPC service owns these; we keep a
    /// weak-ish reference via a closure so the service can manage lifetimes.
    private var snapshotObservers: [@Sendable (AnchorSnapshot) -> Void] = []

    init(
        audio: AudioControlling = AudioController(),
        photos: PhotoCapturing = PhotoCapture(),
        log: EventLogStore = .shared,
        sleepGuard: SleepGuard = SleepGuard()
    ) {
        self.audio = audio
        self.photos = photos
        self.log = log
        self.sleepGuard = sleepGuard
    }

    // MARK: Snapshot publishing

    /// Current snapshot — what we publish over XPC.
    func snapshot() -> AnchorSnapshot {
        lock.lock(); defer { lock.unlock() }
        return AnchorSnapshot(
            state: state,
            mode: mode,
            lastEvent: nil,                   // TODO: surface the latest event
            loanerExpiresAt: loanerExpiresAt
        )
    }

    /// Register a closure called every time the snapshot changes. Returns
    /// nothing — the caller is expected to keep its own reference to the
    /// closure's owning object. Lifetimes are tied to XPC connections.
    func addObserver(_ block: @escaping @Sendable (AnchorSnapshot) -> Void) {
        lock.lock(); defer { lock.unlock() }
        snapshotObservers.append(block)
        // Fire immediately so new subscribers get current state.
        let snap = AnchorSnapshot(
            state: state, mode: mode,
            lastEvent: nil, loanerExpiresAt: loanerExpiresAt
        )
        DispatchQueue.global().async { block(snap) }
    }

    private func publishSnapshot() {
        let snap = AnchorSnapshot(
            state: state, mode: mode,
            lastEvent: nil, loanerExpiresAt: loanerExpiresAt
        )
        for block in snapshotObservers {
            DispatchQueue.global().async { block(snap) }
        }
    }

    // MARK: Signal entry point

    func handle(signal: AnchorSignal) {
        lock.lock(); defer { lock.unlock() }

        switch (state, signal) {

        // Hotkey arms only when unarmed. Same effect as a menubar / XPC arm.
        case (.unarmed, .hotkeyArm):
            performUserArmLocked()

        // Any of the trigger signals starts the grace window while armed.
        case (.armed, let s) where s.triggersGrace:
            transition(to: .grace, trigger: s.asTrigger)

        // Natural screen unlock is our authenticated disarm. macOS already
        // verified the user; we trust it.
        case (.armed, .screenUnlocked),
             (.grace, .screenUnlocked),
             (.alarm, .screenUnlocked):
            transition(to: .unarmed, trigger: .userAction)

        // Anything else: ignore.
        default:
            break
        }
    }

    // MARK: Explicit control (used by XPC / Shortcuts / menubar)

    func armFromUser() {
        lock.lock(); defer { lock.unlock() }
        performUserArmLocked()
    }

    /// Caller must already hold `lock`. Performs the unarmed→armed
    /// transition AND fires the screen-lock side effect. Used by both the
    /// hotkey path (via `handle`) and the XPC path (via `armFromUser`).
    private func performUserArmLocked() {
        guard state == .unarmed else { return }
        transition(to: .armed, trigger: .userAction)
        // ScreenLocker is stateless and thread-safe; safe to call while
        // holding `lock`. The actual lock happens asynchronously.
        ScreenLocker.lockScreen()
    }

    /// Called after the user successfully authenticates. The auth check
    /// itself happens in the XPC layer (Touch ID / password), not here.
    func disarmFromUser() {
        lock.lock(); defer { lock.unlock() }
        guard state != .unarmed else { return }
        transition(to: .unarmed, trigger: .userAction)
    }

    func setMode(_ next: AnchorMode) {
        lock.lock()
        mode = next
        NSLog("[StateMachine] mode → %@", next.rawValue)
        lock.unlock()
        publishSnapshot()
    }

    func enterLoaner(window: LoanerTrustWindow) {
        lock.lock()
        mode = .loaner
        let expiry = Date().addingTimeInterval(window.rawValue)
        loanerExpiresAt = expiry
        scheduleLoanerExpiry(at: expiry)
        lock.unlock()
        publishSnapshot()
    }

    // MARK: Internal transition

    private func transition(to next: AnchorState, trigger: AnchorTrigger?) {
        let prev = state
        state = next
        let params = ModeParameters.parameters(for: mode)

        NSLog("[StateMachine] %@ → %@ (trigger=%@)",
              prev.rawValue, next.rawValue, trigger?.rawValue ?? "nil")
        defer { publishSnapshot() }

        switch next {
        case .unarmed:
            cancelGraceTimer()
            audio.stopAlarm()
            photos.stop()
            // Critical: release the sleep guard so the Mac can sleep normally
            // again when not armed. Otherwise we'd drain the battery and
            // override the user's lid-close behaviour forever.
            sleepGuard.release()
            // Soft confirmation cue only if we're disarming from a non-resting
            // state (don't chirp when we boot fresh into .unarmed).
            if prev != .unarmed {
                audio.playDisarmChirp()
            }
            log.append(.init(
                fromState: prev, toState: next, trigger: trigger,
                photoFilenames: [], modeAtEvent: mode
            ))

        case .armed:
            // Critical: hold the Mac awake. Without this, lid-close →
            // system sleep → helper suspended → grace timer never fires →
            // alarm never plays. This is the difference between "feature"
            // and "actually catches thieves".
            sleepGuard.engage()
            audio.playArmChirp()
            log.append(.init(
                fromState: prev, toState: next, trigger: trigger,
                photoFilenames: [], modeAtEvent: mode
            ))

        case .grace:
            audio.playGraceChirp()
            scheduleGraceExpiry(seconds: params.graceSeconds)
            log.append(.init(
                fromState: prev, toState: next, trigger: trigger,
                photoFilenames: [], modeAtEvent: mode
            ))

        case .alarm:
            cancelGraceTimer()
            audio.startAlarm(audible: params.audible)
            photos.startBurst(cadence: params.photoCadence) { capturedFiles in
                // TODO(week-4): append captured photos to the alarm event.
                _ = capturedFiles
            }
            log.append(.init(
                fromState: prev, toState: next, trigger: trigger,
                photoFilenames: [], modeAtEvent: mode
            ))
        }
    }

    // MARK: Timers

    private func scheduleGraceExpiry(seconds: TimeInterval) {
        cancelGraceTimer()
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now() + seconds)
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            if self.state == .grace {
                self.transition(to: .alarm, trigger: nil)
            }
        }
        t.resume()
        graceTimer = t
    }

    private func cancelGraceTimer() {
        graceTimer?.cancel()
        graceTimer = nil
    }

    private func scheduleLoanerExpiry(at date: Date) {
        loanerTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now() + date.timeIntervalSinceNow)
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            self.mode = .normal
            self.loanerExpiresAt = nil
            NSLog("[StateMachine] Loaner expired → mode=normal")
        }
        t.resume()
        loanerTimer = t
    }
}
