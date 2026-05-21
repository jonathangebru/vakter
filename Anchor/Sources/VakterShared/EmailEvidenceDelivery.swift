import Foundation

/// Off-Mac evidence delivery via macOS Mail.app + AppleScript.
///
/// Multi-channel redundancy: if iMessage delivery fails (recipient
/// offline, Messages.app misconfigured, Automation consent revoked),
/// email gets through anyway. Reaches Android phones too, which
/// `iMessageEvidenceDelivery` cannot.
///
/// **Why not SMTP / URLSession?** Two reasons:
///   1. We'd need the user to expose an SMTP password to Vakter. The
///      iMessage path uses the user's already-signed-in Messages.app
///      identity; the email path uses the user's already-signed-in
///      Mail.app account. No new credentials to manage.
///   2. Going through Mail.app means the sent message lands in the
///      user's Sent folder — useful evidence chain.
///
/// **TCC**: same Automation consent dance as iMessage. The first
/// "Send test" from Settings claims the consent on the binary that
/// invokes osascript.
public final class EmailEvidenceDelivery: EvidenceDelivering, @unchecked Sendable {

    /// Optional Reply-To header. Useful so the recipient can hit
    /// "reply" and reach a friend / lawyer / IT contact rather than
    /// the stolen Mac's own outbox.
    public let replyTo: String?

    public init(replyTo: String? = nil) {
        self.replyTo = replyTo
    }

    public func deliver(_ bundle: EvidenceBundle,
                        to recipient: EvidenceRecipient) async -> Result<Void, Error> {
        let osascript = URL(fileURLWithPath: "/usr/bin/osascript")
        guard FileManager.default.isExecutableFile(atPath: osascript.path) else {
            return .failure(EvidenceDeliveryError.osascriptNotFound)
        }

        let body = renderBody(bundle)
        let subject = subjectLine(bundle)
        let scriptPath: URL
        do {
            scriptPath = try writeScript(
                subject: subject,
                body: body,
                photoURLs: bundle.photoURLs,
                recipient: recipient.handle,
                replyTo: replyTo
            )
        } catch {
            return .failure(EvidenceDeliveryError.scriptWriteFailed(underlying: error))
        }
        defer { try? FileManager.default.removeItem(at: scriptPath) }

        let p = Process()
        p.executableURL = osascript
        p.arguments = [scriptPath.path]
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        do {
            try p.run()
        } catch {
            return .failure(EvidenceDeliveryError.osascriptNonZeroExit(
                code: -1, stderr: error.localizedDescription))
        }
        p.waitUntilExit()

        if p.terminationStatus != 0 {
            let errText = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            return .failure(EvidenceDeliveryError.osascriptNonZeroExit(
                code: p.terminationStatus, stderr: errText))
        }
        return .success(())
    }

    // MARK: - Body composition (public-for-tests)

    public func subjectLine(_ bundle: EvidenceBundle) -> String {
        // Plain ASCII subject — email gateways mangle anything fancier.
        "Vakter alert — your Mac"
    }

    public func renderBody(_ bundle: EvidenceBundle) -> String {
        // Reuse the iMessage body — same information, same locale logic.
        // Keeps the two channels saying the same thing.
        iMessageEvidenceDelivery().renderBody(bundle)
    }

    /// Build an AppleScript that drives Mail.app to compose + send.
    /// Public-for-tests so we can verify the script structure.
    public func writeScript(
        subject: String,
        body: String,
        photoURLs: [URL],
        recipient: String,
        replyTo: String?
    ) throws -> URL {
        let dir = VakterConstants.supportDirectoryURL
            .appendingPathComponent("evidence-scripts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let scriptURL = dir.appendingPathComponent("email-\(UUID().uuidString).applescript")

        let escapedBody = escape(body)
        let escapedSubject = escape(subject)
        let escapedRecipient = escape(recipient)
        let escapedReplyTo = replyTo.map(escape)

        var lines: [String] = [
            "tell application \"Mail\"",
            "    set newMessage to make new outgoing message with properties " +
            "{subject:\"\(escapedSubject)\", content:\"\(escapedBody)\", visible:false}",
            "    tell newMessage",
            "        make new to recipient at end of to recipients " +
            "with properties {address:\"\(escapedRecipient)\"}",
        ]
        if let rt = escapedReplyTo {
            lines.append("        set reply to to \"\(rt)\"")
        }
        for url in photoURLs {
            let escapedPath = escape(url.path)
            lines.append(
                "        tell content to make new attachment " +
                "with properties {file name:(POSIX file \"\(escapedPath)\")} " +
                "at after the last paragraph"
            )
        }
        lines.append("        send")
        lines.append("    end tell")
        lines.append("end tell")

        try lines.joined(separator: "\n")
            .write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
