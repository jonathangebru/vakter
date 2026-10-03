# FLOW — site rebuild plan

Source: https://listentoflow.com (WordPress + Elementor, dark, grain overlay, white logo).
FLOW is DJ Franky Rizardo's brand: a weekly radio show / podcast (655+ episodes), touring club events, a fashion shop.

## 1. Feature inventory of the original

Header
- Logo (white FLOW wordmark), nav: Events · Radioshows · Fashion (shop.listentoflow.com) · Franky Rizardo (frankyrizardo.com) · Tickets button · Search.

Home
- "All events" / "FLOW presents": featured event card — FLOW x Luxor Live, Luxor Live Arnhem, March 23, "More info coming soon".
- "Franky Rizardo presents FLOW": 7 event tiles (LTF Records ADE Label Night, FLOW ADE Gashouder, FLOW Factory Basel, FLOW Austin, FLOW Argentina, FLOW Brazil, FLOW Peru) + "View all events".
- "Radio Shows / Listen to FLOW": 10 latest episodes (655, 651, 649, 646, 644, 642, 641, 640, 639, 637) — each just a title + same boilerplate links block (Spotify playlist, YouTube, Apple Podcasts, SoundCloud, socials). "View all Shows".
- Footer: social icons (Facebook, Instagram, TikTok, Twitter, YouTube, Apple), Go to (Shows, Events, Tickets), Newsletter → Subscribe, Info (Terms, Privacy).

/events — grid of the same 7 event cards (no dates shown, no filters).
/tickets — table of events with venue, date, provider and status:
  LTF Records ADE Label Night · Palladium, Amsterdam · Oct 22 · Weeztix · Available
  FLOW ADE Gashouder · Gashouder, Amsterdam · Oct 24 · Sold out
  FLOW Factory Basel · Factory Town, Miami · Dec 2 · Available
  FLOW Austin · The Concourse Project, Austin · Dec 3 · ItsFramework · Sold out
  FLOW Argentina · La Fabrica, Córdoba · Dec 7 · Paseshow · Available
  FLOW Brazil · São Paulo · Dec 11 · Ingresse · Available
  FLOW Peru · Lima · Dec 12 · Ticketmaster Peru · Available
/shows — paginated list (26 pages), "FLOW NNN – DD.MM.YY", some "Live from …" variants, "Listen now" links. No embedded player, no tracklists.
/subscribe — single email field + consent checkbox + Subscribe button.

Weaknesses to beat: no dates on event cards, no player, shows are just titles with duplicated link spam, no search that works for shows, no sense of "what's next", slow Elementor page, inconsistent image ratios.

## 2. What "better" means here

Keep: the identity (black, white wordmark, grain), the content and all the real outbound links.
Add:
1. "Next up" hero with live countdown to the next event (dates from the tickets table) and the latest episode one tap away.
2. Events as a timeline with real dates, city, venue, provider and status pills (Available / Sold out / Announced), with Upcoming / Past toggle.
3. Episodes browser: generated archive of episodes (number, date, "Live from …" where known) with instant client-side search by number/date/venue, and per-episode listen links (SoundCloud, Apple, Spotify, YouTube) instead of one boilerplate block.
4. Listen strip: a canvas waveform visual as the brand's "signal", with the latest episode's links. (Real embeds are blocked by the viewer sandbox; link out.)
5. Newsletter form that works as UI (validation, success state) — no backend, clearly labelled.
6. Share: a "Share on WhatsApp" link (https://wa.me/?text=…) — the user wants to send this to someone on WhatsApp.
7. Fast: one HTML file + local images, no jQuery/Elementor, loads instantly; works at 400px; keyboard focus states; reduced-motion respected.

## 3. Build spec (for the Opus build agent)

Output: /home/user/vakter/flow/index.html, images in /home/user/vakter/flow/img/ (already downloaded, referenced relatively as img/…).
Follow the Artifact page contract (no doctype/html/head/body wrappers; <title> + <style> first; CDN allowlist; no iframes; no external images; theme tokens on :root; dark-first design with light variants).
Title: "FLOW"
Sections: header (sticky) · hero "Next up" · Events timeline · Listen (latest episode + waveform) · Episodes archive w/ search · Fashion/Franky strip · Newsletter · Footer.
Design: dark-first, grain texture (img/grain.gif as overlay, low opacity), display face with real character (not Inter/Space Grotesk), tight uppercase labels, generous whitespace, one accent that reads as club-lighting (pick deliberately). Mobile-first.
