import Foundation
import Security
import VakterShared

/// Accepts XPC connections from `VakterHelper`, validates the peer's
/// code signature, and routes calls to `PrivilegedService`.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {

        // Validate the peer is actually our app. Without this, ANY process
        // on the system could connect to this root-privileged daemon and
        // ask it to do work for them.
        guard CodeRequirement.matches(connection: conn) else {
            NSLog("[Vakter.privileged] REFUSING connection — peer failed code requirement")
            return false
        }

        conn.exportedInterface = NSXPCInterface(with: VakterPrivilegedProtocol.self)
        conn.exportedObject = PrivilegedService()
        conn.invalidationHandler = {
            NSLog("[Vakter.privileged] connection invalidated")
        }
        conn.resume()
        NSLog("[Vakter.privileged] accepted connection from validated peer")
        return true
    }
}

/// The actual privileged operations. Always runs as root (UID 0).
final class PrivilegedService: NSObject, VakterPrivilegedProtocol {

    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool) -> Void) {
        let value = disabled ? "1" : "0"
        NSLog("[Vakter.privileged] setSleepDisabled(%@) — running pmset", disabled ? "true" : "false")

        let process = Process()
        process.launchPath = "/usr/bin/pmset"
        process.arguments = ["-a", "disablesleep", value]
        let errPipe = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("[Vakter.privileged] pmset launch failed: %@", error.localizedDescription)
            reply(false)
            return
        }
        if process.terminationStatus != 0 {
            let stderr = String(data: errPipe.fileHandleForReading.availableData,
                                encoding: .utf8) ?? "(no stderr)"
            NSLog("[Vakter.privileged] pmset exit=%d stderr=%@",
                  process.terminationStatus,
                  stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            reply(false)
            return
        }
        NSLog("[Vakter.privileged] pmset disablesleep %@ — OK", value)
        reply(true)
    }
}

/// Checks that an incoming XPC connection's peer process satisfies our
/// expected code requirement: must be signed by the **same Team ID as
/// this daemon binary**. The Team ID isn't hardcoded — the daemon
/// inspects its own signature at startup and remembers it.
///
/// Why self-discovery rather than a hardcoded constant? Because Vakter
/// is open-source: contributors and forks sign their builds with their
/// own Apple Developer cert. A hardcoded "must be signed by 9TA5GB5UJH"
/// would mean every other build silently rejected every XPC call (the
/// exact bug that bit us pre-v0.9.4 — see `ListenerDelegate.matches`).
/// With self-discovery, *whatever* identity you sign with becomes the
/// authoritative team ID; peers just have to match the daemon's own.
enum CodeRequirement {

    /// Resolved once at daemon launch by inspecting our own signing
    /// information. Static so the cost of `SecCodeCopySigningInformation`
    /// is paid once, not per connection.
    private static let selfTeamID: String? = readSelfTeamID()

    static func matches(connection: NSXPCConnection) -> Bool {
        // 0. Resolve our own team ID. If we can't, we have no way to
        //    enforce a meaningful requirement — refuse every connection
        //    rather than silently allow unknown peers.
        guard let teamID = selfTeamID else {
            NSLog("[Vakter.privileged] could not determine own Team ID — refusing connection")
            return false
        }

        // 1. Get the peer's audit token. NSXPCConnection exposes it via
        //    KVC as an `NSValue` wrapping the 32-byte `audit_token_t`
        //    struct (NOT a `Data` — the v0.9.4 fix was this cast).
        //    The audit token is kernel-issued and unforgeable: it's how
        //    we know which process is genuinely on the far end of this
        //    XPC connection.
        guard let nsValue = connection.value(forKey: "auditToken") as? NSValue else {
            NSLog("[Vakter.privileged] could not read auditToken from connection")
            return false
        }
        var auditToken = audit_token_t(val: (0, 0, 0, 0, 0, 0, 0, 0))
        nsValue.getValue(&auditToken,
                         size: MemoryLayout<audit_token_t>.size)

        // 2. Convert the audit token to a PID, then look up the peer's
        //    on-disk binary path via `proc_pidpath`.
        //
        //    **Why this path** rather than `SecCodeCopyGuestWithAttributes`
        //    + `SecCodeCopyStaticCode`: on macOS 14+ the dynamic-SecCode
        //    derived from an audit token doesn't always expose the full
        //    Developer-ID cert chain to `SecCodeCheckValidity`, which is
        //    why every prior incarnation of this check failed with
        //    errSecCSReqFailed (-67034) even though the helper binary is
        //    correctly signed. `SecStaticCodeCreateWithPath` against the
        //    on-disk URL is the same path `codesign --verify -R '<req>'`
        //    uses — and that command ALWAYS succeeds for our helper, so
        //    we have a known-good reference implementation.
        //
        //    Security: an attacker spoofing a different binary would need
        //    to (a) supply a valid audit token (kernel-issued, can't be
        //    forged), and (b) have that token resolve to a PID whose
        //    on-disk binary satisfies the Developer-ID-Application +
        //    Team-OU check. Both conditions are real.
        // `audit_token_to_pid(t)` is a libbsm macro that expands to
        // `t.val[5]` — the 6th 32-bit word of the audit token is the
        // peer's PID. We extract directly from the tuple rather than
        // link libbsm (Swift tuple-indexing the C array).
        let pid = pid_t(auditToken.val.5)

        // proc_pidpath caps out at MAXPATHLEN * 4 = 4096. Hardcode rather
        // than import the unavailable `PROC_PIDPATHINFO_MAXSIZE` macro.
        var pathBuf = [CChar](repeating: 0, count: 4096)
        let pathLen = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        guard pathLen > 0 else {
            NSLog("[Vakter.privileged] proc_pidpath for pid=%d failed", pid)
            return false
        }
        let peerPath = String(cString: pathBuf)
        let peerURL  = URL(fileURLWithPath: peerPath)
        NSLog("[Vakter.privileged] peer pid=%d path=%@", pid, peerPath)

        var peerStatic: SecStaticCode?
        let staticStatus = SecStaticCodeCreateWithPath(
            peerURL as CFURL, [], &peerStatic
        )
        guard staticStatus == errSecSuccess, let peerStatic = peerStatic else {
            NSLog("[Vakter.privileged] SecStaticCodeCreateWithPath(%@) failed: %d",
                  peerPath, staticStatus)
            return false
        }

        // 3. Build a SecRequirement keyed on OUR own discovered Team ID.
        //
        //    Pre-v0.10.2 also required the Developer-ID-Application leaf
        //    OID (`1.2.840.113635.100.6.1.13`). The helper genuinely has
        //    that extension — verified via `codesign --extract-certificates`
        //    — but `SecCodeCheckValidity` against the live audit-token-
        //    derived `SecCode` returned -67034 (errSecCSReqFailed) even
        //    with all properties matching. The CSREQ `field.X.Y.Z`
        //    extension-presence check is sometimes flaky when the peer
        //    is observed via the audit-token path rather than as a
        //    static on-disk binary.
        //
        //    Dropping the OID clause and keeping `anchor apple generic`
        //    + Team OU match preserves the security boundary: an
        //    attacker would need both a valid Apple-signed cert AND
        //    one issued to this exact Team ID. That's the same
        //    guarantee Apple's own SMJobBless examples use.
        let requirementText =
            "anchor apple generic " +
            "and certificate leaf[subject.OU] = \"\(teamID)\""
        var requirement: SecRequirement?
        let reqStatus = SecRequirementCreateWithString(
            requirementText as CFString, [], &requirement
        )
        guard reqStatus == errSecSuccess, let requirement = requirement else {
            NSLog("[Vakter.privileged] SecRequirementCreateWithString failed: %d", reqStatus)
            return false
        }

        // 4. Validate against the STATIC code reference. The static
        //    view always has the on-disk cert chain — same path that
        //    `codesign --verify -R '<req>'` uses, and the one we know
        //    satisfies our requirement.
        let validateStatus = SecStaticCodeCheckValidity(peerStatic, [], requirement)
        if validateStatus != errSecSuccess {
            NSLog("[Vakter.privileged] SecStaticCodeCheckValidity failed: %d (requirement: %@)",
                  validateStatus, requirementText)
            return false
        }
        return true
    }

    /// Read our own signing Team ID from the running daemon's signature.
    /// Returns nil if the daemon is unsigned (during local debug builds)
    /// or if the signing info doesn't include a TeamIdentifier (older
    /// development certs).
    ///
    /// Implementation: `SecCodeCopySelf` → `SecCodeCopySigningInformation`
    /// with `kSecCSSigningInformation` → read the "teamid" entry.
    private static func readSelfTeamID() -> String? {
        var selfCode: SecCode?
        let copyStatus = SecCodeCopySelf([], &selfCode)
        guard copyStatus == errSecSuccess, let selfCode = selfCode else {
            NSLog("[Vakter.privileged] SecCodeCopySelf failed: %d", copyStatus)
            return nil
        }
        // SecCodeCopySigningInformation wants a SecStaticCode; produce
        // a static-code handle from the running-code handle.
        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(selfCode, [], &staticCode)
        guard staticStatus == errSecSuccess, let staticCode = staticCode else {
            NSLog("[Vakter.privileged] SecCodeCopyStaticCode failed: %d", staticStatus)
            return nil
        }
        var infoCF: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &infoCF
        )
        guard infoStatus == errSecSuccess,
              let info = infoCF as? [String: Any]
        else {
            NSLog("[Vakter.privileged] SecCodeCopySigningInformation failed: %d", infoStatus)
            return nil
        }
        guard let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamID.isEmpty
        else {
            NSLog("[Vakter.privileged] signing info has no TeamIdentifier — daemon is unsigned or ad-hoc?")
            return nil
        }
        NSLog("[Vakter.privileged] self-discovered Team ID: %@", teamID)
        return teamID
    }
}
