import Foundation
import CloudKit
import WatchConnectivity
import Combine

/// Single source of truth for the iPhone companion + Apple Watch.
///
/// Owns:
///   - the CloudKit connection (read snapshots + events from the Mac)
///   - the WatchConnectivity session (mirror state to the Watch)
///   - the local view-model state (current snapshot, recent events)
///
/// Two ways state changes:
///   1. CloudKit silent push lands → re-fetch snapshot + recent events
///   2. User taps Arm/Disarm → writes a `VakterCommand` record →
///      the Mac picks it up via its own CloudKit subscription
@MainActor
final class CompanionStore: NSObject, ObservableObject {

    @Published var snapshot: CompanionSnapshot?
    @Published var recentEvents: [CompanionEvent] = []
    @Published var iCloudAvailable: Bool = false
    @Published var lastSyncError: String?

    private let container = CKContainer(identifier: "iCloud.app.vakter.shared")
    private var watchSession: WCSession?

    // MARK: - Bootstrap

    func bootstrap() async {
        await checkICloud()
        await refreshAll()
        startWatchConnectivity()
        // CloudKit silent push subscription — wired in iOS app setup
        // doc (Info.plist + entitlement). The notification handler
        // calls `refreshAll()` whenever a push lands.
    }

    func refreshAll() async {
        async let snap = fetchLatestSnapshot()
        async let events = fetchRecentEvents()
        self.snapshot = await snap
        self.recentEvents = await events
        forwardToWatch()
    }

    // MARK: - iCloud availability

    private func checkICloud() async {
        do {
            let status = try await container.accountStatus()
            iCloudAvailable = (status == .available)
        } catch {
            iCloudAvailable = false
            lastSyncError = error.localizedDescription
        }
    }

    // MARK: - CloudKit fetch

    private func fetchLatestSnapshot() async -> CompanionSnapshot? {
        // One record per Mac. For v1.4 we assume a single Mac; v1.5
        // multi-Mac coordination iterates over all snapshot records.
        let query = CKQuery(
            recordType: "VakterSnapshot",
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [
            NSSortDescriptor(key: "updatedAt", ascending: false)
        ]
        do {
            let (results, _) = try await container.privateCloudDatabase
                .records(matching: query, resultsLimit: 1)
            guard let first = results.first else { return nil }
            let record = try first.1.get()
            return CompanionSnapshot(record: record)
        } catch {
            lastSyncError = error.localizedDescription
            return nil
        }
    }

    private func fetchRecentEvents() async -> [CompanionEvent] {
        let query = CKQuery(
            recordType: "VakterEvent",
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [
            NSSortDescriptor(key: "timestamp", ascending: false)
        ]
        do {
            let (results, _) = try await container.privateCloudDatabase
                .records(matching: query, resultsLimit: 50)
            return results.compactMap { try? CompanionEvent(record: $0.1.get()) }
        } catch {
            lastSyncError = error.localizedDescription
            return []
        }
    }

    // MARK: - Remote arm/disarm

    func sendArm() async {
        await sendCommand(action: "arm")
    }

    func sendDisarm() async {
        await sendCommand(action: "disarm")
    }

    private func sendCommand(action: String) async {
        // Each command is a fresh record so the Mac sees the order of
        // requests. Mac processes + deletes on its side.
        let record = CKRecord(recordType: "VakterCommand")
        record["action"] = action as NSString
        record["issuedAt"] = Date() as NSDate
        record["origin"]  = "iPhone" as NSString
        do {
            _ = try await container.privateCloudDatabase.save(record)
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    // MARK: - WatchConnectivity

    private func startWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        watchSession = session
    }

    private func forwardToWatch() {
        guard let session = watchSession,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return }
        let payload: [String: Any] = [
            "state":    snapshot?.state ?? "unknown",
            "mode":     snapshot?.mode ?? "—",
            "lastEventAt": snapshot?.updatedAt.timeIntervalSince1970 ?? 0
        ]
        try? session.updateApplicationContext(payload)
    }
}

// MARK: - WCSessionDelegate

extension CompanionStore: @preconcurrency WCSessionDelegate {

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // No-op — we lazily push state via updateApplicationContext.
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate immediately. Standard iOS pattern.
        WCSession.default.activate()
    }

    /// Watch asks for arm/disarm — we proxy to CloudKit.
    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard let action = message["action"] as? String else {
            replyHandler(["ok": false])
            return
        }
        Task { @MainActor [weak self] in
            if action == "arm"    { await self?.sendArm() }
            if action == "disarm" { await self?.sendDisarm() }
            replyHandler(["ok": true])
        }
    }
}

// MARK: - View models

/// Lightweight snapshot used by the iPhone screens. Built from CKRecord
/// fields; intentionally avoids importing VakterShared so the iOS app
/// has minimal SwiftPM coupling.
struct CompanionSnapshot: Equatable {
    let state: String
    let mode: String
    let deviceName: String
    let updatedAt: Date

    init(record: CKRecord) {
        self.state = record["state"] as? String ?? "unknown"
        self.mode = record["mode"] as? String ?? "—"
        self.deviceName = record["deviceName"] as? String ?? "Mac"
        self.updatedAt = record["updatedAt"] as? Date ?? .distantPast
    }
}

struct CompanionEvent: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let fromState: String
    let toState: String
    let trigger: String?
    let photoFilenames: [String]
    let audioFilenames: [String]
    let locationLat: Double?
    let locationLon: Double?

    init(record: CKRecord) throws {
        self.id = record.recordID.recordName
        self.timestamp = record["timestamp"] as? Date ?? .distantPast
        self.fromState = record["fromState"] as? String ?? "?"
        self.toState   = record["toState"] as? String ?? "?"
        self.trigger   = record["trigger"] as? String
        self.photoFilenames = record["photoFilenames"] as? [String] ?? []
        self.audioFilenames = record["audioFilenames"] as? [String] ?? []
        self.locationLat = record["locationLat"] as? Double
        self.locationLon = record["locationLon"] as? Double
    }
}
