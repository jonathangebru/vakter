# Vakter — Quick facts

- **Name** — Vakter ("the night-watchmen", Norwegian)
- **What** — macOS menubar security utility. Guards your Mac against physical and digital threats.
- **Who** — Jonathan Gebru, solo developer
- **Where** — Built in plain Swift on a Mac
- **When** — v1.4.3 current. v1.6 (ClickFix Paste Shield) targeting Q3 2026.
- **Price** — €29 one-time. 14-day full trial. €12/yr optional for major-version updates
- **Distribution** — Direct DMG download from vakter.app (not Mac App Store; the privileged daemon cannot be sandboxed)
- **Requirements** — macOS 14.0+ (Sonoma), Apple Silicon (M1+), internal camera/mic/speakers
- **Code-signing** — Developer ID Application, Team ID 9TA5GB5UJH, Notarised by Apple
- **Source** — Closed-source, by deliberate choice (see SECURITY page)
- **Privacy** — No cloud. No telemetry. No accounts. Activity Monitor shows zero outbound calls. The v1.6 clipboard shield runs on-device — no text leaves the Mac.
- **Audit** — Public commitment to a paid third-party security audit at €50k MRR
- **Site** — https://vakter.app
- **Press** — press@vakter.app
- **Security** — security@vakter.app (90-day coordinated disclosure)
- **Support** — support@vakter.app

## Tagline candidates

- "The watch that never sleeps." (primary)
- "Calm in normal use. Fierce when someone threatens it — in person or on your clipboard."
- "Your Mac's bodyguard — physical or digital."

## Positioning, one paragraph

Find My is recovery. Vakter is the moment — and the watch is expanding.
Find My locates your Mac after it's already gone — needs the device powered,
signed-in, and online. Vakter operates earlier: the instant the lid closes,
the cable pulls, or your trusted devices leave the room, Vakter screams a
siren, captures photos and audio, and texts your phone with a Maps pin.
Starting in v1.6, Vakter also watches your clipboard: when a web page drops
a shell command there and you move to paste it into Terminal, Vakter steps in
and explains what the command does before it runs. They're complementary
threats; one product covers both.

## Seven most quotable lines

- "Find My is recovery. Vakter is the moment."
- "~150 lines of Swift with exactly one job."
- "No cloud. No telemetry. No accounts."
- "The deterrent + evidence layer Apple deliberately doesn't ship."
- "Calm in normal use. Fierce the moment someone threatens it — in person or on your clipboard."
- "Apple tells you the paste is blocked. Vakter tells you why."
- "Your Mac's bodyguard against every threat that shows up at the dock."
