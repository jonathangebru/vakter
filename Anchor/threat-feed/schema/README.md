# Vakter threat-feed schema — design-time reference

This directory holds the JSON Schema files and minimal examples for the Vakter daily threat-feed bundle. The **canonical narrative spec** lives at:

> `openspec/changes/vakter-watch-pivot/specs/threat-feed/bundle-schema.md`

Read that first. This directory is the machine-readable counterpart. If the two disagree, the narrative spec wins and a JSON Schema fix is needed here.

## What lives here

```
Anchor/threat-feed/schema/
├── README.md                                       <- you are here
├── manifest.schema.json                            <- JSON Schema for manifest.json
├── categories/
│   ├── phishing-domains.schema.json                <- post-parse shape (per-row)
│   ├── phone-numbers.schema.json                   <- post-parse shape
│   ├── apple-support-fakes.schema.json             <- post-parse shape
│   ├── malware-bundle-ids.schema.json              <- post-parse shape
│   ├── sms-templates.schema.json                   <- raw JSON shape
│   ├── romance-scam-patterns.schema.json           <- raw JSON shape
│   ├── package-scam-templates.schema.json          <- raw JSON shape
│   └── sources.schema.json                         <- raw JSON shape
└── examples/
    ├── manifest.example.json
    ├── phishing-domains.example.txt
    └── sms-templates.example.json
```

This directory is **design-time only**. It is NOT bundled into Vakter.app. It exists so:

- The publisher (#61) can validate its output before uploading.
- The client (#62) and other tickets have a single machine-readable contract to write decoders against.
- Reviewers can spot bundle-shape drift in PRs without reading prose.

## The 8 categories (canonical slugs)

| Slug                      | File                          | Indicator type                                |
|---------------------------|-------------------------------|-----------------------------------------------|
| `phishing-domains`        | `phishing-domains.txt`        | Lowercase domains, line-delimited             |
| `phone-numbers`           | `phone-numbers.txt`           | E.164 numbers, line-delimited                 |
| `apple-support-fakes`     | `apple-support-fakes.txt`     | Apple-impersonation domains                   |
| `malware-bundle-ids`      | `malware-bundle-ids.txt`      | macOS `CFBundleIdentifier` strings            |
| `sms-templates`           | `sms-templates.json`          | Regex patterns for scam SMS bodies            |
| `romance-scam-patterns`   | `romance-scam-patterns.json`  | Narrative scoring rules                       |
| `package-scam-templates`  | `package-scam-templates.json` | Shipper-impersonation patterns                |
| `sources`                 | `sources.json`                | Per-category source attribution               |

## Versioning rule — at a glance

Two axes:

1. **`schema_version`** (integer, current `1`) — bumps only on breaking changes (removed field, renamed field, new required field, new closed-vocabulary value). Clients refuse bundles whose `schema_version` is greater than they know.
2. **`bundle_version`** (`YYYY.MM.DD`) — bumps once per day. Monotonic. Lexicographic compare works. Same-day re-publishes use `YYYY.MM.DD.N` (rare hot-fix only).

Full justification (why two axes, why not pure semver, why not an epoch counter) is in the narrative spec.

## Signing

- Algorithm: **Ed25519**.
- Signed payload: the raw bytes of `feed-YYYY-MM-DD.tar.gz` (not the manifest, not the uncompressed contents).
- Signature file: `feed-YYYY-MM-DD.sig` (detached, raw 64-byte Ed25519 signature).
- Key rotation: quarterly. `publisher_key_id` follows `vakter-feed-YYYY-q[1-4]`.
- Public keys: hard-coded in the client binary at build time, keyed by `publisher_key_id`. There is no key-discovery network call.

## How to validate

Until the publisher (#61) lands, validate by hand:

```sh
# parse-check
python3 -m json.tool Anchor/threat-feed/schema/manifest.schema.json > /dev/null
python3 -m json.tool Anchor/threat-feed/schema/examples/manifest.example.json > /dev/null

# schema validation (with `check-jsonschema` if installed)
check-jsonschema \
  --schemafile Anchor/threat-feed/schema/manifest.schema.json \
  Anchor/threat-feed/schema/examples/manifest.example.json
```

The publisher (#61) will wire this into CI. The client (#62) will reproduce the same validation on-device using `JSONSerialization` and explicit Codable types (separate concern — not part of this design ticket).

## What is NOT in scope here

- Swift Codable types. Per issue #60, this design ticket does not touch `Sources/`. The publisher (#61) and client (#62) will add their own types.
- Publisher implementation, signing CI, key-management runbook (ticket #61).
- Client download / verify / atomic-swap logic (ticket #62).
- Settings UI for "disable threat-feed updates" (ticket #64).
- The public docs page at `vakter.app/feed/` (ticket #66).

## Cross-reference

- Canonical narrative spec: `openspec/changes/vakter-watch-pivot/specs/threat-feed/bundle-schema.md`
- Parent change proposal: `openspec/changes/vakter-watch-pivot/` (to be populated by the change-bootstrap dispatch)
- Parent epic: GitHub issue #59
- This ticket: GitHub issue #60
- Next tickets: #61 (publisher), #62 (client), #63 (inspector), #64 (controls), #65 (curation review), #66 (docs page)
