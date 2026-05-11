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

    init(
        audio: AudioControlling = AudioController(),
        photos: PhotoCapturing = PhotoCapture(),
        log: EventLogStore = .shared
    ) {
        self.audio = audio
        self.photos = photos
        self.log = log
    }

    // MARK: Signal entry point

    func handle(signal: AnchorSignal) {
        lock.lock(); defer { lock.unlock() }

        switch (state, signal) {

        // Hotkey arms only when unarmed.
        case (.unarmed, .hotkeyArm):
            transition(to: .armed, trigger: .userAction)

        // While armed, trigger signals start the grace window.
        case (.armed, let s) where s.triggersGrace:
            transition(to: .grace, trigger: s.asTrigger)

        // Anything else: ignore (e.g. powerConnected while armed isn't a trigger).
        default:
            break
        }
    }

    // MARK: Explicit control (used by XPC / Shortcuts / menubar)

    func armFromUser() {
        lock.lock(); defer { lock.unlock() }
        guard state == .unarmed else { return }
        transition(to: .armed, trigger: .userAction)
    }

    /// Called after the user successfully authenticates. The auth check
    /// itself happens in the XPC layer (Touch ID / password), not here.
    func disarmFromUser() {
        lock.lock(); defer { lock.unlock() }
        guard state != .unarmed else { return }
        transition(to: .unarmed, trigger: .userAction)
    }

    func setMode(_ next: AnchorMode) {
        lock.lock(); defer { lock.unlock() }
        mode = next
        NSLog("[StateMachine] mode → %@", next.rawValue)
    }

    func enterLoaner(window: LoanerTrustWindow) {
        lock.lock(); defer { lock.unlock() }
        mode = .loaner
        let expiry = Date().addingTimeInterval(window.rawValue)
        loanerExpiresAt = expiry
        scheduleLoanerExpiry(at: expiry)
    }

    // MARK: Internal transition

    private func transition(to next: AnchorState, trigger: AnchorTrigger?) {
        let prev = state
        state = next
        let params = ModeParameters.parameters(for: mode)

        NSLog("[StateMachine] %@ → %@ (trigger=%@)",
              prev.rawValue, next.rawValue, trigger?.rawValue ?? "nil")

        switch next {
        case .unarmed:
            cancelGraceTimer()
            audio.stopAlarm()
            log.append(.init(
                fromState: prev, toState: next, trigger: trigger,
                photoFilenames: [], modeAtEvent: mode
            ))

        case .armed:
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
