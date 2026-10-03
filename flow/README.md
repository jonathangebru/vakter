# FLOW site

Rebuilt listentoflow.com. Deployed to GitHub Pages from `main` by `.github/workflows/pages.yml`.

Live: https://jonathangebru.github.io/vakter/

Notes:
- `index.html` is the whole site (inline CSS + JS). `v1.html` is the previous version, linked as "Classic version".
- The On Air section embeds the SoundCloud player in an iframe (lazy, inside a closed `<details>`, with a plain link fallback). This replaces the "canvas waveform + link-out only" idea in `PLAN.md`, which was written for a sandboxed viewer that blocked embeds; GitHub Pages does not.
