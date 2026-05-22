# Vakter — press kit copy

## 50 words

Vakter is your Mac's bodyguard — against the grab and against the clipboard.
Press one hotkey and your Mac goes on watch. The instant someone threatens
it — lid closes, cable disconnects, or a web page drops a malicious shell
command into your clipboard — Vakter steps in.
€29, one-time. https://vakter.app

## 150 words

Vakter is your Mac's bodyguard — the deterrent and evidence layer Apple
deliberately doesn't ship, now expanding to cover digital threats as well
as physical ones. A single hotkey arms your Mac. The instant someone tries
to walk off with it, Vakter screams a 100 dB siren, captures a photo burst
from the camera, records ten seconds of ambient audio, and texts your phone
an Apple Maps URL pinning the last known location. Every event is sealed
into a tamper-evident SHA-256 chain.

In v1.6 (coming Q3 2026), Vakter adds a clipboard shield for ClickFix paste
attacks: it intercepts shell commands written to your clipboard by web pages
and explains what they do before you paste into Terminal. Same watch, wider
scope.

Solo-developer indie. macOS 14+, Apple Silicon native, Notarised by
Apple. €29 one-time with a 14-day full trial. https://vakter.app

## 500 words

Vakter ("the night-watchmen", Norwegian) is a macOS menubar utility that
guards your Mac against physical and digital threats — for the people who
realised that nothing actually fires at the moment of theft, and who know
that the most dangerous malware in 2025 arrived not through a vulnerability,
but through a paste.

The physical watch is straightforward. Press a hotkey on the way out the
door and Vakter goes "on watch". When the lid closes, the power cable
disconnects, the user's trusted Bluetooth devices leave the room, or the
Find My token clears, the deck wakes: a 100 dB siren, a photo burst from
the front camera, ten seconds of ambient audio, and an iMessage to your
phone with a Maps pin — all within seconds, before the Mac has reached the
next table.

Every state transition is sealed into a SHA-256 Merkle chain on disk,
so the resulting event log is tamper-evident and exports to a single-page
PDF with device serial, photo manifest, audio paths, location trail, and
chain-of-custody verification — designed to be handed to a police officer
or insurance adjuster without explanation.

The digital watch arrives in v1.6 (Q3 2026). ClickFix is a social-
engineering technique that writes a malicious shell command to your clipboard
and walks you through pasting it into Terminal. ESET measured a 500% jump
in ClickFix activity in H1 2025; it became the second-largest macOS malware
loader vector of the year. Apple added a binary paste warning in macOS 26.1
— it says "possible malware, blocked" with no explanation, which users learn
to dismiss. Vakter's clipboard shield intercepts writes from browsers and
tells the user in one sentence what the command does, distinguishing a
legitimate Homebrew installer from a Matryoshka stealer one-liner. The
analysis runs on-device using Apple's Foundation Models framework — no
clipboard text leaves your Mac.

The architecture is deliberately small. A menubar SwiftUI app talks to a
helper LaunchAgent over XPC; the helper owns the state machine, observers,
and (in v1.6) the pasteboard watcher. A separate privileged daemon, roughly
150 lines of Swift and signed by Apple's Developer ID, has exactly one job:
toggle `pmset disablesleep` while armed. Everything else runs as the user,
no elevated privilege required. No kernel extension, no System Extension,
no network traffic in normal operation.

Five modes adapt the temperament: Normal, Travel, Library, Loaner, and Café.
No cloud, no telemetry, no accounts. Closed-source by deliberate choice;
trust earned through notarisation, Hardened Runtime, a tiny privileged
surface, and a public commitment to fund a paid third-party audit at €50k MRR.

Solo-developer indie. macOS 14 (Sonoma) and later, Apple Silicon native,
Notarised. €29 one-time with a 14-day full trial. Optional €12/year covers
major-version updates after year one.

https://vakter.app · support@vakter.app · security@vakter.app
