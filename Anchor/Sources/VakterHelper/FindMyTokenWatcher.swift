import Foundation
import VakterShared

/// Watches the NVRAM `fmm-mobileme-token-FMM` variable while armed.
/// When the token transitions from non-empty → empty, Vakter assumes
/// someone is wiping Find My (the standard thief move just before a
/// macOS Recovery reinstall) and fires the alarm without grace.
///
/// **What this catches:** the case where the thief has the user's
/// password (coerced, phished, or shoulder-surfed) and is using
/// System Settings → Apple ID → Sign Out to wipe iCloud. Vakter
/// is still running in the user session at this point.
///
/// **What this does NOT catch:** thief reboots to macOS Recovery to
/// wipe (Vakter not running), thief just sells the unwiped Mac (token
/// persists → buyer hits FMM activation lock anyway), thief turns
/// off Wi-Fi first (alarm still fires + photos save locally, but
/// iMessage delivery stalls until reconnection).
///
/// Narrow but real, and uniquely Vakter's wedge — no competitor
/// product has this watcher.
///
/// **Implementation**: just a thin wrapper around `PollingObserver<String>`
/// with a probe that calls `DefensesProbe.findMyTokenValue()`, and a
/// `shouldEmit` predicate that fires only on the "had token → now
/// empty" transition. (Plain inequality would also fire on token
/// rotation, which Apple does silently.)
enum FindMyTokenWatcher {

    static func make() -> PollingObserver<String> {
        PollingObserver<String>(
            tag: "FindMyTokenWatcher",
            interval: 30,
            signal: .findMyTokenCleared,
            probe: {
                // Probe returns the raw NVRAM string (or "" if absent).
                // Treated as opaque — only its emptiness matters.
                DefensesProbe.findMyTokenValue() ?? ""
            },
            shouldEmit: { previous, current in
                // Only emit on the specific "had token → empty" edge.
                // Initial baseline (previous == nil) never fires.
                guard let prev = previous else { return false }
                return !prev.isEmpty && current.isEmpty
            }
        )
    }
}
