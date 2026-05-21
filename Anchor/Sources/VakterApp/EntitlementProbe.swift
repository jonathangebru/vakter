import Foundation
import Security

/// Inspects the running binary's own code-signed entitlements without
/// crashing on missing entries.
///
/// **Why this exists.** `CKContainer(identifier:)` hard-asserts with
/// `EXC_BREAKPOINT` if the calling binary doesn't carry the
/// `com.apple.developer.icloud-container-identifiers` entitlement (or
/// the entitlement is present but the container isn't actually
/// provisioned for the signing Team ID in Developer Portal). Swift
/// cannot catch that — it bypasses do/try/catch and `defer`. The only
/// safe option is to inspect entitlements *before* calling CloudKit
/// constructors.
///
/// We use `SecTaskCopyValueForEntitlement` against the current task,
/// which Apple ships specifically for this kind of self-introspection.
/// No private API, no shelling out.
enum EntitlementProbe {

    /// `true` if THIS process's signed entitlements include
    /// `com.apple.developer.icloud-container-identifiers` containing
    /// `identifier`. Returns `false` for dev/unsigned builds, for
    /// signed builds missing the key, and for any error during the
    /// lookup — defensive in all directions.
    static func hasICloudContainer(_ identifier: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }

        var error: Unmanaged<CFError>?
        let key = "com.apple.developer.icloud-container-identifiers" as CFString
        let value = SecTaskCopyValueForEntitlement(task, key, &error)

        if let error = error?.takeRetainedValue() {
            NSLog("[EntitlementProbe] iCloud lookup failed: %@",
                  String(describing: error))
            return false
        }

        // `SecTaskCopyValueForEntitlement` returns CFTypeRef? — NOT
        // Unmanaged<CFTypeRef>? — so we cast directly to the bridged
        // Swift type rather than calling .takeRetainedValue().
        guard let cfArray = value as? [String] else {
            // Entitlement not present at all — common in dev builds
            // before iOS/SETUP.md is run.
            return false
        }

        let match = cfArray.contains(identifier)
        if !match {
            NSLog("[EntitlementProbe] iCloud container '%@' not in entitlement %@",
                  identifier, cfArray)
        }
        return match
    }

    /// Returns the Team ID embedded in this process's code signature,
    /// or nil for ad-hoc / unsigned builds. Used in conjunction with
    /// XPC peer pinning.
    static func teamIdentifier() -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        let key = "com.apple.developer.team-identifier" as CFString
        guard let value = SecTaskCopyValueForEntitlement(task, key, nil),
              let teamID = value as? String else {
            return nil
        }
        return teamID
    }
}
