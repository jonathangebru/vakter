import Foundation

/// Wire format for events Vakter publishes to the user's private
/// CloudKit database, then read back on iPhone + Apple Watch.
///
/// **Why CloudKit, not our own server?**
///   - Zero server cost to us — each user pays their own iCloud quota
///   - End-to-end encrypted in transit (CloudKit handles it)
///   - Apple-id-scoped: data only ever flows between the same user's
///     own devices, never leaves their Apple account
///   - Push notifications come "free" via CloudKit subscriptions
///   - No accounts to manage on our side, no telemetry possible
///
/// **What we publish.** A compact JSON-equivalent of `VakterEvent`,
/// flattened so it fits the CloudKit field-type constraints (no
/// nested arrays of arbitrary types; everything is a string, number,
/// date, or single-value reference). The original event chain still
/// lives on disk; CloudKit is the *transport*, not the source of truth.
///
/// **What we don't publish.** Photos and audio attachments stay in the
/// cloud-evidence bucket (Backblaze B2 or pre-signed URL, configured
/// in Settings → Auto-arm & Cloud). CloudKit carries pointers
/// (`cloudEvidenceURLs`) so the iPhone can fetch them on demand.
public struct CloudKitEventRecord: Codable, Sendable, Identifiable, Equatable {

    public let id: String              // matches VakterEvent.id.uuidString
    public let timestamp: Date
    public let fromState: String
    public let toState: String
    public let trigger: String?
    public let mode: String
    public let deviceName: String
    public let deviceSerial: String?

    public let photoFilenames: [String]
    public let audioFilenames: [String]
    public let locationLat: Double?
    public let locationLon: Double?
    public let eventHash: String?
    public let previousEventHash: String?

    /// URLs (or B2 paths) where photo + audio attachments live in the
    /// user's evidence bucket. iPhone can hit these directly.
    public let cloudEvidenceURLs: [String]

    public init(
        id: String,
        timestamp: Date,
        fromState: String,
        toState: String,
        trigger: String?,
        mode: String,
        deviceName: String,
        deviceSerial: String?,
        photoFilenames: [String],
        audioFilenames: [String],
        locationLat: Double?,
        locationLon: Double?,
        eventHash: String?,
        previousEventHash: String?,
        cloudEvidenceURLs: [String]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.fromState = fromState
        self.toState = toState
        self.trigger = trigger
        self.mode = mode
        self.deviceName = deviceName
        self.deviceSerial = deviceSerial
        self.photoFilenames = photoFilenames
        self.audioFilenames = audioFilenames
        self.locationLat = locationLat
        self.locationLon = locationLon
        self.eventHash = eventHash
        self.previousEventHash = previousEventHash
        self.cloudEvidenceURLs = cloudEvidenceURLs
    }

    /// Build from a `VakterEvent` + device metadata. The Mac side does
    /// this; the mobile side decodes directly via Codable.
    public static func from(
        event: VakterEvent,
        deviceName: String,
        deviceSerial: String?,
        cloudEvidenceURLs: [String] = []
    ) -> CloudKitEventRecord {
        CloudKitEventRecord(
            id: event.id.uuidString,
            timestamp: event.timestamp,
            fromState: event.fromState.rawValue,
            toState: event.toState.rawValue,
            trigger: event.trigger?.rawValue,
            mode: event.modeAtEvent.rawValue,
            deviceName: deviceName,
            deviceSerial: deviceSerial,
            photoFilenames: event.photoFilenames,
            audioFilenames: event.audioFilenames ?? [],
            locationLat: event.locationLat,
            locationLon: event.locationLon,
            eventHash: event.eventHash,
            previousEventHash: event.previousEventHash,
            cloudEvidenceURLs: cloudEvidenceURLs
        )
    }
}

/// CloudKit container + record-type constants shared by all three apps.
public enum CloudKitConstants {

    /// The iCloud container ID. Must match across Mac app, iOS app,
    /// and Watch app entitlements. Configure in Developer Portal →
    /// Identifiers → iCloud Containers.
    public static let containerID = "iCloud.app.vakter.shared"

    /// The CKRecord type for `CloudKitEventRecord`. CloudKit Dashboard
    /// schema: see `iOS/SETUP.md` for the field definitions.
    public static let eventRecordType = "VakterEvent"

    /// The CKRecord type used to publish the helper's current state
    /// (one record per Mac, updated on every snapshot change). The
    /// iPhone subscribes to this so the home screen reflects the Mac's
    /// state in near real time.
    public static let snapshotRecordType = "VakterSnapshot"
}
