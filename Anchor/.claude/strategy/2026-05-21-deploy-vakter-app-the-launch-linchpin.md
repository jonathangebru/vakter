# Deploy vakter.app — the launch linchpin

**Date:** 2026-05-21
**Mode:** autonomous
**Confidence:** high
**Estimated effort:** small (agent work: 3-5 hours; human deploy step: ~30 minutes)
**Estimated leverage:** Every other marketing channel — Show HN, Product Hunt, Snazzy Labs outreach, 9to5Mac pitch, r/macapps, Setapp application, SEO, email capture — assumes a live `https://vakter.app` URL. Without deployment, those channels cannot run, no DMG download can happen, and no customer can give us money. Deployment is therefore the single root-of-graph dependency for moves 1-7 of the STRATEGY.md launch playbook (§6, §8). With ~4 months to Q3 2026 launch and SEO needing 6-12 weeks to begin compounding, the cost of every additional day undeployed is non-trivial.

## Context

State change since the last idle decision (2026-05-21 earlier today):
- GitHub Project v2 board "Vakter" now exists with 0 open items (https://github.com/users/jonathangebru/projects/1).
- Bootstrap consumed; inbox empty; team unblocked.
- `gh project` CLI scopes granted.

Vakter v1.4.1 is shipping-ready: notarized DMG (4.8 MB), in `/Applications`, daemon registered. The website is fully built at `Anchor/Website/` — landing page (`index.html`), press kit (`press/index.html`), concepts page (`concepts/index.html`), full favicon set, screenshots, press-kit ZIP, architecture diagram SVG, wordmark SVG. Hero copy matches the brand voice in `SECURITY.md` and matches STRATEGY.md §7's alternating-block template. It just isn't deployed anywhere.

STRATEGY.md §6 makes this dependency explicit: every one of the "top 5 highest-leverage moves for the next 30 days" assumes a live site. STRATEGY.md §8 puts website setup at Week -6 of the launch sequence — we are inside that window now.

Why this candidate over the others I evaluated:

- **Sparkle auto-update** (STRATEGY.md §9 item 4) — high leverage, but Sparkle requires an `appcast.xml` hosted at a stable URL. That URL has to exist before Sparkle is wired. Sequence after deployment.
- **Stripe / Paddle integration** — requires a human financial commitment (bank, tax setup, EU VAT decision). Strategy charter says "propose, don't commit" on financials. Premature.
- **CloudKit Dashboard schema** — blocked behind iOS provisioning. Wrong order.
- **iOS companion provisioning** — multi-day Apple Developer Portal work with a human in the middle at every step. Wrong shape for the AI team's first directive.

Deployment is the rare epic that is (a) high-leverage, (b) low-risk, (c) almost-entirely agent-completable, (d) with a tightly-bounded human handoff (one DNS config + one hosting account choice).

## Recommendation

Commission `vakter-brand-keeper` to produce a **deployment-ready snapshot** of `Website/` plus a **runbook** the human executes in one sitting. Concretely:

1. Pre-flight the existing site: link audit, asset audit, validate every `./assets/...` path resolves, confirm all `<a href>`s point somewhere (no `#` stubs), confirm the DMG download button has a concrete destination (placeholder OK if the DMG isn't hosted yet).
2. Add static-host config files at the `Website/` root for the host the human will pick: `_redirects`, `_headers` (Cloudflare Pages / Netlify format) — both formats can coexist harmlessly.
3. Add a placeholder `download/` route or rewrite rule that 302s to a future `releases/Vakter-1.4.1.dmg` URL — even if the DMG isn't on the CDN yet, the redirect target is reserved and stable.
4. Add a `/changelog`, `/security`, `/privacy` route that either resolves to a real page (preferred — pull existing `SECURITY.md` / `PRIVACY.md` into a styled HTML page that matches the brand) or 404s cleanly (do not 200 with empty content).
5. Draft `Website/DEPLOY.md` — a runbook the human can follow in 30 minutes to deploy on Cloudflare Pages (recommended: free, fast, no analytics, no third-party JS), with fallback instructions for Netlify and a "what to do after" checklist (DNS records, the email-forwarding setup for `support@vakter.app` and `security@vakter.app`, the analytics-free verification).
6. Validate everything offline (open `Website/index.html` in Safari + Chrome; verify both light and dark mode; verify Open Graph card preview).
7. Comment on the epic with a single-screenshot proof, the local preview command, and the deploy-step-count for the human.

Out of agent scope (these are the human's 30 minutes):
- Creating the Cloudflare Pages / Netlify account.
- Pointing DNS at the deployment.
- Approving the `vakter.app` domain on the host.
- First-time domain verification email click.
- Setting up `support@`/`security@` email forwarding.

## Risks

- **Risk: human chooses a different host (Vercel, GitHub Pages, S3+CloudFront).** Mitigation: the runbook emphasizes Cloudflare Pages first but lists alternatives. The site is static HTML/CSS/JS with zero build step, so any host works. Wasted effort: <1h if the human picks differently.
- **Risk: DMG isn't on a CDN yet, so the download button is a placeholder.** Mitigation: explicitly accept this. Phase 2 of deployment is "host the DMG"; phase 1 is "ship the marketing site." STRATEGY.md §8 lists these as separate weeks (-6 and -5). The placeholder button can be wired to a mailto-signup or "coming next week" copy in the interim — explicit decision for the agent to make.
- **Risk: deploying the site before we have email forwarding makes `support@vakter.app` and `security@vakter.app` un-routable, which is a credibility hit for security-conscious visitors.** Mitigation: the runbook includes email forwarding as a first-day post-deploy step (Cloudflare Email Routing is free, ~5 minutes).
- **Risk: the deployed site exposes claims (price, features, "notarised") that we don't fully back today.** Mitigation: brand-keeper validates every claim against `STRATEGY.md` + `SECURITY.md` + `PRIVACY.md` + actual shipped product behavior during pre-flight. Anything that doesn't hold today gets softened to "coming soon" or removed.

## Out of scope

What this memo is NOT proposing:
- Building a payment processor flow. Stripe/Paddle/Gumroad is a separate epic.
- Hosting the DMG on a CDN with a working download. Phase 2.
- Wiring Sparkle's `appcast.xml`. Separate epic (sequence after deployment).
- Email-capture / newsletter form. Defer until launch week.
- Plausible analytics. Defer (the brand voice says "no telemetry"; consider only after launch if needed).
- A blog at `vakter.app/blog/`. Defer until post-launch content cadence is decided.
- Multi-language localization. Defer.
- Restructuring `Website/`. The site is in good shape — pre-flight + thin-glue config, not a redesign.

## Directive (if action)

Linked file: `.claude/inbox/po/0002-deploy-vakter-app.md`
