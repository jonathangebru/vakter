# Spike 2 — LAContext brief-tap exploration

## Status: DEFERRED — needs signed app context to fully test

## What we wanted to learn

Can we detect a **brief Touch ID sensor contact (~0.3s)** that:
- Does NOT pop the system biometric-auth dialog
- Does NOT fully authenticate the user
- Just lets Anchor silently disarm during the Grace state when the owner physically taps the sensor

## What's known from APIs

`LAContext` (the public Local Authentication framework) is binary:

```
context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, ...)
  → pops the system Touch ID UI
  → returns success/failure
```

There is **no public API** for "did the user touch the sensor without authenticating." The system absorbs raw sensor touches at a level below LAContext.

## Possible paths forward (all need a signed Mac app target to test)

1. **`kAuthorizationFlagInteractionAllowed` + custom auth right**
   - Define a custom `AuthorizationRight` in `/etc/authorization` that requires biometric but with a low timeout
   - May still pop UI; needs experimentation

2. **HID-level Touch ID sensor events**
   - On Apple Silicon, the power button (= Touch ID sensor) emits HID events
   - We may be able to observe these via `IOHIDManagerCreate` + matching dictionary
   - This is the most promising path but requires entitlements and possibly being a signed app

3. **`SecKey` operation with biometric protection**
   - Store a dummy key in the Secure Enclave that requires biometric to use
   - Attempt to use it — succeeds silently if the user has authenticated recently (within the system's TouchID cache window)
   - This may not be "brief tap" exactly, but it might give us a "is the owner present right now" signal

4. **Accept the design compromise**
   - Drop "brief-tap-silent-disarm" as a feature
   - Use full password/Touch ID auth as the only disarm path
   - Slight UX regression but simplifies the implementation significantly

## What we CAN confirm right now (without Xcode)

- `LAContext` does exist as a framework
- It's importable from a CLI binary
- We chose not to invoke `evaluatePolicy` in a spike because:
  - Unsigned CLI binary popping a system biometric dialog is sketchy UX
  - The CLI process doesn't own a Dock/UI session, so the dialog routing is unpredictable
  - It doesn't answer the brief-tap question anyway

## Recommendation for the project

Treat brief-tap silent-disarm as a **research item for the iOS-companion phase (v1.5)**.
For v1, ship with **full unlock = disarm** as the only authenticated exit from Grace and Alarm.
This costs us a small luxury feature but doesn't block shipping.

Add a follow-up task to investigate path #2 (HID-level sensor events) once we have:
- Full Xcode + a Developer ID
- A signed `.app` bundle with the appropriate entitlements
- Access to Apple Developer documentation for `IOHIDManager` matching dictionaries for the embedded HID controller
