import Foundation
import CoreLocation

/// What Vakter ships off-Mac when an alarm fires.
///
/// The whole point of v0.9: previously Vakter just made noise locally
/// and wrote photos to a directory the owner couldn't access if the
/// Mac was stolen. Now the photos, location, and a human-readable
/// summary reach the owner's iPhone within ~10 s of the alarm
/// triggering, via iMessage. Whoever has the Mac doesn't know.
public struct EvidenceBundle: Sendable {
    public let timestamp: Date
    /// Localised one-line summary of what made the alarm fire.
    /// Already translated via `LocalePhrases`. e.g. "Find My was
    /// disabled while Vakter was armed."
    public let reasonLine: String
    public let mode: VakterMode
    public let photoURLs: [URL]
    /// Fresh location, if a `LocationProbe` succeeded within ~10 s.
    public let location: CLLocationCoordinate2D?
    /// Most-recent cached location, used as a fallback if the current
    /// probe timed out (e.g. thief disabled Wi-Fi). Pair with
    /// `lastKnownLocationAge` so the recipient knows how stale it is.
    public let lastKnownLocation: CLLocationCoordinate2D?
    public let lastKnownLocationAge: TimeInterval?
    public let locale: Locale

    public init(
        timestamp: Date = Date(),
        reasonLine: String,
        mode: VakterMode,
        photoURLs: [URL],
        location: CLLocationCoordinate2D? = nil,
        lastKnownLocation: CLLocationCoordinate2D? = nil,
        lastKnownLocationAge: TimeInterval? = nil,
        locale: Locale = .current
    ) {
        self.timestamp = timestamp
        self.reasonLine = reasonLine
        self.mode = mode
        self.photoURLs = photoURLs
        self.location = location
        self.lastKnownLocation = lastKnownLocation
        self.lastKnownLocationAge = lastKnownLocationAge
        self.locale = locale
    }
}

/// Abstraction over the actual delivery channel so the state machine
/// can be tested with a mock. v0.9 ships exactly one implementation
/// (iMessage); v1.0+ may add Mail and iCloud Drive.
public protocol EvidenceDelivering: Sendable {
    /// Send the bundle to `recipient`. Returns `.success` if the
    /// underlying transport (osascript, etc.) reported a clean handoff.
    /// Does NOT verify the recipient actually received it — Messages.app
    /// handles its own queueing.
    func deliver(_ bundle: EvidenceBundle,
                 to recipient: EvidenceRecipient) async -> Result<Void, Error>
}

/// Errors surface to the caller for log + Settings "Last delivery"
/// status. Never thrown to end-user UI in a panic flow.
public enum EvidenceDeliveryError: Error, LocalizedError {
    case scriptWriteFailed(underlying: Error)
    case osascriptNonZeroExit(code: Int32, stderr: String)
    case osascriptNotFound

    public var errorDescription: String? {
        switch self {
        case .scriptWriteFailed(let e):
            return "Couldn't write AppleScript: \(e.localizedDescription)"
        case .osascriptNonZeroExit(let code, let err):
            return "osascript exited \(code): \(err)"
        case .osascriptNotFound:
            return "/usr/bin/osascript not found"
        }
    }
}

/// Production delivery via Messages.app + osascript.
///
/// **TCC**: the binary that *invokes* osascript is the one that needs
/// Automation consent (System Settings → Privacy → Automation →
/// <binary> → Messages). Vakter's onboarding fires a one-shot
/// "Send test" from the menubar app to claim the consent there; the
/// helper inherits via shared signing identity.
public final class iMessageEvidenceDelivery: EvidenceDelivering, @unchecked Sendable {

    public init() {}

    public func deliver(_ bundle: EvidenceBundle,
                        to recipient: EvidenceRecipient) async -> Result<Void, Error> {
        let osascript = URL(fileURLWithPath: "/usr/bin/osascript")
        guard FileManager.default.isExecutableFile(atPath: osascript.path) else {
            return .failure(EvidenceDeliveryError.osascriptNotFound)
        }

        // Build the full message body + paths to attach.
        let body = renderBody(bundle)
        let scriptPath: URL
        do {
            scriptPath = try writeScript(body: body,
                                         photoURLs: bundle.photoURLs,
                                         recipient: recipient.handle)
        } catch {
            return .failure(EvidenceDeliveryError.scriptWriteFailed(underlying: error))
        }
        defer { try? FileManager.default.removeItem(at: scriptPath) }

        // Run osascript as a child process. Bounded to 20 s — Messages
        // is usually instant but iMessage delivery to a not-yet-reachable
        // device can take a few seconds.
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

    // MARK: - Internals (also called by tests via @testable)

    /// Render the iMessage body. Public-for-tests so we can verify the
    /// composition independently of the osascript invocation.
    public func renderBody(_ bundle: EvidenceBundle) -> String {
        let header   = LocalePhrases.text(.evidenceMessageHeader, locale: bundle.locale)
        let footer   = LocalePhrases.text(.evidenceFooter,        locale: bundle.locale)

        let dateFmt = DateFormatter()
        dateFmt.locale = bundle.locale
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .short
        let ts = dateFmt.string(from: bundle.timestamp)

        let locationLine: String
        if let coord = bundle.location {
            locationLine = LocalePhrases.text(
                .evidenceLocationLine,
                locale: bundle.locale,
                substitutions: ["maps_url": mapsURL(for: coord)]
            )
        } else if let coord = bundle.lastKnownLocation {
            let age = Int((bundle.lastKnownLocationAge ?? 0) / 60)
            locationLine = LocalePhrases.text(
                .evidenceLastKnownLocationLine,
                locale: bundle.locale,
                substitutions: [
                    "maps_url":    mapsURL(for: coord),
                    "age_minutes": String(age),
                ]
            )
        } else {
            locationLine = LocalePhrases.text(.evidenceLocationUnavailable,
                                              locale: bundle.locale)
        }

        return [
            header,
            "",
            ts,
            bundle.reasonLine,
            locationLine,
            "",
            footer,
        ].joined(separator: "\n")
    }

    /// Build an Apple Maps web URL with a pin at the coordinate.
    /// Maps.app on the receiving iPhone deeplinks this automatically.
    public func mapsURL(for coord: CLLocationCoordinate2D) -> String {
        let lat = String(format: "%.6f", coord.latitude)
        let lon = String(format: "%.6f", coord.longitude)
        return "https://maps.apple.com/?ll=\(lat),\(lon)&q=Vakter+alert"
    }

    /// Build the AppleScript file Vakter executes via osascript.
    /// Public-for-tests so we can verify the script structure
    /// without actually sending an iMessage.
    public func writeScript(body: String,
                            photoURLs: [URL],
                            recipient: String) throws -> URL {
        let dir = VakterConstants.supportDirectoryURL
            .appendingPathComponent("evidence-scripts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let scriptURL = dir.appendingPathComponent("evidence-\(UUID().uuidString).applescript")

        // AppleScript string escaping: backslash + quote are the
        // dangerous characters in `"..."` literals. Backslash first.
        let escapedBody = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedRecipient = recipient
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        var lines: [String] = [
            "tell application \"Messages\"",
            "    set targetService to 1st service whose service type = iMessage",
            "    set targetBuddy to buddy \"\(escapedRecipient)\" of targetService",
            "    send \"\(escapedBody)\" to targetBuddy",
        ]
        for url in photoURLs {
            // POSIX file accepts forward-slash paths verbatim.
            let escapedPath = url.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            lines.append("    send (POSIX file \"\(escapedPath)\") to targetBuddy")
        }
        lines.append("end tell")

        try lines.joined(separator: "\n")
            .write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }
}
