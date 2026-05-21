import Foundation
import VakterShared

/// The authoritative Anchor state machine.
///
/// Single source of truth. Driven by:
///   - external `VakterSignal` values from observers (lid, power, BT, hotkey)
///   - explicit control calls from the menubar app over XPC (arm, disarm, setMode)
///   - timer expirations (grace timeout → alarm; loaner expiry → re-arm)
///
/// Side effects (audio start/stop, photo capture, event log writes,
/// snapshot publish) are dispatched from `transition(to:trigger:)`.
/// `@unchecked Sendable` because all mutable state is guarded by `lock`
/// (an `NSLock`). The Swift compiler can't see that invariant, so we
/// vouch for it manually. Without this, every `[weak self]` capture into
/// the photo + audio capture callbacks fails Swift 6 strict-concurrency
/// (they're typed `@escaping @Sendable`).
final class StateMachine: @unchecked Sendable {

    // MARK: State

    private(set) var state: VakterState = .unarmed
    private(set) var mode: VakterMode = .normal
    private(set) var loanerExpiresAt: Date?

    private var graceTimer: DispatchSourceTimer?
    private var loanerTimer: DispatchSourceTimer?

    private let lock = NSLock()

    /// Set to true between Phase 1 (reservation) and Phase 3 (commit
    /// or rollback) of `armFromUser`. Prevents two concurrent arms
    /// from both blocking on the privileged-auth dialog. See the
    /// extensive comment block on `armFromUser(skipScreenLock:)`.
    private var pendingArm = false

    // Wiring (constructor-injected once we have real implementations).
    private let audio: AudioControlling
    private let photos: PhotoCapturing
    private let audioCapture: AudioCapturing
    private let log: EventLogStore
    private let sleepGuard: SleepGuarding
    private let sleepDisabler: SleepDisabling
    private let evidenceBundleBuilder: EvidenceBundleBuilder

    /// Most-recent sealed event in the chain. Used to (a) populate
    /// `previousEventHash` on the next event so the Merkle chain links
    /// properly, and (b) surface as `snapshot.lastEvent` for the menubar.
    private var lastEvent: VakterEvent?

    /// Observers that need arm/disarm lifecycle hooks (start probing
    /// only while armed). Set via `attach(...)` from `main.swift`.
    /// Empty by default so tests don't need to inject these.
    var armGatedObservers: [ArmGatedObserver] = []

    /// Subscribers (typically the menubar app) that want a callback every
    /// time the snapshot changes. The XPC service owns these; we keep a
    /// weak-ish reference via a closure so the service can manage lifetimes.
    private var snapshotObservers: [@Sendable (VakterSnapshot) -> Void] = []

    init(
        audio: AudioControlling = AudioController(),
        photos: PhotoCapturing = PhotoCapture(),
        audioCapture: AudioCapturing = AudioCapture(),
        log: EventLogStore = .shared,
        sleepGuard: SleepGuarding = SleepGuard(),
        sleepDisabler: SleepDisabling = SleepDisabler(),
        evidenceBundleBuilder: EvidenceBundleBuilder = EvidenceBundleBuilder()
    ) {
        self.audio = audio
        self.photos = photos
        self.audioCapture = audioCapture
        self.log = log
        self.sleepGuard = sleepGuard
        self.sleepDisabler = sleepDisabler
        self.evidenceBundleBuilder = evidenceBundleBuilder

        // Seed the chain anchor from the on-disk log so the next event we
        // append links to whatever was there before this helper booted.
        // Walks newest→oldest looking for the first event with a hash;
        // pre-v1.3 entries without hashes are skipped — the chain restarts
        // cleanly at the first v1.3 event we write.
        if let priorHashed = log.recent(limit: 100).first(where: { $0.eventHash != nil }) {
            self.lastEvent = priorHashed
        }
    }

    // MARK: Snapshot publishing

    /// Current snapshot — what we publish over XPC.
    func snapshot() -> VakterSnapshot {
        lock.lock(); defer { lock.unlock() }
        return VakterSnapshot(
            state: state,
            mode: mode,
            lastEvent: lastEvent,
            loanerExpiresAt: loanerExpiresAt
        )
    }

    /// Register a closure called every time the snapshot changes. Returns
    /// nothing — the caller is expected to keep its own reference to the
    /// closure's owning object. Lifetimes are tied to XPC connections.
    func addObserver(_ block: @escaping @Sendable (VakterSnapshot) -> Void) {
        lock.lock(); defer { lock.unlock() }
        snapshotObservers.append(block)
        // Fire immediately so new subscribers get current state.
        let snap = VakterSnapshot(
            state: state, mode: mode,
            lastEvent: lastEvent, loanerExpiresAt: loanerExpiresAt
        )
        DispatchQueue.global().async { block(snap) }
    }

    private func publishSnapshot() {
        let snap = VakterSnapshot(
            state: state, mode: mode,
            lastEvent: lastEvent, loanerExpiresAt: loanerExpiresAt
        )
        for block in snapshotObservers {
            DispatchQueue.global().async { block(snap) }
        }
    }

    // MARK: Signal entry point

    func handle(signal: VakterSignal) {
        // Hotkey-arm requires a blocking privileged-auth dialog and must
        // therefore NOT run under the state-machine lock — see the
        // comment on `armFromUser(skipScreenLock:)`. Route it through
        // the lockless three-phase arm flow and bail before taking the
        // lock for the rest of the switch.
        if case .hotkeyArm = signal {
            // `armFromUser` re-checks `state == .unarmed` under the lock,
            // so the TOCTOU between our outer check and the inner check
            // is benign — armFromUser will no-op if state changed.
            armFromUser()
            return
        }

        lock.lock(); defer { lock.unlock() }

        switch (state, signal) {

        // High-confidence theft signals: skip grace, go straight to
        // alarm. Find My token clear + Apple ID change can both only
        // happen if someone has authenticated into the Mac while we
        // were armed — there's no benign explanation worth a grace
        // window for.
        case (.armed, .findMyTokenCleared), (.grace, .findMyTokenCleared),
             (.armed, .appleIDChanged),    (.grace, .appleIDChanged):
            transition(to: .alarm, trigger: signal.asTrigger)

        // Any of the trigger signals starts the grace window while armed.
        case (.armed, let s) where s.triggersGrace:
            transition(to: .grace, trigger: s.asTrigger)

        // Natural screen unlock is our authenticated disarm. macOS already
        // verified the user; we trust it.
        case (.armed, .screenUnlocked),
             (.grace, .screenUnlocked),
             (.alarm, .screenUnlocked):
            transition(to: .unarmed, trigger: .userAction)

        // Wake-from-sleep while protected = fire alarm immediately.
        // This is the belt-and-braces fallback against Apple Silicon
        // clamshell-close-on-battery sleep ignoring our SleepGuard.
        // If the system slept while .armed or .grace, the grace timer
        // is stale; the moment we resume, the alarm starts.
        case (.armed, .systemWake),
             (.grace, .systemWake):
            NSLog("[StateMachine] systemWake while protected — firing alarm")
            transition(to: .alarm, trigger: trigger(for: signal))

        // Wake-from-sleep while already alarming: re-trigger so the audio
        // engine restarts after sleep-induced audio teardown.
        case (.alarm, .systemWake):
            NSLog("[StateMachine] systemWake during alarm — restarting alarm audio")
            audio.stopAlarm()
            audio.startAlarm(audible: ModeParameters.parameters(for: mode).audible)

        // Anything else: ignore.
        default:
            break
        }
    }

    /// Map a signal to a trigger that the event log can record. Only used
    /// for signals that don't already provide one via `VakterSignal.asTrigger`.
    private func trigger(for signal: VakterSignal) -> VakterTrigger? {
        if let direct = signal.asTrigger { return direct }
        switch signal {
        case .systemWake: return .lidClose  // best fit; the actual cause
                                            // was usually a lid-close-then-
                                            // wake sequence
        default: return nil
        }
    }

    // MARK: Explicit control (used by XPC / Shortcuts / menubar)

    /// Arm Vakter from a user-initiated path (menubar click, hotkey,
    /// XPC, Shortcuts, demo).
    ///
    /// **Three-phase lockless design.** The naive pattern — take the
    /// state lock, call `sleepDisabler.engage()`, transition, release —
    /// has a critical bug: `sleepDisabler.engage()` may show a Touch ID
    /// / password dialog and *block indefinitely* on user interaction.
    /// Any concurrent XPC call (statusSnapshot, disarm, setMode) would
    /// then soft-deadlock waiting for the state-machine lock. The
    /// menubar would appear frozen until the auth dialog resolves.
    ///
    /// Instead we run:
    ///
    ///   • **Phase 1 (under lock):** verify `state == .unarmed`, verify
    ///     no other arm is already pending, set `pendingArm = true`,
    ///     release the lock. Cheap, O(1).
    ///
    ///   • **Phase 2 (OUTSIDE lock):** engage `SleepGuard` (IOPM
    ///     assertions, instant), then call `sleepDisabler.engage()`
    ///     which may block on the auth dialog. The state-machine lock
    ///     is NOT held — every other XPC call works normally.
    ///
    ///   • **Phase 3 (under lock):** re-acquire, clear `pendingArm`,
    ///     re-check `state == .unarmed` (paranoia — grace timer or
    ///     similar mutation), then either commit the transition or
    ///     roll back the resources we just acquired in Phase 2.
    ///
    /// `skipScreenLock = true` is used by `runArmDemo()` so the user
    /// can watch the menubar through the full arm → grace → alarm
    /// cycle without their screen being taken away.
    func armFromUser(skipScreenLock: Bool = false) {
        // Phase 1 — under lock: reserve.
        lock.lock()
        guard state == .unarmed, !pendingArm else {
            lock.unlock()
            return
        }
        pendingArm = true
        lock.unlock()

        // Phase 2 — OUTSIDE lock: engage sleep blockers. The privileged
        // auth dialog may pop here and block until the user responds.
        // Holding the state-machine lock through this would freeze every
        // other XPC call. Doing it lockless is the whole point.
        sleepGuard.engage()
        let result = sleepDisabler.engage()

        // Phase 3 — under lock: commit or roll back.
        lock.lock()
        pendingArm = false

        guard state == .unarmed else {
            // Some other path changed state during the auth dialog.
            // Release the resources we acquired and bail. This is rare
            // but possible if e.g. a grace-timer mutation slipped in.
            sleepGuard.release()
            sleepDisabler.release()  // safe no-op if not engaged
            lock.unlock()
            return
        }

        switch result {
        case .userCancelled:
            // User explicitly said no. Roll back the sleep guard and
            // stay unarmed. No state change, no screen lock, no chirp.
            NSLog("[StateMachine] user cancelled auth prompt — arm aborted")
            sleepGuard.release()
            lock.unlock()
            return

        case .daemonNeedsApproval, .failed:
            // Arm with degraded protection. SleepGuard is engaged; the
            // closed-lid alarm may not survive Apple-Silicon clamshell
            // firmware override, but everything else (lid-open arm,
            // power unplug, Bluetooth proximity) still works.
            NSLog("[StateMachine] arming with degraded sleep protection (result=%@)",
                  String(describing: result))

        case .engaged:
            // Full protection — daemon path or first-time local auth
            // succeeded. Everything will work as designed.
            break
        }

        transition(to: .armed, trigger: .userAction)
        lock.unlock()

        if !skipScreenLock {
            // Delay the screen lock by 0.6 s so the menubar app can
            // render its signature "On watch" arming overlay before the
            // system takes over. The overlay listens for the snapshot
            // transition we just published.
            ScreenLocker.lockScreen(after: 0.6)
        }
    }

    /// Called after the user successfully authenticates. The auth check
    /// itself happens in the XPC layer (Touch ID / password), not here.
    func disarmFromUser() {
        lock.lock(); defer { lock.unlock() }
        guard state != .unarmed else { return }
        transition(to: .unarmed, trigger: .userAction)
    }

    func setMode(_ next: VakterMode) {
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

    // MARK: Diagnostics

    /// Fire the full alarm subsystem for the given duration without
    /// touching state. Used by the "Test alarm" menu item so the user
    /// can verify their speakers + voice cue + photo permissions etc.
    func runTestAlarm(seconds: TimeInterval) {
        audio.playTestAlarm(duration: seconds)
    }

    /// Inject a fake `.lidClosed` signal. Lets the user verify the full
    /// grace → alarm path without physically closing the lid (which on
    /// some Macs causes system sleep that the SleepGuard may not block).
    func simulateLidClose() {
        handle(signal: .lidClosed)
    }

    /// One-click full demo of the arming flow. Transitions to ARMED
    /// without locking the screen (so the user can watch from the
    /// menubar), waits 1 s for the arm chirp to ring out, then injects
    /// a lid-close signal. Grace chirps escalate for 8 s, alarm fires.
    /// User can disarm from the menubar at any point.
    ///
    /// **Implementation note:** previously this method took a shortcut
    /// and transitioned to `.armed` *without* engaging `SleepGuard` or
    /// `SleepDisabler`, which meant a demo-armed Mac would fall asleep
    /// mid-grace on closed lid and the alarm would never fire. Now it
    /// routes through the same three-phase `armFromUser` path as a real
    /// arm — same auth prompt, same protections — just with the screen
    /// lock skipped.
    func runArmDemo() {
        armFromUser(skipScreenLock: true)
        // Schedule the synthetic lid-close after a short pause so the
        // user hears the arm chirp before the grace starts. If the
        // user cancelled the auth dialog, state is still .unarmed and
        // the lid-close signal will be ignored — safe to dispatch
        // unconditionally.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.handle(signal: .lidClosed)
        }
    }

    // MARK: Internal transition

    private func transition(to next: VakterState, trigger: VakterTrigger?) {
        let prev = state
        state = next
        let params = ModeParameters.parameters(for: mode)

        NSLog("[StateMachine] %@ → %@ (trigger=%@)",
              prev.rawValue, next.rawValue, trigger?.rawValue ?? "nil")
        defer { publishSnapshot() }

        // Arm-gated observers run only while `.armed`. Pause on the way
        // out of armed (any transition to .unarmed), resume on the way
        // into armed (.unarmed → .armed). Idempotent on either side.
        let leavingArmed = (prev == .armed || prev == .grace || prev == .alarm)
                           && next == .unarmed
        let enteringArmed = prev == .unarmed && next == .armed
        if leavingArmed {
            for obs in armGatedObservers { obs.pause() }
        }
        if enteringArmed {
            for obs in armGatedObservers { obs.resume() }
        }

        switch next {
        case .unarmed:
            cancelGraceTimer()
            audio.stopAlarm()
            photos.stop()
            audioCapture.stop()
            // Critical: release the sleep guard so the Mac can sleep normally
            // again when not armed. Otherwise we'd drain the battery and
            // override the user's lid-close behaviour forever.
            sleepGuard.release()
            // And restore global sleep — undo the pmset disablesleep 1 we
            // ran on arm. Without this the Mac would never sleep again.
            sleepDisabler.release()
            // Soft confirmation cue only if we're disarming from a non-resting
            // state (don't chirp when we boot fresh into .unarmed).
            if prev != .unarmed {
                audio.playDisarmChirp()
            }
            recordEvent(fromState: prev, toState: next, trigger: trigger)

        case .armed:
            // SleepGuard + SleepDisabler are now engaged *before* we
            // reach this branch (see `performUserArmLocked`). They are
            // released symmetrically in the `.unarmed` branch above.
            audio.playArmChirp()
            recordEvent(fromState: prev, toState: next, trigger: trigger)

        case .grace:
            audio.playGraceChirp()
            // The user's chosen grace duration overrides the mode default.
            // Re-read each time so a Settings change takes effect on the
            // very next grace window with no XPC notification needed.
            let userGrace = GraceSettingsStore.load().seconds
            scheduleGraceExpiry(seconds: userGrace)
            recordEvent(fromState: prev, toState: next, trigger: trigger)

        case .alarm:
            cancelGraceTimer()
            // Per-mode cap honours `.cafe` mode's 30 s ceiling — the
            // siren won't run longer than that in a coffee shop even
            // if the user forgets to disarm.
            audio.startAlarm(audible: params.audible, cap: params.alarmCapSeconds)
            let alarmStart = Date()
            // Stamp alarm time so `recordEvidenceAppendix` can accept
            // capture callbacks that arrive after a fast disarm (within
            // the 60 s grace window). Pre-fix, those callbacks were
            // silently dropped.
            lastAlarmAt = alarmStart
            let eventDir = VakterConstants.eventsDirectoryURL.appendingPathComponent(
                ISO8601DateFormatter().string(from: alarmStart)
                    .replacingOccurrences(of: ":", with: "-"),
                isDirectory: true
            )

            // Kick photo + audio capture in parallel.
            photos.startBurst(cadence: params.photoCadence) { [weak self] capturedPhotos in
                // Append a follow-up event with the captured photos so
                // they show up in Event Log + the police PDF. (Pre-v1.3
                // these were saved to disk but never linked to an event.)
                self?.recordEvidenceAppendix(
                    photoFilenames: capturedPhotos, audioFilenames: nil
                )
            }

            // 10-second ambient audio clip. Captures voices, names,
            // surroundings — the evidence photos miss.
            audioCapture.captureClip(
                duration: 10.0,
                eventDirectory: eventDir
            ) { [weak self] audioFilename in
                if let name = audioFilename {
                    self?.recordEvidenceAppendix(
                        photoFilenames: nil, audioFilenames: [name]
                    )
                }
            }

            // The primary alarm event itself — empty evidence here, the
            // appendix entries above carry the filenames once capture
            // completes asynchronously.
            recordEvent(fromState: prev, toState: next, trigger: trigger)
            // Off-Mac evidence delivery (v0.9). Fire-and-forget — does
            // not block the alarm path. Builder waits ~3s for first
            // frames, probes location, then iMessages the recipient.
            // Skips silently if no recipient is configured.
            evidenceBundleBuilder.fireAndForget(
                trigger: trigger,
                mode: mode,
                eventTimestamp: alarmStart,
                eventDirectory: eventDir
            )
        }
    }

    // MARK: Event recording (chain-stamped, snapshot-publishing)

    /// Build, seal into the Merkle chain, persist, and update `lastEvent`.
    /// Single entry point for everything that wants to add an event row.
    ///
    /// Thread-safety: assumes caller holds the state-machine lock (every
    /// callsite is inside `transition(to:trigger:)` which is locked). We
    /// rely on the lock for `lastEvent` ordering — if two transitions
    /// raced through here we could chain in the wrong order.
    private func recordEvent(
        fromState: VakterState,
        toState: VakterState,
        trigger: VakterTrigger?,
        photoFilenames: [String] = [],
        audioFilenames: [String]? = nil,
        locationLat: Double? = nil,
        locationLon: Double? = nil
    ) {
        let raw = VakterEvent(
            fromState: fromState,
            toState: toState,
            trigger: trigger,
            photoFilenames: photoFilenames,
            modeAtEvent: mode,
            audioFilenames: audioFilenames,
            locationLat: locationLat,
            locationLon: locationLon
        )
        let sealed = EventChain.seal(raw, previousHash: lastEvent?.eventHash)
        log.append(sealed)
        lastEvent = sealed
    }

    /// Most-recent alarm time. Lets `recordEvidenceAppendix` accept
    /// in-flight captures even after a fast disarm — the audit found
    /// that photo + audio capture callbacks legitimately fire 1-7 s
    /// after the alarm started, and a quick disarm (user authenticates
    /// fast) was silently dropping the appendix events.
    private var lastAlarmAt: Date?

    /// Window during which post-alarm capture callbacks still count as
    /// "evidence for that alarm." 60 s is generous — covers the full
    /// `.normal` cadence (3 frames over ~5 s) and audio's 10 s recording.
    private static let alarmAppendixGrace: TimeInterval = 60.0

    /// Asynchronous evidence appendix. Photo + audio capture finish
    /// *after* the primary `.alarm` event was already sealed, so we add
    /// a follow-up row stamped with the captured filenames. This keeps
    /// the chain monotonic and surfaces the evidence in the Event Log
    /// + PDF report.
    ///
    /// Takes the lock itself — runs from a callback dispatched off the
    /// capture queue, so the state-machine lock is NOT held on entry.
    private func recordEvidenceAppendix(
        photoFilenames: [String]?,
        audioFilenames: [String]?
    ) {
        lock.lock(); defer { lock.unlock() }
        // Accept the appendix if EITHER we're still in alarm, OR a
        // recent alarm started within the grace window. Pre-fix, fast
        // disarms (e.g. user authenticates within 2s) dropped any
        // capture that completed after the unarmed transition.
        let inAlarm = lastEvent?.toState == .alarm
        let recentAlarm: Bool = {
            guard let t = lastAlarmAt else { return false }
            return Date().timeIntervalSince(t) < Self.alarmAppendixGrace
        }()
        guard inAlarm || recentAlarm else { return }
        recordEvent(
            fromState: .alarm,
            toState: .alarm,
            trigger: nil,
            photoFilenames: photoFilenames ?? [],
            audioFilenames: audioFilenames
        )
        publishSnapshot()
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
