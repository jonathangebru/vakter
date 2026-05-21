import Foundation
import VakterShared

/// Generic poll-and-diff observer that turns "this value changed" into
/// an `VakterSignal`. Used by `FindMyTokenWatcher` (NVRAM token) and
/// `AppleIDChangeWatcher` (MobileMeAccounts hash).
///
/// **Why not just timer-fire signals unconditionally?** Both the
/// Find-My and Apple-ID watchers care only about *transitions*, not
/// current state. Polling every 30 s and emitting a signal on every
/// fire would spam the state machine; this wraps the diff logic so
/// each concrete watcher is ~15 LoC.
///
/// **Lifecycle**: watchers ARE registered as `VakterSignalObserver`s
/// (so `start(_:)` is called once at daemon launch) but the actual
/// `Process` polling only runs while the state machine is `.armed`.
/// The poller subscribes to snapshot updates and toggles its timer
/// on/off accordingly — see `armGate(_:)`.
final class PollingObserver<Probe>: VakterSignalObserver, ArmGatedObserver, @unchecked Sendable where Probe: Equatable, Probe: Sendable {

    // MARK: Configuration

    /// Short tag used in NSLog so users can grep
    /// `log stream --predicate 'process == "VakterHelper"' | grep <tag>`.
    let tag: String

    /// How often to fire the probe while armed.
    let interval: TimeInterval

    /// Closure that produces the current value. Called from a
    /// background queue, so don't touch UI / main-thread state.
    let probe: @Sendable () -> Probe

    /// Predicate that decides whether a probed pair `(previous, current)`
    /// represents a state change worth emitting. Defaults to plain
    /// inequality but watchers can specialise (e.g. "only emit when
    /// the token went from non-empty to empty").
    let shouldEmit: @Sendable (_ previous: Probe?, _ current: Probe) -> Bool

    /// The signal to emit on a change.
    let signal: VakterSignal

    // MARK: State

    private var timer: DispatchSourceTimer?
    private var emit: ((VakterSignal) -> Void)?
    private var lastSeen: Probe?
    private let queue = DispatchQueue(label: "vakter.polling-observer")

    init(tag: String,
         interval: TimeInterval,
         signal: VakterSignal,
         probe: @escaping @Sendable () -> Probe,
         shouldEmit: @escaping @Sendable (_ previous: Probe?, _ current: Probe) -> Bool
            = { prev, cur in prev != nil && prev != cur })
    {
        self.tag = tag
        self.interval = interval
        self.signal = signal
        self.probe = probe
        self.shouldEmit = shouldEmit
    }

    // MARK: VakterSignalObserver

    func start(_ emit: @escaping (VakterSignal) -> Void) {
        self.emit = emit
        NSLog("[%@] registered (interval=%.0fs, will start polling when armed)",
              tag, interval)
    }

    // MARK: Arm-gating

    /// Called by the state machine whenever it enters `.armed`. Probes
    /// once immediately to capture the baseline, then schedules the
    /// repeating timer.
    func resume() {
        queue.async { [weak self] in
            guard let self = self else { return }
            // Establish baseline so the very next tick doesn't spuriously
            // fire ("previous == nil, current == 'something'").
            self.lastSeen = self.probe()
            NSLog("[%@] resume — baseline captured", self.tag)
            self.scheduleTimer()
        }
    }

    /// Called by the state machine whenever it leaves `.armed`. Cancels
    /// the timer; baseline is preserved so re-arming picks up where we
    /// left off if the user re-arms within the same session.
    func pause() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            NSLog("[%@] pause — polling stopped", self?.tag ?? "?")
        }
    }

    // MARK: Internals

    private func scheduleTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        let current = probe()
        let previous = lastSeen
        lastSeen = current
        if shouldEmit(previous, current) {
            NSLog("[%@] change detected — emitting %@", tag, String(describing: signal))
            emit?(signal)
        }
    }
}
