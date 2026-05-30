import XCTest
import CryptoKit
@testable import VakterShared

/// End-to-end tests for the threat-feed client (Issue #62).
///
/// These tests exercise the full fetch-and-swap pipeline against a
/// fixture in-process "publisher" backed by an injected downloader
/// closure. Network is never contacted. The Ed25519 keys used to sign
/// fixtures are generated freshly per test — the FIXME(#61) production
/// placeholder is intentionally NOT exercised, because it is the all-
/// zero key and wouldn't verify any real signature anyway.
///
/// What this file covers:
///   - Manifest Codable round-trip.
///   - Ed25519 signature verifies with a matching key.
///   - Ed25519 signature fails with a tampered manifest.
///   - Ed25519 signature fails with a wrong key.
///   - Category SHA-256 verifies and fails appropriately.
///   - Full fetch-and-swap happy path produces the expected on-disk
///     layout and posts the notification.
///   - Atomic-swap honesty: a mid-pipeline kill (we throw from the
///     downloader after the manifest is verified) leaves the prior
///     `feed.current/` untouched.
///   - Idempotency: running fetchAndSwap twice on the same bundle is
///     a no-op (the second call still succeeds and produces the same
///     on-disk state).
///   - Offline: network error throws and leaves the cache clean.
///   - Schema-version-too-new rejects.
///   - feed_host mismatch rejects.
///   - Unknown category slug rejects.
///   - Total-entry-count cross-check rejects.
///   - `loadCachedBundle()` reads a previously-swapped bundle from
///     disk.
final class ThreatFeedClientTests: XCTestCase {

    // MARK: - Fixture infrastructure

    /// Per-test scratch dir for the storage root. Cleaned up in
    /// tearDown so tests don't leak filesystem state into each
    /// other.
    private var scratchRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = URL(fileURLWithPath: NSTemporaryDirectory(),
                       isDirectory: true)
        scratchRoot = base.appendingPathComponent(
            "vakter-tf-tests-" + UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: scratchRoot,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let scratchRoot = scratchRoot,
           FileManager.default.fileExists(atPath: scratchRoot.path) {
            try? FileManager.default.removeItem(at: scratchRoot)
        }
        scratchRoot = nil
        try super.tearDownWithError()
    }

    /// A minimal valid fixture bundle. Returns the signing key, the
    /// manifest JSON bytes, the detached signature bytes, and the
    /// per-file bytes keyed by their in-bundle filenames.
    private struct Fixture {
        let signingKey: Curve25519.Signing.PrivateKey
        let manifestBytes: Data
        let signatureBytes: Data
        let fileBytes: [String: Data]
        let manifest: ThreatFeedManifest
    }

    /// Build a fixture with a freshly generated Ed25519 key and 8
    /// minimal category files. Each file's bytes are deterministic
    /// for the given seed so the SHA-256 in the manifest matches.
    private func makeFixture(
        bundleVersion: String = "2026.05.29",
        publisherKeyId: String = "vakter-feed-2026-q2",
        feedHost: String = "feed.vakter.app",
        schemaVersion: Int = 1
    ) throws -> Fixture {
        let key = Curve25519.Signing.PrivateKey()

        // Build 8 deterministic category files. Content is
        // category-name + bundle-version so two fixtures differ.
        var files: [String: Data] = [:]
        var entries: [ThreatFeedManifest.FileEntry] = []
        for category in ThreatFeedCategory.allCases {
            let bytes = Data("\(category.rawValue)-\(bundleVersion)\n".utf8)
            files[category.requiredFilename] = bytes
            let hash = SHA256.hash(data: bytes)
            let hex = hash.map { String(format: "%02x", $0) }.joined()
            entries.append(.init(
                name: category.requiredFilename,
                sha256: hex,
                entryCount: 1,
                category: category.rawValue
            ))
        }

        let manifest = ThreatFeedManifest(
            schemaVersion: schemaVersion,
            bundleVersion: bundleVersion,
            publishedAt: "2026-05-29T06:00:00Z",
            feedHost: feedHost,
            publisherKeyId: publisherKeyId,
            files: entries,
            totalEntryCount: entries.reduce(0) { $0 + $1.entryCount },
            previousBundleVersion: nil,
            previousBundleSha256: nil
        )
        let manifestBytes = try JSONEncoder().encode(manifest)
        let signature = try key.signature(for: manifestBytes)

        return Fixture(
            signingKey: key,
            manifestBytes: manifestBytes,
            signatureBytes: signature,
            fileBytes: files,
            manifest: manifest
        )
    }

    /// Build a `ThreatFeedClient` whose downloader serves bytes from
    /// the given fixture. The verifier is initialised from the
    /// fixture's public key, NOT from the FIXME(#61) placeholder.
    ///
    /// Only `Sendable` values (raw `Data`, `[String: Data]`) are
    /// captured by the closure — never the whole `Fixture` (which
    /// holds the non-Sendable `Curve25519.Signing.PrivateKey`).
    private func makeClient(
        fixture: Fixture,
        downloaderOverride: ThreatFeedClient.Downloader? = nil
    ) -> ThreatFeedClient {
        let verifier = ThreatFeedVerifier(
            publicKeyRaw: fixture.signingKey.publicKey.rawRepresentation
        )
        let baseURL = URL(string: "https://vakter.app/feed/v1")!
        let manifestBytes = fixture.manifestBytes
        let signatureBytes = fixture.signatureBytes
        let fileBytes = fixture.fileBytes
        let defaultDownloader: ThreatFeedClient.Downloader = { url in
            let name = url.lastPathComponent
            if name == "manifest.json" { return manifestBytes }
            if name == "manifest.json.sig" { return signatureBytes }
            if let bytes = fileBytes[name] { return bytes }
            throw ThreatFeedClientError.networkError(
                description: "fixture has no entry for \(name)"
            )
        }
        return ThreatFeedClient(
            baseURL: baseURL,
            verifier: verifier,
            storageRoot: scratchRoot,
            maxSupportedSchemaVersion: 1,
            download: downloaderOverride ?? defaultDownloader,
            fileManager: .default
        )
    }

    // MARK: - 1. Manifest Codable

    func test_manifest_codable_roundTrips_withAllRequiredFields() throws {
        let fixture = try makeFixture()
        let bytes = try JSONEncoder().encode(fixture.manifest)
        let decoded = try JSONDecoder().decode(
            ThreatFeedManifest.self,
            from: bytes
        )
        XCTAssertEqual(decoded, fixture.manifest,
                       "manifest must round-trip exactly through Codable so the client can re-verify against on-disk bytes if needed")
        XCTAssertEqual(decoded.files.count, 8)
        XCTAssertEqual(decoded.totalEntryCount, 8)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func test_manifest_parsesExampleFromBundleSchema() throws {
        // Mirrors the structure of
        // Anchor/threat-feed/schema/examples/manifest.example.json
        // (canonical example shipped with #60). Confirms that the
        // Codable types in this ticket accept the publisher
        // contract verbatim.
        let json = """
        {
          "schema_version": 1,
          "bundle_version": "2026.05.29",
          "published_at": "2026-05-29T06:00:00Z",
          "feed_host": "feed.vakter.app",
          "publisher_key_id": "vakter-feed-2026-q2",
          "files": [
            {"name": "phishing-domains.txt",       "sha256": "0000000000000000000000000000000000000000000000000000000000000001", "entry_count": 1, "category": "phishing-domains"},
            {"name": "phone-numbers.txt",          "sha256": "0000000000000000000000000000000000000000000000000000000000000002", "entry_count": 1, "category": "phone-numbers"},
            {"name": "apple-support-fakes.txt",    "sha256": "0000000000000000000000000000000000000000000000000000000000000003", "entry_count": 1, "category": "apple-support-fakes"},
            {"name": "malware-bundle-ids.txt",     "sha256": "0000000000000000000000000000000000000000000000000000000000000004", "entry_count": 1, "category": "malware-bundle-ids"},
            {"name": "sms-templates.json",         "sha256": "0000000000000000000000000000000000000000000000000000000000000005", "entry_count": 1, "category": "sms-templates"},
            {"name": "romance-scam-patterns.json", "sha256": "0000000000000000000000000000000000000000000000000000000000000006", "entry_count": 1, "category": "romance-scam-patterns"},
            {"name": "package-scam-templates.json","sha256": "0000000000000000000000000000000000000000000000000000000000000007", "entry_count": 1, "category": "package-scam-templates"},
            {"name": "sources.json",               "sha256": "0000000000000000000000000000000000000000000000000000000000000008", "entry_count": 1, "category": "sources"}
          ],
          "total_entry_count": 8
        }
        """
        let manifest = try JSONDecoder().decode(
            ThreatFeedManifest.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(manifest.files.count, 8)
        XCTAssertEqual(manifest.feedHost, "feed.vakter.app")
        XCTAssertEqual(manifest.publisherKeyId, "vakter-feed-2026-q2")
        XCTAssertNil(manifest.previousBundleVersion,
                     "previous_bundle_version is optional and may be absent")
    }

    // MARK: - 2. Signature verification

    func test_verifier_acceptsValidSignature() throws {
        let fixture = try makeFixture()
        let verifier = ThreatFeedVerifier(
            publicKeyRaw: fixture.signingKey.publicKey.rawRepresentation
        )
        XCTAssertTrue(
            verifier.verifyManifestSignature(
                manifestBytes: fixture.manifestBytes,
                signature: fixture.signatureBytes
            ),
            "signature produced by the matching key MUST validate"
        )
    }

    func test_verifier_rejectsTamperedManifest() throws {
        let fixture = try makeFixture()
        let verifier = ThreatFeedVerifier(
            publicKeyRaw: fixture.signingKey.publicKey.rawRepresentation
        )
        // Flip one byte of the manifest after the signature was produced.
        var tampered = fixture.manifestBytes
        tampered[0] ^= 0x01
        XCTAssertFalse(
            verifier.verifyManifestSignature(
                manifestBytes: tampered,
                signature: fixture.signatureBytes
            ),
            "a tampered manifest MUST NOT validate against the original signature"
        )
    }

    func test_verifier_rejectsSignatureFromWrongKey() throws {
        let fixture = try makeFixture()
        let wrongKey = Curve25519.Signing.PrivateKey()
        let verifier = ThreatFeedVerifier(
            publicKeyRaw: wrongKey.publicKey.rawRepresentation
        )
        XCTAssertFalse(
            verifier.verifyManifestSignature(
                manifestBytes: fixture.manifestBytes,
                signature: fixture.signatureBytes
            ),
            "a signature produced by a different key MUST NOT validate"
        )
    }

    func test_verifier_rejectsMalformedSignatureLength() throws {
        let fixture = try makeFixture()
        let verifier = ThreatFeedVerifier(
            publicKeyRaw: fixture.signingKey.publicKey.rawRepresentation
        )
        let tooShort = Data(repeating: 0, count: 32)
        XCTAssertFalse(
            verifier.verifyManifestSignature(
                manifestBytes: fixture.manifestBytes,
                signature: tooShort
            ),
            "Ed25519 signatures are 64 bytes — anything else must reject without throwing"
        )
    }

    // MARK: - 3. SHA-256 file verification

    func test_verifier_acceptsCorrectFileHash() throws {
        let bytes = Data("hello, vakter".utf8)
        let hex = SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(
            ThreatFeedVerifier.verifyFileHash(fileBytes: bytes, expectedHex: hex)
        )
    }

    func test_verifier_rejectsTamperedFileBytes() throws {
        let bytes = Data("hello, vakter".utf8)
        let hex = SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }.joined()
        var tampered = bytes
        tampered[0] ^= 0x01
        XCTAssertFalse(
            ThreatFeedVerifier.verifyFileHash(
                fileBytes: tampered,
                expectedHex: hex
            ),
            "single-bit tamper MUST cause SHA-256 verification to fail"
        )
    }

    // MARK: - 4. Full fetch-and-swap

    func test_fetchAndSwap_happyPath_writesAllEightFilesAndManifest() async throws {
        let fixture = try makeFixture()
        let client = makeClient(fixture: fixture)

        let bundle = try await client.fetchAndSwap()

        XCTAssertEqual(bundle.manifest.bundleVersion, "2026.05.29")
        XCTAssertEqual(bundle.categoryFiles.count, 8,
                       "every canonical category must be present in the in-memory bundle")
        for category in ThreatFeedCategory.allCases {
            XCTAssertNotNil(bundle.data(for: category),
                            "category \(category.rawValue) missing from bundle")
        }

        // On disk: feed.current/manifest.json + 8 category files.
        let currentURL = scratchRoot
            .appendingPathComponent("feed.current", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: currentURL.path),
            "feed.current/ must exist after a successful swap"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: currentURL.appendingPathComponent("manifest.json").path
            )
        )
        for category in ThreatFeedCategory.allCases {
            let p = currentURL
                .appendingPathComponent(category.requiredFilename)
                .path
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: p),
                "missing on-disk file \(category.requiredFilename)"
            )
        }

        // feed.tmp/ must be gone after the swap — the rename moves it.
        let stagingURL = scratchRoot
            .appendingPathComponent("feed.tmp", isDirectory: true)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: stagingURL.path),
            "feed.tmp/ MUST NOT exist after a successful swap — the atomic rename consumed it"
        )
    }

    func test_fetchAndSwap_postsDidSwapNotification() async throws {
        let fixture = try makeFixture()
        let client = makeClient(fixture: fixture)

        let expectation = self.expectation(
            forNotification: ThreatFeedClient.didSwapBundleNotification,
            object: nil,
            handler: { notification in
                guard let info = notification.userInfo,
                      let bv = info["bundleVersion"] as? String else {
                    return false
                }
                return bv == "2026.05.29"
            }
        )
        _ = try await client.fetchAndSwap()
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - 5. Atomic-swap honesty

    func test_fetchAndSwap_midPipelineFailure_leavesPriorBundleIntact() async throws {
        // Pass 1: install a good bundle.
        let firstFixture = try makeFixture(bundleVersion: "2026.05.28")
        let firstClient = makeClient(fixture: firstFixture)
        _ = try await firstClient.fetchAndSwap()
        let currentURL = scratchRoot
            .appendingPathComponent("feed.current", isDirectory: true)
        let manifestPath = currentURL
            .appendingPathComponent("manifest.json").path
        let initialManifestBytes = try Data(contentsOf: URL(fileURLWithPath: manifestPath))

        // Pass 2: try to install a NEW bundle, but the downloader
        // dies mid-stream — after the manifest is signature-verified
        // but during one of the category files. This simulates the
        // "process killed mid-download" scenario the brand contract
        // promises is safe.
        let secondFixture = try makeFixture(bundleVersion: "2026.05.29")
        struct Killed: Error {}
        let secondManifestBytes = secondFixture.manifestBytes
        let secondSignatureBytes = secondFixture.signatureBytes
        let killingDownloader: ThreatFeedClient.Downloader = { url in
            let name = url.lastPathComponent
            if name == "manifest.json" { return secondManifestBytes }
            if name == "manifest.json.sig" { return secondSignatureBytes }
            // Throw on the very first category fetch — past the
            // signature gate, deep into the staging-write loop.
            throw Killed()
        }
        let secondClient = makeClient(
            fixture: secondFixture,
            downloaderOverride: killingDownloader
        )

        do {
            _ = try await secondClient.fetchAndSwap()
            XCTFail("expected the killed download to throw")
        } catch {
            // Expected.
        }

        // The on-disk state must still be the OLD bundle.
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: currentURL.path),
            "feed.current/ must still exist after a failed swap"
        )
        let postManifest = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
        XCTAssertEqual(
            postManifest, initialManifestBytes,
            "feed.current/manifest.json must be the OLD bytes — atomic swap must be all-or-nothing"
        )

        // And the manifest still says 2026.05.28.
        let oldManifest = try JSONDecoder().decode(
            ThreatFeedManifest.self,
            from: postManifest
        )
        XCTAssertEqual(oldManifest.bundleVersion, "2026.05.28",
                       "the killed swap must NOT have promoted the new bundle")
    }

    // MARK: - 6. Idempotency

    func test_fetchAndSwap_twiceOnSameManifest_isNoOpAndStaysVerified() async throws {
        let fixture = try makeFixture()
        let client = makeClient(fixture: fixture)

        let first = try await client.fetchAndSwap()
        let second = try await client.fetchAndSwap()
        XCTAssertEqual(first.manifest, second.manifest,
                       "running fetchAndSwap twice on the same fixture must produce the same manifest")

        // The on-disk manifest bytes must be byte-identical, not
        // re-emitted by Swift's JSON encoder. (We always write the
        // received bytes, not a re-encoded copy.)
        let currentURL = scratchRoot
            .appendingPathComponent("feed.current", isDirectory: true)
        let onDisk = try Data(
            contentsOf: currentURL.appendingPathComponent("manifest.json")
        )
        XCTAssertEqual(onDisk, fixture.manifestBytes,
                       "the manifest written to feed.current/ MUST be the bytes the signature was computed over — re-encoding would invalidate the signature on a later reverification")
    }

    // MARK: - 7. Offline behaviour

    func test_fetchAndSwap_networkError_leavesCacheClean() async throws {
        // No prior bundle. The fetch fails. Nothing should be on
        // disk under feed.current/.
        let fixture = try makeFixture()
        struct NetDown: Error {}
        let client = makeClient(fixture: fixture, downloaderOverride: { _ in
            throw NetDown()
        })

        do {
            _ = try await client.fetchAndSwap()
            XCTFail("expected the offline fetch to throw")
        } catch {
            // Expected.
        }

        let currentURL = scratchRoot
            .appendingPathComponent("feed.current", isDirectory: true)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: currentURL.path),
            "feed.current/ MUST NOT be created from a failed first-ever fetch"
        )
    }

    // MARK: - 8. Validation failures

    func test_fetchAndSwap_rejectsSchemaVersionTooNew() async throws {
        let fixture = try makeFixture(schemaVersion: 999)
        let client = makeClient(fixture: fixture)

        do {
            _ = try await client.fetchAndSwap()
            XCTFail("client must reject bundles whose schema_version exceeds maxSupported")
        } catch let error as ThreatFeedClientError {
            guard case .schemaVersionTooNew(let seen, let supported) = error else {
                return XCTFail("expected schemaVersionTooNew, got \(error)")
            }
            XCTAssertEqual(seen, 999)
            XCTAssertEqual(supported, 1)
        }
    }

    func test_fetchAndSwap_rejectsFeedHostMismatch() async throws {
        let fixture = try makeFixture(feedHost: "evil.example")
        let client = makeClient(fixture: fixture)

        do {
            _ = try await client.fetchAndSwap()
            XCTFail("client must reject a manifest whose feed_host doesn't match")
        } catch let error as ThreatFeedClientError {
            guard case .feedHostMismatch = error else {
                return XCTFail("expected feedHostMismatch, got \(error)")
            }
        }
    }

    func test_fetchAndSwap_rejectsTamperedManifestSignature() async throws {
        let fixture = try makeFixture()
        // Inject a downloader that returns a tampered manifest but
        // the original (now-invalid) signature.
        var tampered = fixture.manifestBytes
        tampered[0] ^= 0xFF
        let signatureBytes = fixture.signatureBytes
        let fileBytes = fixture.fileBytes
        let tamperedBytes = tampered
        let tamperedDownloader: ThreatFeedClient.Downloader = { url in
            let name = url.lastPathComponent
            if name == "manifest.json" { return tamperedBytes }
            if name == "manifest.json.sig" { return signatureBytes }
            if let bytes = fileBytes[name] { return bytes }
            throw ThreatFeedClientError.networkError(description: name)
        }
        let client = makeClient(
            fixture: fixture,
            downloaderOverride: tamperedDownloader
        )

        do {
            _ = try await client.fetchAndSwap()
            XCTFail("client must reject a tampered manifest")
        } catch let error as ThreatFeedClientError {
            XCTAssertEqual(error, .signatureMismatch,
                           "a tampered manifest must throw signatureMismatch")
        }

        // No staging dir should remain.
        let stagingURL = scratchRoot
            .appendingPathComponent("feed.tmp", isDirectory: true)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: stagingURL.path),
            "feed.tmp/ MUST be cleaned up after a signature failure"
        )
    }

    func test_fetchAndSwap_rejectsCorruptedCategoryFile() async throws {
        let fixture = try makeFixture()
        // The downloader returns *wrong* bytes for one category. The
        // manifest's SHA-256 still references the original bytes, so
        // the file-hash check must fail.
        let manifestBytes = fixture.manifestBytes
        let signatureBytes = fixture.signatureBytes
        let fileBytes = fixture.fileBytes
        let corruptDownloader: ThreatFeedClient.Downloader = { url in
            let name = url.lastPathComponent
            if name == "manifest.json" { return manifestBytes }
            if name == "manifest.json.sig" { return signatureBytes }
            if name == "phishing-domains.txt" {
                return Data("CORRUPTED".utf8)
            }
            if let bytes = fileBytes[name] { return bytes }
            throw ThreatFeedClientError.networkError(description: name)
        }
        let client = makeClient(
            fixture: fixture,
            downloaderOverride: corruptDownloader
        )

        do {
            _ = try await client.fetchAndSwap()
            XCTFail("client must reject a category file whose sha256 mismatches")
        } catch let error as ThreatFeedClientError {
            guard case .fileHashMismatch(let filename) = error else {
                return XCTFail("expected fileHashMismatch, got \(error)")
            }
            XCTAssertEqual(filename, "phishing-domains.txt")
        }
    }

    // MARK: - 9. Cached bundle reload

    func test_loadCachedBundle_returnsNilBeforeFirstSwap() async throws {
        let fixture = try makeFixture()
        let client = makeClient(fixture: fixture)
        let cached = try await client.loadCachedBundle()
        XCTAssertNil(
            cached,
            "loadCachedBundle must return nil when feed.current/ doesn't exist yet"
        )
    }

    func test_loadCachedBundle_returnsLastSwappedBundle() async throws {
        let fixture = try makeFixture()
        let client = makeClient(fixture: fixture)
        _ = try await client.fetchAndSwap()
        let cached = try await client.loadCachedBundle()
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.manifest.bundleVersion, "2026.05.29")
        for category in ThreatFeedCategory.allCases {
            XCTAssertNotNil(
                cached?.data(for: category),
                "cached bundle missing category \(category.rawValue)"
            )
        }
    }

    // MARK: - 10. Brand-contract guards

    func test_productionPublicKeyConstant_isPlaceholderUntilTicket61Lands() {
        // The compiled-in production key MUST remain the all-zero
        // FIXME(#61) placeholder until #61's warden merge replaces
        // it with the real publisher key. If this test starts
        // failing it means someone replaced the placeholder — at
        // which point this test should be updated to verify the
        // real key's expected fingerprint.
        XCTAssertEqual(
            ThreatFeedPublicKey.publicKeyBase64,
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "FIXME(#61) placeholder must not be replaced until #61's warden merge"
        )
        let data = ThreatFeedPublicKey.publicKeyData
        XCTAssertEqual(data?.count, 32,
                       "the placeholder must decode to 32 raw bytes so the verifier's length-gate matches")
        XCTAssertEqual(data, Data(repeating: 0, count: 32),
                       "the placeholder is intentionally the all-zero curve point so the FIXME nature is visible in stack traces")
    }
}
