import Foundation
import CoreLocation
import VakterShared

/// One-shot Mac location request via CoreLocation, with caching for
/// the "thief disabled Wi-Fi so I can't get a fresh fix" edge case.
///
/// Macs locate via Wi-Fi BSSID lookup against Apple's database. Real-
/// world accuracy: 20–60 m in dense urban areas, 500 m–5 km elsewhere,
/// nil if Wi-Fi is off entirely. A 10 s hard timeout — beyond that the
/// alarm flow proceeds without a fresh fix.
///
/// **TCC**: Location Services consent is requested via the menubar app
/// (during onboarding). The helper inherits via shared signing identity
/// + same Apple ID approval. If denied, `currentCoordinate()` returns
/// nil silently.
///
/// **Caching**: every successful probe writes `last-location.json` to
/// the support dir. `lastKnown()` reads it. That way a stolen Mac with
/// Wi-Fi disabled still tells the owner *where it was last seen* —
/// usually the cafe table.
final class LocationProbe: NSObject, CLLocationManagerDelegate, @unchecked Sendable {

    static let shared = LocationProbe()

    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Request a one-shot fresh location. Resolves in up to 10 s.
    /// Returns nil on denial, hardware unavailable, or timeout.
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        // Authorization gate. .denied / .restricted → immediate nil.
        let status = manager.authorizationStatus
        switch status {
        case .denied, .restricted:
            NSLog("[LocationProbe] auth denied — returning nil")
            return nil
        case .notDetermined:
            // We do NOT call requestAlwaysAuthorization here. The helper
            // is a daemon-style process and can't show the consent dialog.
            // The menubar app handles the prompt.
            NSLog("[LocationProbe] auth undetermined — returning nil (app must prompt)")
            return nil
        default:
            break
        }

        let coord: CLLocationCoordinate2D? = await withCheckedContinuation { cont in
            lock.lock()
            continuations.append(cont)
            let firstRequest = continuations.count == 1
            lock.unlock()

            if firstRequest {
                manager.requestLocation()
                // 10 s timeout — sometimes Wi-Fi geolocation hangs.
                DispatchQueue.global().asyncAfter(deadline: .now() + 10.0) { [weak self] in
                    self?.resolveAll(with: nil)
                }
            }
        }

        if let c = coord { cache(c) }
        return coord
    }

    /// Read the cached last-known coordinate (plus age in seconds) if any.
    /// Used when `currentCoordinate()` returns nil so we can still ship
    /// *something* to the recipient.
    func lastKnown() -> (CLLocationCoordinate2D, TimeInterval)? {
        let url = Self.cacheURL
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedCoordinate.self, from: data)
        else { return nil }
        let age = Date().timeIntervalSince(cached.timestamp)
        return (CLLocationCoordinate2D(latitude: cached.lat, longitude: cached.lon), age)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else {
            resolveAll(with: nil); return
        }
        resolveAll(with: coord)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[LocationProbe] CL error: %@", error.localizedDescription)
        resolveAll(with: nil)
    }

    // MARK: - Internals

    private func resolveAll(with coord: CLLocationCoordinate2D?) {
        lock.lock()
        let pending = continuations
        continuations.removeAll()
        lock.unlock()
        for cont in pending {
            cont.resume(returning: coord)
        }
    }

    private static var cacheURL: URL {
        VakterConstants.supportDirectoryURL
            .appendingPathComponent("last-location.json")
    }

    private func cache(_ coord: CLLocationCoordinate2D) {
        let cached = CachedCoordinate(lat: coord.latitude,
                                      lon: coord.longitude,
                                      timestamp: Date())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? FileManager.default.createDirectory(
            at: VakterConstants.supportDirectoryURL,
            withIntermediateDirectories: true)
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    private struct CachedCoordinate: Codable {
        let lat: Double
        let lon: Double
        let timestamp: Date
    }
}
