# Validation and known limitations

## Verified during development

- 117 focused regression checks passed: 38 eye-flow/reference checks, 47 result
  summary checks, and 32 motor-analysis/capture-state checks.
- The shared framework compiled against the installed iOS simulator SDK and the
  app entry point type-checked. The contributor subsequently built and ran the
  app on a physical iPhone using Xcode.
- The contributor completed a fresh baseline and a repeat session, with usable
  measurements for all four tasks, successful save/reopen from player history,
  and baseline comparisons.
- Result overview components were rendered at 320 and 390 points to check text
  wrapping. This does not replace device accessibility testing.
- Final wording and reference-protection changes were regression-checked after
  the full phone walkthrough; the contributor also reviewed the updated results.

## Covered by focused regressions

Calibration recovery, brief-blink handling, eight-dot setup, instruction pauses,
failed-calibration diagnostics, duplicate-frame handling, neutral recorded status,
reference compatibility, comparison directions, invalid measurements, failed
baseline protection, interruption behavior, tapping intervals, and motion timing,
coverage, gaps, and nonfinite data. Test fixtures are synthetic, not patient data.

## Known limitations

- Calibration sometimes requires retries on the tested phone. Performance across
  different users and devices has not been established.
- Camera/display/touch timing is not hardware calibrated. Milliseconds describe
  the reported units, not guaranteed measurement accuracy.
- Phone motion includes handling and placement effects and is not body displacement
  or a SCAT6 mBESS score.
- No validated clinical cutoffs establish whether a baseline difference indicates
  concussion, recovery, or safe return to play.
- The app stores records locally in UserDefaults, not encrypted clinical storage.
- Eye baseline comparisons require compatible protocol versions. The current
  guided setup uses `2.7.0-guided-calibration`.

## Before recording a demo on another phone

Build the submitted version, use fictional player details, check camera access
and audible cues, complete a baseline and repeat session with a helper for the
standing task, then save and reopen the results. Do not present synthetic fixtures
as real participant measurements or omit a quality failure from its result.
