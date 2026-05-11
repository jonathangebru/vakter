# Spec: Anchor Core (alarm system)

The core capability of Anchor is a four-state alarm system that arms via an intentional user action and disarms only via authenticated user action.

## ADDED Requirements

### Requirement: Single-action arming via global hotkey

The system SHALL provide a global keyboard shortcut that, when pressed by the user, locks the Mac and transitions the system from Unarmed to Armed in a single intentional action.

#### Scenario: Default shortcut arms the system

- **GIVEN** Anchor is in Unarmed state
- **AND** Anchor has been granted Accessibility permission
- **WHEN** the user presses `⌘⌃⌥L` (default shortcut)
- **THEN** the macOS screen locks
- **AND** Anchor transitions to Armed state
- **AND** the menubar icon changes from outlined shield to filled shield
- **AND** an arm-confirmation chirp plays once

#### Scenario: Customized shortcut arms the system

- **GIVEN** the user has configured a custom shortcut in Settings
- **AND** Anchor is in Unarmed state
- **WHEN** the user presses their custom shortcut
- **THEN** the system arms identically to the default shortcut behavior

#### Scenario: Menubar click arms without locking

- **GIVEN** Anchor is in Unarmed state
- **WHEN** the user clicks "Arm now" in the menubar menu
- **THEN** Anchor transitions to Armed state
- **AND** if the screen is already locked, no additional lock action occurs
- **AND** if the screen is not locked, Anchor optionally locks based on user preference

### Requirement: Three trigger signals while armed

The system SHALL transition from Armed to Grace state when any of three signals fire: lid close, power adapter disconnect, or trusted Bluetooth peer leaving range.

#### Scenario: Lid close triggers grace

- **GIVEN** Anchor is in Armed state
- **WHEN** the MacBook lid is closed
- **THEN** Anchor transitions to Grace state
- **AND** a soft chirp plays at the moment of transition
- **AND** the grace timer starts at the configured duration (default 8 seconds)

#### Scenario: Power adapter disconnect triggers grace

- **GIVEN** Anchor is in Armed state
- **AND** the Mac is receiving AC power
- **WHEN** the power adapter is disconnected
- **THEN** Anchor transitions to Grace state
- **AND** a soft chirp plays at the moment of transition

#### Scenario: Trusted Bluetooth peer leaving triggers grace

- **GIVEN** Anchor is in Armed state
- **AND** a trusted Bluetooth peer is configured and has been visible within the last 30 seconds
- **WHEN** the peer's RSSI drops below the threshold for at least 3 consecutive seconds
- **THEN** Anchor transitions to Grace state
- **AND** a soft chirp plays at the moment of transition

#### Scenario: No trusted Bluetooth peer configured

- **GIVEN** Anchor is in Armed state
- **AND** no trusted Bluetooth peer is configured
- **WHEN** Bluetooth devices come and go in the environment
- **THEN** Anchor does not transition state based on Bluetooth signals

### Requirement: Grace period allows authenticated disarm

The system SHALL provide a configurable grace period (5–15 seconds, default 8) between any trigger signal and the alarm firing, during which authenticated user action disarms the system.

#### Scenario: Touch ID brief tap silently disarms during grace

- **GIVEN** Anchor is in Grace state
- **WHEN** the user taps the Touch ID sensor briefly (≥ 0.3s contact)
- **THEN** Anchor transitions to Unarmed state
- **AND** no audible disarm tone plays
- **AND** the grace timer is cancelled

#### Scenario: Full unlock disarms during grace

- **GIVEN** Anchor is in Grace state
- **WHEN** the user fully authenticates (Touch ID full auth, password, Apple Watch unlock)
- **THEN** Anchor transitions to Unarmed state
- **AND** the disarm tone plays
- **AND** the Mac unlocks normally

#### Scenario: Grace timer expires triggers alarm

- **GIVEN** Anchor is in Grace state
- **WHEN** the grace timer expires without authenticated disarm
- **THEN** Anchor transitions to Alarm state

### Requirement: Alarm fires at maximum volume on internal speakers

The system SHALL fire an audible alarm at maximum effective volume through the Mac's internal speakers, regardless of mute state, current volume setting, or connected external audio devices.

#### Scenario: Alarm overrides mute state

- **GIVEN** Anchor is transitioning to Alarm state
- **AND** the system audio is muted
- **WHEN** the alarm fires
- **THEN** the system audio unmutes
- **AND** the alarm plays at full volume
- **AND** the prior mute state is restored on disarm

#### Scenario: Alarm overrides low volume setting

- **GIVEN** Anchor is transitioning to Alarm state
- **AND** the system volume is set below 100%
- **WHEN** the alarm fires
- **THEN** the system volume is forced to maximum
- **AND** the prior volume is restored on disarm

#### Scenario: Alarm routes to internal speakers despite headphones

- **GIVEN** Anchor is transitioning to Alarm state
- **AND** wired headphones or AirPods are the current output device
- **WHEN** the alarm fires
- **THEN** audio output is forced to the Mac's internal speakers
- **AND** the prior output device is restored on disarm

#### Scenario: Alarm loops until disarmed

- **GIVEN** Anchor is in Alarm state
- **WHEN** the alarm has been playing for any duration
- **THEN** the alarm continues looping
- **AND** the alarm only stops when the user authenticates (Touch ID full or password)

### Requirement: Photo capture on alarm

The system SHALL capture photographs from the FaceTime camera at alarm onset and store them locally for the user's later review.

#### Scenario: Three photos captured on alarm

- **GIVEN** Anchor is transitioning to Alarm state
- **AND** the user has granted Camera permission
- **WHEN** the alarm fires
- **THEN** Anchor captures one photo at t=0
- **AND** one photo at t=2 seconds after alarm start
- **AND** one photo at t=5 seconds after alarm start
- **AND** all photos are written to `~/Library/Application Support/Anchor/events/<timestamp>/`

#### Scenario: Photos shown on unlock

- **GIVEN** an alarm event recently fired and photos were captured
- **WHEN** the user fully unlocks the Mac and opens Anchor
- **THEN** the captured photos are displayed in the event log

#### Scenario: Camera permission denied

- **GIVEN** the user has denied Camera permission
- **WHEN** the alarm fires
- **THEN** the alarm still plays normally
- **AND** no photos are captured
- **AND** the event log shows the event without photos

### Requirement: Alarm cannot be silenced without authentication

The system SHALL ensure that the alarm cannot be stopped by any means other than full user authentication.

#### Scenario: Quitting the app while armed is blocked

- **GIVEN** Anchor is in any of Armed, Grace, or Alarm states
- **WHEN** the user attempts to quit the menubar app
- **THEN** the quit is blocked
- **AND** a prompt explains that the system must be disarmed first

#### Scenario: Force quit the helper does not stop alarm

- **GIVEN** Anchor is in Alarm state
- **WHEN** an attacker attempts to force-quit `com.anchor.helper`
- **THEN** the LaunchAgent automatically relaunches
- **AND** the alarm resumes within 1 second

#### Scenario: Pulling power does not stop alarm immediately

- **GIVEN** Anchor is in Alarm state
- **AND** the Mac is on battery
- **WHEN** an attacker attempts to drain the battery or trigger sleep
- **THEN** the alarm continues until battery is fully depleted or Mac is unlocked
- **AND** Anchor uses `IOPMAssertion` to prevent forced sleep during alarm

### Requirement: Event log preserves alarm history

The system SHALL maintain a local log of arm/disarm/alarm events for user review and confidence-building.

#### Scenario: Each state transition logged

- **GIVEN** Anchor is operating normally
- **WHEN** any state transition occurs
- **THEN** a structured event entry is written to the local event log with timestamp, prior state, new state, and trigger source

#### Scenario: Event log viewable in-app

- **GIVEN** an event log exists with prior entries
- **WHEN** the user opens the Anchor menubar app
- **THEN** the most recent 30 events are viewable
- **AND** any associated photos are displayed inline

### Requirement: Single-user local operation

The system SHALL operate entirely on the local Mac without requiring an internet connection, account creation, or cloud service for core functionality.

#### Scenario: First launch offline

- **GIVEN** the Mac has no internet connection
- **WHEN** the user installs and launches Anchor for the first time
- **THEN** onboarding can complete fully
- **AND** all core arm/disarm/alarm functionality works

#### Scenario: License validation offline

- **GIVEN** the user has purchased a license
- **AND** the Mac has no internet connection
- **WHEN** the user activates Anchor
- **THEN** license validation succeeds via offline cryptographic verification
- **AND** no telemetry is transmitted

### Requirement: Voice cue accompanies the alarm

The system SHALL play a spoken phrase alongside the siren during the Alarm state, in the user's system language, mixed through the forced-internal-speakers output.

#### Scenario: Default voice phrase plays during alarm

- **GIVEN** Anchor is in Alarm state
- **AND** the user has not customized the voice phrase
- **WHEN** the alarm has been firing for at least 1 second
- **THEN** the default voice phrase for the system language is spoken via AVSpeechSynthesizer
- **AND** the phrase repeats every 4 seconds for the duration of the alarm

#### Scenario: Custom voice phrase plays during alarm

- **GIVEN** the user has set a custom voice phrase in Settings
- **WHEN** the alarm fires
- **THEN** the custom phrase is spoken instead of the default
- **AND** the phrase repeats every 4 seconds for the duration of the alarm

#### Scenario: Unsupported language falls back to English

- **GIVEN** the user's system language has no bundled default phrase
- **AND** the user has not set a custom phrase
- **WHEN** the alarm fires
- **THEN** the English default phrase is spoken

### Requirement: Multiple trusted Bluetooth peers

The system SHALL allow the user to pair 1–10 Bluetooth peers as trusted, treating any present peer as proof of owner proximity.

#### Scenario: Any trusted peer present dampens the leave signal

- **GIVEN** Anchor is in Armed state
- **AND** three trusted peers are paired
- **WHEN** one of the three peers leaves Bluetooth range
- **AND** at least one of the other paired peers remains in range
- **THEN** Anchor does not transition to Grace state
- **AND** the event is logged but does not trigger

#### Scenario: All trusted peers leaving triggers Grace

- **GIVEN** Anchor is in Armed state
- **AND** three trusted peers are paired
- **WHEN** all three peers' RSSI drops below threshold for at least 3 consecutive seconds
- **THEN** Anchor transitions to Grace state

### Requirement: Mode-conditional behavior

The system SHALL support four selectable modes (Normal, Travel, Library, Loaner), each adjusting grace duration, audible-alarm behavior, and camera capture cadence.

#### Scenario: Normal mode uses standard parameters

- **GIVEN** the user has selected Normal mode
- **WHEN** the alarm fires
- **THEN** grace duration is 8 seconds
- **AND** audible siren plus voice cue play
- **AND** 3 photos are captured at t=0/2/5s

#### Scenario: Travel mode shortens grace and extends photo burst

- **GIVEN** the user has selected Travel mode
- **WHEN** the alarm fires
- **THEN** grace duration is 5 seconds
- **AND** audible siren plus voice cue play
- **AND** photo burst captures every 5 seconds for the first minute, then every 30 seconds until disarmed

#### Scenario: Library mode without iPhone companion uses elevated chirps

- **GIVEN** the user has selected Library mode
- **AND** no iPhone companion is paired
- **WHEN** the alarm fires
- **THEN** the audible alarm is replaced by a louder version of the grace chirp pattern (not the siren)
- **AND** photo burst captures as in Travel mode

#### Scenario: Loaner mode trust window suppresses arming

- **GIVEN** the user has selected Loaner mode with a 2-hour trust window
- **WHEN** the user presses the arm shortcut
- **THEN** the system stays in Unarmed state
- **AND** the menubar displays the remaining countdown

#### Scenario: Loaner trust window expires and rearms

- **GIVEN** the user is in Loaner mode with an active trust window
- **WHEN** the trust window expires
- **THEN** Anchor silently switches back to the previously-selected mode
- **AND** a notification informs the user that Loaner has ended

### Requirement: Power-button intercept while armed (if feasible)

The system SHALL intercept brief power-button presses during Armed state and treat them as trigger events instead of system sleep requests, contingent on the spike-confirmed feasibility of detection.

#### Scenario: Brief power-button press triggers grace

- **GIVEN** the power-button intercept spike has confirmed feasibility
- **AND** Anchor is in Armed state
- **WHEN** the user (or attacker) presses the power button briefly (< 0.5 seconds)
- **THEN** Anchor transitions to Grace state
- **AND** sleep is suppressed via `IOPMAssertion` for the duration of the Grace window

#### Scenario: Long power-button press cannot be intercepted

- **GIVEN** Anchor is in any armed state
- **WHEN** the attacker holds the power button for the firmware-forced shutdown duration
- **THEN** the Mac shuts down despite Anchor
- **AND** this limitation is documented to the user during onboarding

### Requirement: Pre-flight security checklist

The system SHALL provide a Defenses pane that reads (but does not silently modify) the Mac's security posture and surfaces actionable items.

#### Scenario: Checklist reads system state

- **GIVEN** the user opens the Defenses pane
- **WHEN** the pane loads
- **THEN** Anchor reports the current state of: FileVault, Find My Mac, login password, screen auto-lock, login-window message, firmware password, automatic-login flag
- **AND** displays a score from 0–10 reflecting overall posture

#### Scenario: Failing item provides actionable CTA

- **GIVEN** the Defenses pane shows a failing item (e.g., FileVault off)
- **WHEN** the user clicks the item's CTA
- **THEN** the appropriate System Settings panel opens via deep link
- **OR** a guided in-app walkthrough is presented for items without a deep-link target
- **AND** Anchor never silently modifies the system setting

#### Scenario: Login-window message is the sole in-app edit

- **GIVEN** the user is configuring the login-window message
- **WHEN** the user enters a message and confirms
- **THEN** Anchor writes to `LoginwindowText` via a privileged helper (admin prompt on first set only)
- **AND** the configured message appears on the lock screen

### Requirement: Lock-screen "if found" message with last-alarm summary

The system SHALL append a dynamic summary of the most recent alarm event to the user's configured lock-screen message, unless explicitly disabled.

#### Scenario: Last alarm suffix updates on alarm disarm

- **GIVEN** the user has configured a static "if found" message
- **AND** the dynamic suffix is enabled (default)
- **WHEN** an alarm event completes (state transitions ALARM → UNARMED)
- **THEN** the lock-screen message is updated with a suffix containing the alarm timestamp and the count of photos captured

#### Scenario: User disables dynamic suffix

- **GIVEN** the dynamic suffix is enabled
- **WHEN** the user toggles "Show last alarm on lock screen" off in Settings
- **THEN** the lock-screen message is restored to the static text only on the next state change
- **AND** subsequent alarms do not modify the message

#### Scenario: Combined message exceeds Login Window display limit

- **GIVEN** the static message plus the dynamic suffix would exceed 250 characters
- **WHEN** Anchor composes the final message
- **THEN** the suffix is truncated before the static text is truncated
- **AND** at minimum the timestamp portion of the suffix is preserved

### Requirement: Shortcuts and App Intents

The system SHALL expose its core actions as App Intents so users can compose them into Shortcuts and Focus-mode automations.

#### Scenario: Shortcuts can arm Anchor

- **GIVEN** Anchor is installed and Shortcuts has discovered its intents
- **WHEN** a Shortcut invokes the `ArmAnchorIntent`
- **THEN** Anchor transitions to Armed state using the current mode
- **AND** the Shortcut completes successfully

#### Scenario: Shortcuts can change mode

- **GIVEN** Anchor is installed
- **WHEN** a Shortcut invokes the `SetAnchorModeIntent` with mode "Travel"
- **THEN** Anchor's active mode is updated to Travel
- **AND** the menubar reflects the new mode

#### Scenario: Disarm intent requires Touch ID

- **GIVEN** a Shortcut invokes the `DisarmAnchorIntent`
- **WHEN** Anchor is in any armed state
- **THEN** a Touch ID prompt is presented
- **AND** disarm only occurs if authentication succeeds

#### Scenario: Pre-flight intent returns a score

- **GIVEN** a Shortcut invokes the `RunPreflightCheckIntent`
- **WHEN** the intent executes
- **THEN** Anchor runs the security checklist
- **AND** returns the numeric score and a list of failing items as output the Shortcut can consume
