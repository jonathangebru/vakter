import Foundation
import CryptoKit

/// Cryptographic primitives for verifying a downloaded threat-feed
/// bundle. Wraps CryptoKit's Curve25519 signing facilities.
///
/// ## Why this is its own type
///
/// The verifier is split from ``ThreatFeedClient`` so that:
///   - Tests can call the verifier directly with arbitrary key/data
///     fixtures without spinning up the full client actor.
///   - The "verify signature" and "verify file hash" responsibilities
///     are isolated from "download" and "atomic swap" — easier to
///     audit at code-review time.
///
/// ## Brand contract — fail closed
///
/// Every verifier call returns either *exact match* or *reject*. There
/// is no partial-trust mode, no "this signature is from yesterday's
/// key so we'll still trust it for an hour" exception. If a signature
/// or hash mismatches, the caller MUST drop the bundle and keep the
/// last known-good snapshot.
public struct ThreatFeedVerifier: Sendable {

    /// The Ed25519 public key bytes (32 raw bytes) the verifier will
    /// check signatures against. Tests inject a freshly generated key;
    /// production code uses ``ThreatFeedPublicKey/publicKeyData``.
    public let publicKeyRaw: Data

    public init(publicKeyRaw: Data) {
        self.publicKeyRaw = publicKeyRaw
    }

    /// Convenience initialiser using the compiled-in production key
    /// from ``ThreatFeedPublicKey``. Returns `nil` if the placeholder
    /// base64 fails to decode (i.e. the FIXME(#61) constant has been
    /// replaced with a malformed value). In that case the caller MUST
    /// treat every bundle as unsigned and reject it.
    public init?(productionKey: Void = ()) {
        guard let raw = ThreatFeedPublicKey.publicKeyData else {
            return nil
        }
        self.init(publicKeyRaw: raw)
    }

    /// Verifies that `signature` is a valid Ed25519 signature over
    /// `manifestBytes` for the verifier's public key.
    ///
    /// **Returns `true` if and only if** the signature validates. Any
    /// other condition — wrong key length, malformed signature,
    /// signature mismatch, CryptoKit throw — returns `false`. The
    /// verifier swallows the CryptoKit error rather than propagating
    /// because the only thing the caller can do is reject the bundle,
    /// and the brand contract requires that path to look identical
    /// regardless of *why* verification failed (an attacker shouldn't
    /// be able to distinguish "wrong key" from "wrong signature" from
    /// "malformed bytes" via timing or error string).
    ///
    /// - Parameters:
    ///   - manifestBytes: The raw bytes the publisher signed. Per the
    ///     bundle-schema spec, the signature is over the manifest's
    ///     bytes as published (not over the uncompressed contents).
    ///   - signature: The raw 64-byte Ed25519 signature bytes.
    public func verifyManifestSignature(
        manifestBytes: Data,
        signature: Data
    ) -> Bool {
        guard publicKeyRaw.count == 32 else { return false }
        guard signature.count == 64 else { return false }
        do {
            let key = try Curve25519.Signing.PublicKey(
                rawRepresentation: publicKeyRaw
            )
            return key.isValidSignature(signature, for: manifestBytes)
        } catch {
            return false
        }
    }

    /// Verifies the SHA-256 of `fileBytes` against the lowercase-hex
    /// `expectedHex` carried in the manifest's `FileEntry.sha256`.
    ///
    /// Returns `true` on exact match. Returns `false` on any
    /// mismatch, including non-hex characters, wrong length, or a
    /// genuine hash mismatch. The caller MUST reject the entire
    /// bundle on the first mismatch — per the bundle-schema spec, a
    /// single bad file invalidates the whole bundle.
    public static func verifyFileHash(
        fileBytes: Data,
        expectedHex: String
    ) -> Bool {
        let digest = SHA256.hash(data: fileBytes)
        let actualHex = digest.map { String(format: "%02x", $0) }.joined()
        return actualHex == expectedHex.lowercased()
    }
}
