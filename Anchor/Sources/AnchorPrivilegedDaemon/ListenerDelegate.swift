import Foundation
import Security
import AnchorShared

/// Accepts XPC connections from `AnchorHelper`, validates the peer's
/// code signature, and routes calls to `PrivilegedService`.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {

        // Validate the peer is actually our app. Without this, ANY process
        // on the system could connect to this root-privileged daemon and
        // ask it to do work for them.
        guard CodeRequirement.matches(connection: conn) else {
            NSLog("[Anchor.privileged] REFUSING connection — peer failed code requirement")
            return false
        }

        conn.exportedInterface = NSXPCInterface(with: AnchorPrivilegedProtocol.self)
        conn.exportedObject = PrivilegedService()
        conn.invalidationHandler = {
            NSLog("[Anchor.privileged] connection invalidated")
        }
        conn.resume()
        NSLog("[Anchor.privileged] accepted connection from validated peer")
        return true
    }
}

/// The actual privileged operations. Always runs as root (UID 0).
final class PrivilegedService: NSObject, AnchorPrivilegedProtocol {

    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool) -> Void) {
        let value = disabled ? "1" : "0"
        NSLog("[Anchor.privileged] setSleepDisabled(%@) — running pmset", disabled ? "true" : "false")

        let process = Process()
        process.launchPath = "/usr/bin/pmset"
        process.arguments = ["-a", "disablesleep", value]
        let errPipe = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("[Anchor.privileged] pmset launch failed: %@", error.localizedDescription)
            reply(false)
            return
        }
        if process.terminationStatus != 0 {
            let stderr = String(data: errPipe.fileHandleForReading.availableData,
                                encoding: .utf8) ?? "(no stderr)"
            NSLog("[Anchor.privileged] pmset exit=%d stderr=%@",
                  process.terminationStatus,
                  stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            reply(false)
            return
        }
        NSLog("[Anchor.privileged] pmset disablesleep %@ — OK", value)
        reply(true)
    }
}

/// Checks that an incoming XPC connection's peer process satisfies our
/// expected code requirement: must be signed by our Team ID and have
/// our app or helper bundle identifier.
enum CodeRequirement {

    /// Substituted at build time? Hardcoded for now. If you re-sign with
    /// a different identity, edit this. (TODO: have build-app.sh
    /// templatise this from the active Developer ID Application cert.)
    static let expectedTeamID = "9TA5GB5UJH"

    static func matches(connection: NSXPCConnection) -> Bool {
        // 1. Get the peer's audit token via the connection's `auditToken`
        //    property (private SPI on macOS but stable; many tools use it).
        //    We access it via KVC since the Swift overlay doesn't expose
        //    it as a public property.
        guard let auditTokenData = connection.value(forKey: "auditToken") as? Data else {
            NSLog("[Anchor.privileged] could not read auditToken from connection")
            return false
        }

        // 2. Make a SecCode for the peer from the audit token.
        var attrs: [String: Any] = [
            kSecGuestAttributeAudit as String: auditTokenData
        ]
        var peerCode: SecCode?
        let copyStatus = SecCodeCopyGuestWithAttributes(nil, attrs as CFDictionary, [], &peerCode)
        guard copyStatus == errSecSuccess, let peerCode = peerCode else {
            NSLog("[Anchor.privileged] SecCodeCopyGuestWithAttributes failed: %d", copyStatus)
            return false
        }

        // 3. Build a SecRequirement: anchor apple generic and certificate
        //    leaf field 1.2.840.113635.100.6.1.13 = "anchor apple generic
        //    Developer ID" + team ID match.
        let requirementText =
            "anchor apple generic " +
            "and certificate leaf[field.1.2.840.113635.100.6.1.13] " +
            "and certificate leaf[subject.OU] = \"\(expectedTeamID)\""
        var requirement: SecRequirement?
        let reqStatus = SecRequirementCreateWithString(
            requirementText as CFString, [], &requirement
        )
        guard reqStatus == errSecSuccess, let requirement = requirement else {
            NSLog("[Anchor.privileged] SecRequirementCreateWithString failed: %d", reqStatus)
            return false
        }

        // 4. Validate.
        let validateStatus = SecCodeCheckValidity(peerCode, [], requirement)
        if validateStatus != errSecSuccess {
            NSLog("[Anchor.privileged] SecCodeCheckValidity failed: %d", validateStatus)
            return false
        }
        return true
    }
}
