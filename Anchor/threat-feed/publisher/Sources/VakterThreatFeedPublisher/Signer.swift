// Signer.swift
//
// Ed25519 signing of the bundle tarball. Wraps swift-crypto so the call
// sites stay short and so we have one place to swap out crypto if we
// ever migrate (we won't).
//
// Key handling rule: the publisher receives the private key as bytes
// (32 raw bytes, hex-encoded, OR a PKCS#8 PEM). It MUST NEVER write the
// private key to disk; the GitHub Actions workflow injects it from a
// secret env var. Tests load a freshly-generated ephemeral key — also
// in memory only.

import Foundation
import Crypto

/// Loads an Ed25519 private key from one of the supported encodings.
///
/// Accepted formats (in order tried):
///  1. PEM string starting with `-----BEGIN PRIVATE KEY-----` (PKCS#8 DER).
///  2. 64-char lowercase hex string = 32 raw bytes of the seed.
///
/// PKCS#8-from-PEM is the common output of `openssl genpkey -algorithm Ed25519`,
/// which is what operators are instructed to run in the README.
public enum SignerKeyError: Error, CustomStringConvertible {
    case emptyKeyMaterial
    case malformedPEM
    case wrongLengthHex(actual: Int)
    case invalidHexDigit
    case unsupportedFormat

    public var description: String {
        switch self {
        case .emptyKeyMaterial:
            return "Ed25519 private key material is empty."
        case .malformedPEM:
            return "Could not parse PEM-encoded Ed25519 private key."
        case .wrongLengthHex(let actual):
            return "Ed25519 hex key must be 64 hex chars (32 bytes); got \(actual)."
        case .invalidHexDigit:
            return "Ed25519 hex key contains a non-hex character."
        case .unsupportedFormat:
            return "Ed25519 key is not a recognised PEM or 64-char hex string."
        }
    }
}

public struct Signer {
    public let key: Curve25519.Signing.PrivateKey

    public init(key: Curve25519.Signing.PrivateKey) {
        self.key = key
    }

    /// Build a Signer from raw key material loaded by `loadEd25519PrivateKey`.
    public static func from(material: String) throws -> Signer {
        Signer(key: try loadEd25519PrivateKey(from: material))
    }

    /// Sign the raw bytes of the tarball. Returns the 64-byte detached
    /// Ed25519 signature, which is what the client will verify against
    /// the embedded public key.
    public func sign(_ data: Data) throws -> Data {
        try key.signature(for: data)
    }

    /// Convenience for tests / verification: the matching public key.
    public var publicKey: Curve25519.Signing.PublicKey {
        key.publicKey
    }
}

/// Parse an Ed25519 private key from a PEM string or a 64-char hex
/// string. Trims whitespace so a `cat secret.pem` with a trailing
/// newline works.
public func loadEd25519PrivateKey(
    from material: String
) throws -> Curve25519.Signing.PrivateKey {
    let trimmed = material.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { throw SignerKeyError.emptyKeyMaterial }

    // 1. PEM path. PKCS#8-wrapped Ed25519 keys come out of openssl as
    //    a base64 blob between the PEM markers. The last 32 bytes of
    //    that DER blob are the raw key seed; this is true for the
    //    standard PKCS#8 v1 / v2 Ed25519 encodings and is what we need.
    if trimmed.contains("BEGIN") && trimmed.contains("PRIVATE KEY") {
        let lines = trimmed.split(separator: "\n").filter { line in
            !line.hasPrefix("-----")
        }
        let base64 = lines.joined()
        guard let der = Data(base64Encoded: base64) else {
            throw SignerKeyError.malformedPEM
        }
        // PKCS#8 Ed25519 keys are short; the raw seed is the trailing
        // 32 bytes. We do a cheap suffix grab rather than ship an ASN.1
        // parser. swift-crypto verifies length below.
        guard der.count >= 32 else { throw SignerKeyError.malformedPEM }
        let seed = der.suffix(32)
        return try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    }

    // 2. Hex path. 32 raw bytes => 64 hex chars.
    if trimmed.count == 64 {
        guard let raw = Data(hex: trimmed) else {
            throw SignerKeyError.invalidHexDigit
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    }

    if trimmed.count.isMultiple(of: 2),
       trimmed.allSatisfy({ $0.isHexDigit }),
       trimmed.count != 64 {
        throw SignerKeyError.wrongLengthHex(actual: trimmed.count)
    }

    throw SignerKeyError.unsupportedFormat
}

extension Data {
    /// Initialiser for "deadbeef..." style strings. Returns nil on a
    /// non-hex character so we can surface a clear error to the caller.
    init?(hex: String) {
        let s = hex.lowercased()
        guard s.count.isMultiple(of: 2) else { return nil }
        var out = Data(capacity: s.count / 2)
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            guard let byte = UInt8(s[index..<next], radix: 16) else {
                return nil
            }
            out.append(byte)
            index = next
        }
        self = out
    }

    /// Lowercase hex string. Used for sha256 digests in the manifest.
    func hexString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension Character {
    fileprivate var isHexDigit: Bool {
        return ("0"..."9").contains(self) ||
               ("a"..."f").contains(self) ||
               ("A"..."F").contains(self)
    }
}
