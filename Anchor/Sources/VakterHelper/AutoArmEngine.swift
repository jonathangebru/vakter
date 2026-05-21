import Foundation
import CoreLocation
import CoreWLAN
import IOKit
import IOKit.hid
import VakterShared

/// Continuously evaluates the user's `AutoArmRule` set and arms Vakter
/// when any rule fires.
///
/// **Why this lives in the helper, not the app.** The helper is the
/// always-running LaunchAgent. If auto-arm rules lived in the menubar
/// app, they'd stop firing whenever the user closed the menubar (e.g.
/// during a software update relaunch). The helper has no UI; it runs
/// continuously from login.
///
/// **Idle detection.** Uses `CGEventSourceSecondsSinceLastEventType` with
/// `combinedSessionState` — the same API macOS itself uses for screen
/// saver activation. Polled every 30 s; finer granularity isn't useful
/// for an "arm if idle for 5 minutes" rule.
///
/// **Geofence.** CoreLocation `CLCircularRegion` monitoring with
/// `startMonitoring(for:)`. macOS will fire region-exit callbacks even
/// when the helper is asleep, which is exactly what we want.
///
/// **Wi-Fi.** CoreWLAN `CWWiFiClient` — observe BSSID/SSID changes via
/// the `CWEventDelegate` interface.
///
/// Cooldown is respected per rule — a fired rule won't re-fire within
/// its `cooldownSeconds` window. Prevents "I left the geofence radius,
/// walked back in, walked back out" from arming repeatedly.
@MainActor
final class AutoArmEngine: NSObject {

    private weak var stateMachine: StateMachine?
    private let locationManager = CLLocationManager()
    private var rules: [AutoArmRule] = []
    private var lastFired: [UUID: Date] = [:]
    private var idleTimer: DispatchSourceTimer?
    private var dailyTimer: DispatchSourceTimer?
    private var lastIdleFired: Date = .distantPast

    init(stateMachine: StateMachine) {
        self.stateMachine = stateMachine
        super.init()
        self.locationManager.delegate = self
    }

    /// Reload rules from disk and re-subscribe to OS notifications.
    /// Called at startup and whenever the user edits rules.
    func reload() {
        rules = AutoArmRuleStore.load().filter { $0.enabled }
        NSLog("[AutoArm] loaded %d enabled rules", rules.count)

        // Tear down existing observers; re-install for active rules.
        stopAll()
        for rule in rules {
            install(rule)
        }
    }

    /// Stop all observers + timers. Called on disarm of the engine,
    /// before re-installing for a new ruleset.
    private func stopAll() {
        // Stop all monitored regions.
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        idleTimer?.cancel()
        idleTimer = nil
        dailyTimer?.cancel()
        dailyTimer = nil
    }

    private func install(_ rule: AutoArmRule) {
        switch rule.trigger {
        case .geofenceExit(let lat, let lon, let radius):
            installGeofence(rule: rule, lat: lat, lon: lon, radius: radius)
        case .wifiDisconnect(let ssids):
            installWifi(rule: rule, ssids: ssids)
        case .idleForSeconds(let seconds):
            installIdle(rule: rule, seconds: seconds)
        case .dailyAt(let hour, let minute):
            installDaily(rule: rule, hour: hour, minute: minute)
        }
    }

    // MARK: - Geofence

    private func installGeofence(
        rule: AutoArmRule, lat: Double, lon: Double, radius: Double
    ) {
        // Permission gate. The helper requests `Always` so it can
        // receive region-exit events even when the app is closed.
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
        if status == .denied || status == .restricted {
            NSLog("[AutoArm] geofence rule %@ disabled — location permission denied",
                  rule.id.uuidString)
            return
        }

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            radius: radius,
            identifier: rule.id.uuidString
        )
        region.notifyOnExit = true
        region.notifyOnEntry = false
        locationManager.startMonitoring(for: region)
        NSLog("[AutoArm] geofence installed for rule %@ (%.5f,%.5f r=%.0fm)",
              rule.name, lat, lon, radius)
    }

    // MARK: - Wi-Fi

    private func installWifi(rule: AutoArmRule, ssids: [String]) {
        // CWWiFiClient.shared().startMonitoringEvent reports SSID changes.
        // The full event-loop wiring is non-trivial — for v1.4 we poll
        // every 15 s, which is plenty fast for "arm when I leave home
        // Wi-Fi" because the disconnect is usually accompanied by the
        // physical act of standing up.
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 15.0, repeating: 15.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let current = CWWiFiClient.shared().interface()?.ssid()
            // Fire if we were on one of the named SSIDs and now we're not.
            let stillOnTrusted = current.map { ssids.contains($0) } ?? false
            if !stillOnTrusted {
                Task { @MainActor in self.fireIfCooledDown(rule) }
            }
        }
        timer.resume()
        // We re-use the dailyTimer slot for wifi too because at most one
        // of each trigger type can be active in v1.4. Future enhancement:
        // per-rule timer registry.
        dailyTimer = timer
    }

    // MARK: - Idle

    private func installIdle(rule: AutoArmRule, seconds: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 30.0, repeating: 30.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let idle = idleSecondsSinceLastInput()
            if idle >= seconds {
                Task { @MainActor in self.fireIfCooledDown(rule) }
            }
        }
        timer.resume()
        idleTimer = timer
    }

    /// System-wide idle time via IOKit's HIDIdleTime registry key —
    /// the canonical macOS approach used by ScreenSaverEngine and the
    /// `ioreg -c IOHIDSystem` CLI. Returns 0 on lookup failure (better
    /// to under-fire than over-fire).
    private nonisolated func idleSecondsSinceLastInput() -> TimeInterval {
        let matching = IOServiceMatching("IOHIDSystem")
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }
        var unmanagedProps: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry, &unmanagedProps, kCFAllocatorDefault, 0
        ) == KERN_SUCCESS,
              let props = unmanagedProps?.takeRetainedValue() as? [String: Any],
              let nanos = props["HIDIdleTime"] as? Int64
        else { return 0 }
        return TimeInterval(nanos) / 1_000_000_000
    }

    // MARK: - Daily

    private func installDaily(rule: AutoArmRule, hour: Int, minute: Int) {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        let next = nextOccurrence(hour: hour, minute: minute)
        timer.schedule(deadline: .now() + next.timeIntervalSinceNow,
                       repeating: 86_400)   // 24 h
        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.fireIfCooledDown(rule) }
        }
        timer.resume()
        dailyTimer = timer
    }

    private func nextOccurrence(hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let candidate = cal.date(from: components) else { return Date() }
        return candidate > Date() ? candidate : candidate.addingTimeInterval(86_400)
    }

    // MARK: - Firing

    private func fireIfCooledDown(_ rule: AutoArmRule) {
        if let last = lastFired[rule.id],
           Date().timeIntervalSince(last) < rule.cooldownSeconds {
            return
        }
        lastFired[rule.id] = Date()
        NSLog("[AutoArm] firing rule %@ (%@)", rule.id.uuidString, rule.name)
        stateMachine?.armFromUser()
    }
}

// MARK: - CLLocationManagerDelegate

extension AutoArmEngine: CLLocationManagerDelegate {

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        guard let uuid = UUID(uuidString: region.identifier) else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let rule = self.rules.first(where: { $0.id == uuid }) else { return }
            self.fireIfCooledDown(rule)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        NSLog("[AutoArm] CL error: %@", error.localizedDescription)
    }
}
