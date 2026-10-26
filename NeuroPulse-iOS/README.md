# Pupil Check — native iPhone app

This is the phone-tested Congressional App Challenge submission. The internal
Xcode project, module, and scheme are named **NeuroPulse**.

## Build and run

1. Install Xcode and its iOS SDK on a Mac.
2. Open **`NeuroPulse.xcodeproj`**, not just `Package.swift`, to install the app.
3. Select **NeuroPulse** and your physical iPhone as the run destination.
4. Select your own team in **Signing & Capabilities**, with automatic signing.
   Use a unique bundle identifier if Xcode reports that the existing one is
   unavailable. Do not commit personal signing or workspace changes.
5. Enable Developer Mode and trust your development certificate on the phone
   when prompted, then run with **Command-R**.

The deployment target is iOS 17. Eye tasks require supported ARKit face tracking;
a TrueDepth iPhone is the intended device. Simulator camera and motion results
are unavailable. The native app needs no Python backend or cloud account.

## Demo walkthrough

Create a fictional player. Choose **Baseline**, complete the eye setup and four
tasks, then save motor results to the player. Choose **Session** for the same
player to make a repeat recording and inspect personal comparisons. Reopen both
sessions from player history. The standing task requires a nearby helper and a
safe stance; follow the in-app setup and stop instructions.

Eye setup is one eight-dot sequence: five fitting targets, two independent check
targets, and a final center check. Brief blinks pause collection. Failed accuracy
checks offer retry and diagnostic details before recording; continuing keeps
results flagged. Failed eye baselines stay in history without replacing a usable
reference. Each eye task waits for an explicit readiness tap.

Standing uses an audible cue, a one-second settling pause, and a fixed ten-second
sensor window. Sensor warm-up occurs during settling. Sound must be checked and
confirmed; interruption resets the recording. Reaction uses five valid visual
trials followed by a separately started, five-second one-finger tapping task.

## Results and storage

Results distinguish usable, unavailable, and not-yet-recorded measurements.
Details and graphs expand on demand. Baseline differences describe changes, not
injury probability or clearance. Protocol changes can make old eye references
incompatible; use a fresh baseline for the current setup.

Camera images are not saved. Player records and measurements use local
UserDefaults storage, not encrypted clinical storage. Motor references are saved
independently only for usable measurements; repeat sessions retain their reference
snapshot. The response guide links to external health resources.

## Checks

From the repository root on macOS with Xcode selected:

```sh
python3 scripts/check_native_recovery.py
python3 scripts/check_native_summary.py
python3 scripts/check_native_motor.py
```

These checks compile production Swift code, write temporary output under
`.tools/`, and exercise synthetic recordings. They do not establish sensor or
clinical accuracy. For the full Swift package test suite:

```sh
cd NeuroPulse-iOS
swift test
```

Some package tests use temporary UserDefaults suites. Run tests with fictional
data only. See [review notes](UI_REVIEW.md) for completed checks and known limits.

Pupil Check is experimental. It does not diagnose concussion, measure pupil
response, provide SCAT6 mBESS scores, or decide whether someone may return to play.
