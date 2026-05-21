import Foundation
import CryptoKit
import VakterShared

/// Watches for the signed-in Apple ID changing while Vakter is armed.
/// Thief's standard flow after a successful wipe is to sign in with
/// their own Apple ID — that's what makes the Mac usable to them.
/// Watching for the change gives Vakter a second checkpoint beyond
/// the Find My token watcher.
///
/// **What we read**: `defaults read MobileMeAccounts Accounts` returns
/// a property-list array; the first account's `AccountID` is the
/// user's Apple ID email. We SHA-256-hash it so neither the helper
/// nor any disk artefact ever stores the raw Apple ID (privacy
/// invariant — even Vakter's logs don't see the user's identity).
///
/// **What this does NOT catch**: thief doesn't sign in with an Apple
/// ID at all (uses local-account-only). Vakter's other triggers
/// (Find My, photo burst on first arm-after-theft) cover that path.
enum AppleIDChangeWatcher {

    static func make() -> PollingObserver<String> {
        PollingObserver<String>(
            tag: "AppleIDChangeWatcher",
            interval: 60,
            signal: .appleIDChanged,
            probe: { currentAppleIDHash() }
        )
    }

    /// Hash the first Apple-ID account currently signed in. Returns
    /// "none" when no Apple ID is signed in (also a meaningful state
    /// — it's a change from "had one" to "have none").
    static func currentAppleIDHash() -> String {
        let text = Shell.run("/usr/bin/defaults", ["read", "MobileMeAccounts", "Accounts"])
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
           || text.contains("does not exist") {
            return "none"
        }
        // We only need the AccountID line (it changes on Apple ID swap).
        // The rest of the plist contains tokens that rotate over time.
        let line = text
            .components(separatedBy: .newlines)
            .first(where: { $0.contains("AccountID") }) ?? text
        let digest = SHA256.hash(data: Data(line.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
