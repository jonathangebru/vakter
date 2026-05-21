import XCTest
@testable import VakterShared

/// Smoke tests for the cloud-upload configuration store.
///
/// We don't network-test here — that would require a live B2 bucket.
/// These tests cover the JSON shape, persistence semantics, and the
/// keychain-secret round-trip (against the user's actual keychain;
/// they self-clean via `clear()`).
final class CloudEvidenceConfigTests: XCTestCase {

    /// Ensure each test starts with a clean slate.
    override func setUp() async throws {
        CloudEvidenceConfig.clear()
    }
    override func tearDown() async throws {
        CloudEvidenceConfig.clear()
    }

    func test_loadReturnsNilWhenUnconfigured() {
        XCTAssertNil(CloudEvidenceConfig.load())
    }

    func test_saveAndLoad_backblazeRoundTrip() {
        let config = CloudEvidenceUpload.Configuration(
            provider: .backblazeB2,
            keyID: "K001-test",
            secret: "secret-key-bytes",
            bucket: "my-bucket-id"
        )
        XCTAssertTrue(CloudEvidenceConfig.save(config))

        let loaded = CloudEvidenceConfig.load()
        XCTAssertEqual(loaded?.provider, .backblazeB2)
        XCTAssertEqual(loaded?.keyID,    "K001-test")
        XCTAssertEqual(loaded?.secret,   "secret-key-bytes")
        XCTAssertEqual(loaded?.bucket,   "my-bucket-id")
    }

    func test_clearRemovesAll() {
        let config = CloudEvidenceUpload.Configuration(
            provider: .presignedURL,
            keyID: nil,
            secret: "https://bucket.s3.amazonaws.com/{filename}?sig=abc",
            bucket: "https://bucket.s3.amazonaws.com"
        )
        XCTAssertTrue(CloudEvidenceConfig.save(config))
        XCTAssertNotNil(CloudEvidenceConfig.load())

        CloudEvidenceConfig.clear()
        XCTAssertNil(CloudEvidenceConfig.load())
    }

    func test_uploadReturnsNotConfiguredWhenNil() async {
        let result = await CloudEvidenceUpload.upload(
            fileURL: URL(fileURLWithPath: "/tmp/anything"),
            keyPrefix: "vakter/test",
            config: nil
        )
        switch result {
        case .failure(.notConfigured):
            break // expected
        default:
            XCTFail("expected .notConfigured, got \(result)")
        }
    }
}
