# Make vakter.app deployment-ready and hand the human a 30-minute runbook

**Strategy memo:** `.claude/strategy/2026-05-21-deploy-vakter-app-the-launch-linchpin.md`
**Priority:** p1 (this sprint — root-of-graph dependency for every launch channel)
**Estimated complexity:** small

## Epic title for the board
Deploy vakter.app: pre-flight the static site, add host config, write the human's 30-minute deploy runbook

## Goal

`vakter.app` is live on the open internet by end of week. The agent team produces a deploy-ready `Website/` snapshot — every link resolves, every asset is referenced correctly, every claim matches shipped product behavior, host config files exist, and a runbook tells the human exactly which buttons to click in Cloudflare Pages (and which DNS records to add at the registrar) to take the site from zero to live in ~30 minutes.

"Done" means: the human can run the runbook in one sitting and have a working `https://vakter.app` resolving to the landing page with a valid TLS cert, with `support@vakter.app` and `security@vakter.app` mailboxes routing to the human's personal email.

## Acceptance criteria (epic-level)

- [ ] Every internal `<a href>` in `Website/` resolves to a real page or asset (no `#` stubs, no 404s). Tracked in a checklist in the epic comment.
- [ ] Every `./assets/...` referenced from `index.html`, `press/index.html`, `concepts/index.html` exists on disk. Tracked.
- [ ] Every external claim (price `$29 one-time`, "Notarised", "Apple Silicon", "macOS Sequoia", "20 defenses checks", feature counts) is verified against `STRATEGY.md` + `SECURITY.md` + `PRIVACY.md` + the README's feature table. Mismatches are softened to "coming soon" or removed. List the verification in the epic comment.
- [ ] `Website/_redirects` and `Website/_headers` exist with sane defaults (`/download` -> placeholder release URL; HSTS; `X-Content-Type-Options`; `Referrer-Policy: strict-origin-when-cross-origin`; cache headers for `/assets/*`).
- [ ] Routes for `/changelog`, `/security`, `/privacy` either render real styled pages (preferred — `SECURITY.md` and `PRIVACY.md` content piped into the existing brand template) or are deliberately omitted with a comment explaining why. No empty 200 responses.
- [ ] `Website/DEPLOY.md` exists with: Cloudflare Pages step-by-step (primary), Netlify fallback, DNS record table, email-forwarding setup, post-deploy verification checklist, rollback notes.
- [ ] The Open Graph card (`./assets/screenshots/og-image.png`) renders correctly when previewed via a standard OG validator (note: agent can verify metadata is set correctly; live OG check is post-deploy).
- [ ] Light mode and dark mode both look correct when opened locally in Safari and Chrome. Screenshot proof attached to the epic comment.
- [ ] The hero CTA's destination is decided: either it points to a placeholder "download coming next week" anchor, or to a reserved `/download` redirect (preferred). Explicit decision documented.
- [ ] Brand-keeper has run a final voice-pass: zero banned words ("leverage", "synergy", "empower", "unleash", "boost productivity", "AI-powered", "revolutionary", "game-changing", "next-generation"); every sentence could appear in `SECURITY.md`.
- [ ] The ticket is moved to `Review` for human approval. Human runs the runbook. Site goes live. Human comments "live at https://vakter.app" on the epic. Epic moves to `Done`.

## Suggested Features for PO to file

1. **Site pre-flight: link + asset audit** [agent:vakter-brand-keeper] — Walk every `<a href>` and `./assets/...` reference in `Website/index.html`, `Website/press/index.html`, `Website/concepts/index.html`. Confirm each resolves. Fix the ones that don't (either by softening copy or by adding the missing target).
2. **Claim verification pass** [agent:vakter-brand-keeper] — Cross-reference every product claim on the site against `STRATEGY.md`, `SECURITY.md`, `PRIVACY.md`, `README.md`, and `BACKLOG.md`. Anything that doesn't hold today gets softened, removed, or marked "coming soon." List the mismatches in the ticket comment.
3. **Static host config: `_redirects` + `_headers`** [agent:vakter-brand-keeper] — Write Cloudflare Pages / Netlify-compatible config files at `Website/_redirects` and `Website/_headers`. Include the `/download` placeholder redirect, security headers (HSTS, X-Content-Type-Options, Referrer-Policy), and asset cache rules.
4. **Render SECURITY.md and PRIVACY.md as styled web pages** [agent:vakter-brand-keeper] — Take the existing `SECURITY.md` and `PRIVACY.md` content and render them as `Website/security/index.html` and `Website/privacy/index.html` using the existing landing-page palette + type stack. No copy changes — the markdown content is canonical; this is a pure visual conversion.
5. **Stub `/changelog` route** [agent:vakter-brand-keeper] — Create `Website/changelog/index.html` with the v1.4.1 release as its first (and only) entry. Voice matches Panic / 1Password release notes: terse, technical, no hype. Future releases append here.
6. **Write DEPLOY.md runbook** [agent:vakter-brand-keeper] — `Website/DEPLOY.md`. Primary path: Cloudflare Pages. Cover: account creation expectations, GitHub repo connection, build settings (none — static), domain attachment, DNS records to add at the registrar, the email-forwarding setup via Cloudflare Email Routing (`support@` and `security@` to the human's personal email), post-deploy verification checklist (TLS cert valid, OG card renders, both light/dark mode visible), rollback procedure. ~150-300 lines, structured as numbered steps the human can check off.
7. **Final voice pass + commit** [agent:vakter-brand-keeper] — Read every changed file. Run grep for banned words. Confirm tone matches `SECURITY.md`. Commit the changes with a single coherent commit message. Comment on the epic with the local preview command (`open Website/index.html`) + screenshot proof + the deploy-step count. Move ticket to `Review`.

## Anti-scope

What PO must NOT file as part of this epic:
- Wiring a payment processor (Stripe, Paddle, Gumroad). Separate epic.
- Hosting the DMG on a CDN. Phase 2 — needs the deployed site infra first.
- Wiring Sparkle's `appcast.xml`. Separate epic — depends on this one.
- Email-capture / newsletter form. Defer.
- Plausible / Fathom / any analytics. The brand voice says "no telemetry"; revisit only after launch if conversion data is needed.
- Building a blog index or first blog post. Defer until post-launch.
- Redesigning the site. The site is in good shape — this is pre-flight + thin-glue config, not a redesign.
- Touching product code under `Sources/`, `iOS/`, `WatchOS/`, `Package.swift`, `Scripts/`, `Tests/`.
- Multi-language localization.
- Manually creating the Cloudflare account, doing the DNS, or clicking the verification email. Those are the human's steps and live in `DEPLOY.md`, not in agent-executed work.
- Posting anything to social, press, or third-party services. Brand-keeper is draft-only.

## Reading priority for PO

- `Anchor/STRATEGY.md` §6 (channel playbook), §7 (website template), §8 (launch sequence) — explains why deployment is the linchpin.
- `Anchor/Website/index.html` — see the existing state of the site.
- `Anchor/Website/press/index.html` — see the press-kit page.
- `Anchor/Website/concepts/index.html` — see the concepts page.
- `Anchor/SECURITY.md` and `Anchor/PRIVACY.md` — canonical source content for the new `/security` and `/privacy` pages.
- `Anchor/.claude/agents/vakter-brand-keeper.md` — the agent's charter, especially the "voice calibration" and "deployment is human-pushed for now" notes.
- `Anchor/.claude/strategy/2026-05-21-deploy-vakter-app-the-launch-linchpin.md` — the strategy memo this directive implements.
