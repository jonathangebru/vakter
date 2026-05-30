import Foundation

/// The one-way client that downloads, verifies, and atomically swaps
/// the daily threat-feed bundle.
///
/// ## Brand contract — locked
///
/// 1. **One-way.** This actor sends one outbound HTTPS GET per file
///    (manifest + signature + 8 category files). It NEVER sends user
///    data. There is no per-user identifier in any request, no
///    telemetry, no query parameters derived from app state. The
///    same bytes are pulled by every Vakter installation.
/// 2. **Signature-first.** The manifest is downloaded, then the
///    detached signature, then the signature is verified BEFORE any
///    category file is fetched. A failed signature short-circuits
///    the whole operation; no further bytes are downloaded.
/// 3. **Atomic-swap.** Verified files are written into a staging
///    directory (`feed.tmp/`), each file's SHA-256 checked against
///    the manifest, and only then is `feed.tmp/` atomically renamed
///    over `feed.current/`. A process kill or power loss at any
///    point leaves `feed.current/` pointing at the previous
///    known-good bundle (or empty, if this is the very first
///    download).
/// 4. **Fail-closed.** Any verification failure — signature
///    mismatch, schema-version too new, file hash mismatch,
///    entry-count cross-check failure, unknown category slug —
///    throws and leaves the previous bundle in place. Network
///    errors throw without touching the on-disk cache. The product
///    never breaks because the feed is broken.
///
/// ## Why an actor
///
/// - The fetch pipeline mutates shared state (staging dir,
///   `feed.current/`, the in-memory bundle published via
///   notification). Concurrent fetches would race and could clobber
///   each other's staging directory mid-write.
/// - The Wave-1 daemon code already runs in async contexts, so an
///   actor is the natural shape.
public actor ThreatFeedClient {

    // MARK: - Public configuration

    /// The base URL the client polls for the manifest. Per the
    /// bundle-schema spec this is `https://vakter.app/feed/v1/`
    /// (the consumer-facing CDN edge of the publisher's
    /// `feed.vakter.app`). The full manifest URL is
    /// `<baseURL>/manifest.json`.
    public let baseURL: URL

    /// The verifier responsible for Ed25519 signature checks.
    /// Production code uses the compiled-in
    /// ``ThreatFeedPublicKey``; tests inject a freshly generated
    /// test key (the FIXME(#61) placeholder doesn't verify any real
    /// signature).
    public let verifier: ThreatFeedVerifier

    /// Filesystem URL where staging + current bundle live. Defaults
    /// to ``ThreatFeedStorage/rootDirectoryURL``. Tests override
    /// this to point at a `URLSession` per-test scratch directory so
    /// they don't share state across runs.
    public let storageRoot: URL

    /// The highest schema_version this client knows how to parse.
    /// A bundle whose `schema_version` exceeds this value is
    /// rejected; the client keeps the last known-good and surfaces
    /// an "update Vakter" prompt to the user (the surface is
    /// future-ticket #63 — at #62 we just throw the error and let
    /// the caller log it).
    public let maxSupportedSchemaVersion: Int

    /// Injected downloader. Returns the bytes for the URL or throws.
    /// Production uses `URLSession.shared.data(from:)`; tests inject
    /// a closure that serves bytes from a fixture dictionary. The
    /// indirection is essential — without it the unit tests in this
    /// module would hit the live network, which we never allow.
    public typealias Downloader = @Sendable (URL) async throws -> Data
    public let download: Downloader

    /// The file manager used for staging + atomic swap. Defaulted to
    /// `.default`; tests inject a per-test instance pointing at
    /// `URL(fileURLWithPath: NSTemporaryDirectory())` so they don't
    /// clobber each other.
    public let fileManager: FileManager

    // MARK: - Init

    /// Production initialiser. Uses `URLSession.shared` and the
    /// compiled-in production public key. Returns `nil` if the
    /// FIXME(#61) public-key constant is malformed (which would
    /// mean the placeholder hasn't been replaced correctly at merge
    /// time — fail-closed, the client refuses to construct).
    public init?(
        baseURL: URL = URL(string: "https://vakter.app/feed/v1")!,
        storageRoot: URL = ThreatFeedStorage.rootDirectoryURL
    ) {
        guard let verifier = ThreatFeedVerifier(productionKey: ()) else {
            return nil
        }
        self.baseURL = baseURL
        self.verifier = verifier
        self.storageRoot = storageRoot
        self.maxSupportedSchemaVersion = 1
        self.download = { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode else {
                throw ThreatFeedClientError.networkError(
                    description: "non-2xx status for \(url.lastPathComponent)"
                )
            }
            return data
        }
        self.fileManager = .default
    }

    /// Test / injection initialiser. Tests use this to wire a
    /// fixture downloader and a freshly generated Ed25519 test key
    /// pair so they can produce *real* valid signatures over fixture
    /// bundles without coupling to the production key.
    public init(
        baseURL: URL,
        verifier: ThreatFeedVerifier,
        storageRoot: URL,
        maxSupportedSchemaVersion: Int = 1,
        download: @escaping Downloader,
        fileManager: FileManager = .default
    ) {
        self.baseURL = baseURL
        self.verifier = verifier
        self.storageRoot = storageRoot
        self.maxSupportedSchemaVersion = maxSupportedSchemaVersion
        self.download = download
        self.fileManager = fileManager
    }

    // MARK: - Public surface

    /// The notification posted on a successful atomic swap. The
    /// menubar status item ("Threat feed: just now.") and the
    /// EXPLAIN module subscribe to this. Posted on the main actor
    /// via `NotificationCenter.default.post(name:object:)`.
    public static let didSwapBundleNotification =
        Notification.Name("app.vakter.threatfeed.didSwapBundle")

    /// Runs the full fetch-and-swap pipeline. On success the new
    /// bundle lives at ``ThreatFeedStorage/currentBundleDirectoryURL``
    /// and the in-memory `ThreatFeedBundle` is returned.
    ///
    /// Pipeline:
    ///   1. Clear staging dir.
    ///   2. Download `manifest.json` and `manifest.json.sig`.
    ///   3. Verify Ed25519 signature on the manifest bytes.
    ///   4. Parse manifest. Validate: schema_version,
    ///      feed_host, file count (exactly 8), category slugs (all
    ///      8 present and unique), entry-count cross-check.
    ///   5. For each of the 8 category files: download, write to
    ///      staging dir, verify SHA-256 against the manifest entry.
    ///   6. Write manifest.json to staging.
    ///   7. Atomic-swap staging dir over `feed.current/`.
    ///   8. Build and return the in-memory ``ThreatFeedBundle``.
    ///   9. Post ``didSwapBundleNotification``.
    ///
    /// Throws on any failure. Throws DO NOT corrupt the on-disk
    /// cache: `feed.current/` is left untouched until the very last
    /// step (the rename), which is itself atomic.
    @discardableResult
    public func fetchAndSwap() async throws -> ThreatFeedBundle {
        // Step 0: ensure the directory tree exists.
        try ThreatFeedStorage.ensureDirectoriesExist(fileManager: fileManager)
        let storageRoot = self.storageRoot
        let stagingURL = storageRoot
            .appendingPathComponent("feed.tmp", isDirectory: true)
        let currentURL = storageRoot
            .appendingPathComponent("feed.current", isDirectory: true)

        // Step 1: clear staging dir. Idempotent — a previous failed
        // run might have left bytes behind.
        try clearStaging(at: stagingURL)
        try fileManager.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: true
        )

        // Step 2: download manifest + signature.
        let manifestURL = baseURL.appendingPathComponent("manifest.json")
        let signatureURL = baseURL.appendingPathComponent("manifest.json.sig")
        let manifestBytes = try await download(manifestURL)
        let signatureBytes = try await download(signatureURL)

        // Step 3: signature first. If it fails we throw without
        // touching any further bytes or any on-disk state outside
        // staging.
        guard verifier.verifyManifestSignature(
            manifestBytes: manifestBytes,
            signature: signatureBytes
        ) else {
            try? clearStaging(at: stagingURL)
            throw ThreatFeedClientError.signatureMismatch
        }

        // Step 4: parse + validate manifest.
        let manifest: ThreatFeedManifest
        do {
            manifest = try JSONDecoder().decode(
                ThreatFeedManifest.self,
                from: manifestBytes
            )
        } catch {
            try? clearStaging(at: stagingURL)
            throw ThreatFeedClientError.malformedManifest(
                description: error.localizedDescription
            )
        }
        try validateManifest(manifest)

        // Step 5: download + verify each category file. Write to
        // staging only after the SHA-256 check passes — never write
        // a file whose hash we haven't yet verified.
        var categoryFiles: [ThreatFeedCategory: Data] = [:]
        for entry in manifest.files {
            guard let category = ThreatFeedCategory(rawValue: entry.category) else {
                try? clearStaging(at: stagingURL)
                throw ThreatFeedClientError.unknownCategory(
                    slug: entry.category
                )
            }
            guard entry.name == category.requiredFilename else {
                try? clearStaging(at: stagingURL)
                throw ThreatFeedClientError.malformedManifest(
                    description: "filename '\(entry.name)' does not match required '\(category.requiredFilename)' for category '\(category.rawValue)'"
                )
            }
            let fileURL = baseURL.appendingPathComponent(entry.name)
            let fileBytes = try await download(fileURL)
            guard ThreatFeedVerifier.verifyFileHash(
                fileBytes: fileBytes,
                expectedHex: entry.sha256
            ) else {
                try? clearStaging(at: stagingURL)
                throw ThreatFeedClientError.fileHashMismatch(
                    filename: entry.name
                )
            }
            let stagedFile = stagingURL.appendingPathComponent(entry.name)
            try fileBytes.write(to: stagedFile, options: .atomic)
            categoryFiles[category] = fileBytes
        }

        // Step 6: write manifest.json to staging (we always include
        // the manifest in the swap so on-disk readers can re-verify).
        try manifestBytes.write(
            to: stagingURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        // Step 7: atomic swap. `replaceItemAt(_:withItemAt:...)` is
        // the right call for directory-over-directory replacement —
        // it uses the same `renamex_np(2)` swap under the hood as
        // Apple's APFS atomic replace. If `feed.current/` doesn't
        // exist yet (first-ever download), `replaceItemAt` returns
        // nil but does NOT create the destination, so we fall back
        // to a plain `moveItem`. Either way, after this line the
        // staging dir no longer exists.
        let swapResult: URL?
        if fileManager.fileExists(atPath: currentURL.path) {
            swapResult = try fileManager.replaceItemAt(
                currentURL,
                withItemAt: stagingURL
            )
        } else {
            try fileManager.moveItem(at: stagingURL, to: currentURL)
            swapResult = currentURL
        }
        _ = swapResult

        // Step 8: build the in-memory bundle from verified bytes.
        let bundle = ThreatFeedBundle(
            manifest: manifest,
            categoryFiles: categoryFiles,
            onDiskURL: currentURL
        )

        // Step 9: publish. Synchronous post — subscribers run on
        // the same thread; the menubar status item and Settings
        // pane both observe and hop to their own actor as needed.
        NotificationCenter.default.post(
            name: Self.didSwapBundleNotification,
            object: nil,
            userInfo: ["bundleVersion": manifest.bundleVersion]
        )

        return bundle
    }

    /// Loads the currently-on-disk bundle without touching the
    /// network. Used by consumers (Watch domains, EXPLAIN module)
    /// at startup so they have an indicator set to match against
    /// before today's fetch has completed. Returns `nil` if there
    /// is no `feed.current/` yet (first-ever launch, or the user
    /// has disabled feed updates and never had a bundle).
    public func loadCachedBundle() throws -> ThreatFeedBundle? {
        let currentURL = storageRoot
            .appendingPathComponent("feed.current", isDirectory: true)
        guard fileManager.fileExists(atPath: currentURL.path) else {
            return nil
        }
        let manifestURL = currentURL.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        let manifestBytes = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(
            ThreatFeedManifest.self,
            from: manifestBytes
        )
        var categoryFiles: [ThreatFeedCategory: Data] = [:]
        for entry in manifest.files {
            guard let category = ThreatFeedCategory(rawValue: entry.category) else {
                throw ThreatFeedClientError.unknownCategory(slug: entry.category)
            }
            let fileURL = currentURL.appendingPathComponent(entry.name)
            categoryFiles[category] = try Data(contentsOf: fileURL)
        }
        return ThreatFeedBundle(
            manifest: manifest,
            categoryFiles: categoryFiles,
            onDiskURL: currentURL
        )
    }

    // MARK: - Validation helpers

    /// Cross-checks the manifest against the bundle-schema rules:
    ///   - `schema_version` ≤ ``maxSupportedSchemaVersion``.
    ///   - `feed_host` matches the publishing host constant.
    ///   - `files.count == 8`.
    ///   - All 8 canonical category slugs are present exactly once.
    ///   - `total_entry_count == sum(files.entry_count)`.
    private func validateManifest(_ manifest: ThreatFeedManifest) throws {
        guard manifest.schemaVersion <= maxSupportedSchemaVersion else {
            throw ThreatFeedClientError.schemaVersionTooNew(
                seen: manifest.schemaVersion,
                supported: maxSupportedSchemaVersion
            )
        }
        guard manifest.feedHost == "feed.vakter.app" else {
            throw ThreatFeedClientError.feedHostMismatch(
                seen: manifest.feedHost
            )
        }
        guard manifest.files.count == 8 else {
            throw ThreatFeedClientError.malformedManifest(
                description: "files.count must be exactly 8, got \(manifest.files.count)"
            )
        }
        let seenCategories = manifest.files.map(\.category)
        let uniqueCategories = Set(seenCategories)
        guard uniqueCategories.count == seenCategories.count else {
            throw ThreatFeedClientError.malformedManifest(
                description: "duplicate category in files array"
            )
        }
        let canonical = Set(ThreatFeedCategory.allCases.map(\.rawValue))
        guard uniqueCategories == canonical else {
            throw ThreatFeedClientError.malformedManifest(
                description: "files array categories do not match the 8 canonical slugs"
            )
        }
        let summed = manifest.files.reduce(0) { $0 + $1.entryCount }
        guard summed == manifest.totalEntryCount else {
            throw ThreatFeedClientError.malformedManifest(
                description: "total_entry_count (\(manifest.totalEntryCount)) does not match sum of entry_count (\(summed))"
            )
        }
    }

    /// Removes the staging directory in full. Best-effort; if the
    /// directory doesn't exist we silently no-op. Throws only on
    /// removal failures of an existing directory.
    private func clearStaging(at stagingURL: URL) throws {
        guard fileManager.fileExists(atPath: stagingURL.path) else {
            return
        }
        try fileManager.removeItem(at: stagingURL)
    }
}

/// All errors the threat-feed client can throw. Every case carries
/// enough information for the Settings pane (#63) to render a useful
/// message; none carry user data.
public enum ThreatFeedClientError: Error, Equatable, Sendable {
    /// Underlying `URLSession` error or non-2xx HTTP status. The
    /// client wraps these so call sites don't see arbitrary
    /// `Foundation`/`URLError` shapes — useful both for consistent
    /// logging and to keep the threat-feed contract closed.
    case networkError(description: String)

    /// The Ed25519 signature did not validate against the
    /// compiled-in publisher key. The client drops the bundle and
    /// keeps the last known-good.
    case signatureMismatch

    /// The manifest JSON failed to decode against the expected
    /// schema (missing required field, wrong type, etc.).
    case malformedManifest(description: String)

    /// The manifest declares a schema_version higher than this
    /// client knows. The client keeps last known-good and the
    /// caller surfaces an "update Vakter" prompt (#63).
    case schemaVersionTooNew(seen: Int, supported: Int)

    /// The `feed_host` field in the manifest doesn't match the
    /// compiled-in publishing host. Defence against a
    /// misconfigured CDN or a redirected DNS entry.
    case feedHostMismatch(seen: String)

    /// One of the category files' SHA-256 did not match the
    /// manifest's entry. The bundle is dropped wholesale.
    case fileHashMismatch(filename: String)

    /// A category slug in the manifest wasn't one of the 8
    /// canonical values. This can happen if a future publisher
    /// adds a category without bumping `schema_version`; per the
    /// schema contract that's a publisher bug and we reject.
    case unknownCategory(slug: String)
}
