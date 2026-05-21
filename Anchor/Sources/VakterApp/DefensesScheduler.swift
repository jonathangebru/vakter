import Foundation
import AppKit
import VakterShared

/// Runs `DefensesProbe.runAll()` on a schedule, caches the latest
/// result to disk, and notifies observers (the menubar dropdown
/// rendering) when a new snapshot is available.
///
/// Lifecycle:
///   - Created and `start()`-ed at app launch from `AppDelegate`.
///   - First run fires within ~1.5 s (gives the helper time to come
///     up so its logs don't drown the user's first menubar click).
///   - Re-runs every 30 minutes by default. The user can force a
///     re-run via the menubar's "Run Checks" item.
///   - Cached snapshot persisted via `DefenseChecklistStore` so the
///     menubar always has *something* to render even on cold-launch
///     before the first scheduled run completes.
///
/// **Thread model:** the probe itself shells out to ~10 binaries and
/// takes ~250–400 ms. We run it on a background queue. State is
/// published back on `@MainActor` for SwiftUI / AppKit consumption.
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

    /// Off-main queue for the actual shell work. Concurrent so we
    /// don't queue runs behind each other (though `isRunning` blocks
    /// the user from triggering more than one anyway).
    private let workQueue = DispatchQueue(
        label: "app.vakter.mac.defenses-scheduler",
        qos: .utility
    )

    /// Load the last persisted snapshot so the menubar has data to
    /// render before the first scheduled run completes.
    init() {
        self.checklist = DefenseChecklistStore.load()
    }

    /// Begin the schedule. Fires the first run after 1.5 s so the
    /// menubar isn't blocked at launch, then every `interval`
    /// seconds thereafter.
    func start() {
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
    /// item (⌘R). Idempotent — no-ops if a run is already in flight.
    func runNow() {
        guard !isRunning else { return }
        isRunning = true
        workQueue.async { [weak self] in
            let snapshot = DefensesProbe.runAll()
            // Persist before publishing so a crash during the publish
            // doesn't leave us with a fresh in-memory state that the
            // next launch can't see.
            DefenseChecklistStore.save(snapshot)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.checklist = snapshot
                self.isRunning = false
                NotificationCenter.default.post(
                    name: .vakterDefensesChecklistUpdated,
                    object: nil
                )
            }
        }
    }
}

public extension Notification.Name {
    /// Posted on the main queue when `DefensesScheduler` finishes a
    /// run. `MenuBarController` subscribes so the next dropdown click
    /// rebuilds with the latest checklist.
    static let vakterDefensesChecklistUpdated =
        Notification.Name("app.vakter.defensesChecklistUpdated")
}
