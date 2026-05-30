# Vakter threat-feed publisher

The daily, signed, one-way publisher half of Vakter's XProtect-pattern
threat feed. Builds a signed `feed-YYYY-MM-DD.tar.gz` per the
[bundle schema](../../../openspec/changes/vakter-watch-pivot/specs/threat-feed/bundle-schema.md)
and the [machine schemas](../schema/README.md).

This tool is a separate Swift package from the main Vakter app so it can
build on a clean CI runner without pulling in AppKit, XPC, SMAppService,
or the helper LaunchDaemon.

## What it does

1. Pulls indicators from public threat-intel sources.
2. Deduplicates and normalises per category.
3. Validates against the bundle schema (eight category files, unique
   slugs, total entry-count sums, etc.).
4. Writes the bundle to `out/v1/`, gzipped-tarred, and produces a
   detached Ed25519 signature.
5. Emits `latest.json` so the Cloudflare Pages deploy can swap atomically.

## Source coverage in v1

The publisher ships live adapters for **3 of the 8** category files:

| Category              | Source                            | License        | URL                                                      |
| --------------------- | --------------------------------- | -------------- | -------------------------------------------------------- |
| `phishing-domains`    | PhishTank (verified-online CSV)   | open-data      | https://data.phishtank.com/data/online-valid.csv         |
| `phishing-domains`    | URLhaus (abuse.ch) recent URLs    | CC0            | https://urlhaus.abuse.ch/downloads/csv_recent/           |
| `phone-numbers`       | FCC consumer-complaint unwanted-calls | public-domain | https://opendata.fcc.gov/resource/sr6c-syda.csv          |
| `apple-support-fakes` | Vakter manually-curated seed list | vakter-curated | `Anchor/threat-feed/sources/apple-support-fakes-manual.txt` |

The other 5 categories (`malware-bundle-ids`, `sms-templates`,
`romance-scam-patterns`, `package-scam-templates`, `sources` for them)
emit valid-but-empty files. Ticket #65 (curation review) is the
follow-on that widens coverage.

## Language choice — Swift, not Python

We picked Swift over Python because:

- CryptoKit / swift-crypto gives Ed25519 with no extra dependencies, and
  the same import path works on macOS dev boxes and the Linux GHA
  runners we may add later.
- The main Vakter codebase is Swift; one fewer toolchain to maintain.
- The publisher's bundle-shape contract is shared with the on-device
  client (ticket #62); having both written in Swift means the Codable
  types can eventually be lifted into a shared module if we want.

Python would have been fine too — the spec doesn't require Swift. If we
ever need to move to a Linux runner with a slim image, Python is the
escape hatch.

## Running it locally

### Dry-run (no network, ephemeral signing key)

```sh
cd Anchor/threat-feed/publisher
swift build
./.build/debug/vakter-threat-feed-publisher --dry-run --out out/v1
ls out/v1
```

`--dry-run` uses built-in fixture bytes for every adapter and generates a
throwaway Ed25519 keypair in memory. Nothing leaves the machine and the
output is not signed with the production key. Good for verifying the
pipeline on a laptop without the prod secret.

### Live run with the production key

```sh
# 1. Place your PEM private key somewhere local (never check it in)
export THREAT_FEED_ED25519_PRIVATE="$(cat ~/.config/vakter/feed-priv.pem)"

# 2. Run
./.build/debug/vakter-threat-feed-publisher \
  --out out/v1 \
  --key-id vakter-feed-2026-q2 \
  --apple-fakes-path Anchor/threat-feed/sources/apple-support-fakes-manual.txt
```

`THREAT_FEED_ED25519_PRIVATE` accepts either:

- a PKCS#8 PEM (output of `openssl genpkey -algorithm Ed25519 -out priv.pem`), or
- a 64-character lowercase hex string of the 32-byte raw seed.

The publisher never writes the private key to disk.

### Verifying a signature

The committed public key is `Anchor/threat-feed/keys/threat-feed-public.pem`.
To verify a published tarball:

```sh
openssl pkeyutl -verify \
  -pubin \
  -inkey Anchor/threat-feed/keys/threat-feed-public.pem \
  -rawin \
  -in out/v1/feed-2026-05-30.tar.gz \
  -sigfile out/v1/feed-2026-05-30.sig
# => Signature Verified Successfully
```

## CI workflow

`.github/workflows/threat-feed-publish.yml` runs every day at 03:00 UTC
on `macos-latest`. It builds the publisher, runs the test suite, and
either does a dry-run (if no signing secret is set) or signs with the
prod key and deploys the bundle to Cloudflare Pages.

Workflow-dispatch (manual) runs default to `dry_run: true`, so a human
can exercise the pipeline from the Actions tab without producing a
signed artifact.

## HUMAN ACTIONS REQUIRED (operator runbook)

These are the things only a human can do. Do them in order.

### 1. Generate the production Ed25519 keypair

On a trusted machine, in a directory **outside** any git worktree:

```sh
openssl genpkey -algorithm Ed25519 -out vakter-feed-2026-q2-priv.pem
openssl pkey -in vakter-feed-2026-q2-priv.pem -pubout -out vakter-feed-2026-q2-pub.pem
```

Verify the public key matches the one committed at
`Anchor/threat-feed/keys/threat-feed-public.pem` (a fingerprint diff is
enough):

```sh
openssl pkey -in vakter-feed-2026-q2-pub.pem -pubin -outform DER \
  | shasum -a 256
openssl pkey -in Anchor/threat-feed/keys/threat-feed-public.pem -pubin -outform DER \
  | shasum -a 256
# Two lines, identical sha256.
```

If the fingerprints do NOT match (because you regenerated the keypair),
commit your new `vakter-feed-2026-q2-pub.pem` over the old one and
re-deploy the client (ticket #62) so the embedded public key matches.

### 2. Store the private key as a GitHub Actions secret

```sh
gh secret set THREAT_FEED_ED25519_PRIVATE \
  --repo jonathangebru/vakter \
  < vakter-feed-2026-q2-priv.pem
```

After `gh secret set` confirms, securely erase the local PEM:

```sh
shred -u vakter-feed-2026-q2-priv.pem   # Linux
# OR
rm -P vakter-feed-2026-q2-priv.pem      # macOS bsd-rm
```

Or store it in 1Password / a hardware token — anywhere except the
filesystem of a developer laptop.

### 3. (Optional) Wire up Cloudflare Pages deploy

```sh
gh secret set CLOUDFLARE_API_TOKEN --repo jonathangebru/vakter
gh secret set CLOUDFLARE_ACCOUNT_ID --repo jonathangebru/vakter
gh variable set CLOUDFLARE_PAGES_PROJECT --body vakter-feed \
  --repo jonathangebru/vakter
```

The Cloudflare Pages project (`vakter-feed`) must already exist with
the custom domain `feed.vakter.app` attached.

Until these are set, scheduled runs still build + sign the bundle and
upload it as a GitHub Actions artifact. The deploy step is a no-op.

### 4. Verify the first scheduled run

After the next 03:00 UTC tick (or via `Actions → threat-feed-publish →
Run workflow → dry_run: false`):

- Workflow finishes green.
- The artifact `threat-feed-bundle` is downloadable.
- `latest.json` reachable at `https://feed.vakter.app/latest.json`.
- A manual verify with `openssl pkeyutl -verify` succeeds (see above).

## Key rotation

`publisher_key_id` follows `vakter-feed-YYYY-qN`. Rotate quarterly:

1. Generate a new keypair (step 1 above) with the next quarter's id.
2. Commit the new public key to `Anchor/threat-feed/keys/`, leaving the
   old public key file in place for one quarter (the client may still
   have last-known-good bundles signed with the old key).
3. Update `gh secret set THREAT_FEED_ED25519_PRIVATE` to the new private key.
4. Ship a client release whose embedded public-key table includes both
   the old and new public keys (the client refuses on
   `publisher_key_id` it doesn't recognise — both must be in the table
   during the overlap window).

## Tests

```sh
cd Anchor/threat-feed/publisher
swift test
```

Covers: end-to-end bundle build, manifest schema rigour, Ed25519
signature round-trip with both Swift-generated and OpenSSL-generated
keys, same-day re-publish `.N` suffix, source adapter parsers, and
PEM/hex private-key loading.

## What the publisher does NOT do

- **Push to the client.** Vakter installs poll `feed.vakter.app`; there
  is no per-user state on the server. See ticket #62 for the client.
- **Verify on download.** Verification is the client's job; the
  publisher just signs.
- **Phone home.** No telemetry. No analytics. The publisher does HTTP
  GETs to the upstream sources listed above and writes files to disk.
  That is the full network footprint.
- **Mutate already-published bundles.** Old bundles are immutable. Same-
  day re-publishes use the `.N` suffix per the bundle-schema spec.

## Cross-reference

- Bundle schema (canonical): `openspec/changes/vakter-watch-pivot/specs/threat-feed/bundle-schema.md`
- Machine schemas: `Anchor/threat-feed/schema/`
- This ticket: GitHub issue #61
- Parent Epic: GitHub issue #59
- Client consumer: GitHub issue #62
