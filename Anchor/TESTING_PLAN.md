# Vakter — v0.9 Comprehensive Testing Plan

This plan covers every shippable feature of Vakter as of v0.9.3. Each
test has an **Automated** part (Claude can run it) and a **Manual**
part (you, the human, must verify physically). The four parallel test
agents in Section 8 run all the automated checks at once.

---

## 1. State machine + transitions

| ID | Check | Automated | Manual |
|---|---|---|---|
| SM-1 | All 4 modes load with expected params | unit test `VakterModeTests` | — |
| SM-2 | `.cafe` mode has 12s grace, silent, 30s cap | unit test | Pick `.cafe` → Test alarm self-stops at 30s |
| SM-3 | Three-phase arm doesn't deadlock | unit test `test_bug2_snapshot_doesNotBlockDuringAuthDialog` | — |
| SM-4 | runArmDemo engages sleep guard | unit test `test_bug3_runArmDemo_engagesSleepGuards` | — |
| SM-5 | User-cancelled auth rolls back | unit test `test_bug2_userCancelled_rollsBack` | Click "Cancel" on auth prompt → no arm |
| SM-6 | Pending-arm dedup prevents double-engage | unit test `test_concurrentArms_dedupViaPendingArm` | — |
| SM-7 | screenUnlocked → unarmed transition | code trace | Lock screen while armed → unlock → menubar disarms |
| SM-8 | systemWake fires alarm while armed | code trace | Close lid while armed → wake → alarm fires |

## 2. Hotkey

| ID | Check | Automated | Manual |
|---|---|---|---|
| HK-1 | `RunLoop` fix lives in helper binary | `strings VakterHelper \| grep "NSApp run loop"` | — |
| HK-2 | InstallEventHandler log fires | `log show \| grep "InstallEventHandler ok"` | — |
| HK-3 | 30s heartbeat log fires | `log show \| grep "HotkeyObserver. alive"` | — |
| HK-4 | Collision guard rejects `⌘L` etc. | unit tests `HotkeyCollisionTests` | — |
| HK-5 | `⌘L` on disk is auto-healed to default | unit test `test_load_healsCollidingFile` | — |
| HK-6 | Press default `⌘⌃⌥L` → arming overlay | — | **Press combo, observe "On watch" overlay** |
| HK-7 | Settings → Shortcut → rebind to `⌥⌘V` → press → arms | — | **Rebind + press** |

## 3. Audio + sirens + voice TTS

| ID | Check | Automated | Manual |
|---|---|---|---|
| AU-1 | All 6 AlarmSound cases compile + Codable | unit test `test_alarmSound_newCasesPresentAndCodable` | — |
| AU-2 | Helper-side testAlarm fires audio engine | `AnchorHelperPoke testalarm` + log grep "siren started" | — |
| AU-3 | Settings → Sound → Preview button plays sound | log grep `[Audio] TEST alarm` after click | **Click Preview, hear 3s of selected siren** |
| AU-4 | All 6 siren waveforms produce expected freq | unit test (instantaneousTone) | — |
| AU-5 | Voice cue uses locale-correct phrase | unit test `test_voiceLanguageTag_perLocale` | **Set system to Dutch → Test alarm → hear NL voice** |
| AU-6 | System-volume override forces 100% | log grep `forceMax: any-write=yes master 1.00` | — |
| AU-7 | Audio teardown restores prior volume | log grep `default output restored` | — |
| AU-8 | Local fallback fires when helper unreachable | unit test `AckGate` race | — |

## 4. Photo capture + evidence

| ID | Check | Automated | Manual |
|---|---|---|---|
| PC-1 | EventLog path correct (Vakter not Anchor) | grep `eventLogURL` | — |
| PC-2 | EventLog migration moves legacy Anchor data | code review | If you had pre-rebrand data, check `events.jsonl` exists |
| PC-3 | Photo burst dir auto-created on alarm | code trace | Trigger alarm → check `~/Library/Application Support/Vakter/events/<ts>/` |
| PC-4 | Evidence bundle delivers via iMessage | unit test `iMessageEvidenceDelivery` | **Settings → Notifications → Send test → iPhone receives** |
| PC-5 | Maps URL is well-formed | unit test `test_evidenceDelivery_mapsURL_isWellFormed` | — |
| PC-6 | AppleScript escapes quotes correctly | unit test `test_evidenceDelivery_appleScript_escapesQuotes` | — |
| PC-7 | Body falls back to last-known location | unit test `test_evidenceDelivery_bodyFallsBackToLastKnownWhenFreshNil` | — |

## 5. Find My + Apple ID watchers

| ID | Check | Automated | Manual |
|---|---|---|---|
| FM-1 | FindMyTokenWatcher wired in main.swift | grep `FindMyTokenWatcher.make` | — |
| FM-2 | AppleIDChangeWatcher wired | grep `AppleIDChangeWatcher.make` | — |
| FM-3 | Both signals route to `.alarm` direct | grep StateMachine cases | — |
| FM-4 | nvram probe returns token or empty cleanly | live `nvram fmm-mobileme-token-FMM` | — |
| FM-5 | defaults read MobileMeAccounts returns | live shell probe | — |
| FM-6 | Watchers are arm-gated (pause/resume) | code trace | — |
| FM-7 | Find My disable triggers alarm | — | **Arm → System Settings → Apple ID → Find My → disable → alarm fires** |

## 6. Settings UI

| ID | Check | Automated | Manual |
|---|---|---|---|
| UI-1 | All 10 tabs render | code trace | Cycle through every tab |
| UI-2 | Mode picker → setMode XPC reaches helper | log grep after click | **Pick mode → menubar mode badge updates** |
| UI-3 | Hotkey rebind → reloadHotkey XPC reaches helper | log grep | **Rebind + press new combo** |
| UI-4 | Notifications tab saves recipient | unit test round-trip | **Type number, save, reload window — number persists** |
| UI-5 | Privacy tab cycles 3 appearances | unit test | **Click each → menubar visually changes** |
| UI-6 | Diagnostic export writes zip | unit test `test_zipper_zipsRealFiles` | **Click "Export to Desktop" — zip appears** |
| UI-7 | Stealth `.hidden` is greyed when no custom hotkey | code review | — |

## 7. Privileged daemon

| ID | Check | Automated | Manual |
|---|---|---|---|
| PD-1 | Daemon binary in bundle | `ls Vakter.app/Contents/MacOS/VakterPrivilegedDaemon` | — |
| PD-2 | LaunchDaemon plist in bundle | `ls Vakter.app/Contents/Library/LaunchDaemons/` | — |
| PD-3 | Auto-heal detects stale binding | log grep `stale daemon binding detected` | — |
| PD-4 | Daemon running with new binary path | `launchctl print system/...` shows `/Vakter.app/.../VakterPrivilegedDaemon` | — |
| PD-5 | Helper XPC to daemon succeeds | log grep `engaged via daemon` (after arm) | **Arm → no password prompt** |
| PD-6 | LWCR auto-recovery for helper | log grep `auto force-refresh` | — |

## 8. Distribution

| ID | Check | Automated | Manual |
|---|---|---|---|
| DI-1 | Build script renames binaries | grep build-app.sh | — |
| DI-2 | Signature is Developer ID Application | `codesign -dvvv /Applications/Vakter.app` | — |
| DI-3 | Entitlements include camera + bluetooth + audio | grep Vakter.entitlements | — |
| DI-4 | Notarisation script exists | `ls Scripts/notarize.sh` | — |

---

## Test agent batches (4 in parallel)

The four agents below run all the automated checks. Manual items are
left to you and listed at the end of each agent's report as
`MANUAL-PENDING`.

**Agent A — SoundFix Verifier** (SM, AU)
**Agent B — Hotkey + State machine** (HK, SM)
**Agent C — Evidence + Watchers** (PC, FM)
**Agent D — Daemon + UI + Distribution** (PD, UI, DI)
