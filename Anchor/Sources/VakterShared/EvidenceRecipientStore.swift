import Foundation

/// Persisted iMessage recipient for evidence delivery — the phone
/// number or Apple-ID email Vakter sends the photo burst + Maps URL
/// to when an alarm fires.
///
/// Stored as a tiny JSON blob in
/// `~/Library/Application Support/Vakter/evidence-recipient.json`
/// so both the menubar app (writes from Settings) and the helper
/// (reads at alarm time) see the same value. Same pattern as
/// `HotkeyStore` — avoids needing an app-group or XPC roundtrip.
///
/// Recipient is optional. If unset, evidence delivery is silently
/// skipped (photos still land locally, event log still records).
public struct EvidenceRecipient: Codable, Sendable, Equatable {
    /// Free-form handle: a phone number (E.164 preferred,
    /// e.g. "+14155551212") or an iMessage-registered email.
    /// Messages.app does its own resolution; we don't validate
    /// beyond non-empty.
    public var handle: String

    public init(handle: String) {
        self.handle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValid: Bool { !handle.isEmpty }
}

public enum EvidenceRecipientStore {

    private static var fileURL: URL {
        VakterConstants.supportDirectoryURL
            .appendingPathComponent("evidence-recipient.json")
    }

    /// Returns the stored recipient, or nil if none has been set.
    public static func load() -> EvidenceRecipient? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let recipient = try? JSONDecoder().decode(EvidenceRecipient.self, from: data)
        return recipient?.isValid == true ? recipient : nil
    }

    /// Persist a recipient. Pass `nil` to clear.
    public static func save(_ recipient: EvidenceRecipient?) {
        let fm = FileManager.default
        try? fm.createDirectory(at: VakterConstants.supportDirectoryURL,
                                withIntermediateDirectories: true)

        guard let recipient = recipient, recipient.isValid else {
            try? fm.removeItem(at: fileURL)
            return
        }
        guard let data = try? JSONEncoder().encode(recipient) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
