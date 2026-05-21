# Deploying vakter.app — Runbook

Estimated time: 30 minutes for a technically comfortable human.
Assumed: you have a Cloudflare account (free tier is sufficient), access to the
registrar where `vakter.app` is registered, and this repo either cloned locally
or pushed to GitHub under `jonathangebru/vakter`.

---

## 1. Prerequisites

Before starting, confirm:

1. You can log in to `https://dash.cloudflare.com` (create a free account if not).
2. You have registrar access for `vakter.app` — specifically, the ability to
   change nameservers or add DNS records. If Cloudflare is already the DNS
   authority, skip Section 3's "point nameservers" step.
3. `jonathangebru/vakter` is pushed to GitHub and the branch you want to deploy
   is `main`.
4. The site root is `Anchor/Website/` relative to the repository root. That is
   the value you will enter as the build output directory.

No build step exists. The site is static HTML/CSS with no bundler, no npm, no
Node. Cloudflare Pages will treat this as a plain file upload.

---

## 2. Cloudflare Pages — primary path

### 2.1 Create the Pages project

1. In the Cloudflare dashboard, select **Workers & Pages** in the left sidebar.
2. Click **Create application**, then **Pages** → **Connect to Git**.
3. Authorise Cloudflare to access your GitHub account if prompted.
4. Select the repository `jonathangebru/vakter` and click **Begin setup**.

### 2.2 Configure the build

Fill in the fields exactly as follows:

| Field                   | Value                 |
|-------------------------|-----------------------|
| Project name            | `vakter`              |
| Production branch       | `main`                |
| Framework preset        | None                  |
| Build command           | *(leave empty)*       |
| Build output directory  | `Anchor/Website`      |
| Root directory          | *(leave empty)*       |

Leave all environment variables empty. Click **Save and Deploy**.

### 2.3 First deployment

Cloudflare will clone the repo, find `Anchor/Website/`, and deploy every file
in that directory. Watch the build log — it should complete in under 60 seconds.

When the log shows **Success**, Cloudflare gives you a preview URL in the form:
```
https://vakter-<hash>.pages.dev
```

Open that URL. Confirm:
- The landing page loads without console errors.
- `/security` and `/privacy` resolve.
- `/download` 302-redirects to GitHub Releases (it will 404 at the CDN until the
  first GitHub Release with a `Vakter.dmg` asset is published — that is expected).

If the preview URL is broken, check that the **Build output directory** field
is exactly `Anchor/Website` (no trailing slash, correct case).

### 2.4 Attach the custom domain

1. In the Pages project, go to **Custom domains** → **Set up a custom domain**.
2. Enter `vakter.app` (apex, no `www`). Click **Continue**.
3. Cloudflare will tell you the DNS record(s) to add. For an apex domain it will
   provision a `CNAME` flattened via Cloudflare's CNAME-at-root feature — this
   only works if Cloudflare is your DNS authority (see Section 3).
4. Once DNS resolves, Cloudflare issues a TLS certificate automatically via
   Let's Encrypt. No manual certificate steps are needed.

---

## 3. DNS records

Add the following records at your DNS authority. If you transfer DNS to
Cloudflare (recommended — free, fast propagation), you enter these in the
Cloudflare DNS dashboard for `vakter.app`. If you keep your current registrar
as the DNS authority, enter them there instead.

| Type  | Name    | Value / Target                          | TTL  | Proxy |
|-------|---------|-----------------------------------------|------|-------|
| CNAME | `@`     | `vakter.pages.dev`                      | Auto | Yes   |
| CNAME | `www`   | `vakter.app`                            | Auto | Yes   |

> **Note on the `@` CNAME (CNAME-flattening):** Standard DNS forbids a CNAME
> at the apex. Cloudflare resolves this transparently when Proxy is enabled —
> the record behaves as a CNAME in Cloudflare's edge but is returned to clients
> as A/AAAA records. This only works with Cloudflare as DNS authority.
>
> If you are keeping your current registrar as the authority and it does not
> support CNAME-at-root, use the ALIAS/ANAME record type if available, or
> point an A record at Cloudflare's IP (check the Cloudflare dashboard for the
> current IP when you attach the custom domain).

The `www` CNAME points to the apex. Because the `www` DNS entry goes through
Cloudflare's proxy alongside the `_redirects` rules in `Anchor/Website/_redirects`,
traffic to `www.vakter.app` is served by the same Cloudflare Pages deployment.
If you want `www` to issue a 301 to the apex, add this line to `_redirects`:

```
https://www.vakter.app/* https://vakter.app/:splat 301
```

That rule is not in the current `_redirects` file — add it if canonical-apex
is a priority for SEO.

### DNS propagation

Global propagation typically completes in 5–30 minutes with Cloudflare. If
`vakter.app` does not resolve after 30 minutes, run:

```bash
dig +short vakter.app
dig +short www.vakter.app
```

If both return IP addresses, DNS is resolving. If the TLS cert is still
pending in the Cloudflare dashboard, wait another 5 minutes and refresh.

---

## 4. Email forwarding via Cloudflare Email Routing

Cloudflare Email Routing is free and takes roughly five minutes.

### 4.1 Enable Email Routing

1. In the Cloudflare dashboard, select the `vakter.app` zone.
2. In the left sidebar, go to **Email** → **Email Routing**.
3. Click **Get started** and follow the activation wizard.
4. Cloudflare will offer to add the required MX and SPF records automatically.
   Accept. The records added will be:

| Type | Name      | Value                              | Priority |
|------|-----------|------------------------------------|----------|
| MX   | `@`       | `route1.mx.cloudflare.net`         | 36       |
| MX   | `@`       | `route2.mx.cloudflare.net`         | 71       |
| MX   | `@`       | `route3.mx.cloudflare.net`         | 59       |
| TXT  | `@`       | `v=spf1 include:_spf.mx.cloudflare.net ~all` | — |

Do not add these manually — let the wizard add them to avoid typos.

### 4.2 Add the forwarding rules

After enabling Email Routing:

1. Click **Routing rules** → **Create address**.
2. Enter `support@vakter.app` → Destination: `jonathangebru@gmail.com`. Save.
3. Repeat: `security@vakter.app` → `jonathangebru@gmail.com`. Save.

Cloudflare will send a verification email to `jonathangebru@gmail.com`.
Click the link in that email within 24 hours or the forwarding rules will
not activate.

### 4.3 Verify

Send a test email from any external address to `support@vakter.app`. It should
arrive at `jonathangebru@gmail.com` within a minute. Repeat for `security@vakter.app`.

If email does not arrive, check **Email** → **Email Routing** → **Activity log**
in the Cloudflare dashboard for delivery errors.

---

## 5. Post-deploy verification checklist

Run these checks after DNS has propagated and TLS is active.

### 5.1 HTTP and headers

```bash
# TLS and headers — should return HTTP/2 200
curl -sI https://vakter.app | head -20

# Expected headers present:
# strict-transport-security: max-age=63072000; includeSubDomains; preload
# x-content-type-options: nosniff
# x-frame-options: DENY
# referrer-policy: strict-origin-when-cross-origin
# permissions-policy: camera=(), microphone=(), geolocation=(), payment=()

# /download redirect — should return 302 to GitHub Releases
curl -sI https://vakter.app/download

# /press trailing-slash redirect — should return 301
curl -sI https://vakter.app/press

# /concepts trailing-slash redirect — should return 301
curl -sI https://vakter.app/concepts
```

> The `/download` redirect will follow through to a 404 at GitHub until the
> first GitHub Release (`v1.0.0` or similar) with a `Vakter.dmg` asset is
> published. The redirect itself is correct; the target is a placeholder.
> See `_redirects` line 20 and its comment for the Phase 2 CDN migration plan.

### 5.2 Page load checks

- [ ] `https://vakter.app` loads; hero copy visible; no console errors in Safari.
- [ ] `https://vakter.app/security` loads the styled security page.
- [ ] `https://vakter.app/privacy` loads the styled privacy page.
- [ ] `https://vakter.app/changelog` loads (or 404s cleanly — confirm current state).
- [ ] `https://vakter.app/download` issues a 302 to GitHub Releases.
- [ ] `https://vakter.app/press/` loads the press kit page.
- [ ] `https://vakter.app/concepts/` loads the concepts page.

### 5.3 Open Graph

Paste `https://vakter.app` into `https://metatags.io` or the
[Cloudflare Radar URL Scanner](https://radar.cloudflare.com/scan).

Confirm:
- `og:title` is populated.
- `og:description` is populated.
- `og:image` renders (check the press assets path resolves under `/assets/`).

### 5.4 Light mode and dark mode

Open `https://vakter.app` in Safari. Toggle System Preferences → Appearance
between Light and Dark. The site uses `prefers-color-scheme` CSS; both should
look correct with no broken contrast areas.

### 5.5 Lighthouse baseline

Run once, record the score. This is a baseline — not a gate.

```bash
# Requires Node + lighthouse installed
npx lighthouse https://vakter.app --only-categories=performance,accessibility,best-practices,seo --output=json | python3 -c "
import json, sys
d = json.load(sys.stdin)
for k, v in d['categories'].items():
    print(f'{k}: {round(v[\"score\"]*100)}')"
```

Expected baseline for a static site with no third-party JS and system fonts:
Performance ≥ 90, Accessibility ≥ 90, Best Practices ≥ 90, SEO ≥ 90.
If any category is below 80, check the Lighthouse report for specifics before
recording the baseline in the team notes.

### 5.6 Email verification

- [ ] Send a test email to `support@vakter.app` from an external address.
      Confirm it arrives at `jonathangebru@gmail.com`.
- [ ] Send a test email to `security@vakter.app`.
      Confirm it arrives at `jonathangebru@gmail.com`.

---

## 6. Netlify — fallback path

Use this section only if you prefer Netlify over Cloudflare Pages. The
`_redirects` and `_headers` files in `Anchor/Website/` use the same syntax
for both hosts — no changes needed.

The steps below assume you have a Netlify account.

1. In the Netlify dashboard, click **Add new site** → **Import an existing project**.
2. Choose GitHub, authorise Netlify, select `jonathangebru/vakter`.
3. Set the build settings:

   | Field                  | Value            |
   |------------------------|------------------|
   | Base directory         | `Anchor/Website` |
   | Build command          | *(leave empty)*  |
   | Publish directory      | `Anchor/Website` |

4. Click **Deploy site**. Netlify gives you a `*.netlify.app` preview URL.
5. Attach the custom domain: **Domain settings** → **Add custom domain** →
   enter `vakter.app`. Netlify will prompt you to add a DNS record.

**DNS for Netlify:** Netlify does support CNAME-at-root via their load
balancer if you use Netlify DNS. If you keep an external DNS provider:

| Type  | Name  | Value                         |
|-------|-------|-------------------------------|
| A     | `@`   | `75.2.60.5` *(Netlify's IP)* |
| CNAME | `www` | `vakter.netlify.app`          |

> Check `https://docs.netlify.com/domains-https/custom-domains/` for the
> current Netlify load-balancer IP — this can change.

**Email forwarding:** Netlify does not offer email routing. If you deploy to
Netlify, add a Cloudflare Email Routing-only configuration: add `vakter.app`
to Cloudflare as a DNS-only zone (no proxying), enable Email Routing, then
point your registrar's nameservers to Cloudflare so MX records are served
from Cloudflare while A/CNAME records resolve to Netlify. This is a valid
but slightly more complex configuration.

**Headers difference:** Netlify processes `_headers` files slightly differently
from Cloudflare Pages for wildcard patterns. If a header is missing after
deploy, check `https://docs.netlify.com/routing/headers/` for syntax nuances.
The current `Anchor/Website/_headers` file has been verified against both
parsers and should work as-is.

---

## 7. Rollback procedure

Cloudflare Pages keeps a full deployment history.

1. In the Cloudflare dashboard, go to **Workers & Pages** → **vakter** →
   **Deployments**.
2. Find the deployment you want to restore. Click the three-dot menu → **Rollback
   to this deployment**.
3. Cloudflare promotes that deployment to production immediately. No rebuild
   occurs; the previous file snapshot is served from the edge.

This takes under a minute and requires no git revert. Use it for immediate
relief if a new deploy breaks the site. Fix the underlying issue in the repo
and push a new commit to trigger a corrected deploy.

---

## 8. HSTS preload — Phase 2 (30+ days after launch)

The `_headers` file already sets:
```
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
```

The `preload` directive is a declaration of intent, not an automatic action.
To get `vakter.app` added to browser HSTS preload lists:

1. Wait at least 30 days after initial deployment with no downtime.
2. Verify `https://vakter.app` and `https://www.vakter.app` both resolve
   correctly over HTTPS.
3. Submit at `https://hstspreload.org/`.
4. The site will be reviewed and added to Chrome's preload list (also consumed
   by Firefox, Edge, Safari). This is a one-way door: removal takes months
   and requires a human review. Only submit when the domain is stable.

**Do not submit on launch day.** If the deployment has any issues in the first
30 days, the preload list makes them harder to recover from.

---

## 9. What can go wrong — honest notes

**Cloudflare Pages vs Netlify differences worth knowing:**

- Cloudflare Pages ignores `_headers` blocks that are missing their closing
  blank line. If a header is not appearing in `curl` output, check that the
  `_headers` file has a blank line after each pattern block.
- Netlify evaluates redirect rules top-to-bottom and stops at the first match.
  Cloudflare Pages also evaluates top-to-bottom. The current `_redirects` file
  has no overlapping rules, so order does not matter here.
- Cloudflare Pages CNAME-at-apex only works when Cloudflare is the DNS
  authority. If you keep external DNS and see an error when attaching the custom
  domain, the workaround is to either transfer DNS to Cloudflare or use an A
  record pointed at Cloudflare's IP (shown in the dashboard when you attach the
  custom domain).

**DNS propagation:**

- Internal DNS caches (ISP resolvers) can lag up to 24 hours even when TTL is
  short. If `vakter.app` resolves on your phone but not your laptop, flush the
  local DNS cache:
  ```bash
  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
  ```

**The `/download` redirect:**

- `_redirects` line 20 sends `/download` to
  `https://github.com/jonathangebru/vakter/releases/latest/download/Vakter.dmg`.
  This will 404 until a GitHub Release tagged (e.g.) `v1.0.0` exists with a
  `Vakter.dmg` asset attached. The redirect is correct; the destination is the
  placeholder. Create the release to make the download live — no change to the
  site files required.

**TLS certificate delays:**

- Cloudflare issues certificates via Let's Encrypt. On a newly attached custom
  domain this can take 5–15 minutes. The Cloudflare dashboard shows certificate
  status under **Custom domains**. If the cert is stuck for more than 30 minutes,
  verify that the CNAME records are resolving and that there is no CAA record at
  the registrar blocking Let's Encrypt.

**Email forwarding verification email:**

- The Cloudflare forwarding verification email expires in 24 hours. If you miss
  it, go to **Email** → **Email Routing** → **Routing rules** and resend the
  verification. The forwarding rules will not activate until the destination
  address is verified.
