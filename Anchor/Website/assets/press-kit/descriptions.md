# Vakter — press kit copy

## 50 words

Vakter is a calm anti-theft menubar app for macOS. Press one hotkey
and your Mac goes on watch. The instant someone grabs it — lid
closes, cable disconnects, your phone leaves the room — Vakter
screams, photographs, records audio, and texts your phone.
$29, one-time. https://vakter.app

## 150 words

Vakter is the deterrent + evidence layer Apple deliberately doesn't
ship. A single hotkey arms your Mac. The instant someone tries to
walk off with it, Vakter screams a 100 dB siren, captures a photo
burst from the camera, records ten seconds of ambient audio, and
texts your phone an Apple Maps URL pinning the last known location.
Every event is sealed into a tamper-evident SHA-256 chain, and a
police-ready PDF report can be exported on demand.

Five modes — Normal, Travel, Library, Loaner, Café — adapt grace
windows and audibility to context. The architecture is small and
legible: one privileged daemon, 150 lines of C, with exactly one
job. No cloud, no telemetry, no accounts.

Solo-developer indie. macOS 14+, Apple Silicon native, Notarised by
Apple. $29 one-time with a 14-day full trial. https://vakter.app

## 500 words

Vakter ("the night-watchmen", Norwegian) is a macOS menubar
anti-theft app for the people who realised, somewhere between Find
My's recovery-after-the-fact model and the cost of replacing a
stolen MacBook, that nothing actually fires at the moment of theft.

The model is straightforward. A user presses a hotkey — typically
on the way to the bathroom at the coffee shop, or while standing up
to leave a hotel lobby — and Vakter goes "on watch". When the lid
closes, the power cable disconnects, the user's trusted Bluetooth
devices leave the room, or the Find My token clears, the deck wakes.

What "the deck wakes" means in practice: the Mac plays a sample-
quality 100 dB siren with a multi-language voice cue ("This MacBook
is being tracked") in any of seven languages; the front-facing
camera captures a photo burst (three to thirteen JPEGs depending
on mode); the microphone records ten seconds of ambient audio at
22 kHz mono AAC; the location is probed via CoreLocation; an
iMessage goes out to a user-configured handle with the photos
attached and an Apple Maps URL pinning the last known coordinate.

Every state transition is sealed into a SHA-256 Merkle chain on
disk, so the resulting event log is tamper-evident and exports to a
single-page PDF with device serial, photo manifest, audio paths,
location trail, and chain-of-custody verification — designed to be
handed to a police officer or insurance adjuster without
explanation.

The architecture is deliberately small. A menu bar SwiftUI app
talks to a helper LaunchAgent over XPC; the helper owns the state
machine and all observers. A separate privileged daemon, roughly
150 lines of C and signed by Apple's Developer ID, has exactly one
job: toggle `pmset disablesleep` while armed so the lid-close
doesn't sleep the Mac before the alarm fires. Everything else runs
as the user, no elevated privilege required. The XPC peers are
pinned to Vakter's Team ID — any process not signed by us is
rejected at the connection layer.

Vakter is closed-source by deliberate choice. The trade-off:
auditability is replaced with notarisation, Hardened Runtime, a
tiny privileged surface, no cloud / no telemetry / no accounts, and
a public commitment to fund a third-party security audit at $50k
MRR. Little Snitch has been closed-source for twenty years; the
Mac-utility playbook works.

Five modes adapt the temperament: Normal (6 s grace, loud), Travel
(3 s grace, paranoid), Library (silent, evidence-only), Loaner (30 s
grace, forgiving), and Café (30 s alarm cap, considerate of shared
spaces). Optional cloud-bucket upload (Backblaze B2 or any
pre-signed URL — user-owned) gets the evidence off-device before
the thief defeats authentication, so it survives a wipe.

Solo-developer indie. macOS 14 (Sonoma) and later, Apple Silicon
native, Notarised. $29 one-time with a 14-day full trial. Optional
$12/year covers major-version updates after year one.

https://vakter.app · support@vakter.app · security@vakter.app
