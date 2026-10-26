# Pupil Check

An experimental iPhone app for guided eye-movement and motor measurements,
personal baseline comparisons, and organized player records.

Built by **Aniruddh Maheshwari and Vivaan Mahajan** for the **2026 Congressional
App Challenge, Arkansas District 3**.

## Start here

The submitted, phone-tested app is the **native Swift app in
[`NeuroPulse-iOS`](NeuroPulse-iOS/README.md)**. Open
`NeuroPulse-iOS/NeuroPulse.xcodeproj` in Xcode. The project and scheme retain the
internal name **NeuroPulse**; the app is displayed as **Pupil Check**.

This repository contains the native app demonstrated in the submission video.
Earlier browser and Flutter prototypes are not included.

## What the app does

1. **Eye tracking:** follow a moving dot while ARKit estimates eye movement.
2. **Side gaze hold:** look toward each side while the app records estimated
   steadiness and inward drift.
3. **Reaction and tapping:** respond to five visual cues, then alternate taps
   between two pads with one finger for five seconds.
4. **Standing phone movement:** during a supervised stance, a helper holds the
   phone against the player's chest for a ten-second motion recording.

Create a player, record a baseline, then select Session to compare later attempts
with that player's saved reference. Results explain changes and flag recordings
that need attention. Graphs and technical details are expandable. A head-injury
response guide is available in the app.

**These are experimental measurements, not a concussion diagnosis or a
return-to-play decision.** The app does not replace medical evaluation or
specialized clinical equipment.

## Run the app

- Use a Mac with Xcode and the iOS SDK, plus a compatible physical iPhone running
  iOS 17 or later. Eye tests require supported ARKit face tracking; a TrueDepth
  iPhone is the intended demo device.
- Open the `.xcodeproj`, select the NeuroPulse scheme and your connected iPhone.
- In Signing & Capabilities, select your own development team with automatic
  signing. Enable Developer Mode and trust your developer certificate if asked.
- Run with **Command-R** and allow camera access.

The simulator can show navigation and layouts but cannot demonstrate real eye
tracking or standing sensor measurements. No Python server is required for the
native app. See [native setup](NeuroPulse-iOS/README.md) for details and checks.

## Technology and data

Swift, SwiftUI, ARKit, SceneKit, Swift Charts, CoreMotion, and AVFAudio. The native
Swift package has no external package dependencies. Camera images are displayed
live and are not saved. Player records are stored locally using UserDefaults;
this is not encrypted clinical record storage. Opening an external resource
link may require internet access.

## Validation and limitations

The team completed an iPhone baseline and repeat session with all four usable
results, saved/reopened history, and personal-baseline comparisons. Automated
checks cover recording timing, interruptions, calibration recovery, quality
checks, reference protection, and result explanations.

Calibration can require retries. Display/touch delays are uncalibrated, phone
motion includes placement and grip effects, and differences from baseline have
no validated clinical significance threshold. Software tests do not establish
medical accuracy. See [validation notes](NeuroPulse-iOS/UI_REVIEW.md).

## Repository guide

- `NeuroPulse-iOS/`: native app, Xcode project, tests, and validation notes.
- `scripts/`: focused native regression checks.
- `docs/CREDITS.md`: team contributions and AI assistance.
- `THIRD_PARTY_NOTICES.md`: frameworks, source references, and rights information.
