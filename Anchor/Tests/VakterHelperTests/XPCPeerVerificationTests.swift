import XCTest
@testable import VakterHelper

/// Verifies the code-signing requirement string format used to pin XPC
/// peers to our Developer ID Team ID.
///
/// The full peer-verification path can't be exercised in unit tests
/// (it requires a real signed binary and an `NSXPCConnection`), but the
/// requirement string is a pure function of the Team ID and must match
/// the format Apple's `csreq` tool accepts:
///
///     anchor apple generic and certificate leaf[subject.OU] = "TEAMID"
final class XPCPeerVerificationTests: XCTestCase {

    func test_requirementString_pinsCorrectTeamID() {
        let req = XPCPeerVerification.requirementString(forTeamID: "9TA5GB5UJH")
        XCTAssertEqual(
            req,
            "anchor apple generic and certificate leaf[subject.OU] = \"9TA5GB5UJH\""
        )
    }

    /// Sanity: changing the team ID changes the requirement.
    func test_requirementString_isPerTeamID() {
        let a = XPCPeerVerification.requirementString(forTeamID: "AAAAAAAAAA")
        let b = XPCPeerVerification.requirementString(forTeamID: "BBBBBBBBBB")
        XCTAssertNotEqual(a, b)
    }

    /// Requirement must anchor to Apple-issued certs (not self-signed),
    /// which is what `anchor apple generic` enforces.
    func test_requirementString_anchorsToAppleGeneric() {
        let req = XPCPeerVerification.requirementString(forTeamID: "TEST")
        XCTAssertTrue(req.contains("anchor apple generic"),
                      "requirement must reject self-signed peers")
    }
}
