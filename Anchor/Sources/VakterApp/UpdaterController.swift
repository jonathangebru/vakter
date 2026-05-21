import AppKit
import Combine
import Foundation
import Sparkle
import SwiftUI

/// Vakter's thin wrapper around `SPUStandardUpdaterController`.
///
/// Why a wrapper instead of using `SPUStandardUpdaterController` directly?
/// Three small reasons:
///
///  1. **Lifetime ownership.** Sparkle's controller must outlive every
///     update check it kicks off — if it is released mid-download, the
///     XPC InstallerLauncher orphans and the in-flight prompt silently
///     dies. Owning it via a single `@MainActor`-isolated property on
///     `AppDelegate` makes that lifetime explicit.
///  2. **Testability.** `BundleSparkleConfigTests` reads the Info.plist
///     keys via this type's `current()` helper, so we keep all of the
///     Sparkle-config knowledge in one place rather than scattering
///     `Bundle.main.object(forInfoDictionaryKey:)` calls.
///  3. **Settings UI hooks.** The Settings → General → "Check for
///     updates" panel needs (a) a "check now" button, (b) an
///     "automatically check" toggle, and (c) a "last checked …" label.
///     Each one routes through `updater` here; the SwiftUI layer never
///     imports Sparkle directly.
///
/// **Security note.** All update verification is performed by Sparkle
/// itself using the EdDSA public key embedded in `Info.plist` under
/// `SUPublicEDKey`. We never touch downloaded bytes — Sparkle's
/// hardened-runtime XPC InstallerLauncher runs the verify + install
/// out-of-process. Vakter's only contribution is the feed URL and the
/// public key, both committed to source. There is no way for a
/// compromised vakter.app mirror to push a malicious update without
/// also stealing the EdDSA private key, which lives in the developer's
/// login keychain and never touches the repository.
@MainActor
final class UpdaterController {

    /// Sparkle's controller. We keep this as a stored property so the
    /// owning AppDelegate keeps it alive for the app's lifetime; see
    /// the lifetime note above. `startingUpdater: true` kicks off the
    /// first feed check after Sparkle's polite delay (a couple of
    /// minutes post-launch). `SUScheduledCheckInterval` in Info.plist
    /// then governs the cadence (currently 24h).
    let controller: SPUStandardUpdaterController

    /// Convenience accessor for the Sparkle updater itself. Used by the
    /// "Check for updates now" button and the "automatic checks" toggle
    /// in `SettingsRoot.GeneralTab`.
    var updater: SPUUpdater { controller.updater }

    init() {
        // No custom delegate yet — the stock Sparkle UI prompt is fine
        // for v1.4.x. When we want the prompt to match the Vakter
        // design system (lighthouse mark, calm typography, native
        // attributed strings) we'll swap in an SPUUserDriverDelegate.
        // Until then the default driver gives us the right behaviour:
        // sheet-style prompt that respects hardened runtime + EdDSA.
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    // MARK: - Settings UI surface

    /// Whether automatic background checks are enabled. Read from + bound
    /// to `SPUUpdater.automaticallyChecksForUpdates`. Persisted by Sparkle
    /// in `~/Library/Preferences/app.vakter.mac.plist` under
    /// `SUEnableAutomaticChecks`.
    var automaticChecksEnabled: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// User explicitly clicked "Check for updates now…". This fires the
    /// foreground update path, so the prompt shows even if there is no
    /// update available ("You're up to date.").
    @objc func checkForUpdatesNow(_ sender: Any?) {
        updater.checkForUpdates()
    }

    /// Last successful feed check. Used by the Settings UI to render a
    /// human "Last checked: 2h ago" label. `nil` on a fresh install
    /// (the first launch hasn't reached the polite-delay timer yet).
    var lastCheckDate: Date? {
        updater.lastUpdateCheckDate
    }

    // MARK: - Diagnostic snapshot

    /// Returns the Info.plist-derived Sparkle configuration, for tests
    /// and for the "About" tab's "Update channel" line. Reads from the
    /// app bundle rather than asking Sparkle so the test can assert
    /// what shipped without needing to instantiate a real updater
    /// (which would otherwise want a writable Application Support dir).
    static func current() -> SparkleConfig {
        SparkleConfig.fromMainBundle()
    }
}

/// The Sparkle-related keys we set in `Info.plist`. Parsed once for
/// tests + debug surfaces. Keep this type strictly read-only — Sparkle
/// itself is the single writer for any of these values at runtime
/// (settings come from `SPUUpdater.*` defaults, NOT this struct).
struct SparkleConfig {
    /// `SUFeedURL` — HTTPS URL the updater hits for `appcast.xml`.
    /// Must be HTTPS (Sparkle 2 refuses plain http); reviewers who
    /// inspect the binary look for this.
    let feedURL: URL?

    /// `SUPublicEDKey` — base64-encoded ed25519 public key. The matching
    /// private key lives in the developer's login keychain and never
    /// ships in the repo or the binary. Sparkle verifies every download
    /// against this key before extracting; the EdDSA signature is in
    /// `<enclosure sparkle:edSignature="…"/>` of the appcast item.
    let publicEDKey: String?

    /// `SUEnableAutomaticChecks` — whether background checks fire on
    /// the scheduled cadence. We ship `YES`; the user can flip this
    /// from Settings → General → "Automatically check for updates".
    let enableAutomaticChecks: Bool

    /// `SUScheduledCheckInterval` — seconds between background checks.
    /// We ship 86400 (24h) which is the Sparkle default but spelled
    /// explicitly so a reviewer can confirm we're not phoning home
    /// constantly.
    let scheduledCheckInterval: TimeInterval

    /// `SUEnableAutomaticUpdates` — whether Sparkle is allowed to apply
    /// updates without showing the prompt first. We ship `NO`: a
    /// security-conscious user should always see "Vakter 1.4.3 is
    /// ready — review the changes" and click Install themselves. This
    /// is conservative; we may flip it on for patch releases later.
    let enableAutomaticUpdates: Bool

    static func fromMainBundle() -> SparkleConfig {
        let dict = Bundle.main.infoDictionary ?? [:]
        let feed = (dict["SUFeedURL"] as? String).flatMap(URL.init(string:))
        let key  = dict["SUPublicEDKey"] as? String

        // Plist bools come through as `Bool` once parsed via
        // infoDictionary, but defensively coerce in case the dev plist
        // ever ships them as strings ("YES"/"NO").
        let autoChecks = boolFromPlist(dict["SUEnableAutomaticChecks"]) ?? true
        let autoApply  = boolFromPlist(dict["SUEnableAutomaticUpdates"]) ?? false

        // Integers can arrive as NSNumber or as String; accept both.
        let interval: TimeInterval = {
            if let n = dict["SUScheduledCheckInterval"] as? NSNumber {
                return TimeInterval(truncating: n)
            }
            if let s = dict["SUScheduledCheckInterval"] as? String,
               let n = TimeInterval(s) {
                return n
            }
            return 86_400
        }()

        return SparkleConfig(
            feedURL: feed,
            publicEDKey: key,
            enableAutomaticChecks: autoChecks,
            scheduledCheckInterval: interval,
            enableAutomaticUpdates: autoApply
        )
    }

    private static func boolFromPlist(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String {
            switch s.uppercased() {
            case "YES", "TRUE", "1": return true
            case "NO", "FALSE", "0": return false
            default: return nil
            }
        }
        return nil
    }
}

/// SwiftUI `EnvironmentObject` wrapper around the (optional) updater
/// controller. The `Settings` window is hosted via `NSHostingController`
/// and built in `AppDelegate.showSettingsWindow()`; injecting an
/// `ObservableObject` here is how the Settings panes reach the live
/// updater without falling back to the brittle
/// `NSApp.delegate as? AppDelegate` cast (which silently returns nil
/// when SwiftUI re-hosts the view in a separate window — same trap
/// `HelperClient` already learned about).
///
/// The `controller` is `Optional` so the GeneralTab can be rendered
/// in unit tests + Xcode previews where Sparkle is never instantiated.
/// In those cases the "Check for updates" buttons disable themselves
/// rather than crash.
@MainActor
final class UpdaterControllerBox: ObservableObject {

    /// The live Sparkle controller, or `nil` in tests / previews.
    let controller: UpdaterController?

    /// Mirror of `controller.automaticChecksEnabled`. We re-publish the
    /// value here so the SwiftUI Toggle binds cleanly without driving
    /// a separate `@State` in the view (which would risk going out of
    /// sync after Sparkle updates the underlying default — e.g. if the
    /// user toggled it via Settings on another window, or if Sparkle
    /// changed its mind because the user said "no thanks, never check
    /// again" in a recent prompt).
    @Published var automaticChecksEnabled: Bool

    /// Mirror of `controller.lastCheckDate`. Refreshed manually by the
    /// GeneralTab on appear + every time the user hits "Check now",
    /// so the "Last checked …" label is current without subscribing
    /// to Sparkle's internal KVO timeline.
    @Published var lastCheckDate: Date?

    init(controller: UpdaterController?) {
        self.controller = controller
        self.automaticChecksEnabled = controller?.automaticChecksEnabled ?? true
        self.lastCheckDate = controller?.lastCheckDate
    }

    /// Re-pull the latest values from Sparkle. Cheap (both are simple
    /// property reads on `SPUUpdater`); we call this on
    /// `GeneralTab.onAppear` and after every explicit "Check now".
    func refresh() {
        guard let c = controller else { return }
        automaticChecksEnabled = c.automaticChecksEnabled
        lastCheckDate = c.lastCheckDate
    }

    /// Sets the automatic-checks default on Sparkle and re-publishes.
    func setAutomaticChecks(_ on: Bool) {
        controller?.automaticChecksEnabled = on
        automaticChecksEnabled = on
    }

    /// User asked for an immediate check. Fires Sparkle's foreground
    /// flow (shows a prompt even if no update is available). Refreshes
    /// `lastCheckDate` shortly afterwards so the UI label updates.
    func checkNow() {
        controller?.checkForUpdatesNow(nil)
        // Sparkle records `lastUpdateCheckDate` once the network call
        // returns. Pull it on a brief delay so the label refreshes
        // after the round-trip without us needing to subscribe to KVO.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
        }
    }
}
