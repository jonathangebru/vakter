# Vakter Changelog

Technical changelog maintained by the release warden. User-facing changelog lives at `Website/changelog/index.html`.

---

## v1.4.2 — 2026-05-21

**Notarization submission ID:** c68987a4-001b-472a-b0fd-96a94b55d268
**CFBundleVersion:** 2
**Merged PRs:** #39 (ticket #25), #40 (ticket #21)

### Feature #25 — Wire ArmVakterIntent + SetVakterModeIntent to helper over XPC

`VakterIntents.swift` only. Replaces the `NSLog` TODO stubs in `ArmVakterIntent.perform()` and `SetVakterModeIntent.perform()` with real one-shot `NSXPCConnection` calls to the helper's Mach service.

- `VakterIntentXPC.callArm()` calls `proxy.arm()` on the helper. The helper's `arm(reply:)` calls `stateMachine.armFromUser()` (no Touch ID gate — safe for Shortcuts context) and replies immediately.
- `VakterIntentXPC.callSetMode(raw:)` calls `proxy.setMode(_:)`, bridging `VakterModeAppEnum` through `asVakterMode.rawValue`. All 5 modes covered.
- Each invocation opens a fresh `NSXPCConnection`, defers `conn.invalidate()` on every exit path.
- `AckGate` arbitrates between XPC reply (background queue) and 5-second timeout (main queue). Prevents silent hangs when the helper LaunchAgent isn't approved.
- `VakterIntentError.helperUnreachable` surfaces "Vakter's background helper isn't running" in Shortcuts' error banner.

Known limitation: `arm(reply:)` on the helper always replies `true` regardless of whether `armFromUser()` actually transitioned state (method is void-returning). The `armRejected` error case is unreachable in practice. Follow-up ticket needed to have `armFromUser()` return a result.

### Feature #21 — Defenses +8 checks (12 to 20)

`DefensesAudit.swift`, `DefensesProbe.swift`, `DefenseChecklistTests.swift`. Adds 8 new security checks, bringing the audit total from 12 to 20.

New checks (all appended after existing 12 — order is load-bearing for `DefensesScoreHistory`):

| Check | Probe command | Category | Healthy → severity |
|---|---|---|---|
| AirDrop discovery scope | `defaults read com.apple.sharingd DiscoverableMode` | `.firewallSharing` | Off/Contacts Only = healthy; Everyone = `.warning` |
| AirPlay Receiver | `launchctl list \| grep AirPlayXPCHelper` | `.firewallSharing` | Off = healthy; On = `.warning` |
| File Sharing (SMB) | `launchctl list \| grep com.apple.smbd` | `.firewallSharing` | Off = healthy; On = `.warning` |
| Media Sharing | `launchctl list \| grep com.apple.mediasharingd` | `.firewallSharing` | Off = healthy; On = `.warning` |
| Printer Sharing | `cupsctl` → `_share_printers=0` | `.firewallSharing` | Off = healthy; On = `.warning` |
| Remote Login (SSH) | `launchctl list com.openssh.sshd` | `.firewallSharing` | Off = healthy; On = `.attention` |
| Remote Management (ARD) | `launchctl list com.apple.RemoteManagement` | `.firewallSharing` | Off = healthy; On = `.attention` |
| Boot security policy | `bputil -d` (Apple Silicon only) | `.systemIntegrity` | Full Security = healthy; Reduced = `.warning`; Permissive = `.attention` |

AirDrop + Boot Security mirrored into `DefensesProbe.swift` so the menubar dropdown stays in sync with the Settings Defenses tab. 10 new test cases in `DefenseChecklistTests`.

**Known limitation (boot security):** `bputil -d` requires root on macOS 14 (Sonoma). On macOS 14 machines all users see `.unknown` ("Couldn't read the LocalPolicy"). Check only functions correctly on macOS 15+. Degrades gracefully — no crash, no misreport.

### Ship verification

- `swift test`: 113/113 passed (both branches verified independently)
- `swift build --configuration release --arch arm64`: clean (pre-existing AppDelegate-Sendable warnings only)
- Provisioning profile: present at `Contents/embedded.provisionprofile`
- Entitlements post-signing: 4 iCloud keys confirmed (`icloud-container-environment`, `icloud-container-identifiers`, `icloud-services`, `ubiquity-container-identifiers`)
- `spctl --assess`: `source=Notarized Developer ID`
- `xcrun stapler validate /Applications/Vakter.app`: passed
- Probe spot-tests on macOS 14 / Darwin 23.6.0 / Apple Silicon: AirDrop, SSH, and boot security all handled correctly

---

## v1.4.1 and earlier

See `Website/changelog/index.html` for v1.4.1. Prior technical history not yet backfilled.
