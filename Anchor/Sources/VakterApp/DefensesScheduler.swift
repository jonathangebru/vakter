import Foundation
import AppKit
import VakterShared

/// Runs the Pareto-style defenses checklist on a schedule, caches the
/// latest result to disk, and notifies observers (the menubar dropdown
/// rendering) when a new snapshot is available.
///
/// **Source of truth (post-#27):** the scheduler prefers the helper's
/// `runPreflight` XPC call as the canonical audit path, falling back to
/// in-process `DefensesProbe.runAll()` only when the helper is
/// unreachable (dev builds, pre-approval onboarding, LWCR mismatch).
/// Routing through XPC means the helper — which is always running, even
/// while the app is hidden / quit — owns the latest snapshot and the
/// menubar dropdown's Defenses submenu reflects helper-side checks
/// without an obvious gap between "what Settings shows" and "what the
/// menubar shows". Before #27 the audit ran in-process; if the helper
/// ever served the same probe via XPC the two callers could disagree
/// on timing, which is the trust-eroding glitch #27 closes.
///
/// Lifecycle:
///   - Created at app launch from `AppDelegate` BEFORE `helperClient`.
///   - `start(helperClient:)` is called once the XPC client exists so
///     the scheduler can route through it; if `nil` is passed the
///     scheduler degrades to a pure in-process probe.
///   - First run fires within ~1.5 s (gives the helper time to come
///     up so its logs don't drown the user's first menubar click).
///   - Re-runs every 5 minutes. The user can force a re-run via the
///     menubar's "Run Checks" item.
///   - Cached snapshot persisted via `DefenseChecklistStore` so the
///     menubar always has *something* to render even on cold-launch
///     before the first scheduled run completes.
///
/// **Thread model:** the probe itself shells out to ~10 binaries and
/// takes ~2–6 s end-to-end. When routed through XPC the work happens
/// on the helper's `DispatchQueue.global(.utility)` and the reply
/// posts back via the XPC connection's background queue; when the
/// fallback fires we run it on `workQueue` ourselves. State is
/// always published back on `@MainActor` for SwiftUI / AppKit
/// consumption.
@MainActor
final class DefensesScheduler: ObservableObject {

    /// Most-recent snapshot. Published so the menubar's `NSMenu`
    /// rebuild + the Settings → Defenses tab observe it.
    @Published private(set) var checklist: DefenseChecklist?

    /// `true` while a `runNow()` is in flight. The menubar's
    /// "Run Checks" item disables itself during this window so
    /// the user can't queue 20 simultaneous probes.
    @Published private(set) var isRunning: Bool = false

    private var timer: Timer?
    /// 5-minute background cadence. Short enough that even if the
    /// user never opens the dropdown, Vakter notices a Firewall
    /// flip or a Sharing toggle within a few minutes. Cheap — each
    /// run is ~300 ms of shell-outs to `defaults` / `launchctl`,
    /// negligible battery cost at 5-minute intervals.
    ///
    /// The dropdown ALSO re-probes synchronously when the user
    /// clicks the menubar icon (via `freshenSync`), so the visible
    /// data is always at most ~1 second stale at the moment the
    /// user looks at it. And when System Settings deactivates, an
    /// async probe runs immediately so toggling Firewall/Sharing
    /// reflects in Vakter within a second of closing the Settings
    /// pane — addressing the "I flipped a switch and the dropdown
    /// kept showing the old value" v0.10.0 bug.
    private let interval: TimeInterval = 5 * 60

    /// Off-main queue for the actual shell work. Used only on the
    /// fallback path (helper unreachable). The XPC route runs the
    /// probe inside the helper process, so this queue stays idle in
    /// the steady state.
    private let workQueue = DispatchQueue(
        label: "app.vakter.mac.defenses-scheduler",
        qos: .utility
    )

    /// XPC client owned by `AppDelegate`. When set, `runNow()` routes
    /// through `helperClient.runPreflight(...)` so the helper is the
    /// canonical audit source. Held weakly so we never become the
    /// reason the client outlives the AppDelegate — though in practice
    /// the AppDelegate is the only retainer and lives for the app's
    /// entire lifetime.
    private weak var helperClient: HelperClient?

    /// Soft deadline for the XPC reply before we fall back to a local
    /// probe. The helper's probe typically completes in 2–6 s; this
    /// gives it generous room before we conclude it's unreachable.
    /// Tuned alongside the 5-min cadence: even at the worst case the
    /// user only loses ~8 s of staleness on a single tick.
    private let xpcReplyDeadline: TimeInterval = 8.0

    /// Load the last persisted snapshot so the menubar has data to
    /// render before the first scheduled run completes.
    init() {
        self.checklist = DefenseChecklistStore.load()
    }

    /// Begin the schedule. Fires the first run after 1.5 s so the
    /// menubar isn't blocked at launch, then every `interval`
    /// seconds thereafter.
    ///
    /// Pass `helperClient` so the scheduler can route the audit
    /// through the helper over XPC. Without it (legacy `start()`,
    /// kept for callers that don't yet have a client) the scheduler
    /// runs probes in-process — same behaviour as pre-#27.
    func start(helperClient: HelperClient? = nil) {
        self.helperClient = helperClient

        // Defer the first run a beat — gives the helper time to
        // settle and avoids racing with the SMAppService register
        // calls in AppDelegate.applicationDidFinishLaunching.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.runNow()
        }

        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runNow() }
        }
        // common-mode so the timer still fires during menu tracking
        // (otherwise `runNow()` would never tick while the user has
        // the menubar dropdown open).
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stop the schedule (used at app teardown).
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Trigger a manual run. Called by the menubar's "Run Checks"
    /// item (⌘R) and by the 5-min scheduler tick. Idempotent —
    /// no-ops if a run is already in flight.
    ///
    /// Path selection:
    ///   1. If `helperClient` is set, ask the helper to run the audit
    ///      over XPC. The helper owns `DefensesProbe.runAll()` already
    ///      (see `XPCService.runPreflight`); we just unwrap the reply.
    ///   2. If the XPC reply doesn't arrive within `xpcReplyDeadline`
    ///      seconds, OR the helper returns `nil` (decode failure /
    ///      proxy disconnected), we run the probe locally as a
    ///      fallback. This keeps the menubar useful during onboarding
    ///      (helper pending approval) and on dev builds.
    ///   3. If no `helperClient` was passed to `start(_:)`, we skip
    ///      step 1 and go straight to the local probe (legacy path).
    func runNow() {
        guard !isRunning else { return }
        isRunning = true

        // Local-only path: no helper client was injected at start().
        // Used by callers that have not yet wired the XPC route — e.g.
        // an outright Settings → "Run Checks" debug button or future
        // tests that exercise the scheduler in isolation.
        guard let client = helperClient else {
            runViaLocalProbe()
            return
        }

        // XPC path with deadline fallback. We use an AckGate so the
        // first arrival (whichever it is — helper reply or 8 s
        // timeout) wins; the second is a no-op. Same race-safe
        // pattern as `HelperClient.testAlarm`'s local fallback.
        let gate = AckGate()
        client.runPreflight { [weak self] checklist in
            // Hop happens inside HelperClient — already on MainActor.
            guard gate.claim() else { return }
            if let checklist = checklist {
                self?.publish(snapshot: checklist, source: "helper")
            } else {
                // Helper replied but decode failed — degrade to a
                // local probe rather than leave the menubar with a
                // stale checklist.
                NSLog("[DefensesScheduler] helper reply decoded as nil — falling back to local probe")
                self?.runViaLocalProbe(skipIsRunningGuard: true)
            }
        }

        // Deadline: if the helper doesn't ack within 8 s, the LaunchAgent
        // is almost certainly unreachable (not approved, killed mid-call,
        // LWCR-pinned to a stale binary). Bail to the local probe so the
        // user still gets fresh data — silent failure here would leave the
        // menubar Defenses submenu permanently stale.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + xpcReplyDeadline
        ) { [weak self] in
            guard gate.claim() else { return }
            NSLog("[DefensesScheduler] XPC reply deadline (%.0fs) — falling back to local probe",
                  self?.xpcReplyDeadline ?? 0)
            self?.runViaLocalProbe(skipIsRunningGuard: true)
        }
    }

    /// Run `DefensesProbe.runAll()` on `workQueue` and publish the
    /// result on the main actor.
    ///
    /// `skipIsRunningGuard` is true when called from the XPC fallback
    /// paths above (we already incremented `isRunning` on the way in
    /// and don't want the early-return to swallow the fallback).
    private func runViaLocalProbe(skipIsRunningGuard: Bool = false) {
        if !skipIsRunningGuard {
            // Setter path for the legacy "no helperClient" case.
            // isRunning was already flipped true in runNow() above,
            // but defensive double-set is harmless.
            isRunning = true
        }
        workQueue.async { [weak self] in
            let snapshot = DefensesProbe.runAll()
            DispatchQueue.main.async {
                self?.publish(snapshot: snapshot, source: "local")
            }
        }
    }

    /// Final delivery point — persist, publish, post the update
    /// notification. Always called on the main actor.
    private func publish(snapshot: DefenseChecklist, source: String) {
        // Persist before publishing so a crash during the publish
        // doesn't leave us with a fresh in-memory state that the
        // next launch can't see.
        DefenseChecklistStore.save(snapshot)
        checklist = snapshot
        isRunning = false
        NSLog("[DefensesScheduler] published checklist via %@: %d items, %d%% pass",
              source, snapshot.items.count, snapshot.passPercentage)
        NotificationCenter.default.post(
            name: .vakterDefensesChecklistUpdated,
            object: nil
        )
    }
}

public extension Notification.Name {
    /// Posted on the main queue when `DefensesScheduler` finishes a
    /// run. `MenuBarController` subscribes so the next dropdown click
    /// rebuilds with the latest checklist.
    static let vakterDefensesChecklistUpdated =
        Notification.Name("app.vakter.defensesChecklistUpdated")
}
