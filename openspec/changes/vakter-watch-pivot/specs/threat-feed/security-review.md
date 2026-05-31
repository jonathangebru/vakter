# Threat-feed publisher — security-watcher review (ticket #65)

> Adversarial review of the threat-feed publisher merged in PR #96 (closes #61).
> Reviewer: vakter-security-watcher.
> Reviewed at: 2026-05-31.
> Scope: code review only — no changes to publisher code; HIGH/CRITICAL findings filed as separate p0 issues and cross-linked.

## 0. Sources of truth for this review

- Workflow: [`.github/workflows/threat-feed-publish.yml`](../../../../.github/workflows/threat-feed-publish.yml)
- Publisher Swift package: [`Anchor/threat-feed/publisher/`](../../../../Anchor/threat-feed/publisher/)
- Curated seed: [`Anchor/threat-feed/sources/apple-support-fakes-manual.txt`](../../../../Anchor/threat-feed/sources/apple-support-fakes-manual.txt)
- Committed public key: [`Anchor/threat-feed/keys/threat-feed-public.pem`](../../../../Anchor/threat-feed/keys/threat-feed-public.pem)
- Bundle contract: [`bundle-schema.md`](./bundle-schema.md)
- README (operator runbook): [`Anchor/threat-feed/publisher/README.md`](../../../../Anchor/threat-feed/publisher/README.md)

## 1. Threat model

The Vakter threat feed is **signed, daily, one-way, pattern-style**. The brand-contract reminder in `bundle-schema.md` §1 is the binding statement of what we must not break. Within that scope, an attacker has the following plausible objectives:

| # | Adversary | Goal | Capability needed |
|---|---|---|---|
| T1 | External attacker | Distribute a malicious "signed" bundle to all Vakter installs | Compromise the Ed25519 signing key (CI secret) |
| T2 | External attacker | Cause Vakter to flag a legitimate domain (apple.com, banks) as a scam | Poison one of the upstream sources (PhishTank submission, URLhaus reporter abuse, malicious PR into `apple-support-fakes-manual.txt`) |
| T3 | Supply-chain attacker | Get arbitrary indicators into the bundle | Operator compromise on PhishTank or URLhaus side; or DNS/MitM on the upstream CSV fetches |
| T4 | Squatter / spammer | Force a denial-of-service by inflating the bundle so it doesn't ship within the 30-min job timeout | Mass-submit phishing reports to PhishTank; abuse the FCC's open dataset |
| T5 | CI compromise | Read or exfiltrate the Ed25519 private key from a GHA runner | Compromise a step or a transitive build dependency (swift-crypto fork, wrangler npm package) |
| T6 | Replay attacker (CDN MitM) | Convince a client to consume an old but validly-signed bundle | Tamper with `latest.json` (unsigned pointer) |
| T7 | Social engineer | Land a malicious PR adding `apple.com` to the curated seed | Submit a PR with a plausible citation |
| T8 | Malformed-upstream attacker | Crash the publisher (DoS the feed) by injecting CSV content that breaks the parser | Submit a maliciously crafted CSV row |

This review evaluates the v1 publisher's resilience against T1–T8.

## 2. Findings, by severity

Severity ladder: CRITICAL → HIGH → MEDIUM → LOW → INFO.

### F1 — Secret interpolated directly into shell command line — **HIGH**

- **Where:** `.github/workflows/threat-feed-publish.yml:91`
- **Description:** The `Pick run mode` step interpolates the signing secret directly into the bash conditional:

  ```yaml
  if [ -n "${{ secrets.THREAT_FEED_ED25519_PRIVATE }}" ]; then
  ```

  GitHub Actions masks known-secret substrings in *log output*, but inline `${{ secrets... }}` expansion places the literal secret bytes into the rendered shell script that the runner executes. Three concrete risks:
  1. A malformed or pasted-with-extra-newlines PEM that contains shell metacharacters (`$(...)`, backticks, semicolons, glob characters) will be re-parsed by bash and may execute or echo into stderr before masking applies.
  2. The rendered shell script is briefly written to disk on the runner (under `/tmp/`) — any concurrent step or any build dependency with arbitrary-file-read could read it.
  3. Switching this conditional to "check if the secret env var is non-empty" requires the secret to be set as an `env:` map entry on the step, which is the documented hardening pattern.
- **Recommendation:** Replace the inline expansion with an `env:` map and reference the env var instead:

  ```yaml
  - name: Pick run mode
    id: mode
    env:
      THREAT_FEED_ED25519_PRIVATE: ${{ secrets.THREAT_FEED_ED25519_PRIVATE }}
    run: |
      if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
        MODE="${{ inputs.dry_run }}"
      elif [ -n "$THREAT_FEED_ED25519_PRIVATE" ]; then
        MODE="false"
      else
        MODE="true"
      fi
      echo "dry_run=$MODE" >> "$GITHUB_OUTPUT"
  ```

  This matches the pattern already used by the `Publish bundle (live)` step at L113–114, which is correct.
- **Status:** **open** (filed as GH issue — see §7).

### F2 — URLhaus parser does not filter `url_status=offline` rows — **MEDIUM**

- **Where:** `Anchor/threat-feed/publisher/Sources/VakterThreatFeedPublisher/Sources.swift:207–222` (`URLhausAdapter.parseCSV`)
- **Description:** URLhaus's `csv_recent` feed includes `url_status` at column index 3 with values `online`, `offline`, or `unknown`. The current parser pulls col[2] (the URL) regardless of the status. The brand contract is to ship indicators that are actively malicious; shipping offline / sinkholed URLs means we burn user time on false-positive warnings for dead infrastructure that's already been taken down. Compounded by F4 (no allowlist), this widens the false-positive surface.
- **Recommendation:** Add an `online`-only filter:

  ```swift
  guard cols.count > 3, cols[3].lowercased() == "online" else { continue }
  ```

  Alternative: switch the source URL from `csv_recent` to `csv_online` (URLhaus already exposes that endpoint), which guarantees online-only at upstream.
- **Status:** open (recommendation, not filing a separate issue per the review-doc charter; this rolls up under #65's curation findings).

### F3 — No sanity-allowlist of known-good domains — **MEDIUM**

- **Where:** `Anchor/threat-feed/publisher/Sources/VakterThreatFeedPublisher/Publisher.swift:283–311` (`gatherPhishingDomains`, `gatherPhoneNumbers`, `gatherAppleSupportFakes`)
- **Description:** The publisher applies no filter against legitimate-domain false-positives. If PhishTank's verified-online feed ever includes a submission of `accounts.google.com`, `appleid.apple.com`, `login.microsoftonline.com`, `github.com`, or a major bank's login portal, the publisher ships it into the bundle without contest. The acceptance criteria on ticket #65 explicitly call for this allowlist (apple, google, microsoft, cloudflare, github at minimum).
- **Recommendation:** Add a static allowlist module enumerating the eTLD+1 of: `apple.com`, `icloud.com`, `apple-cdn.com`, `appleid.com`, `google.com`, `gmail.com`, `googleusercontent.com`, `microsoft.com`, `microsoftonline.com`, `office.com`, `outlook.com`, `cloudflare.com`, `github.com`, `githubusercontent.com`, `amazon.com`, `amazonaws.com`, plus the top-20 US/EU bank login domains. Drop (and log) any indicator whose domain matches `^(.+\.)?<allowlisted-etld+1>$`. Run the allowlist filter *after* normalisation in `hostFromURL` and *before* the dedup write into the bundle. The list should live next to `apple-support-fakes-manual.txt` under `Anchor/threat-feed/sources/` so it's reviewable.
- **Status:** open (recommendation; rolls up under #65).

### F4 — FCC robocall dataset has no cross-day dedup or rate-limit handling — **MEDIUM**

- **Where:** `Anchor/threat-feed/publisher/Sources/VakterThreatFeedPublisher/Publisher.swift:295–302` (`gatherPhoneNumbers`); `Sources.swift:230–243` (`FCCRobocallAdapter`)
- **Description:** Two related concerns:
  1. The FCC adapter uses Socrata's `?$limit=2000` against the full open dataset. Without a `where` clause anchored on `date_received` or `issue`, the publisher pulls the most-recent 2000 *complaints*, not specifically robocalls or unwanted calls. The Socrata dataset (`sr6c-syda`) includes consumer complaints across many categories; filtering on `issue=Unwanted Calls` upstream would be cleaner.
  2. There is no rate-limit / retry safety. A single 5xx from `opendata.fcc.gov` raises straight out of `URLSessionFetcher.fetch` and crashes the publisher run. The daily cadence makes a one-shot failure non-catastrophic (the client just keeps last-known-good), but means a flaky upstream silently skips a day of updates. The dedup logic in `gatherPhoneNumbers` (L296) only deduplicates *within a single run*, not against yesterday's bundle. Two consecutive days will re-emit the same numbers — which is technically fine for the client (the bundle is a static snapshot, not a delta), but reviewers should know that "dedupe" here is intra-run only.
- **Recommendations:**
  1. Add `&$where=issue='Unwanted Calls'` to the Socrata URL.
  2. Wrap each `fetch()` in a 3-retry exponential-backoff loop in `URLSessionFetcher`, with a hard 60s timeout per attempt (already present) and a 5-minute overall budget. On final failure: log loudly, fall back to last-known-good for that category, do NOT fail the whole bundle build.
  3. Document explicitly in the README that dedup is intra-run only, not cross-day.
- **Status:** open (recommendation; rolls up under #65).

### F5 — Same-day re-publish race / non-atomic same-day counter — **MEDIUM**

- **Where:** `Publisher.swift:366–391` (`resolveBundleVersion`)
- **Description:** The same-day `.N` suffix is computed by `contentsOfDirectory` on the output dir, then picking `max + 1`. If two publisher invocations run concurrently (e.g. a human triggers a manual `workflow_dispatch` while the cron run is in flight), both can read `max = 0` and both produce `feed-YYYY-MM-DD.tar.gz` — the second one overwrites the first on disk. Cloudflare Pages would then see two deploys with different `latest.json` contents pointing to the same tarball but with possibly different signatures. The job has `timeout-minutes: 30` and no GHA concurrency group, so this race is reachable.
- **Recommendation:** Add `concurrency: { group: threat-feed-publish, cancel-in-progress: false }` to the workflow. Optionally also add a fail-fast check inside `resolveBundleVersion` that errors if the chosen output path already exists.
- **Status:** open (recommendation; rolls up under #65).

### F6 — `latest.json` is not signed — **MEDIUM**

- **Where:** `Publisher.swift:259–269` (latest.json write); `bundle-schema.md` §"Bundle layout"
- **Description:** `latest.json` carries `{ date, bundle_version, sha256 }` and points the client at the current bundle. The tarball is signed; `latest.json` is not. The spec says `latest.json` is updated last so partial publishes are not visible, but it doesn't address replay or tampering. An attacker who can MitM the Cloudflare Pages CDN edge (or the DNS for `feed.vakter.app`) for a single client can swap `latest.json` to point at an old-but-validly-signed tarball. The client (#62) is expected to compare `bundle_version` against its own last-known-good and reject regressions, which mitigates downgrade — but the publisher should still sign `latest.json` as defense-in-depth. The marginal cost is one extra Ed25519 sign per day.
- **Recommendation:** Emit `latest.json.sig` (Ed25519 over the bytes of `latest.json`) alongside `latest.json`. Client (#62) verifies before trusting the pointer. Bundle-replay protection then requires that the attacker compromise the signing key, which is the same bar as forging a bundle.
- **Status:** open (recommendation; rolls up under #65).

### F7 — Tar `mtime` is not deterministic — **LOW**

- **Where:** `Anchor/threat-feed/publisher/Sources/VakterThreatFeedPublisher/Tar.swift:68–69`
- **Description:** `mtime = UInt64(Date().timeIntervalSince1970)` writes the publisher's wall clock into each tar header. The author's comment acknowledges this is fine because we sign the tarball bytes verbatim. The integrity story holds (the client verifies whatever bytes were signed), but the bundle is now non-reproducible across runs even on identical inputs. That removes a useful audit primitive — a reviewer can no longer rebuild and byte-compare to confirm "this published bundle is what the source claims it is". Setting `mtime = 0` (or the manifest's `published_at`) preserves all of the existing semantics and adds reproducibility.
- **Recommendation:** Set tar entry mtime to a constant per run (e.g. `UInt64(config.bundleDate.timeIntervalSince1970)`). Combined with the already-`.sortedKeys` JSON encoder, the tarball becomes byte-deterministic on identical inputs.
- **Status:** open (recommendation; rolls up under #65 as "reproducibility nice-to-have").

### F8 — `actions/checkout` keeps git credentials on the runner for the whole job — **LOW**

- **Where:** `.github/workflows/threat-feed-publish.yml:55–57` (Checkout step)
- **Description:** `actions/checkout@v4` defaults to `persist-credentials: true`, which writes the GITHUB_TOKEN into `.git/config` for the duration of the job. The job processes the Ed25519 signing secret, so reducing credential surface area is a defense-in-depth win. The workflow has `permissions: contents: read` so token impact is bounded, but `persist-credentials: false` removes even that.
- **Recommendation:** `with: { persist-credentials: false }` on the checkout step.
- **Status:** open (recommendation).

### F9 — `wrangler` is `npm install -g`-ed at deploy time — **LOW**

- **Where:** `.github/workflows/threat-feed-publish.yml:171`
- **Description:** `npm install -g wrangler` pulls a fresh latest-tag every cron tick from the public npm registry. A wrangler-supply-chain compromise would land in the signing job with full read on the env (which holds the Ed25519 private key). Pinning a specific wrangler version and using `npm ci` against a checked-in `package-lock.json` would close this; even better is to pin a sha-tag and ideally move the deploy step into a separate job that does not see the signing secret.
- **Recommendation:** Pin wrangler (`npm install -g wrangler@<exact-version>`). Better: split the workflow into a `build-and-sign` job (sees the Ed25519 secret) and a `deploy` job (only sees Cloudflare secrets, downloads the artifact from the previous job). Cross-job secret isolation in GHA prevents a compromised deploy step from reading the signing key.
- **Status:** open (recommendation).

### F10 — Tar entry size cap silently constrains file names — **INFO**

- **Where:** `Tar.swift:52` (`fileNameTooLong` if `> 100` bytes)
- **Description:** The custom tar writer uses the v7 (old) tar format with a 100-byte name limit. The fixed file names (`phishing-domains.txt`, `sources.json`, etc.) are well under that — this is a non-issue today. Filing as INFO so future maintainers don't add a long category name without realising. If the schema ever evolves to per-shipper subdirectories, this will need to switch to ustar `prefix` or pax extended headers.
- **Status:** open (informational note).

### F11 — Publisher emits empty JSON arrays for 5 of 8 categories — **INFO**

- **Where:** `Publisher.swift:113–116` (the empty arrays); `Sources.swift:7–17` (README of the file)
- **Description:** The v1 bundle ships valid-but-empty `sms-templates.json`, `romance-scam-patterns.json`, `package-scam-templates.json`, plus an empty `malware-bundle-ids.txt`. This is explicitly intended (PR #96 description, ticket #65 widens coverage). Calling it out so it isn't misread as a curation gap. The bundle does pass schema rigour (8 files, 8 unique categories, total_entry_count sums correctly).
- **Status:** **accepted-risk** for v1; ticket #65 (this review) and follow-ons cover coverage.

## 3. Ed25519 key handling audit

| Check | Result | Evidence |
|---|---|---|
| Public key committed to repo | PASS | `Anchor/threat-feed/keys/threat-feed-public.pem` is tracked. |
| Private key never committed | PASS | `git log --all -p -- 'Anchor/threat-feed/keys/threat-feed-private.pem'` returns empty. `git ls-files \| grep -iE 'private.*pem\|priv\.pem\|\.key$'` returns no matches. |
| `.gitignore` defends against accidental commit | PASS | `.gitignore` contains `Anchor/threat-feed/keys/threat-feed-private.pem`, `Anchor/threat-feed/keys/*-private.pem`, `Anchor/threat-feed/keys/*.key` (three independent globs — defence in depth). |
| Private key sourced from GHA secret | PASS | Workflow L114 `THREAT_FEED_ED25519_PRIVATE: ${{ secrets.THREAT_FEED_ED25519_PRIVATE }}` is correctly scoped to the `Publish bundle (live)` step as an `env:` map entry. |
| Private key never written to disk by publisher | PASS | `Signer.swift:7–11` documents the rule. `Main.swift:76–80` reads the secret directly from `ProcessInfo.processInfo.environment` and passes it through `Signer.from(material:)`. No `write(to:)` or temp-file creation touches the key material. The `loadEd25519PrivateKey` function (`Signer.swift:75–116`) operates on the string in-memory only. |
| Public-key fingerprint matches README's claim | PASS | `openssl pkey -in Anchor/threat-feed/keys/threat-feed-public.pem -pubin -outform DER \| shasum -a 256` = `3b58f0422a324bfcefc7c24a8cd50328065db5d9c96a8a6ec79cf860bcadac36`. README says `The keypair fingerprint is 3b58f04…dac36 (sha256 of the public key DER)` — match. |
| Detached signature is over the raw tarball bytes (not the manifest) | PASS | `Publisher.swift:249` (`makeTar`) → `253` (`tarSHA = sha256Hex(tarball)`) → `255` (`config.signer.sign(tarball)`). Signature is over the gzipped tar bytes, exactly as the bundle-schema spec mandates. |
| Test suite includes a positive + negative signature round-trip | PASS | `PublisherTests.swift:126–152` (`testSignatureRoundTripsWithPublicKey`): positive verify with own pubkey, then negative verify with an unrelated key — both asserted. |
| Workflow performs `openssl pkeyutl -verify` against the committed public key after live signing | PASS | Workflow L133–145 (`Verify signature against committed public key`). |
| Signing secret is not leaked into a shell expansion | **FAIL → F1** | Workflow L91 — see finding F1 above. The `Publish bundle (live)` step at L113 uses the correct `env:` pattern, but `Pick run mode` at L84 uses inline `${{ secrets... }}`. |
| Key rotation has a defined process | PASS | README L188–202 documents quarterly rotation: generate new keypair, commit new public key (leave old in place during overlap), update GHA secret, ship a client release with the new key in its embedded key table. |

**Overall key-handling verdict:** PASS with one HIGH finding (F1) on workflow shell hygiene. Key material itself is handled correctly by the publisher; the gap is in the cron workflow's secret interpolation pattern.

## 4. Curation-logic audit (per source)

### 4.1 PhishTank (`PhishTankAdapter`)

- **License compliance:** PhishTank's `online-valid.csv` is verified+online entries only, distributed under their open-data terms (free for non-commercial / verified use). The publisher includes `License: open-data` in `sources.json` — correct.
- **Column robustness:** Parser finds the `url` column by header lookup (`Sources.swift:174`). Resilient to upstream re-ordering of columns. Does NOT depend on the `phish_id` numeric column — which is good, because PhishTank has historically renumbered the dataset.
- **`verified=yes` filter:** Not needed — the source URL `online-valid.csv` is already verified-only at upstream. Documented in the adapter doc comment.
- **Rate-limit / retry:** None. See F4.
- **Dedup:** Intra-run only (Publisher.swift:283–293).

### 4.2 URLhaus (`URLhausAdapter`)

- **License compliance:** URLhaus is CC0. Correctly attributed in `sources.json` (Publisher.swift:131–137).
- **Column robustness:** Parses by index, not header name (`Sources.swift:215`, col[2] = URL). URLhaus's docstring says "Field index 2 is the URL per the upstream README" but URLhaus has historically been stable on column order. Lower risk than parsing by header for this source.
- **`online` vs `offline`:** **NOT filtered** — see F2. Ships dead URLs.
- **Comment-line handling:** Correct — `if line.hasPrefix("#") ... { continue }` (L212).
- **Rate-limit / retry:** None. See F4.

### 4.3 FCC robocall (`FCCRobocallAdapter`)

- **License compliance:** US public-domain. Correctly attributed.
- **Column robustness:** Parser finds the column by *substring* match on `caller_id_number` or `phone` (`Sources.swift:252–254`). Resilient to Socrata renaming the column (the FCC has, in the past).
- **E.164 normalisation:** `normaliseUSPhone` (Sources.swift:384–392) accepts 10-digit (`8005551234`) and 11-digit-leading-1 (`18005551234`), rejects everything else, returns nil on anything ambiguous. Correct conservative behaviour ("false E.164 numbers are worse than no number" — author's comment).
- **Dataset filtering:** Pulls ALL recent complaints, not just "Unwanted Calls". See F4.
- **Cross-day dedup:** None — see F4. (Bundle is a static snapshot, so this is not a *correctness* bug; the same number can appear in consecutive days' bundles. Filed for visibility.)

### 4.4 Apple-support-fakes (manually curated)

- **License compliance:** `vakter-curated` — correctly attributed.
- **Parser robustness:** Strips comments (`# ...`), blank lines, trims trailing whitespace-prefixed comments. Lowercases. Tested at `PublisherTests.swift:212–224`.
- **Citation requirement:** Documented in the file header (must include `# source: <URL>` on the preceding line). Not enforced in code — relies on PR review. This is the highest-leverage place for a social-engineering attack (T7); see §5 for the supply-chain review.
- **Content audit:** All 10 entries use `.example` TLD. Per the file's own header (last review 2026-05-30) and the `.example` TLD convention, these are placeholder demonstrative entries, not real production indicators. v1 production will need real entries (with citations) before the seed is useful — but ALSO before a malicious PR is plausible.

### 4.5 Empty categories (malware-bundle-ids, sms-templates, romance-scam-patterns, package-scam-templates)

- v1 emits valid-but-empty files. Schema rigour is met (8 unique categories, 0 entries each). Accepted by review (PR #96, ticket #65 widens coverage).

## 5. False-positive controls

Per the spec's brand contract: false positives are worse than misses, because they break user trust and convert Vakter into a tool that warns about Apple's own properties.

### 5.1 Manual seed audit

Searched `Anchor/threat-feed/sources/apple-support-fakes-manual.txt` for the canonical-known-good patterns:

```
grep -iE 'google\.com|apple\.com|microsoft\.com|icloud\.com|aol|yahoo|outlook|github|cloudflare|amazon|facebook|wells|chase|bofa|paypal|venmo' \
  Anchor/threat-feed/sources/apple-support-fakes-manual.txt
```

Result: **zero matches.** Every entry uses the `.example` TLD (placeholder). PASS for v1, but this is mostly because the seed is illustrative rather than productionised. Once the seed contains real domains, the spot-check must run as a CI step.

### 5.2 Programmatic sanity allowlist

**NOT IMPLEMENTED.** See F3. The first time an attacker submits `accounts.google.com` to PhishTank and it gets through their verifier, the publisher will ship it. The fix is a static allowlist module — see F3's recommendation.

### 5.3 Recommended allowlist contents (for the F3 fix)

At minimum, the allowlist module should cover the eTLD+1 of:

- Apple: `apple.com`, `icloud.com`, `apple-cdn.com`, `appleid.com`, `mzstatic.com`, `cdn-apple.com`
- Google: `google.com`, `gmail.com`, `googleusercontent.com`, `googleapis.com`, `youtube.com`, `googlevideo.com`
- Microsoft: `microsoft.com`, `microsoftonline.com`, `office.com`, `outlook.com`, `windows.com`, `live.com`, `azurewebsites.net`
- Cloudflare: `cloudflare.com`, `cloudflareaccess.com`, `pages.dev`, `workers.dev`
- GitHub: `github.com`, `githubusercontent.com`, `github.io`
- Amazon: `amazon.com`, `amazonaws.com`, `awsstatic.com`, `cloudfront.net`
- US banks (top 20 by deposits): chase, wellsfargo, bankofamerica, citi, pnc, usbank, capitalone, etc.
- Major IdPs: okta.com, auth0.com, onelogin.com, duo.com

Match logic: drop if the candidate's eTLD+1 OR any subdomain `*.<allowlisted-etld+1>` matches.

## 6. Bundle-replay analysis

**Verdict: PASS for tarball replay; CONDITIONAL PASS for `latest.json` replay.**

Reasoning:

1. **Tarball-level replay:** The Ed25519 signature is over `tarball` (Publisher.swift:255). The tarball contains `manifest.json` (written at L246), which carries `bundle_version`, `published_at`, and `previous_bundle_version`/`previous_bundle_sha256`. Therefore the `bundle_version` is **inside the signed payload, not a header**. An attacker who captures yesterday's signed tarball cannot present it as a "new" bundle, because the signed manifest still says `2026.05.30`. The client (#62)'s `bundle_version` comparison rejects regressions per `bundle-schema.md` §"Client compatibility policy" #2.

2. **`latest.json` replay:** `latest.json` is unsigned (Publisher.swift:259–269). An attacker who can MitM the CDN can swap a current `latest.json` for an older one. This convinces the client to re-fetch an old (validly-signed) tarball. The client SHOULD reject if the older bundle's `bundle_version` is not strictly greater than its current last-known-good — that's the spec's mandate. But the publisher could harden this with a signed `latest.json.sig` (see F6). Without that, the chain of trust depends entirely on the client's regression check.

3. **First-fetch replay:** A fresh Vakter install with no last-known-good is theoretically vulnerable to "tricked into trusting an old bundle". Mitigation is the client's responsibility: the client should check `published_at` against the OS clock and refuse a bundle older than, say, 60 days. That's a client concern (#62), not a publisher concern.

**Recommendation:** Sign `latest.json` (F6). Defense-in-depth: even without a client-side regression check, an attacker cannot forge a `latest.json` pointing at any tarball they don't already have a signature for.

## 7. Recommendations (action list)

| ID | Action | Severity | Disposition |
|---|---|---|---|
| F1 | Move `secrets.THREAT_FEED_ED25519_PRIVATE` reference from inline expansion to `env:` map on the `Pick run mode` step. | HIGH | **File as separate p0 GH issue** (cross-link to this doc). |
| F2 | URLhaus parser: filter out `url_status != online` rows, or switch source URL to `csv_online`. | MEDIUM | v1.5.1 hardening — rolls up under #65. |
| F3 | Add static sanity-allowlist of known-good domains (Apple, Google, Microsoft, banks, GitHub, Cloudflare, …). Apply to all phishing-domain sources before write. | MEDIUM | v1.5.1 hardening — rolls up under #65. |
| F4 | (a) Add `&$where=issue='Unwanted Calls'` to the FCC Socrata URL. (b) Wrap fetchers in retry-with-backoff. (c) Document intra-run-only dedup. | MEDIUM | v1.5.1 / v1.6 — rolls up under #65. |
| F5 | Add `concurrency: { group: threat-feed-publish, cancel-in-progress: false }` to the cron workflow. | MEDIUM | v1.5.1 — rolls up under #65. |
| F6 | Sign `latest.json` and emit `latest.json.sig`. Client (#62) verifies before trusting the pointer. | MEDIUM | v1.6 consideration — rolls up under #65 (touches the client too). |
| F7 | Set tar entry `mtime` to a constant (e.g. `config.bundleDate`) for byte-deterministic bundles. | LOW | v1.6+ nice-to-have. |
| F8 | `actions/checkout` with `persist-credentials: false`. | LOW | v1.6+ defense-in-depth. |
| F9 | Pin `wrangler` to an exact version; ideally split publish into two jobs so the deploy step never sees the Ed25519 secret. | LOW | v1.6+ supply-chain hygiene. |
| F10 | Document tar name-length cap (100 bytes) so future schema changes don't blow past it. | INFO | doc-only. |
| F11 | Empty placeholder files for 5 categories — accepted for v1, follow-on tickets widen coverage. | INFO | accepted-risk. |

**Top recommendation for the next 30 days:** ship the fix for F1 (move the secret interpolation to an `env:` map). It's a one-line workflow edit and closes a HIGH-severity defense-in-depth gap before the first real production cron run signs anything.

## 8. Sign-off

The publisher's **core integrity story is sound**: keys are handled correctly inside the Swift code, the signed payload includes `bundle_version` (so replay of yesterday's tarball is detectable by the client), the public key fingerprint matches the README claim, and the test suite exercises sign-and-verify with both positive and negative key cases. Brand contract preserved: signed, daily, one-way, pattern-style, optional. Schema rigour holds (8 files, unique categories, total_entry_count cross-check).

The defects that exist are concentrated on the **edges** — the cron workflow's shell hygiene (F1), the lack of a sanity allowlist (F3), and URLhaus's online-vs-offline filter (F2). F1 is the only one rising to HIGH; the rest are MEDIUM hardening items that can land in v1.5.1 or v1.6 without delaying the first production run.

**Verdict:** **conditional sign-off** — production cron may run once F1 is fixed. F2 through F6 should land before the first published bundle contains real (non-placeholder) indicators, because that is when the false-positive risk becomes user-facing.

GitHub issues filed for HIGH/CRITICAL findings are referenced at the top of this section's table.
