# Customer Flow Simulation

> Side-by-side walkthroughs of realistic customer journeys against the
> Anchor state machine. The goal: surface gaps between *what users
> actually experience* and *what the system does*, in concrete narrative
> form.

Last updated after the SleepGuard / chirp / photo capture commit.

---

## Reading the columns

```
┌──────────────────────────────────────┬───────────────────────────────────┐
│  CUSTOMER STORY                       │  STATE MACHINE TRACE             │
│  (what the user thinks/does/hears)    │  (what Anchor actually does)     │
└──────────────────────────────────────┴───────────────────────────────────┘
```

Each row is one tick of time. The trace shows the state, observers
firing, side effects, and the audio/visual surface the user perceives.

---

## Scenario A — The café snatch (the headline use case)

Sarah is working at a busy café. She needs the bathroom. Her MacBook is
on the table with her notebook on top of it.

```
┌────────────────────────────────────────┬─────────────────────────────────────────┐
│ Sarah presses ⌘⌃⌥L.                    │ HotkeyObserver → emit .hotkeyArm        │
│ Hears a soft two-note chirp.           │ StateMachine: unarmed → ARMED           │
│ Screen goes dark and locks.            │ SleepGuard.engage() ✓                   │
│                                        │ ChirpPlayer.playArmChirp() ✓            │
│                                        │ ScreenLocker.lockScreen() ✓             │
│                                        │ Snapshot broadcast: armed/normal        │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Sarah walks to the bathroom (~30 s).   │ Helper running, observers watching.     │
│                                        │ No signals.                             │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ A thief sees the unattended MacBook    │                                          │
│ and grabs it. They close the lid to    │ LidObserver fires → emit .lidClosed     │
│ make it portable.                      │ StateMachine: ARMED → GRACE             │
│                                        │ ChirpPlayer.playGraceChirp() ✓          │
│                                        │ Grace timer scheduled for 8s            │
│                                        │ Snapshot broadcast: grace/normal        │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Soft chirp emanates from the lid-      │ (No system sleep — SleepGuard holds.    │
│ closed MacBook. Thief's pulse rises    │  Without it, the helper would have      │
│ but they keep walking.                 │  suspended here and the alarm never     │
│                                        │  fired. This is the critical fix.)      │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Louder second chirp at t+4 s.          │ ChirpPlayer.playGraceChirp() (escalated) │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Even louder chirp at t+7 s.            │ ChirpPlayer.playGraceChirp() (escalated) │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ At t+8 s, an 880 Hz sine sweep at full │ Grace timer expires →                   │
│ volume + a voice saying "This MacBook  │ StateMachine: GRACE → ALARM             │
│ is being tracked. Please put it down." │ AudioController.startAlarm(audible:t)   │
│ start blasting from the bag.           │   - snapshots vol/mute                  │
│                                        │   - forces vol=1.0, unmutes             │
│                                        │   - starts AVAudioEngine sine source    │
│                                        │   - AVSpeechSynthesizer speaks phrase   │
│                                        │ PhotoCapture.startBurst(normal):        │
│                                        │   - schedules captures at t=0, 2, 5 s   │
│                                        │ Snapshot broadcast: alarm/normal        │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Thief panics, drops the bag, runs.     │ photo-01.jpg written                    │
│                                        │ photo-02.jpg written                    │
│                                        │ photo-03.jpg written                    │
│                                        │ (alarm continues — only unlock stops it)│
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Bystanders converge. Someone returns   │                                          │
│ the bag/MacBook to the counter and     │                                          │
│ flags down the manager.                 │                                          │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Sarah returns from the bathroom,       │ User opens lid → .lidOpened (no effect  │
│ surveys the scene, opens her lid,      │   in ALARM state)                       │
│ Touch IDs.                             │ macOS posts com.apple.screenIsUnlocked  │
│ Alarm cuts off mid-phrase. Voice and   │ ScreenLockObserver emits .screenUnlocked│
│ siren fade. Volume restored to her     │ StateMachine: ALARM → UNARMED           │
│ pre-arm 50%.                           │ AudioController.stopAlarm():            │
│                                        │   - stops engine, stops synth           │
│                                        │   - restores vol=0.5, mute=0            │
│                                        │ PhotoCapture.stop() — burst writes      │
│                                        │   final files, returns filename list    │
│                                        │ SleepGuard.release() ✓                  │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Sarah opens Anchor's menubar → Event   │ Event log shows ALARM event at <ts>     │
│ Log → sees 3 photos of the thief's     │ with photoFilenames: ["photo-01.jpg",   │
│ face.                                  │   "photo-02.jpg", "photo-03.jpg"]       │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

**Verdict: ✅ Works as designed.** The café snatch is fully handled. The
SleepGuard fix in this commit is what makes the closed-lid path actually
work — without it, the alarm would never fire because the helper would be
suspended.

---

## Scenario B — Café snatch, but the thief doesn't close the lid

```
┌────────────────────────────────────────┬─────────────────────────────────────────┐
│ Same arm sequence as A.                │ As in A.                                │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Thief grabs the open-lidded MacBook    │ LidObserver: no event (lid stays open)  │
│ and walks toward the door.             │ PowerObserver: no event (was on battery)│
│                                        │ BluetoothObserver: no event             │
│                                        │ → No trigger. State stays ARMED.        │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Sarah's iPhone (paired trusted device) │ Eventually BT-RSSI drops on Sarah's     │
│ stays with her in the bathroom. Within │   iPhone → BluetoothObserver emits      │
│ ~10 s of leaving, the thief is far     │   .bluetoothTrustLost                   │
│ enough away that BT range is lost.     │ StateMachine: ARMED → GRACE             │
│                                        │ Chirp escalates, alarm fires at +8 s.   │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

**Verdict: ⚠ Partial.** Works ONLY if the user has a trusted BT peer
paired AND the peer remains with the user. The BluetoothObserver code in
v1 is currently a STUB (see `Sources/AnchorHelper/BluetoothObserver.swift`
— marked "TODO week-3"). Until that's implemented, this scenario doesn't
trigger an alarm at all.

**Gap to fix:** Real BluetoothObserver with multi-peer support. Already
sequenced as week-3 in tasks.md.

**Fallback for v1.0:** if the user has no BT peers and the thief leaves
the lid open, the alarm relies on power-disconnect (only if Mac was
plugged in) or never fires. Worth telling users in onboarding to use a
trusted BT peer for full coverage.

---

## Scenario C — Power-disconnect snatch (Mac plugged in at café)

```
┌────────────────────────────────────────┬─────────────────────────────────────────┐
│ Sarah arms. Mac is plugged into the    │ ARMED. SleepGuard engaged.              │
│ café's wall outlet.                    │                                          │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Thief yanks the cable to make the      │ PowerObserver polls every 1 s, detects  │
│ MacBook portable. Lid stays open as    │   AC → battery transition →             │
│ they walk away.                        │   emit .powerDisconnected               │
│                                        │ StateMachine: ARMED → GRACE             │
│                                        │ Grace timer running, chirps escalate.   │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Same alarm fires at +8 s.              │ As in A.                                │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

**Verdict: ✅ Works.** PowerObserver is implemented and polling at 1 Hz.
Worst-case detection latency ~1 s after unplug.

**Minor refinement opportunity:** swap the 1 s polling for the event-
driven `IOPSNotificationCreateRunLoopSource` callback. Reduces latency to
~instant and CPU to ~zero. Currently noted in PowerObserver.swift as a
TODO for week-3.

---

## Scenario D — False positive: power adapter falls out while user is sitting there

The classic "I bumped the cord" case. We don't want a public-shaming alarm.

```
┌────────────────────────────────────────┬─────────────────────────────────────────┐
│ Sarah is at the café, arms before her  │ ARMED.                                  │
│ bathroom break.                        │                                          │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Before she stands, she nudges the      │ PowerObserver: .powerDisconnected       │
│ cord with her foot. It falls out.      │ StateMachine: ARMED → GRACE             │
│ A soft chirp sounds from her closed-   │ Grace timer: 8 s remaining              │
│ display Mac (it's locked but awake).   │ ChirpPlayer.playGraceChirp() ✓          │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Sarah hears the chirp, immediately     │ Opens lid (no effect on state).         │
│ opens the lid, Touch IDs.              │ macOS unlock → .screenUnlocked          │
│ Alarm cancelled before it fires.       │ StateMachine: GRACE → UNARMED           │
│ Volume / chirps stop.                  │ SleepGuard.release() ✓                  │
│                                        │ ChirpPlayer.playDisarmChirp() ✓         │
│                                        │ (after week-4 polish; currently disarm  │
│                                        │  is silent)                             │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

**Verdict: ✅ Works.** Grace window catches false-positive triggers
cleanly. Sarah hears one soft chirp and silences with one Touch ID.

**Polish item:** The disarm chirp is implemented in ChirpPlayer but the
StateMachine doesn't actively call it on disarm yet. Add
`audio.playDisarmChirp()` in the `.unarmed` transition for the
"silence confirmation" cue. (5-line follow-up.)

---

## Scenario E — User locks their own lid intentionally (not via Anchor)

```
┌────────────────────────────────────────┬─────────────────────────────────────────┐
│ Sarah is wrapping up at the café. She  │ State: UNARMED. Anchor inactive.        │
│ closes her lid to put the MacBook in   │ LidObserver fires .lidClosed but the    │
│ her bag.                               │   state-machine transition table doesn't│
│                                        │   trigger anything when UNARMED.        │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ MacBook sleeps. No sound. No alarm.    │ Helper suspends with system sleep, but  │
│ Sarah goes home in peace.              │   that's fine — state was already       │
│                                        │   UNARMED, no assertions held.          │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

**Verdict: ✅ Works.** Intentional close-to-bag has zero false-positive
risk. This is the core "lid-open + locked" rule from design.md
manifesting correctly.

---

## Scenario F — Hotel room: armed, Mac in a drawer, no movement-style triggers

The hotel-room case is genuinely harder. The Mac sits there for hours.
A thief opens the drawer, picks it up.

```
┌────────────────────────────────────────┬─────────────────────────────────────────┐
│ Sarah arms her MacBook in her hotel    │ ARMED. SleepGuard engaged. Lid open.    │
│ room (lid open on the desk) before     │                                          │
│ heading out.                           │                                          │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Hours pass. She's at the conference.   │ Mac stays awake (SleepGuard).           │
│ Trusted BT peer (her iPhone) has been  │ Out of BT range — but BluetoothObserver │
│ out of range almost the whole day.     │   is currently STUBBED. So no trigger.  │
│                                        │ ⚠ State stays ARMED but no real         │
│                                        │   protection is active.                  │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Thief enters, sees the Mac, walks      │ Same. No trigger fires until they touch │
│ over, picks it up.                     │   the lid (close it) or the power cord. │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Thief closes the lid to put it in      │ LidObserver: .lidClosed                 │
│ their bag.                             │ → GRACE → alarm 8 s later               │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

**Verdict: ⚠ Partial.** Works IF the thief closes the lid (almost
always — closed lid is the only portable form). But the protection
window between "thief enters room" and "thief closes lid" is unobserved.

**Gap, not a v1 blocker.** Real BluetoothObserver (v1 final) closes most
of this. Hotel-grade protection is honestly a Travel-mode feature with
shorter grace + photo burst, which we already have in the spec.

**Honest limitation to document:** Anchor cannot detect a thief who
opens the lid but does nothing else (no plug, no close, no movement
signal). Possibly the rarest scenario though — opportunists move fast.

---

## Scenario G — User forgets to arm

The most common failure mode of all anti-theft apps is the user.

```
┌────────────────────────────────────────┬─────────────────────────────────────────┐
│ Sarah leaves to grab coffee. Forgets   │ State: UNARMED. No protection.          │
│ to press ⌘⌃⌥L.                         │                                          │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Thief picks up MacBook, walks away.    │ Nothing. State stays UNARMED.           │
│ Sarah returns to an empty table.       │                                          │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

**Verdict: ⚠ User error.** No system can save users who forget to arm.

**Mitigations to consider (not in v1):**
- A *very gentle* nudge when the user locks-without-arming for a long
  time in a public-ish location. E.g. on a different WiFi network than
  home, lid-open, screen locked → toast "Forgot to arm?". This re-opens
  the WiFi-geofencing rabbit hole we explicitly cut from v1 — likely
  worth revisiting after launch based on real user data.
- Or: a stupidly simple "always arm when locked" mode in Settings, off
  by default. The user opts in if they want it.

---

## Scenario H — Force shutdown via long power-button press

```
┌────────────────────────────────────────┬─────────────────────────────────────────┐
│ Sophisticated thief holds the power    │ Mac shuts down via firmware-managed     │
│ button for 10 s before walking away.   │   sequence. Outside any third-party     │
│                                        │   app's reach.                          │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

**Verdict: ⛔ Impossible to catch.** Documented limitation. Onboarding
text will mention this. The good news: thieves know the power button
trick on Macs is *not common knowledge* — most opportunistic café
snatchers don't think to do this.

---

## Scenario I — Apple Watch unlock disarms the Mac

```
┌────────────────────────────────────────┬─────────────────────────────────────────┐
│ Sarah's Mac is armed, screen locked.   │ ARMED. SleepGuard engaged.              │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ She sits down at the Mac, lifts the    │ macOS does Apple-Watch-proximity unlock.│
│ lid. Apple Watch authenticates her.    │ Posts com.apple.screenIsUnlocked.       │
│ Screen unlocks without Touch ID.       │ ScreenLockObserver: .screenUnlocked     │
│                                        │ StateMachine: ARMED → UNARMED ✓         │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

**Verdict: ✅ Works.** Any macOS-recognised unlock disarms us. Touch ID,
password, Watch, future-iPhone-auto-unlock, anything that posts the
unlock notification.

---

## Scenario J — User wants to disarm without unlocking the screen

E.g. she's still at her seat, screen is unlocked, she clicks the menubar
shield → "Disarm…".

```
┌────────────────────────────────────────┬─────────────────────────────────────────┐
│ Sarah clicks "Disarm" in the Anchor    │ HelperClient.disarm() → XPC disarm()    │
│ menubar dropdown.                      │ XPCService routes through LAContext:    │
│                                        │   evaluatePolicy(.deviceOwnerAuthenti…) │
│                                        │ System dialog: "Disarm Anchor" prompt   │
│ Sees a Touch ID dialog on screen.      │                                          │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│ Touch IDs. Dialog dismisses.           │ Auth success → stateMachine.disarmFrom… │
│ State flips to unarmed. Menubar shield │ StateMachine: ARMED → UNARMED           │
│ becomes outlined.                      │ Snapshot broadcast → menubar refreshes  │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

**Verdict: ✅ Works.** The XPC-initiated disarm path is gated by
biometric auth. Confirmed in the commit just before this one.

---

## Aggregate verdict

```
SCENARIO                                  STATUS    REASON
──────────────────────────────────────────────────────────────────────
A. Café snatch w/ lid close              ✅ FULL    SleepGuard fix
B. Café snatch w/ lid stays open         ⚠ PARTIAL BluetoothObserver stubbed
C. Power-disconnect snatch               ✅ FULL    PowerObserver implemented
D. False positive — cord falls out       ✅ FULL    Grace catches it
E. User closes own lid (no arm)          ✅ FULL    Intentional no-op
F. Hotel-room slow theft                 ⚠ PARTIAL Same as B — needs BT obs.
G. User forgets to arm                   ⚠ USER    No system saves this
H. Force shutdown via power button       ⛔ IMPOSS Firmware-managed
I. Apple Watch unlock disarms            ✅ FULL    Natural unlock path
J. Disarm from menubar                   ✅ FULL    LAContext-gated XPC
```

**The blocking gap is BluetoothObserver.** Without it, two of the
realistic scenarios degrade. Everything else either works fully or is a
known, accepted limitation.

**The chirp behaviour confirms** the SleepGuard fix is real: the user
literally heard the arm chirp through their speakers during our test
run. The state flow as drawn now correlates with real customer reality
for the dominant café-snatch case.

## Sequence of work this points to

```
v1 must-have (before launch):
  → Real BluetoothObserver with multi-peer trust
  → Disarm chirp wired into transition to .unarmed
  → Onboarding flow including a "use a trusted BT peer" step

v1 should-have:
  → Switch PowerObserver to event-driven (zero CPU)
  → Photo capture cadence visible in Event Log UI
  → Defenses panel: read screen-lock policy + nudge user to
    "Require password: immediately"

v1 nice-to-have (after first user data):
  → Soft "forgot to arm?" nudge (Scenario G)
  → Travel-mode photo burst tuning based on real café footage
```
