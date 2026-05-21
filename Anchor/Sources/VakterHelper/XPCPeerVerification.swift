import Foundation
import Security

/// Installs a code-signing requirement on the XPC listener so only
/// peers signed with our Developer ID Team ID can connect.
///
/// **Why this matters.** Without a requirement, *any* process running as
/// the same user can open an XPC connection to the helper's Mach service
/// and call privileged methods (arm, disarm, defenses checklist, trusted-
/// peer mutations). With our Team ID pinned, only our own signed binaries
/// — the menubar app, helper-poke CLI, or a future Shortcuts extension —
/// pass the check; everything else gets `error: NSXPCConnectionInvalid`
/// before any method is dispatched.
///
/// macOS 13+ exposes `NSXPCListener.setCodeSigningRequirement(_:)`
/// directly, so we don't need to extract `audit_token_t` ourselves.
///
/// **Dev-build behaviour.** Unsigned builds (Xcode debug, ad-hoc) have no
/// Team ID. We detect that at startup and skip the requirement install,
/// logging a clear warning so the dev mode is loud about the gap. In
/// production (Developer ID + notarized) the Team ID is always present.
enum XPCPeerVerification {

    /// Read this binary's Team ID from its own code-signing info.
    /// Returns nil for unsigned / ad-hoc-signed builds.
    static func currentTeamID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &code) == errSecSuccess,
              let code = code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
              let staticCode = staticCode else {
            return nil
        }

        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else {
            return nil
        }

        return dict["teamid"] as? String
    }

    /// Build the requirement string for a given Team ID. Anchor to Apple
    /// generic (rejects self-signed roots) and pin the leaf certificate's
    /// `subject.OU` field, which is where Apple writes the Team ID.
    static func requirementString(forTeamID teamID: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// Apply the requirement to one incoming connection. macOS evaluates
    /// the peer's signature against the requirement immediately; if it
    /// doesn't match, subsequent message dispatches throw
    /// `NSXPCConnectionInvalid` and the connection is torn down. Call
    /// this once per `shouldAcceptNewConnection`.
    ///
    /// Returns true on success, false if dev mode (no Team ID) or if the
    /// requirement string is rejected by the API.
    @discardableResult
    static func install(on connection: NSXPCConnection) -> Bool {
        guard let teamID = currentTeamID() else {
            NSLog("[XPCPeerVerification] no Team ID — running unsigned (dev build)? Peer verification DISABLED.")
            return false
        }
        let req = requirementString(forTeamID: teamID)

        // Validate the requirement string up front via Security framework
        // so we get a real error if it's malformed. The
        // `setCodeSigningRequirement` API itself returns Void and silently
        // ignores bad input.
        var secReq: SecRequirement?
        let parseStatus = SecRequirementCreateWithString(req as CFString,
                                                          SecCSFlags(rawValue: 0),
                                                          &secReq)
        guard parseStatus == errSecSuccess else {
            NSLog("[XPCPeerVerification] requirement string rejected by SecRequirement (status=%d): %@",
                  parseStatus, req)
            return false
        }

        connection.setCodeSigningRequirement(req)
        return true
    }
}
