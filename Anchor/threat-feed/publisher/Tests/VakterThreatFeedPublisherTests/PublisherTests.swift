// PublisherTests.swift
//
// Cover the contract that ticket #61 promises:
//   1. The publisher can build a sample bundle end-to-end.
//   2. The manifest matches the JSON Schema shape.
//   3. The signed tarball round-trips with the matching public key.
//   4. Re-running the same day produces a `.N` bundle (idempotency rule
//      from the bundle-schema spec).
//   5. Source adapters parse upstream fixture bytes correctly.

import XCTest
import Crypto
@testable import VakterThreatFeedPublisher

final class PublisherTests: XCTestCase {

    // MARK: - Test fixtures

    func makeAppleFakesFile(_ tmp: URL) throws -> URL {
        let url = tmp.appendingPathComponent("apple-support-fakes-manual.txt")
        try """
        # apple-support-fakes (test fixture)

        apple-id-verify.example   # first-seen 2026-05-01
        applecare-helpdesk.example
        """.data(using: .utf8)!.write(to: url)
        return url
    }

    func makeConfig(in tmp: URL, signer: Signer, bundleDate: Date = Date()) throws -> PublisherConfig {
        let appleFile = try makeAppleFakesFile(tmp)
        return PublisherConfig(
            outputDirectory: tmp.appendingPathComponent("out"),
            bundleDate: bundleDate,
            feedHost: "feed.vakter.app",
            publisherKeyID: "vakter-feed-2026-q2",
            schemaVersion: 1,
            phishTank: PhishTankAdapter(fetcher: FixtureFetcher([
                PhishTankAdapter.url: dryRunPhishTankFixture()
            ])),
            urlHaus: URLhausAdapter(fetcher: FixtureFetcher([
                URLhausAdapter.url: dryRunURLhausFixture()
            ])),
            fccRobocall: FCCRobocallAdapter(fetcher: FixtureFetcher([
                FCCRobocallAdapter.url: dryRunFCCFixture()
            ])),
            appleSupportFakes: AppleSupportFakesAdapter(path: appleFile),
            previousBundleVersion: nil,
            previousBundleSHA256: nil,
            signer: signer
        )
    }

    // MARK: - 1. End-to-end smoke

    func testPublisherBuildsBundleEndToEnd() throws {
        let tmp = try makeTmp()
        let signer = Signer(key: .init())
        let config = try makeConfig(in: tmp, signer: signer)

        let result = try Publisher(config).run()

        // Bundle dir contains all 9 files.
        let fm = FileManager.default
        let expected: [String] = [
            "manifest.json",
            "phishing-domains.txt",
            "phone-numbers.txt",
            "apple-support-fakes.txt",
            "malware-bundle-ids.txt",
            "sms-templates.json",
            "romance-scam-patterns.json",
            "package-scam-templates.json",
            "sources.json"
        ]
        for name in expected {
            let path = result.bundleDirectory.appendingPathComponent(name).path
            XCTAssertTrue(fm.fileExists(atPath: path), "missing \(name)")
        }
        XCTAssertEqual(result.manifest.files.count, 8, "exactly 8 file entries")
    }

    // MARK: - 2. Schema rigour

    func testManifestMatchesSchemaShape() throws {
        let tmp = try makeTmp()
        let signer = Signer(key: .init())
        let config = try makeConfig(in: tmp, signer: signer)
        let result = try Publisher(config).run()
        let m = result.manifest

        XCTAssertEqual(m.feed_host, "feed.vakter.app")
        XCTAssertEqual(m.schema_version, 1)
        XCTAssertTrue(m.bundle_version.range(
            of: #"^\d{4}\.\d{2}\.\d{2}(\.\d+)?$"#,
            options: .regularExpression
        ) != nil, "bundle_version must match YYYY.MM.DD[.N]")
        XCTAssertTrue(m.publisher_key_id.range(
            of: #"^vakter-feed-\d{4}-q[1-4]$"#,
            options: .regularExpression
        ) != nil, "publisher_key_id must match vakter-feed-YYYY-qN")
        XCTAssertEqual(m.files.count, 8)
        XCTAssertEqual(
            Set(m.files.map { $0.category }).count, 8,
            "each of the 8 category slugs appears once"
        )
        XCTAssertEqual(
            m.total_entry_count,
            m.files.reduce(0) { $0 + $1.entry_count },
            "total_entry_count must equal sum of FileEntry.entry_count"
        )
        for file in m.files {
            XCTAssertTrue(file.sha256.range(
                of: #"^[a-f0-9]{64}$"#,
                options: .regularExpression
            ) != nil, "sha256 hex must be lowercase 64 chars")
            XCTAssertTrue(file.name.range(
                of: #"^[a-z][a-z0-9-]*\.(txt|json)$"#,
                options: .regularExpression
            ) != nil, "file name must match the schema pattern")
        }
    }

    // MARK: - 3. Signature round-trip

    func testSignatureRoundTripsWithPublicKey() throws {
        let tmp = try makeTmp()
        let signer = Signer(key: .init())
        let config = try makeConfig(in: tmp, signer: signer)
        let result = try Publisher(config).run()

        // Read the tarball back off disk and verify the detached signature
        // against the published public key.
        let stem = "feed-" + bundleVersionToDirComponent(result.bundleVersion)
        let tarPath = config.outputDirectory.appendingPathComponent(stem + ".tar.gz")
        let tarBytes = try Data(contentsOf: tarPath)
        let sigPath = config.outputDirectory.appendingPathComponent(stem + ".sig")
        let sigBytes = try Data(contentsOf: sigPath)

        XCTAssertEqual(sigBytes.count, 64, "Ed25519 detached signature is 64 raw bytes")
        XCTAssertTrue(
            signer.publicKey.isValidSignature(sigBytes, for: tarBytes),
            "publisher signature must verify under its own public key"
        )

        // Negative control: a different key must NOT verify the same sig.
        let other = Curve25519.Signing.PrivateKey()
        XCTAssertFalse(
            other.publicKey.isValidSignature(sigBytes, for: tarBytes),
            "an unrelated public key must NOT verify the signature"
        )
    }

    // MARK: - 4. Idempotency / same-day .N suffix

    func testReRunningSameDayProducesNSuffix() throws {
        let tmp = try makeTmp()
        let signer = Signer(key: .init())
        let fixedDate = Date(timeIntervalSince1970: 1748563200) // 2025-05-30 UTC
        let config = try makeConfig(in: tmp, signer: signer, bundleDate: fixedDate)

        let first = try Publisher(config).run()
        let second = try Publisher(config).run()
        let third = try Publisher(config).run()

        XCTAssertEqual(first.bundleVersion, "2025.05.30")
        XCTAssertEqual(second.bundleVersion, "2025.05.30.1")
        XCTAssertEqual(third.bundleVersion, "2025.05.30.2")

        // Both tarballs must exist on disk.
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath:
            config.outputDirectory.appendingPathComponent("feed-2025-05-30.tar.gz").path
        ))
        XCTAssertTrue(fm.fileExists(atPath:
            config.outputDirectory.appendingPathComponent("feed-2025-05-30.1.tar.gz").path
        ))
        XCTAssertTrue(fm.fileExists(atPath:
            config.outputDirectory.appendingPathComponent("feed-2025-05-30.2.tar.gz").path
        ))
    }

    // MARK: - 5. Source adapters

    func testPhishTankCSVParser() {
        let csv = """
        phish_id,url,phish_detail_url,verified,target
        1,https://Bad-Apple-LOGIN.example/x,...,yes,Apple
        2,http://wells.example/login,...,yes,Wells Fargo
        3,not-a-url,...,no,Other
        """
        let domains = PhishTankAdapter.parseCSV(csv.data(using: .utf8)!)
        XCTAssertTrue(domains.contains("bad-apple-login.example"),
            "lowercased host from URL extracted")
        XCTAssertTrue(domains.contains("wells.example"))
        XCTAssertFalse(domains.contains("not-a-url"),
            "rows whose url column doesn't parse to a host are dropped")
    }

    func testFCCNormalisesToE164() {
        let csv = """
        ticket_id,caller_id_number,issue
        1,8005551234,Unwanted call
        2,(415) 555-9876,Unwanted call
        3,18475550000,Unwanted call
        4,call from anonymous,
        """
        let numbers = FCCRobocallAdapter.parseCSV(csv.data(using: .utf8)!)
        XCTAssertEqual(Set(numbers), Set(["+18005551234", "+14155559876", "+18475550000"]))
    }

    func testAppleSupportFakesParserDropsComments() {
        let text = """
        # header
        apple-id-verify-team.example      # first-seen 2026-05-04

        applecare-helpdesk.example
        """
        let domains = AppleSupportFakesAdapter.parseText(text)
        XCTAssertEqual(domains, [
            "apple-id-verify-team.example",
            "applecare-helpdesk.example"
        ])
    }

    // MARK: - 6. Signer key loader

    func testSignerLoadsHex() throws {
        let key = Curve25519.Signing.PrivateKey()
        let hex = key.rawRepresentation.hexString()
        let loaded = try loadEd25519PrivateKey(from: hex)
        XCTAssertEqual(loaded.rawRepresentation, key.rawRepresentation)
    }

    func testSignerRejectsMalformedInputs() {
        XCTAssertThrowsError(try loadEd25519PrivateKey(from: "")) { err in
            XCTAssertTrue("\(err)".contains("empty"))
        }
        XCTAssertThrowsError(try loadEd25519PrivateKey(from: "deadbeef"))
        XCTAssertThrowsError(try loadEd25519PrivateKey(
            from: "-----BEGIN PRIVATE KEY-----\nnot-base-64!!\n-----END PRIVATE KEY-----"
        ))
    }

    /// End-to-end: generate an Ed25519 key via openssl (the same command
    /// the publisher README instructs operators to run), load it through
    /// the PEM loader, sign + verify a payload. This is the operator
    /// happy-path expressed as a test.
    ///
    /// macOS ships LibreSSL at /usr/bin/openssl which does NOT support
    /// Ed25519. We probe a small list of likely locations and skip if
    /// none is real OpenSSL. CI runners (macos-latest GitHub Actions)
    /// have Homebrew OpenSSL in /opt/homebrew/bin, which works.
    func testSignerLoadsOpenSSLGeneratedPEMAndSigns() throws {
        let tmp = try makeTmp()
        let pem = tmp.appendingPathComponent("priv.pem")
        let candidates = [
            "/opt/homebrew/bin/openssl",
            "/usr/local/bin/openssl",
            "/usr/local/opt/openssl@3/bin/openssl"
        ]
        var success = false
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["genpkey", "-algorithm", "Ed25519", "-out", pem.path]
            process.standardError = Pipe()
            process.standardOutput = Pipe()
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0,
               FileManager.default.fileExists(atPath: pem.path) {
                success = true
                break
            }
        }
        guard success else {
            throw XCTSkip("real OpenSSL with Ed25519 unavailable; PEM-loader integration test skipped")
        }
        let raw = try String(contentsOf: pem, encoding: .utf8)
        let key = try loadEd25519PrivateKey(from: raw)
        let signer = Signer(key: key)

        let payload = Data("vakter-threat-feed".utf8)
        let sig = try signer.sign(payload)
        XCTAssertEqual(sig.count, 64)
        XCTAssertTrue(
            signer.publicKey.isValidSignature(sig, for: payload),
            "PEM-loaded key must sign + verify"
        )
    }

    // MARK: - 7. CLI dry-run fixtures are well-formed

    func testDryRunFixturesParse() {
        XCTAssertFalse(PhishTankAdapter.parseCSV(dryRunPhishTankFixture()).isEmpty)
        XCTAssertFalse(URLhausAdapter.parseCSV(dryRunURLhausFixture()).isEmpty)
        XCTAssertFalse(FCCRobocallAdapter.parseCSV(dryRunFCCFixture()).isEmpty)
    }

    // MARK: - Helpers

    func makeTmp() throws -> URL {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vakter-publisher-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }
}
