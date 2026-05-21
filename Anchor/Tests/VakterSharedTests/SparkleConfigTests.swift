import Foundation
import XCTest

/// Smoke tests for Vakter's Sparkle 2 auto-update configuration.
///
/// We test two things, both at the file level:
///
///   1. The app's `Info.plist` declares the keys Sparkle reads
///      (`SUFeedURL`, `SUPublicEDKey`, the schedule, etc.). If a
///      developer accidentally removes one of these during a future
///      Info.plist edit, this test catches it before the build sandbox
///      ships an app that silently can't auto-update.
///   2. The static appcast feed (`Website/appcast.xml`) parses as
///      well-formed XML and contains at least one `<item>` referencing
///      the current shipped version. Saves us from pushing a
///      typo-broken appcast that breaks every existing user's update
///      check.
///
/// We deliberately don't `@testable import VakterApp` or instantiate
/// `SparkleConfig` against `Bundle.main` — when this test runs under
/// `swift test`, `Bundle.main` is the xctest harness, not the Vakter
/// app bundle. Reading from the source tree directly gives us the
/// same coverage with none of the Bundle.main brittleness.
final class SparkleConfigTests: XCTestCase {

    // MARK: Paths

    /// Locate the repo root by walking up from the test bundle until we
    /// find `Package.swift`. The xctest harness's working directory is
    /// unstable across local builds + CI, so we cannot just use `FileManager
    /// .default.currentDirectoryPath` — instead, anchor on the bundle.
    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        // #filePath points at this Swift file; walk up until we hit a
        // sibling Package.swift. The repo root is the dir that contains
        // Package.swift, Sources/, Tests/, etc.
        while dir.pathComponents.count > 1 {
            dir.deleteLastPathComponent()
            let manifest = dir.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return dir
            }
        }
        throw XCTSkip("Could not locate repo root from \(#filePath)")
    }

    // MARK: Info.plist coverage

    func test_appInfoPlist_containsAllSparkleKeys() throws {
        let root = try repoRoot()
        let plist = root.appendingPathComponent("Sources/VakterApp/Resources/Info.plist")
        let dict = try Self.readPlist(at: plist)

        // Required keys — if any of these go missing, Sparkle silently
        // can't auto-update and the user sees no signal in-app.
        let feed = dict["SUFeedURL"] as? String
        XCTAssertEqual(
            feed, "https://vakter.app/appcast.xml",
            "SUFeedURL must point at the production appcast (HTTPS, vakter.app)."
        )

        let publicKey = dict["SUPublicEDKey"] as? String
        XCTAssertNotNil(publicKey, "SUPublicEDKey is required for Sparkle 2 — Sparkle refuses to launch without it.")
        XCTAssertFalse(
            (publicKey ?? "").isEmpty,
            "SUPublicEDKey must not be empty."
        )

        // The placeholder is acceptable during initial setup but should
        // never ship to users. We assert the key is PRESENT here; a
        // separate ship-gate check (release-warden's `verify_release`
        // script) catches the placeholder before the DMG is built.
        if publicKey == "PLACEHOLDER_PUBLIC_KEY_RUN_GENERATE_KEYS_FIRST" {
            // Emit a warning-style message in the test output. Not a
            // failure — release-warden flags it at ship time.
            NSLog("[SparkleConfigTests] SUPublicEDKey is still the placeholder. Run generate_keys before the first release. See SPARKLE_SETUP.md §2.")
        }

        // Schedule / behaviour keys.
        if let auto = dict["SUEnableAutomaticChecks"] as? Bool {
            XCTAssertTrue(auto, "Default-on for automatic checks is intentional — users can disable in Settings.")
        } else {
            XCTFail("SUEnableAutomaticChecks must be a Boolean.")
        }

        if let interval = dict["SUScheduledCheckInterval"] as? NSNumber {
            XCTAssertEqual(interval.intValue, 86_400, "Daily background checks.")
        } else {
            XCTFail("SUScheduledCheckInterval must be an integer (seconds).")
        }

        // Be conservative on automatic INSTALL — a security tool should
        // never mutate itself without user consent.
        if let autoApply = dict["SUEnableAutomaticUpdates"] as? Bool {
            XCTAssertFalse(autoApply, "SUEnableAutomaticUpdates must be false — user must always click Install.")
        } else {
            XCTFail("SUEnableAutomaticUpdates must be a Boolean.")
        }

        // Release-note rendering — without this Sparkle shows version
        // + size only, which gives users no reason to install.
        if let notes = dict["SUEnableDownloadedReleaseNotes"] as? Bool {
            XCTAssertTrue(notes, "Release notes must be enabled so the user sees the changelog in the update prompt.")
        }
    }

    /// SUFeedURL must be HTTPS. Sparkle 2 rejects plain http feeds
    /// outright, but the codebase should also refuse to ship a non-
    /// HTTPS URL — reviewers + security-conscious buyers will inspect
    /// this field in the shipped binary.
    func test_appInfoPlist_feedURLisHTTPS() throws {
        let root = try repoRoot()
        let plist = root.appendingPathComponent("Sources/VakterApp/Resources/Info.plist")
        let dict = try Self.readPlist(at: plist)
        let feedString = dict["SUFeedURL"] as? String
        XCTAssertNotNil(feedString)
        let url = feedString.flatMap(URL.init(string:))
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "https",
                       "SUFeedURL must be HTTPS. Plain http exposes users to MITM-injected fake updates.")
    }

    // MARK: appcast.xml coverage

    func test_appcast_isWellFormedXML() throws {
        let root = try repoRoot()
        let appcast = root.appendingPathComponent("Website/appcast.xml")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: appcast.path),
            "Website/appcast.xml must exist — it's the feed Sparkle reads."
        )

        let data = try Data(contentsOf: appcast)
        // XMLParser is a well-formedness check; the parser only fails
        // for malformed XML. We don't care about the parsed nodes here,
        // just that it parses end-to-end.
        let parser = XMLParser(data: data)
        let ok = parser.parse()
        if !ok, let err = parser.parserError {
            XCTFail("appcast.xml is malformed: \(err.localizedDescription)")
        }
    }

    func test_appcast_referencesCurrentVersion() throws {
        let root = try repoRoot()
        let appcast = root.appendingPathComponent("Website/appcast.xml")
        let xml = try String(contentsOf: appcast, encoding: .utf8)

        // Cross-check the appcast version against the Info.plist version.
        // If a developer bumps Info.plist but forgets the appcast (a real
        // mistake we want to prevent), this fires.
        let plist = root.appendingPathComponent("Sources/VakterApp/Resources/Info.plist")
        let dict = try Self.readPlist(at: plist)
        let shortVersion = dict["CFBundleShortVersionString"] as? String ?? ""
        XCTAssertFalse(shortVersion.isEmpty)

        // Match `<sparkle:shortVersionString>X.Y.Z</…>` OR the same as
        // an enclosure attribute `sparkle:shortVersionString="X.Y.Z"`.
        // Either form is valid Sparkle 2 — the binary attribute is the
        // newer style.
        XCTAssertTrue(
            xml.contains(">\(shortVersion)<") || xml.contains("\"\(shortVersion)\""),
            "Website/appcast.xml must reference the current shipped version (\(shortVersion))."
        )
    }

    // MARK: Helpers

    private static func readPlist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = parsed as? [String: Any] else {
            throw NSError(
                domain: "SparkleConfigTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Plist root is not a dict: \(url.path)"]
            )
        }
        return dict
    }
}
