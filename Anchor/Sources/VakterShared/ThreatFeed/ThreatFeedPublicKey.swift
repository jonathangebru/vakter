import Foundation

/// The Ed25519 public key the threat-feed client trusts for verifying
/// signed manifests.
///
/// ## Brand contract
///
/// The client is **one-way**: it downloads, verifies, swaps. It never
/// transmits user data. Cryptographic trust is anchored in this single
/// compiled-in public key. There is no fallback host, no certificate
/// store, no out-of-band key delivery — if this key is wrong, the
/// client rejects every bundle and continues operating with the last
/// known-good snapshot (or with no snapshot at all if there has never
/// been one). The product never breaks because the feed is broken.
///
/// ## FIXME(#61): placeholder key
///
/// The value of ``publicKeyBase64`` below is a **placeholder** that is
/// shaped like a real Ed25519 public key (32 raw bytes, base64-encoded
/// to 44 characters) but is NOT the publisher's actual production key.
/// Ticket #61 (the publisher / GitHub Actions cron) owns the real key
/// pair. At merge time the warden replaces this placeholder with the
/// value emitted by #61's key-generation step.
///
/// The placeholder is shaped correctly so that:
///   - The Swift build compiles and runs.
///   - ``ThreatFeedVerifier`` exercises every code path (load key →
///     verify signature → reject or accept) without `fatalError`s.
///   - The unit tests for #62 can swap in a *test* key generated
///     inline (see ``ThreatFeedClientTests``). Production code uses
///     the constant below; tests inject their own key via the
///     verifier's initialiser.
///
/// The placeholder is 32 bytes of `0x00` (the all-zero curve point —
/// not a real key, definitely doesn't validate any real signature).
/// Choosing all-zero rather than random hex makes the FIXME nature
/// loud at code-review time and makes it obvious in stack traces if
/// somehow this ships unmodified.
public enum ThreatFeedPublicKey {

    /// The compiled-in Ed25519 public key, base64-encoded.
    ///
    /// FIXME(#61): replace with publisher's actual public key.
    ///
    /// The publisher generates its key pair in
    /// `.github/workflows/threat-feed-publish.yml` and emits the
    /// public half as base64. At merge time the warden coordinates
    /// the swap so that #62 (this client) and #61 (the publisher)
    /// land with a matching key pair.
    ///
    /// Until then this constant is 32 bytes of `0x00`, base64-encoded.
    /// Tests inject their own key and ignore this value entirely.
    public static let publicKeyBase64: String =
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

    /// The compiled-in Ed25519 public key, as raw 32-byte `Data`.
    /// Returns `nil` if the base64 string fails to decode — which
    /// would indicate that the FIXME placeholder above has been
    /// replaced with a malformed value. In that case the client
    /// rejects every bundle (the strict, safe behaviour).
    public static var publicKeyData: Data? {
        Data(base64Encoded: publicKeyBase64)
    }
}
