import XCTest
@testable import VakterShared

/// Verifies the heuristics used to filter macOS-native crash files in
/// `~/Library/Logs/DiagnosticReports/` down to just our binaries.
final class CrashReportCollectorTests: XCTestCase {

    func test_isVakterProcess_matchesVakterBinaries() {
        XCTAssertTrue(CrashReportCollector.isVakterProcess(name: "Vakter-2026-05-15-120000.ips"))
        XCTAssertTrue(CrashReportCollector.isVakterProcess(name: "VakterHelper-2026-05-15.crash"))
        XCTAssertTrue(CrashReportCollector.isVakterProcess(name: "VakterPrivilegedDaemon-x.ips"))
    }

    func test_isVakterProcess_matchesLegacyAnchorBinaries() {
        // Defensive: pre-rebrand binaries on user disks.
        XCTAssertTrue(CrashReportCollector.isVakterProcess(name: "AnchorApp-2026-04-01.ips"))
        XCTAssertTrue(CrashReportCollector.isVakterProcess(name: "anchorhelper-stuff.crash"))
    }

    func test_isVakterProcess_rejectsUnrelatedBinaries() {
        XCTAssertFalse(CrashReportCollector.isVakterProcess(name: "Safari-2026-05-15.ips"))
        XCTAssertFalse(CrashReportCollector.isVakterProcess(name: "Spotify-x.crash"))
        XCTAssertFalse(CrashReportCollector.isVakterProcess(name: "kernel-x.ips"))
    }

    func test_processName_stripsTimestamp() {
        XCTAssertEqual(
            CrashReportCollector.processName(from: "VakterHelper-2026-05-15-120000-1.ips"),
            "VakterHelper"
        )
        XCTAssertEqual(
            CrashReportCollector.processName(from: "Vakter.crash"),
            "Vakter"
        )
    }

    /// Scanning a directory that doesn't exist must not crash; returns [].
    func test_recent_handlesMissingDirectory() {
        let nonexistent = URL(fileURLWithPath: "/tmp/vakter-does-not-exist-\(UUID().uuidString)")
        let results = CrashReportCollector.recent(limit: 10, in: nonexistent)
        XCTAssertTrue(results.isEmpty)
    }

    /// End-to-end: write two fake report files into a tmp dir, scan, see them.
    func test_recent_returnsNewestFirst() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(
            "vakter-crash-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let older = dir.appendingPathComponent("Vakter-old.ips")
        let newer = dir.appendingPathComponent("VakterHelper-new.ips")
        let unrelated = dir.appendingPathComponent("Safari-x.ips")
        try "older crash".data(using: .utf8)!.write(to: older)
        try "newer crash".data(using: .utf8)!.write(to: newer)
        try "unrelated".data(using: .utf8)!.write(to: unrelated)

        // Force a meaningful mtime ordering.
        try fm.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)],
            ofItemAtPath: older.path)

        let results = CrashReportCollector.recent(in: dir)
        XCTAssertEqual(results.count, 2, "Safari should be filtered out")
        XCTAssertEqual(results.first?.url.lastPathComponent, "VakterHelper-new.ips")
        XCTAssertEqual(results.last?.url.lastPathComponent, "Vakter-old.ips")
    }
}
