# Vakter Privacy Policy

**Last updated: 14 May 2026**

Vakter is an anti-theft alarm for Mac. This document explains what data
the app accesses, what it does with it, and what it does NOT do.

The short version:

> Vakter runs **entirely on your Mac**. It does not have servers. It
> does not send your data anywhere unless you specifically configure it
> to. There are no accounts, no telemetry, no analytics.

---

## 1. What Vakter accesses

| Data | Where it lives | What Vakter does with it |
|---|---|---|
| **Webcam** (FaceTime / built-in camera) | macOS, gated by Camera permission | Captures photos **only during an active alarm**. Frames are written to `~/Library/Application Support/Vakter/events/<timestamp>/` on your local disk. |
| **Bluetooth scanning** | macOS, gated by Bluetooth permission | Reads advertisements from nearby devices to detect when your *trusted* devices (phone, AirPods, watch — the ones you paired in Settings → Trusted Devices) leave Bluetooth range. We do not log advertisements from devices you didn't add. |
| **System defaults / preferences** | Local shell-outs to `/usr/bin/defaults`, `/usr/sbin/spctl`, `/usr/sbin/csrutil`, `/usr/bin/fdesetup`, `/usr/sbin/nvram`, `/bin/launchctl` | The Defenses checklist reads system-wide security settings (FileVault status, Firewall state, Find My, etc.) and reports them to you in the menubar dropdown. The results are written to `~/Library/Application Support/Vakter/defenses-checklist.json` on your local disk. |
| **Apple ID hash** | SHA-256 of the email in `MobileMeAccounts` | Used to detect when the signed-in Apple ID *changes* while Vakter is armed (theft indicator). We store only the hash, never the email. |
| **Find My token** | `nvram fmm-mobileme-token-FMM` | Used to detect when Find My is disabled while Vakter is armed. We don't extract anything from the token — only its presence/absence is observed. |
| **Location** *(optional)* | macOS Location Services, gated by Location permission | If you've granted Location access AND set an evidence recipient (Settings → Notifications), Vakter attaches an Apple Maps URL to the iMessage it sends you when the alarm fires. We do not log location otherwise. |
| **Your iMessage recipient handle** *(if set)* | `~/Library/Application Support/Vakter/evidence-recipient.json` | The phone number or Apple-ID email you designate as the alarm recipient. Stored locally only. |

---

## 2. What Vakter sends off your Mac

By default, **nothing**.

If you explicitly configure an Evidence Recipient under Settings →
Notifications, then when an alarm fires Vakter sends one iMessage to
that recipient containing:

- A short alarm summary ("Vakter alert — your Mac may have been moved or accessed")
- An Apple Maps URL (if Location was granted)
- The first few photos from the alarm burst (attached inline)

The iMessage is sent **directly through Apple's Messages.app** via the
local AppleScript bridge. Vakter never sees the message after it leaves
Messages.app. Apple delivers the message under its own terms (see
Apple's iMessage privacy policy).

---

## 3. What Vakter does NOT do

- **No servers**: Vakter has no backend infrastructure. There is nothing
  for an attacker to breach because nothing leaves your Mac without
  your configuration.
- **No analytics**: We don't count app launches, button taps, alarm
  fires, or anything else. We have no idea who uses Vakter or how
  often.
- **No accounts**: There is no sign-in. You don't have a Vakter ID.
- **No advertising**: No ads, no ad SDKs, no profiling.
- **No third-party SDKs**: The only frameworks Vakter links are
  Apple's first-party ones (`AppKit`, `AVFoundation`, `CoreLocation`,
  `CoreBluetooth`, `SwiftUI`, `Security`).

---

## 4. Where the data lives

All Vakter data is stored under
`~/Library/Application Support/Vakter/` on your Mac. You can delete it
at any time. Specifically:

- `events.jsonl` — the event log (one JSON line per arm / disarm / grace / alarm)
- `events/<timestamp>/photo-NN.jpg` — captured photos
- `evidence-recipient.json` — your iMessage recipient handle (if set)
- `defenses-checklist.json` — the last security-checklist scan
- `last-location.json` — the most recent successful CoreLocation fix
- `hotkey.json`, `alarm-sound.json`, `active-mode.json`, `menubar-appearance.json`, `grace.json` — your preferences

Vakter also writes runtime logs to `/tmp/vakter-helper.{out,err}.log`
and `/tmp/vakter-privileged.{out,err}.log` for debugging. These are
cleared on every reboot.

---

## 5. Your rights

Because Vakter has no server and stores no personal data outside your
own Mac, the data-subject rights afforded by GDPR / CCPA (access,
correction, deletion, portability) are satisfied by your existing
control over your own file system. Delete
`~/Library/Application Support/Vakter/` and Vakter has nothing of yours.

---

## 6. Children's privacy

Vakter doesn't knowingly collect anything from anyone, of any age.

---

## 7. Changes

If we ever change this policy in a meaningful way (we add a feature
that talks to a server, for instance — currently no plans to do so),
the new version will be published here and reflected in the About tab
inside Vakter. Continued use of the app after a change constitutes
acceptance.

---

## 8. Contact

Privacy questions: **support@vakter.app** *(placeholder — to be set up
before public release)*.

Until then, open an issue on the repository or DM the author.
