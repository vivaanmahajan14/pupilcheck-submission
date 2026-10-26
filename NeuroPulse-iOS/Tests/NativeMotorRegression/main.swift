// Small executable for hosts without a working SwiftPM/Xcode test runner.
// Compiled with the real production analysis and capture-state declarations.
import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    checks += 1
}
func analyze(_ times: [Double]) -> MotorMeasurement {
    MotorTestAnalysis.reaction(times: [0.291, 0.274, 0.290], early: 1, missed: 0,
        taps: times.enumerated().map { MotorTap(t: $0.element, side: $0.offset % 2) },
        duration: 5, maxFrameGap: 0.016)
}
let even = analyze([0, 0.1, 0.3, 0.6, 1.0])
check(even.status == "measured", "complete reaction accepted")
check(abs(even.metrics["median_alternating_interval_ms"]! - 250) < 0.001, "even median averages middle pair")
let odd = analyze([0, 0.1, 0.3, 0.6])
check(abs(odd.metrics["median_alternating_interval_ms"]! - 200) < 0.001, "odd median stays correct")
check(even.metrics["reaction_trial_1_ms"] == 291, "trial order retained")
check(even.metrics["median_reaction_ms"] == 290, "reaction median retained")

var capture = MotorCaptureState()
capture.tonePlayed = true
check(!capture.soundConfirmed, "playback alone is not audibility confirmation")
capture.heardTone = true
check(capture.soundConfirmed, "explicit confirmation enables sound gate")
capture.resetSound()
check(!capture.soundConfirmed, "replay resets confirmation")
capture.heardTone = true
check(!capture.soundConfirmed, "cannot confirm without playing tone")
for stage in [MotorCaptureState.Stage.reaction, .cadence] {
    capture = MotorCaptureState(stage: stage, tonePlayed: true, heardTone: true)
    check(capture.interrupt() == .reaction, "reaction/cadence interrupted")
    check(capture.stage == .intro && !capture.soundConfirmed, "reaction must restart")
}
for stage in [MotorCaptureState.Stage.eyesOpen, .eyesClosed] {
    capture = MotorCaptureState(stage: stage, tonePlayed: true, heardTone: true)
    check(capture.interrupt() == .balance, "countdown/recording interrupted")
    check(capture.stage == .balanceSetup && !capture.soundConfirmed, "balance must restart with sound check")
}
for stage in [MotorCaptureState.Stage.intro, .balanceSetup, .results] {
    capture = MotorCaptureState(stage: stage, tonePlayed: true, heardTone: true)
    check(capture.interrupt() == nil, "idle and completed tests not invalidated")
    check(capture.stage == stage && !capture.soundConfirmed, "idle stage preserved, sound reset")
}
let samples = (0..<500).map {
    MotorMotionSample(t: Double($0) * 0.02, acceleration: (0.1, 0, 0),
        gravity: (0, 0, 9.80665), rotation: (0, 0, 0))
}
check(MotorTestAnalysis.balance(samples: samples).status == "measured", "continuous motion accepted")
check(MotorTestAnalysis.balance(samples: samples, duration: 12).status == "insufficient_quality", "overrun not reported as ten seconds")
check(MotorTestAnalysis.balance(samples: samples, duration: 10.02).status == "measured", "small deadline scheduling overhead accepted")
check(MotorTestAnalysis.balance(samples: samples, duration: 10.2).reason?.contains("10.20") == true, "timer overrun reports actual elapsed time")
check(MotorTestAnalysis.balance(samples: Array(samples.prefix(150))).reason?.contains("150 motion samples") == true, "low sample count is distinct from timing failure")
check(MotorTestAnalysis.balance(samples: Array(samples.dropFirst(15))).status == "insufficient_quality", "sensor startup gap still rejected")
let gapSamples = samples.filter { $0.t < 4 || $0.t > 4.5 }
check(MotorTestAnalysis.balance(samples: gapSamples).status == "insufficient_quality", "interior sensor outage remains rejected")
let invalidSample = MotorMotionSample(t: -0.02, acceleration: (0,0,0), gravity: (0,0,9.8), rotation: (0,0,0))
check(MotorTestAnalysis.balance(samples: [invalidSample] + samples).status == "insufficient_quality", "settling samples cannot enter analysis")
let nonfinite = MotorMotionSample(t: 10, acceleration: (.nan,0,0), gravity: (0,0,9.8), rotation: (0,0,0))
check(MotorTestAnalysis.balance(samples: samples + [nonfinite]).status == "insufficient_quality", "nonfinite sensor values rejected")
print("PASS: \(checks) native motor regression checks (not an iOS UI/device test)")
