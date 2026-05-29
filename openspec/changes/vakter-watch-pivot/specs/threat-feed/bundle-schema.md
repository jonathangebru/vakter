# Threat-feed bundle schema

> Canonical bundle format for Vakter's daily signed threat feed. This document is the single source of truth that ticket #61 (publisher) and ticket #62 (client consumer) must code against. Any divergence from this document is a bug in the implementation, not in the contract.

## Brand-contract reminder

Vakter's threat feed is:

- **Signed.** Every bundle ships an Ed25519 signature. The client refuses an unsigned or wrongly-signed bundle.
- **Daily.** Published once per UTC day at a deterministic time. Skipping a day is permitted; the client keeps the last-known-good bundle.
- **One-way.** The client downloads a public bundle. Vakter NEVER sends user data to the publisher. There is no network query API and no per-user state on the server.
- **Pattern-style** (like Apple's XProtect). The bundle is a flat list of known-bad indicators the client matches against locally. It is NOT a real-time threat-intelligence feed.
- **Optional.** The user can disable feed updates entirely and Vakter still works. Last-known-good is the floor, not the ceiling.
- **Free.** All paid tiers and the free tier get the same bundle. The feed is not a paywalled product.

Anything below that violates the contract is wrong and must be fixed before the publisher or client ships.

## Bundle layout

A bundle is a single gzipped tarball plus a detached signature, published under a stable URL.

```
https://feed.vakter.app/feed-YYYY-MM-DD.tar.gz       <- bundle
https://feed.vakter.app/feed-YYYY-MM-DD.sig          <- detached Ed25519 signature of the tarball
https://feed.vakter.app/latest.json                  <- pointer record: { "date": "YYYY-MM-DD", "sha256": "..." }
```

The publishing host is `feed.vakter.app`. The host name is hard-coded in the client and pinned at build time. There is no fallback host — if `feed.vakter.app` is unreachable, the client keeps last-known-good and waits.

Inside the tarball, the layout is flat. No nested directories.

```
feed-YYYY-MM-DD/
├── manifest.json
├── phishing-domains.txt
├── phone-numbers.txt
├── apple-support-fakes.txt
├── malware-bundle-ids.txt
├── sms-templates.json
├── romance-scam-patterns.json
├── package-scam-templates.json
└── sources.json
```

That's **1 manifest + 8 data files = 9 files total**. No more, no fewer. If a future revision needs to add a category, the schema version increments and the change is treated as breaking (see "Versioning rules" below).

## File-by-file specification

### `manifest.json`

The bundle's table of contents. Every other file in the bundle is listed here with its sha256. The client validates the signature on the tarball, then validates each file's sha256 against the manifest, then loads the file.

```json
{
  "schema_version": 1,
  "bundle_version": "2026.05.29",
  "published_at": "2026-05-29T06:00:00Z",
  "feed_host": "feed.vakter.app",
  "publisher_key_id": "vakter-feed-2026-q1",
  "files": [
    {
      "name": "phishing-domains.txt",
      "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "entry_count": 12483,
      "category": "phishing-domains"
    }
  ],
  "total_entry_count": 18920,
  "previous_bundle_version": "2026.05.28",
  "previous_bundle_sha256": "a1f2e9..."
}
```

Field semantics:

| Field | Type | Required | Meaning |
|---|---|---|---|
| `schema_version` | integer | yes | The schema this bundle conforms to. See "Versioning rules". Current: `1`. |
| `bundle_version` | string | yes | Date-based version of this bundle, format `YYYY.MM.DD`. Monotonic. Two bundles with the same date are forbidden. |
| `published_at` | RFC 3339 UTC timestamp | yes | The instant the publisher signed this bundle. Always UTC, always `Z` suffix. |
| `feed_host` | string | yes | The host the bundle was published from. Must match the client's compiled-in `feed.vakter.app`. Reject if it doesn't. |
| `publisher_key_id` | string | yes | Identifier of the Ed25519 key that signed the tarball. The client carries a list of known public keys keyed by this id. |
| `files` | array of `FileEntry` | yes | One entry per data file in the bundle. Must list exactly 8 entries — the 8 category files defined below. No more, no fewer. |
| `total_entry_count` | integer | yes | Sum of all `entry_count` across `files`. The client cross-checks this; mismatch is a hard reject. |
| `previous_bundle_version` | string | no | The previous bundle's `bundle_version`. First bundle ever published has this field absent. |
| `previous_bundle_sha256` | hex string | no | The previous bundle's tarball sha256. First bundle ever published has this field absent. |

`FileEntry`:

| Field | Type | Required | Meaning |
|---|---|---|---|
| `name` | string | yes | Filename inside the tarball. No path components. Must match `^[a-z][a-z0-9-]*\.(txt\|json)$`. |
| `sha256` | hex string (64 chars) | yes | Lowercase hex sha256 of the file's bytes. |
| `entry_count` | integer | yes | Number of indicators in the file. For `.txt` files, this is the line count excluding comment and blank lines. For `.json` files, this is the count of items in the file's top-level array. |
| `category` | string | yes | One of the 8 category slugs defined below. Must be unique across the `files` array. |

The signature in `feed-YYYY-MM-DD.sig` is Ed25519 over the raw bytes of `feed-YYYY-MM-DD.tar.gz`. NOT over the manifest, NOT over the uncompressed contents. The client verifies the signature first, then unpacks, then walks the manifest.

### `phishing-domains.txt`

Generic phishing domains. One lowercase domain per line. No protocol, no path.

```
# phishing-domains — Vakter threat feed 2026.05.29
# Source attribution lives in sources.json, not inline.
# first-seen YYYY-MM-DD as trailing comment on each domain.

apple-id-verify.example   # first-seen 2026-05-12
icloud-login.example      # first-seen 2026-05-14
```

Rules:

- Comment lines start with `#` and are ignored by the parser.
- Blank lines are ignored.
- Each non-comment line is `<domain>` or `<domain>  # first-seen YYYY-MM-DD`.
- Domains MUST be lowercase ASCII, punycode for IDN (`xn--...`).
- Domains MUST be eTLD+1 or deeper. No bare TLDs. No IP addresses (IP indicators belong in a future `malicious-ips` category, not here).
- The `entry_count` in the manifest is the number of non-comment, non-blank lines.

### `phone-numbers.txt`

Phone numbers known to be used by scam operations (tech-support scams, IRS-impersonation, etc.). E.164 format only.

```
# phone-numbers — Vakter threat feed 2026.05.29
+18005551234   # category=tech-support-scam first-seen=2026-05-09
+442012345678  # category=hmrc-impersonation first-seen=2026-05-22
```

Rules:

- One number per line, E.164 format (`+` followed by country code and digits, no spaces, no dashes).
- Trailing comment is optional but recommended for human review.
- The `entry_count` in the manifest is the number of non-comment, non-blank lines.

### `apple-support-fakes.txt`

Same format as `phishing-domains.txt`, but scoped to domains that specifically impersonate Apple Support, AppleCare, or Apple ID. The client treats matches here with a stronger UI warning ("This site is impersonating Apple") than generic phishing.

Rules: identical to `phishing-domains.txt`. The file is kept separate (not folded into `phishing-domains.txt`) so the client can apply category-specific UX without re-classifying at match time.

### `malware-bundle-ids.txt`

macOS `CFBundleIdentifier` strings of known-malicious apps. One per line.

```
# malware-bundle-ids — Vakter threat feed 2026.05.29
com.example.fakeupdater       # family=Adload first-seen=2026-04-30
com.example.fakeflashplayer   # family=Pirrit first-seen=2026-05-01
```

Rules:

- One bundle id per line. Format: reverse-DNS (`com.example.foo`).
- Trailing comment is optional; recommended fields are `family=<malware-family>` and `first-seen=YYYY-MM-DD`.
- Bundle ids are case-sensitive (Apple's spec).
- The `entry_count` in the manifest is the number of non-comment, non-blank lines.

### `sms-templates.json`

Regex patterns for known scam SMS message bodies. JSON array of pattern objects.

```json
[
  {
    "id": "usps-redelivery-2026-05",
    "pattern": "USPS:.{0,40}redelivery.{0,40}https?://",
    "category": "package-impersonation",
    "source_id": "fcc-scam-report-2026-05-15",
    "first_seen": "2026-05-15"
  }
]
```

Rules:

- Top-level is a JSON array of objects.
- `pattern` is an ICU/POSIX-extended regex (the subset that Foundation `NSRegularExpression` and Swift `Regex` both support). Anchors and lookahead are forbidden — keep patterns simple so they run cheaply on-device.
- `category` is a free-form lowercase-kebab-case string scoped to SMS scams (e.g. `package-impersonation`, `bank-otp-phish`, `irs-impersonation`).
- `source_id` references an entry in `sources.json`.
- `id` is unique across the file. The client uses it as the stable handle for "why was this flagged?" UI.
- The `entry_count` in the manifest is `array.count`.

### `romance-scam-patterns.json`

Narrative patterns identifying romance-scam conversations. These are not single regexes; they're scoring rules with multiple required signals.

```json
[
  {
    "id": "oil-rig-engineer-2026-q2",
    "narrative_tags": ["overseas-worker", "delayed-meet", "wire-request"],
    "minimum_signals": 2,
    "category": "romance-scam",
    "source_id": "ftc-romance-2026-q1",
    "first_seen": "2026-04-20"
  }
]
```

Rules:

- Top-level is a JSON array.
- `narrative_tags` is an array of tag slugs the client's local NLP layer (v1.7+) will score. Tags are a closed vocabulary; the publisher MUST NOT invent new tags without bumping `schema_version`.
- `minimum_signals` is how many tags must score above the client's threshold to consider this pattern a match. Always ≥ 1.
- `source_id` references `sources.json`.
- `id` is unique. `category` is `romance-scam`.
- The `entry_count` in the manifest is `array.count`.

### `package-scam-templates.json`

USPS, FedEx, DHL, Royal Mail, La Poste, etc. impersonator patterns. Distinct from `sms-templates.json` because these are cross-channel (SMS, email, web push) and have shipper-specific structure.

```json
[
  {
    "id": "fedex-customs-2026-05",
    "shipper": "fedex",
    "channels": ["sms", "email"],
    "pattern": "(?i)fedex.{0,40}customs.{0,40}(fee|hold)",
    "category": "package-impersonation",
    "source_id": "urlhaus-2026-05-21",
    "first_seen": "2026-05-21"
  }
]
```

Rules:

- Top-level is a JSON array.
- `shipper` is a closed vocabulary: `usps`, `fedex`, `dhl`, `ups`, `royal-mail`, `la-poste`, `dpd`, `posti`, `australia-post`, `canada-post`, `correos`, `deutsche-post`, `evri`, `other`. The publisher MUST NOT invent new shipper slugs without bumping `schema_version`.
- `channels` is an array drawn from `sms`, `email`, `web-push`. At least one entry required.
- `pattern`, `category`, `source_id`, `id`, `first_seen` follow the same rules as `sms-templates.json`.
- The `entry_count` in the manifest is `array.count`.

### `sources.json`

Per-category source attribution. Every `source_id` referenced from the pattern files MUST resolve here. Inversely, an unreferenced source is permitted but should be pruned by the publisher to keep the bundle small.

```json
{
  "sources": [
    {
      "id": "phishtank-2026-05-29",
      "name": "PhishTank",
      "url": "https://phishtank.org/",
      "license": "open-data",
      "categories": ["phishing-domains", "apple-support-fakes"],
      "fetched_at": "2026-05-29T05:30:00Z"
    },
    {
      "id": "urlhaus-2026-05-29",
      "name": "URLhaus (abuse.ch)",
      "url": "https://urlhaus.abuse.ch/",
      "license": "CC0",
      "categories": ["phishing-domains", "package-scam-templates"],
      "fetched_at": "2026-05-29T05:32:00Z"
    },
    {
      "id": "fcc-scam-report-2026-05-15",
      "name": "FCC Consumer Complaint Data",
      "url": "https://www.fcc.gov/consumer-help-center-data",
      "license": "public-domain",
      "categories": ["sms-templates", "phone-numbers"],
      "fetched_at": "2026-05-15T12:00:00Z"
    }
  ]
}
```

Rules:

- Top-level is an object with a single key `sources` whose value is an array. (This is the one file in the bundle whose top-level is NOT a bare array, so existing JSON-array readers don't accidentally treat it as data.)
- `id` is unique across the file.
- `license` is a closed vocabulary: `open-data`, `CC0`, `CC-BY`, `CC-BY-SA`, `public-domain`, `vakter-curated`, `proprietary-with-permission`. Anything `proprietary-with-permission` MUST also include a `permission_note` field; the publisher fails the build if it doesn't.
- `categories` lists which of the 8 category slugs this source contributed to. Must be a subset of the canonical 8.
- `fetched_at` is when the publisher last pulled this source.
- The `entry_count` for `sources.json` in the manifest is `sources.length`.

## Canonical category slugs

These are the 8 categories and their stable slugs. Every reference in the bundle MUST use exactly these strings. The client treats unknown category strings as a hard reject.

| Slug | File | Indicator type |
|---|---|---|
| `phishing-domains` | `phishing-domains.txt` | Domains, line-delimited |
| `phone-numbers` | `phone-numbers.txt` | E.164 numbers, line-delimited |
| `apple-support-fakes` | `apple-support-fakes.txt` | Domains, line-delimited (Apple-impersonation subset) |
| `malware-bundle-ids` | `malware-bundle-ids.txt` | macOS `CFBundleIdentifier` strings, line-delimited |
| `sms-templates` | `sms-templates.json` | Regex patterns for scam SMS bodies |
| `romance-scam-patterns` | `romance-scam-patterns.json` | Narrative scoring rules |
| `package-scam-templates` | `package-scam-templates.json` | Shipper-impersonation patterns |
| `sources` | `sources.json` | Source attribution |

`sources` counts as a category for schema-rigour purposes (the client must know how to parse it). It is the 8th. We do not use a 9th file for source attribution because every other category embeds `source_id` foreign keys.

## Versioning rules

We use a **two-axis** versioning model. Both axes appear in `manifest.json`.

### Axis 1 — `schema_version` (integer, semver-like for breaking changes)

`schema_version` increments only when the file shape changes in a way that breaks naive parsers.

- **Breaking (`schema_version + 1`):** removing a field, renaming a field, adding a required field, removing a category, renaming a category, changing the meaning of an existing field, adding a new file to the bundle, adding a new value to a closed vocabulary (`shipper`, `license`, `narrative_tags`).
- **Non-breaking (`schema_version` unchanged):** adding an optional field that the client may ignore, adding a new `source_id`, adding new indicators to any file.

The client MUST refuse a bundle whose `schema_version` is greater than the highest version the client knows. It keeps the last-known-good bundle and surfaces an "update Vakter" prompt to the user. This is the safety hatch that prevents a future publisher from accidentally bricking older clients.

The client MAY parse a bundle whose `schema_version` is lower than its own, but it SHOULD log a downgrade warning. In practice, the publisher monotonically increases `schema_version` and never re-issues old bundles at lower versions, so the lower-than-own case only happens during local testing.

Current `schema_version` is **`1`**.

### Axis 2 — `bundle_version` (string, `YYYY.MM.DD` for daily cadence)

`bundle_version` is the date the bundle was assembled, in `YYYY.MM.DD` form. Always monotonically increases. Two bundles with the same `bundle_version` are forbidden — if the publisher needs to re-publish on the same day (rare, for a hot-fix), the bundle version becomes `YYYY.MM.DD.N` where `N` is a 1-indexed counter (`2026.05.29.2` is the second publish on 2026-05-29).

The client uses `bundle_version` to decide "is this newer than what I have?" with a simple lexicographic compare: `2026.05.29 > 2026.05.28 > 2026.04.30`. The `.N` suffix sorts correctly under lexicographic compare because `.2` > `.10` is wrong — so when re-publishing on the same day, the suffix is zero-padded if it reaches 10: `.10` not `.10`. In practice we'll never re-publish 10 times in a day; this is a paper specification only.

### Why two axes instead of pure semver

Pure semver was tempting but wrong for a daily feed:

- A semver patch bump per day would push us through `0.365.0` in the first year and `0.730.0` in the second. Confusing.
- A semver minor bump per breaking change is what `schema_version` already does, just renamed.
- The date-form `bundle_version` makes "is this newer?" obvious to a human reading logs and crash reports. It also makes "is this stale?" trivial: today minus `bundle_version` in days.

We do NOT use a Unix-epoch counter because the publisher publishes at most once per day, the date form is more human-readable, and we want the file names on disk to sort sensibly without parsing.

### Why not a generation counter

A pure monotonic counter (`1`, `2`, `3`, ...) was the third option. We rejected it because it carries no semantic information and the client and operator both want to know "how old is this bundle?" at a glance. The date form encodes age directly.

## Client compatibility policy

The following are non-negotiable contracts the client (#62) must implement:

1. **Signature first.** Verify the Ed25519 signature against the embedded public key for `publisher_key_id` before touching the bytes inside the tarball. A bundle that fails signature verification is dropped without inspection.
2. **Schema-version gate.** After signature passes, parse `manifest.json` and check `schema_version`. If greater than the client knows, drop the bundle, keep last-known-good, log the version mismatch, and surface an "update Vakter" prompt the next time the user opens the app.
3. **Per-file sha256 check.** For every entry in `manifest.files`, compute the sha256 of the unpacked file and reject the whole bundle if any sha256 mismatches.
4. **Entry-count cross-check.** Sum the parsed `entry_count` from each `FileEntry` and reject if it doesn't equal `total_entry_count`.
5. **Atomic swap.** The client unpacks into a staging directory, validates everything, and only then atomically renames the staging dir over the active bundle dir. A power loss during validation must never leave the client with a half-applied bundle.
6. **Last-known-good floor.** If any of the above fails, the client retains its previous good bundle and continues operating with it. The feed being broken NEVER bricks the product.
7. **User-disabled mode.** If the user has turned off feed updates in Settings, the client does not contact `feed.vakter.app` at all. The last bundle on disk continues to be used, or — if the user has never had a bundle — the client operates with an empty indicator set. Vakter still works.

## Publisher contract (binding inputs for #61)

The publisher MUST:

- Build the bundle with exactly the 9 files defined above. The `manifest.files` array MUST have exactly 8 entries.
- Sign the tarball — not the manifest, not the uncompressed contents.
- Publish atomically. `latest.json` is updated last, after the tarball and signature are both reachable at their stable URLs. Until `latest.json` updates, the client cannot see the new bundle.
- Refuse to publish if any source carries `proprietary-with-permission` without a `permission_note`. This is a build-time hard fail in the GitHub Actions cron, not a runtime check.
- Refuse to publish if `total_entry_count` doesn't match the sum of `FileEntry.entry_count`. This is a build-time hard fail.

The publisher MUST NOT:

- Re-issue an old `bundle_version`. Old bundles are immutable.
- Push a `schema_version` that is more than 1 greater than the previous bundle. (A jump from `1` to `3` indicates lost bundles. The client refuses to skip schemas.)
- Embed any per-user data. The bundle is the same bytes for every Vakter installation in the world.

## Examples

Three minimal valid examples live alongside the JSON schemas at `Anchor/threat-feed/schema/examples/`:

- `examples/manifest.example.json` — a complete minimal manifest with 8 file entries.
- `examples/phishing-domains.example.txt` — a minimal valid domain file.
- `examples/sms-templates.example.json` — a minimal valid pattern file.

These examples validate against the JSON schemas in `Anchor/threat-feed/schema/`. Treat them as the smallest possible valid bundle: anything smaller is too sparse to be useful, anything larger is just more rows of the same shape.

## Out of scope for this document

- The publisher's GitHub Actions cron and Ed25519 key management (ticket #61).
- The client's download, verify, and atomic-swap implementation (ticket #62).
- The in-app inspector UI (ticket #63).
- The Settings toggle and offline banner (ticket #64).
- The security-watcher's review of curation logic (ticket #65).
- The public docs page at `vakter.app/feed/` (ticket #66).

Anything those tickets do MUST conform to this document. If a downstream ticket wants to change the bundle shape, it changes this document first and bumps `schema_version`.
