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

    // MARK: - Origin
    //
    // Tracks *how* the user arrived at their current license — independent
    // of *what* they're entitled to (which is `Tier`). Specifically: did
    // they install v1.5 fresh, or did they upgrade from v1.4.x?
    //
    // Why a separate enum (instead of e.g. a `.freeGrandfathered` Tier
    // case):
    //  1. Existing `isPaid()` + every Tier switch in the codebase stays
    //     correct by construction. Adding a fourth Tier case would force
    //     every switch (MenuBarController, future AI feature gates, etc.)
    //     to grow a new arm, and the smallest miss could silently downgrade
    //     a grandfathered user OR silently unlock paid features for them.
    //  2. Cleanly separates "what you have access to" (Tier — feature gates
    //     read this) from "where you came from" (Origin — analytics +
    //     messaging read this). Single-responsibility per type.
    //  3. The brand contract — "anti-theft stays free forever" — means a
    //     v1.4.4 upgrader is conceptually a free user. Only the provenance
    //     differs, so origin is metadata, not entitlement.
    //
    // Stored in Keychain under the same service but a different account
    // so it lives alongside the license without leaking into UserDefaults
    // (consistent with the rest of the license surface).
    public enum Origin: String, Codable, Sendable, Equatable {
        /// Net-new v1.5 install. The default for anyone who installed
        /// Vakter after the v1.5 release.
        case fresh
        /// Upgraded from v1.4.x. Detected by the presence of v1.4.x-era
        /// UserDefaults markers at first v1.5 launch. v1.4.4 owners are
        /// grandfathered into the Free tier per the pricing contract;
        /// this flag exists so the menubar / settings can render upgrade
        /// affordances that acknowledge "thanks for being a v1.4 user"
        /// rather than treating them as a brand-new install.
        case upgraded
    }

    // MARK: - Keychain item identity
    //
    // All kept private — only `LicenseManager` should know the exact
    // Keychain coordinates. The service name is documented in the
    // ticket so support staff can recognise it in a user's Keychain
    // Access dump.

    private static let keychainService = "app.vakter.mac.license"
    private static let keychainAccount = "default"
    /// Distinct account on the same service for the per-install origin
    /// value (`Origin` enum). Kept on the license service so a `security
    /// dump-keychain` audit pulls both rows together, and so deactivate /
    /// "Sign out of this Mac" wipes both with one query if we ever add
    /// that affordance.
    private static let keychainOriginAccount = "origin"

    /// UserDefaults flag that the v1.4.4 → v1.5 grandfather migration
    /// has run on this account. Stored in UserDefaults (NOT Keychain)
    /// because it is not a secret — it is operational state — and we
    /// need a fast, side-effect-free way for `migrateFromV144IfNeeded`
    /// to early-exit on every launch after the first. Idempotency
    /// guarantee depends on this marker.
    private static let migrationDoneKey = "vakter.license.migration.v144.done"

    /// The UserDefaults key Vakter v1.4.x wrote when the user finished
    /// the post-rebrand onboarding flow (see `OnboardingState` in
    /// `Onboarding.swift` v1.4.4). Universally present on any Mac that
    /// ran v1.4.4 past first-launch onboarding, and NOT something the
    /// migration itself writes — so its presence at migration time is
    /// a strong signal "this user existed before v1.5". Net-new v1.5
    /// installs won't have it set when the migration check runs,
    /// because the migration runs in `applicationDidFinishLaunching`
    /// BEFORE the onboarding sheet is presented (which is the only
    /// place this key is written).
    private static let v144OnboardingMarkerKey = "vakter.onboarding.completed"

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

    /// Whether AI / paid-tier features (Mail Watch, Messages Watch, Web
    /// Watch, LLM chat panel) should be unlocked for the current user.
    ///
    /// This is the **single source of truth** every AI-feature surface
    /// MUST call. It deliberately delegates to `isPaid()` so a
    /// grandfathered v1.4.4 user — who has `Origin.upgraded` but
    /// `Tier.free` — does NOT get paid features for free. The pricing
    /// contract is "anti-theft stays free forever" (including for
    /// upgraders) but AI features are gated by purchase.
    ///
    /// Why a dedicated method instead of just calling `isPaid()` at
    /// every call site:
    ///   1. Intent at the call site reads as "is THIS feature unlocked"
    ///      rather than "is the user paid" — easier to grep, easier to
    ///      audit.
    ///   2. If the gating model ever changes (e.g. a v1.6 trial period
    ///      that briefly unlocks AI for free users), we change one
    ///      method body rather than every call site.
    ///   3. Tests can verify the AI gate semantics independently of the
    ///      generic isPaid() check.
    public static func isAIFeatureUnlocked() -> Bool {
        return isPaid()
    }

    /// The origin of this install — net-new v1.5 (`.fresh`) vs an
    /// upgrade from v1.4.x (`.upgraded`). Defaults to `.fresh` if no
    /// value is stored (which is the correct posture for any code path
    /// that runs before `migrateFromV144IfNeeded()` has had a chance to
    /// set it, or on a fresh install where the migration was a no-op
    /// before we adopted the explicit "fresh" write below).
    ///
    /// Like `currentTier()`, this reads Keychain on every call rather
    /// than caching, so a future "Reset all data" affordance immediately
    /// reflects in callers without an app restart.
    public static func currentOrigin() -> Origin {
        guard let raw = readOrigin(),
              let parsed = Origin(rawValue: raw) else {
            return .fresh
        }
        return parsed
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
    ///
    /// We deliberately do NOT clear the `Origin` row here — a v1.4.4
    /// upgrader who later activates Essential and then deactivates is
    /// still a v1.4.4 upgrader. Origin is install-provenance, not
    /// session state.
    public static func deactivate() {
        deleteKey()
        NSLog("[LicenseManager] deactivated — tier reset to free")
    }

    /// One-shot migration: if this Mac was running Vakter v1.4.x and is
    /// now booting v1.5 for the first time, grandfather the user into
    /// the Free tier with `Origin.upgraded`. Net-new v1.5 installs are
    /// left alone (their origin will be read as `.fresh`).
    ///
    /// MUST be called from `applicationDidFinishLaunching` BEFORE any
    /// UI shows — the detection signal is the v1.4.x onboarding marker
    /// in UserDefaults, and the v1.5 onboarding sheet writes to that
    /// same key. If we ran the check after onboarding, a net-new user
    /// would be misidentified as an upgrader on their second launch.
    ///
    /// Idempotency contract:
    ///   - First call writes `migrationDoneKey = true` in UserDefaults
    ///     regardless of whether the user was identified as an upgrader.
    ///   - Subsequent calls see the flag and return immediately. No
    ///     Keychain access, no UserDefaults writes, no log line on the
    ///     hot path.
    ///   - Calling this twice in a single launch is therefore a free
    ///     no-op on the second call, as required by the unit-test
    ///     contract.
    ///
    /// Detection rule (intentionally conservative — false negatives are
    /// better than false positives, because a missed v1.4.4 user can
    /// still pay €29 for AI features and a false grandfathered net-new
    /// user shows no functional difference at v1.5, but DOES skew our
    /// "how many upgraders did we have" analytics):
    ///   - Keychain `app.vakter.mac.license` must be empty (any stored
    ///     license — paid or otherwise — means the user has already
    ///     interacted with v1.5's license surface; don't touch them).
    ///   - UserDefaults `vakter.onboarding.completed` must be `true`
    ///     (means v1.4.x ran onboarding to completion on this Mac).
    ///
    /// What we write when the rule matches:
    ///   - `Origin.upgraded` to Keychain. We do NOT write a license
    ///     key — there's no key to write; the user is on the free tier
    ///     and `currentTier()` returns `.free` from "no key stored",
    ///     which is exactly what we want for the grandfather case.
    ///
    /// What we write when the rule does NOT match (net-new install):
    ///   - `Origin.fresh` to Keychain. Explicit so `currentOrigin()`
    ///     returns a non-default value on a clean v1.5 install and
    ///     analytics can distinguish "we wrote .fresh" from "the
    ///     read defaulted because the row is missing".
    public static func migrateFromV144IfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationDoneKey) else {
            // Already ran. Hot-path no-op — no Keychain touch, no log.
            return
        }

        // Mark done immediately. Even if the writes below partially
        // fail (Keychain locked, etc.), we never want to re-run this
        // detection: re-running risks misidentifying a now-onboarded
        // v1.5 user as an upgrader.
        defaults.set(true, forKey: migrationDoneKey)

        let keychainEmpty = (readKey() == nil)
        let v144MarkerPresent = defaults.bool(forKey: v144OnboardingMarkerKey)

        if keychainEmpty && v144MarkerPresent {
            writeOrigin(.upgraded)
            NSLog("[LicenseManager] v1.4.x upgrader detected — origin=.upgraded, tier remains .free (grandfathered)")
        } else {
            // Either a net-new install OR an existing v1.5 user with a
            // license already stored. In both cases the origin is
            // .fresh (we never overwrite an existing licence's origin
            // because this branch only runs when the migration-done
            // flag was unset, which is itself a one-shot signal).
            writeOrigin(.fresh)
            NSLog("[LicenseManager] migration: net-new install, origin=.fresh (keychain empty=%@, v1.4 marker=%@)",
                  keychainEmpty ? "yes" : "no",
                  v144MarkerPresent ? "yes" : "no")
        }
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

    // MARK: - Origin Keychain helpers (private)
    //
    // Same storage posture as the license key: per-device Keychain row,
    // ThisDeviceOnly accessibility (so origin doesn't roam to a Mac
    // that didn't run v1.4.4). The value is the `Origin.rawValue`
    // string — small, stable, future-proof against adding new cases.

    private static func readOrigin() -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  keychainService,
            kSecAttrAccount as String:  keychainOriginAccount,
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
    private static func writeOrigin(_ origin: Origin) -> Bool {
        let data = origin.rawValue.data(using: .utf8) ?? Data()
        deleteOrigin()
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  keychainService,
            kSecAttrAccount as String:  keychainOriginAccount,
            kSecValueData as String:    data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func deleteOrigin() {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  keychainService,
            kSecAttrAccount as String:  keychainOriginAccount
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
        deleteOrigin()
        // Also wipe the migration-done flag + the v1.4.x marker so each
        // test starts from a "clean install" baseline. We touch BOTH so
        // a test can independently set the v1.4.x marker to simulate an
        // upgrader without first-launch tests leaking that signal into
        // net-new-install tests.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: migrationDoneKey)
        defaults.removeObject(forKey: v144OnboardingMarkerKey)
    }

    /// Test seam: lets a test set the v1.4.x onboarding marker without
    /// reaching into the (private) UserDefaults key constant from the
    /// test file. Internal-only — production code never touches the
    /// onboarding marker through `LicenseManager`; that's owned by
    /// `OnboardingState` in the app target.
    internal static func _testSetV144Marker(_ present: Bool) {
        let defaults = UserDefaults.standard
        if present {
            defaults.set(true, forKey: v144OnboardingMarkerKey)
        } else {
            defaults.removeObject(forKey: v144OnboardingMarkerKey)
        }
    }
}
