import Foundation
import Security

/// Owns the user's Vakter license: storage, validation, current tier.
///
/// Design contract:
///  - The license key is stored in the user's Keychain under the service
///    name `app.vakter.mac.license` — never in UserDefaults or a plist
///    file on disk. The Keychain ACL keeps the secret out of casual file
///    inspection (Time Machine, iCloud Drive backups, "show package
///    contents", etc.).
///  - Validation is **structural + dev-key only** at v1.5. The roadmap
///    (Issue #56) wires a real signed-key check against the Stripe
///    webhook payload — until then, we accept three explicit dev keys
///    (so the Mac engineer can exercise the activate flow without
///    standing up the webhook) plus the on-the-wire format used by
///    Issue #57's spec (`VKT-XXXX-XXXX-XXXX-XXXX`).
///  - **No network calls.** Ever. Validation is purely local. This is a
///    brand-level commitment (see `openspec/changes/vakter-watch-pivot/
///    proposal.md` — "Vakter never phones home").
///  - **The activated key never appears in NSLog output.** We log the
///    *tier* (the user-visible result) but never the raw key bytes,
///    even in error paths, to keep the secret out of Console.app.
///
/// Public surface mirrors `CloudEvidenceConfig` — a small enum-namespace
/// of static methods over a Keychain item — but adds a tier accessor
/// so the rest of the app can gate features without re-validating the
/// key on every call.
///
/// Related:
///  - Issue #57 — in-app pricing flow (this file's parent)
///  - Issue #56 — Stripe webhook + real signed key validation
///  - `MenuBarController` — reads `currentTier()` to decide whether to
///    show the "Upgrade Vakter…" item
///  - `SettingsRoot` Activate tab — calls `activate(key:)` from the UI
public enum LicenseManager {

    // MARK: - Tier

    /// What the user is entitled to. v1.5 pre-launch has three tiers;
    /// future expansions (e.g. an `.educational` discount) can be
    /// added without breaking persistence because the rawValue lives
    /// in Keychain only via the activated key itself, never in the
    /// stored payload.
    public enum Tier: String, Codable, Sendable, Equatable {
        /// Anti-theft + Defenses + LLM Defenses explainer + Threat
        /// feed. Default for every install. No key required.
        case free
        /// Anti-theft + everything in Free + Mail/Messages/Web/Mac
        /// Watch + LLM chat panel. €29 one-time lifetime.
        case essential
        /// Same feature set as Essential but allows multi-seat usage
        /// per the B2B SKU (€29/Mac one-time, €20/Mac at ≥10 Macs).
        /// At v1.5 the seat-enforcement is honour-system; the type
        /// exists so future code (v2.0 centralised dashboard) can
        /// gate against it.
        case business
    }

    // MARK: - Keychain item identity
    //
    // Both kept private — only `LicenseManager` should know the exact
    // Keychain coordinates. The service name is documented in the
    // ticket so support staff can recognise it in a user's Keychain
    // Access dump.

    private static let keychainService = "app.vakter.mac.license"
    private static let keychainAccount = "default"

    // MARK: - Dev test keys
    //
    // EXPLICIT dev shortcuts so the engineer can exercise the activate
    // flow without standing up the Stripe webhook. These are hardcoded
    // *intentionally* with `VAKTER-DEV-…` prefixes so a quick `strings`
    // pass on the binary makes them obvious to anyone auditing.
    //
    // They are NOT a secret. They are debug affordances. The real
    // license-key check (Issue #56) will be a signed payload validated
    // against a public key embedded at build time, at which point these
    // dev keys MAY remain (per ticket: "Real key validation will be
    // added later when Stripe webhook (#56) is live") — but the human
    // running #56 may choose to gate them behind a debug build flag.
    private static let devKeyFree      = "VAKTER-DEV-FREE"
    private static let devKeyEssential = "VAKTER-DEV-ESSENTIAL"
    private static let devKeyBusiness  = "VAKTER-DEV-BUSINESS"

    // MARK: - Production key format
    //
    // Issue #57 spec uses `VKT-XXXX-XXXX-XXXX-XXXX` (5 dash-separated
    // groups, the first being `VKT`, the next four being 4-character
    // alphanumeric chunks). We accept anything matching this regex as
    // structurally valid at v1.5; #56 will add a cryptographic check
    // on top. Until then a structurally-valid key activates Essential
    // tier — *not* a security risk because the binary is unpaid
    // distribution and the moat is the URL the customer reaches after
    // payment (`vakter.app/upgrade` is the only place to get a real key).
    //
    // The regex is intentionally permissive (alphanumeric, case-
    // insensitive) so the human-readable invoice email Stripe sends
    // doesn't trip on a hyphen/space copy-paste. Whitespace is
    // tolerated and stripped at the entry point.
    private static let productionKeyPattern = "^VKT(?:-[A-Z0-9]{4}){4}$"

    // MARK: - Activation result

    /// Outcome of `activate(key:)`. The UI maps these to the user-facing
    /// checkmark / cross states. Errors carry no key material so they
    /// are safe to log via NSLog.
    public enum ActivationResult: Equatable {
        case activated(Tier)
        case rejectedUnrecognised
        case rejectedMalformed
    }

    // MARK: - Public API

    /// Returns the tier the user is currently entitled to.
    ///
    /// Reads the Keychain on every call (rather than caching) because:
    ///   1. The Keychain read is fast — a few ms at most.
    ///   2. Caching would mean a stale tier if the user activates in
    ///      one place and reads in another (e.g. Settings + menubar).
    ///   3. The audit story is simpler when there's no in-memory mirror.
    ///
    /// Returns `.free` if no key is stored, or if the stored key is no
    /// longer recognised (e.g. the user pasted a key from a future
    /// build that this older binary can't parse — fail safe to free).
    public static func currentTier() -> Tier {
        guard let key = readKey() else { return .free }
        return validate(key: key) ?? .free
    }

    /// Whether the user has an active paid license (Essential or
    /// Business). Convenience over `currentTier() != .free` — call sites
    /// like the menubar "Upgrade Vakter…" item read more cleanly this
    /// way.
    public static func isPaid() -> Bool {
        switch currentTier() {
        case .free:               return false
        case .essential, .business: return true
        }
    }

    /// Attempts to activate the given key. On success the key is
    /// persisted to Keychain and the resolved tier is returned. On
    /// failure no state is mutated.
    ///
    /// The raw key is normalised before validation: trimmed and
    /// upper-cased. We do this so users can paste from email with
    /// surrounding whitespace or accidental lowercase without seeing a
    /// "not recognised" error.
    ///
    /// IMPORTANT: this method never logs the key. The caller (Settings
    /// activate panel) MUST also avoid logging the input field. The
    /// returned `ActivationResult` is safe to log.
    @discardableResult
    public static func activate(key rawKey: String) -> ActivationResult {
        let normalised = normalise(rawKey)
        // Empty / whitespace-only input is malformed (distinct from
        // "wrong key" — the UI can render a tighter error if it wants
        // to, e.g. don't disable the Activate button if the field is
        // blank).
        guard !normalised.isEmpty else { return .rejectedMalformed }

        guard let tier = validate(key: normalised) else {
            // Distinguish "wrong shape" from "valid shape, unknown
            // value" so the UI can show a more useful message — but
            // tests treat both as a rejection of the activate call.
            if looksWellFormed(normalised) {
                return .rejectedUnrecognised
            } else {
                return .rejectedMalformed
            }
        }
        guard writeKey(normalised) else {
            // Keychain write failed — surfaces as rejectedMalformed
            // so the user retries (rather than thinking their key is
            // bad). Real-world keychain write failures are rare but
            // possible (locked keychain, disk full).
            NSLog("[LicenseManager] activate: keychain write failed")
            return .rejectedMalformed
        }
        NSLog("[LicenseManager] activated tier=%@", tier.rawValue)
        return .activated(tier)
    }

    /// Removes any stored license. The user reverts to `.free`. Public
    /// so a future "Deactivate" / "Sign out of this Mac" UI affordance
    /// can call it; not wired into any UI today.
    public static func deactivate() {
        deleteKey()
        NSLog("[LicenseManager] deactivated — tier reset to free")
    }

    // MARK: - Validation

    /// Determines the tier a given key unlocks, or `nil` if the key
    /// isn't recognised. Pure function — no Keychain side effects, no
    /// network. Exposed `internal` for testability.
    internal static func validate(key: String) -> Tier? {
        switch key {
        case devKeyFree:      return .free
        case devKeyEssential: return .essential
        case devKeyBusiness:  return .business
        default:
            // Structural check against the production format. Anything
            // matching the pattern is provisionally Essential at v1.5
            // because the cryptographic check (#56) isn't live yet.
            // When #56 lands, this branch becomes a signature check;
            // the dev-key cases above can stay or be removed at the
            // human's discretion.
            if looksWellFormed(key) {
                return .essential
            }
            return nil
        }
    }

    /// True if the key matches the production `VKT-XXXX-XXXX-XXXX-XXXX`
    /// shape. Exposed `internal` for tests + the activate() flow's
    /// "malformed vs unrecognised" branching.
    internal static func looksWellFormed(_ key: String) -> Bool {
        let range = NSRange(key.startIndex..., in: key)
        guard let regex = try? NSRegularExpression(
            pattern: productionKeyPattern,
            options: []
        ) else {
            return false
        }
        return regex.firstMatch(in: key, options: [], range: range) != nil
    }

    /// Trim + upper-case. Internal so tests can exercise it directly.
    internal static func normalise(_ key: String) -> String {
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    // MARK: - Keychain (private)
    //
    // Mirrors `CloudEvidenceConfig`'s helpers. Kept private to this
    // type so no other code can write a license key into our Keychain
    // service — only `activate()` / `deactivate()` are public mutators.

    private static func readKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  keychainService,
            kSecAttrAccount as String:  keychainAccount,
            kSecMatchLimit as String:   kSecMatchLimitOne,
            kSecReturnData as String:   true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func writeKey(_ value: String) -> Bool {
        let data = value.data(using: .utf8) ?? Data()
        // Delete first; SecItemAdd fails if the item already exists.
        // Same pattern as CloudEvidenceConfig.writeKeychainSecret.
        deleteKey()
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  keychainService,
            kSecAttrAccount as String:  keychainAccount,
            kSecValueData as String:    data,
            // `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` —
            // available after first login (so launch-at-login can
            // read it), never syncs to iCloud Keychain (so the
            // user's license doesn't roam to a Mac that didn't pay
            // for the seat). This is the same posture used by
            // CloudEvidenceConfig for the B2 secret, and it's the
            // right posture for a per-Mac license too.
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  keychainService,
            kSecAttrAccount as String:  keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Test seam
    //
    // `resetForTests()` clears the Keychain entry. Exposed `internal`
    // (not public) so production code can't accidentally call it.
    // Tests use `@testable import VakterShared`.
    internal static func resetForTests() {
        deleteKey()
    }
}
