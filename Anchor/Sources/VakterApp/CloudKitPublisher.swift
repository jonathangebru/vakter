import Foundation
import CloudKit
import VakterShared

/// Publishes Vakter events + state-machine snapshots to the user's
/// private CloudKit database so the iPhone companion app and Apple
/// Watch app can read them.
///
/// **Lifecycle.** Owned by `AppDelegate`; instantiated once. Subscribes
/// to the helper's snapshot stream via the existing `HelperClient`
/// callback. On each snapshot push it publishes a `VakterSnapshot`
/// record (overwriting the prior one — there's exactly one per Mac).
/// Separately, on every `lastEvent` change it appends a new
/// `VakterEvent` record.
///
/// **What if iCloud isn't configured?** Two distinct failure modes:
///
///   1. **No entitlement** (dev build, not yet provisioned in Developer
///      Portal). `CKContainer(identifier:)` hard-crashes with
///      EXC_BREAKPOINT — Swift cannot catch this. We use the failable
///      initialiser below + `EntitlementProbe` to detect this *before*
///      calling CloudKit, so the app boots cleanly.
///
///   2. **Entitlement present but user not signed into iCloud.** Safe —
///      `accountStatus()` returns `.noAccount` and we skip the publish.
///
/// **Entitlements required (see `iOS/SETUP.md`):**
///   - `com.apple.developer.icloud-container-identifiers`
///   - `com.apple.developer.icloud-services` = `["CloudKit"]`
///   - matching container ID in the iOS app + Watch app
@MainActor
final class CloudKitPublisher {

    private let container: CKContainer
    private let privateDB: CKDatabase
    private var lastPublishedEventID: String?
    private var lastPublishedState: String?

    /// Deduplication window for snapshot publishes — CloudKit charges
    /// quota per write, so we don't push every duplicate snapshot.
    private static let snapshotDedupWindow: TimeInterval = 5.0
    private var lastSnapshotPublish: Date = .distantPast

    /// Failable initialiser. Returns `nil` when the iCloud entitlement
    /// isn't present in the binary — which prevents the fatal
    /// `CKContainer(identifier:)` EXC_BREAKPOINT crash on dev builds.
    /// Callers should treat a `nil` result as "iCloud disabled" and
    /// continue running the app normally.
    init?(containerID: String = CloudKitConstants.containerID) {
        guard EntitlementProbe.hasICloudContainer(containerID) else {
            NSLog("[CloudKitPublisher] iCloud entitlement absent for '%@' — publisher disabled. " +
                  "Add the entitlement and provision the container per iOS/SETUP.md.",
                  containerID)
            return nil
        }
        self.container = CKContainer(identifier: containerID)
        self.privateDB = container.privateCloudDatabase
    }

    // MARK: - Snapshot publishing

    /// Called on every helper snapshot push. Idempotent — repeated
    /// snapshots with the same state don't re-publish.
    func publish(snapshot: VakterSnapshot) {
        // Dedup: state hasn't changed AND we published recently.
        let stateChanged = snapshot.state.rawValue != lastPublishedState
        let recent = Date().timeIntervalSince(lastSnapshotPublish) < Self.snapshotDedupWindow
        if !stateChanged && recent { return }

        Task { [weak self] in
            await self?.doPublish(snapshot: snapshot)
        }

        // Also publish a new event row if the lastEvent has changed.
        if let event = snapshot.lastEvent,
           event.id.uuidString != lastPublishedEventID {
            lastPublishedEventID = event.id.uuidString
            Task { [weak self] in
                await self?.doPublish(event: event)
            }
        }
    }

    private func doPublish(snapshot: VakterSnapshot) async {
        guard await iCloudAvailable() else { return }

        let recordID = CKRecord.ID(recordName: deviceName())
        let record = CKRecord(recordType: CloudKitConstants.snapshotRecordType,
                              recordID: recordID)
        record["state"] = snapshot.state.rawValue as NSString
        record["mode"] = snapshot.mode.rawValue as NSString
        record["deviceName"] = deviceName() as NSString
        record["updatedAt"] = Date() as NSDate
        if let exp = snapshot.loanerExpiresAt {
            record["loanerExpiresAt"] = exp as NSDate
        }

        do {
            // Save with overwrite policy: the same recordID always
            // refers to *this* Mac's current snapshot. iPhone sees the
            // latest by reading that one record ID.
            _ = try await privateDB.save(record)
            lastPublishedState = snapshot.state.rawValue
            lastSnapshotPublish = Date()
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Concurrent update — refetch + retry once.
            await retrySaveAfterServerChange(record)
        } catch {
            NSLog("[CloudKitPublisher] snapshot save failed: %@",
                  error.localizedDescription)
        }
    }

    private func doPublish(event: VakterEvent) async {
        guard await iCloudAvailable() else { return }

        let record = CKRecord(
            recordType: CloudKitConstants.eventRecordType,
            recordID: CKRecord.ID(recordName: event.id.uuidString)
        )
        // Flatten VakterEvent into CKRecord fields. The
        // `CloudKitEventRecord` Codable struct mirrors these field
        // names so the iOS app can decode them with a fixed key set.
        record["timestamp"] = event.timestamp as NSDate
        record["fromState"] = event.fromState.rawValue as NSString
        record["toState"]   = event.toState.rawValue as NSString
        record["mode"]      = event.modeAtEvent.rawValue as NSString
        record["deviceName"] = deviceName() as NSString
        if let trigger = event.trigger {
            record["trigger"] = trigger.rawValue as NSString
        }
        record["photoFilenames"] = event.photoFilenames as NSArray
        if let audio = event.audioFilenames {
            record["audioFilenames"] = audio as NSArray
        }
        if let lat = event.locationLat, let lon = event.locationLon {
            record["locationLat"] = lat as NSNumber
            record["locationLon"] = lon as NSNumber
        }
        if let hash = event.eventHash {
            record["eventHash"] = hash as NSString
        }
        if let prev = event.previousEventHash {
            record["previousEventHash"] = prev as NSString
        }

        do {
            _ = try await privateDB.save(record)
        } catch {
            NSLog("[CloudKitPublisher] event save failed: %@",
                  error.localizedDescription)
        }
    }

    private func retrySaveAfterServerChange(_ record: CKRecord) async {
        // The snapshot record uses last-write-wins. Refetch to grab the
        // current change tag, then re-save our values onto it.
        do {
            let existing = try await privateDB.record(for: record.recordID)
            for key in record.allKeys() {
                existing[key] = record[key]
            }
            _ = try await privateDB.save(existing)
        } catch {
            NSLog("[CloudKitPublisher] retry save failed: %@",
                  error.localizedDescription)
        }
    }

    // MARK: - Availability check

    /// `true` if the user is signed into iCloud + Vakter has the
    /// required entitlement. Wraps `CKContainer.accountStatus` in a
    /// nice-to-use async form.
    private func iCloudAvailable() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    private func deviceName() -> String {
        Host.current().localizedName ?? "Mac"
    }
}
