# Vakter Security Architecture

This document is the audit guide for security-conscious users, researchers,
and reviewers. Vakter guards your Mac against physical threats (theft,
hands-on access) and, starting in v1.6, digital threats (ClickFix clipboard
attacks, hostile LaunchAgents, malicious configuration profiles). It runs two
background processes — one in your user session, one as root — to deliver
lid-close-while-asleep alarms, evidence capture, and on-device clipboard
analysis. Putting that kind of trust in an indie app deserves a clear answer
to *"what does it actually do with that privilege?"*

If you find something concerning, email **security@vakter.app**. 90-day
coordinated disclosure. No bounty at v1.x, but you will be credited in
release notes if you'd like.

---

## 1. Process model

Vakter ships three binaries:

| Binary | Bundle path | Privilege | Lifetime |
|---|---|---|---|
| `Vakter` | `Vakter.app/Contents/MacOS/Vakter` | User (LSUIElement) | Foreground / menubar |
| `VakterHelper` | `Vakter.app/Contents/MacOS/VakterHelper` | User (LaunchAgent) | Per-user, always running |
| `VakterPrivilegedDaemon` | `Vakter.app/Contents/MacOS/VakterPrivilegedDaemon` | **root** (LaunchDaemon) | System-wide, always running |

All three are Developer-ID signed by Team ID **9TA5GB5UJH** (Jonathan
Gebru) with the macOS Hardened Runtime. The DMG is notarized by Apple
on every release.

### Why each process exists

- **`Vakter`** is the menubar UI. It owns no privileged operations; it
  speaks to `VakterHelper` over XPC and to `VakterPrivilegedDaemon` via
  `SMAppService` registration. **All UI lives here**, nowhere else.
- **`VakterHelper`** is the always-running watcher. It registers the
  global hotkey (Carbon `RegisterEventHotKey`), tracks Bluetooth peer
  proximity (CoreBluetooth), runs the state machine, captures photos
  + audio on alarm, and writes the event log. It runs as your user, no
  elevated privilege.
- **`VakterPrivilegedDaemon`** exists for one reason: to call
  `pmset disablesleep 1` while armed. macOS requires root for that one
  call. The daemon refuses every other XPC method. It's ~600 lines.

### What none of them do

- No kernel extension. No `kextload`.
- No System Extension. No Network Extension.
- No firewall. No DNS interception. No traffic logging.
- No telemetry to vakter.app or anywhere else.
- No account system. No cloud storage.
- No screen recording. No keylogging. No screenshot capture.
- No reading of your other apps' data, keychain entries, or files.

---

## 2. Privilege boundary — what each process *can* do

### `Vakter` (the menubar app)

Sandboxed-equivalent operations only. Has TCC entries for:
- Camera (photo burst on alarm)
- Microphone (audio capture on alarm)
- Apple Events / Automation → Messages.app (to send the evidence iMessage)
- Bluetooth (proximity disarm)

### `VakterHelper`

Same TCC surface as the app — no additional privilege. Talks XPC
to the privileged daemon for the one operation it can't perform itself
(toggling system-wide sleep disable).

### `VakterPrivilegedDaemon`

Root, but has **exactly one job**: the XPC method
`setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool) -> Void)`,
which shells out to `/usr/bin/pmset disablesleep 0` or `… disablesleep 1`.
The full Swift source is ~150 lines. There are no other methods. There
is no shell-out path that accepts user-controlled strings.

---

## 3. XPC peer authentication

Both XPC services use macOS 13+'s
[`NSXPCConnection.setCodeSigningRequirement(_:)`](https://developer.apple.com/documentation/foundation/nsxpcconnection/4151265-setcodesigningrequirement)
to pin the *peer's* code signature:

```text
anchor apple generic and certificate leaf[subject.OU] = "9TA5GB5UJH"
```

This requirement rejects connections from any process that isn't signed
by an Apple-issued cert under Team ID `9TA5GB5UJH`. macOS evaluates the
requirement before any method is dispatched; mismatched peers receive
`NSXPCConnectionInvalid` and the connection is torn down.

Source: `Sources/VakterHelper/XPCPeerVerification.swift`.

**Why this matters.** Without a peer requirement, any process running as
the same user could open the helper's Mach service and call `arm()`,
`disarm()`, `currentSnapshot()`, or list/mutate trusted Bluetooth peers.
With the Team ID pinned, only our own signed binaries (the menubar app,
the dev-only helper-poke CLI, or a future Shortcuts extension) can call.

---

## 4. Event log integrity

Every event written by the state machine is sealed into a SHA-256
Merkle hash chain:

- Each event carries its own `eventHash` — SHA-256 over its canonical
  JSON encoding (with `eventHash` itself nilled to avoid self-reference)
- Each event carries `previousEventHash` — the prior event's `eventHash`
- `EventChain.verify(_:)` walks the chain and reports the first break

If anyone tampers with the on-disk `events.jsonl` — modifies a field,
swaps two events, deletes an event — the chain breaks visibly and the
police-ready PDF report stamps the break loud and red.

The chain doesn't *prevent* tampering (the log file is still on a disk
the thief may control after authenticating). It *proves* tampering to
a third party reading the exported report.

Source: `Sources/VakterShared/EventChain.swift`.

---

## 5. Data handling

### What's stored on disk

- `~/Library/Application Support/Vakter/events.jsonl` — the event log
- `~/Library/Application Support/Vakter/events/<ts>/photo-NN.jpg` —
  alarm-burst photos
- `~/Library/Application Support/Vakter/events/<ts>/audio-NN.m4a` —
  alarm ambient-audio clips
- `~/Library/Application Support/Vakter/last-location.json` — last
  successful CoreLocation probe (latitude/longitude/timestamp)
- `~/Library/Application Support/Vakter/evidence-recipient.json` — the
  iMessage handle the user configured (their own phone or Apple ID)
- `~/Library/Application Support/Vakter/trusted-peers.json` —
  Bluetooth identifiers of the user's trusted disarm devices
- `~/Library/Application Support/Vakter/hotkey.json` — the user's
  arming hotkey binding
- UserDefaults under `vakter.*` keys — small persisted preferences

### What's transmitted off-device

Only one path: the iMessage evidence delivery on alarm. Sent **through
Messages.app via `osascript`** to the recipient the user configured.
Vakter does not run its own SMS gateway, mail server, or HTTP client.

No automatic uploads. No "phone home" check-ins. No analytics.

### Sparkle update checks (when enabled)

If you enable auto-updates (`Sources/VakterApp/UpdaterController.swift`),
Vakter fetches `https://vakter.app/appcast.xml` once per 24 hours. This
is the only outbound request Vakter makes during normal operation. The
response is signed with our EdDSA public key, embedded in the app's
Info.plist; tampered responses are rejected by Sparkle.

---

## 6. Permissions Vakter requests, and why

| Permission | TCC key | Why |
|---|---|---|
| Camera | `NSCameraUsageDescription` | Photo burst on alarm |
| Microphone | `NSMicrophoneUsageDescription` | 10s ambient audio on alarm |
| Bluetooth | `NSBluetoothAlwaysUsageDescription` | Trusted-peer proximity disarm |
| Location | `NSLocationUsageDescription` | Best-known location attached to evidence iMessage |
| Apple Events → Messages | `NSAppleEventsUsageDescription` | Sending the evidence iMessage |
| Input Monitoring (helper) | implicit via Carbon | Global hotkey registration |
| Login Items (app) | `SMAppService.mainAppService` | Auto-launch on login |
| Login Items (helper) | `SMAppService.daemon` | Helper LaunchAgent registration |
| Login Items (daemon) | `SMAppService.daemon` | Root daemon registration |

If you deny any of these, Vakter continues to work — minus that one
capability — without crashing or nagging.

---

## 7. How we earn your trust without open source

Vakter is closed-source. We considered open-sourcing the privileged
binaries and decided against it — see §8 for the reasoning. To
compensate, we lean harder on every other trust signal that's
available to a closed-source security app on macOS:

1. **Apple notarization.** Every release is submitted to Apple for
   automated malware + privilege-abuse scanning and the resulting
   ticket is stapled into the DMG. Gatekeeper refuses to launch
   anything we ship that hasn't passed Apple's scan.
2. **Hardened Runtime + Developer ID Application signing** under Team
   ID `9TA5GB5UJH`. `codesign --display --entitlements -` on the
   installed bundle lets anyone audit exactly what capabilities we
   asked for.
3. **Tiny privileged surface.** The root daemon is ~150 LOC and has
   *one* exported XPC method: shell `pmset disablesleep`. Nothing else
   runs as root. The helper LaunchAgent runs as your user — same
   privilege level as your browser. There is no kernel extension, no
   System Extension, no Network Extension.
4. **No outbound network in normal operation.** The only HTTPS request
   Vakter makes is the daily Sparkle appcast check to `vakter.app`. No
   telemetry. No analytics. No "phone home." Verify with Activity
   Monitor → Network or Little Snitch.
5. **All evidence flows to user-owned destinations only.** iMessage to
   your configured recipient. Email to your configured recipient.
   Cloud bucket you own and pay for. We never proxy your evidence.
6. **Third-party security audit at $50k MRR.** We commit to a paid
   independent audit (NCC Group, Trail of Bits, or similar) once
   revenue can sustain the $10–30k cost. The audit report will be
   published.
7. **Real human accountability.** I'm Jonathan Gebru. Photo, location,
   support email all on vakter.app. If something goes wrong, you can
   find me.

---

## 8. Why we chose closed-source

We considered open-sourcing the helper + daemon under GPLv3 and chose
not to. The honest reasoning:

- **Vakter is a product, not a project.** The closed-source path lets
  us iterate on architecture without GPL constraints, ship features
  that touch the daemon without coordinating with a public-facing
  community, and avoid the operational tax of maintaining issue
  triage / PR review / disclosure intake on a public repo while we're
  still finding product-market fit.
- **The trust signal trade-off is real but not absolute.** Little
  Snitch has been closed-source for 20 years and is the gold standard
  of Mac security tools. Bartender, CleanShot X, 1Password — all
  closed. Trust on macOS doesn't require auditable source; it
  requires *predictable behavior* (which §7 enumerates).
- **Source availability does not protect against the failure modes
  most users care about.** A reproducible-build claim helps the 0.1%
  of users who'd verify it; the other 99.9% trust based on
  notarization + reviews + reputation, which we provide identically
  whether the source is public or not.

If you'd prefer a fully open-source anti-theft tool, **LuLu**
(Objective-See) and **Pareto Security** are excellent alternatives.
They solve adjacent problems and we recommend them alongside Vakter.

---

## 9. Reporting issues

- **Email:** security@vakter.app
- **PGP:** (TODO: publish key)
- **Disclosure timeline:** 90 days from initial report. We'll
  acknowledge within 72h, share a fix timeline within 7 days, and
  credit you in release notes if desired.
- **Out of scope:** denial of service via the user choosing to deny TCC
  permissions; physical attacks (someone with your password); attacks
  requiring root on a machine where the attacker already has root.

---

## 10. Things we explicitly chose not to ship

Listed here so reviewers know they're deliberate omissions, not
oversights:

- **Real-time location streaming during alarm.** Considered, deferred
  to v1.4 with the iOS companion app — needs the right consent UX.
- **Continuous keylogger / app-launch logger to detect anomalous
  behaviour.** Creepy, ethically tricky, fails App Store review even if
  we wanted to ship there. We have multi-trigger detection instead.
- **Account system / centralised dashboard.** Doesn't fit "no cloud, no
  telemetry, no accounts." Multi-Mac coordination in v1.5 uses
  user-configured B2/S3 buckets (user-owned credentials).
- **Honeypot password swap on theft.** Considered. Too dangerous
  without FileVault recovery-key escrow, which itself is a UX
  landmine. Deferred to v1.6+ with deep onboarding redesign.
- **Hidden / stealth tracking after a wipe.** Apple's macOS security
  model deliberately prevents this (Find My is the sanctioned path).
  Every legacy "hidden tracker" Mac app died trying. We didn't try.
