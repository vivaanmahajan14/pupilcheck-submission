import Foundation
import CoreGraphics
import NeuroPulse

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let samples = [
    CalibrationSample(rawX: 0, rawY: 0, screenX: 0.5, screenY: 0.5, distanceCm: 25),
    CalibrationSample(rawX: -0.02, rawY: 0, screenX: 0.15, screenY: 0.5, distanceCm: 25),
    CalibrationSample(rawX: 0.02, rawY: 0, screenX: 0.85, screenY: 0.5, distanceCm: 25),
    CalibrationSample(rawX: 0, rawY: -0.015, screenX: 0.5, screenY: 0.25, distanceCm: 25),
    CalibrationSample(rawX: 0, rawY: 0.015, screenX: 0.5, screenY: 0.75, distanceCm: 25)
]
guard let map = GazeMath.fitCalibration(samples) else { fputs("FAIL: calibration fit\n", stderr); exit(1) }
let center = map.apply(rawX: 0, rawY: 0)
check(abs(center.x - 0.5) < 0.001 && abs(center.y - 0.5) < 0.001, "affine calibration")
check(GazeMath.fitCalibration(Array(repeating: samples[0], count: 5)) == nil, "reject stationary gaze")
check(GazeMath.gazeAngles(raw: CGPoint(x: 0.01, y: 0), map: map, distanceCm: 25) != nil, "calibrated gaze geometry")
let times = (0..<301).map { Double($0) / 30 }
let trace = times.map { t in
    TraceSample(t: t, eyeXDeg: 6 * sin(2 * .pi * 0.4 * t), eyeYDeg: 0,
                targetXDeg: 6 * sin(2 * .pi * 0.4 * t), targetYDeg: 0)
}
guard let pursuit = GazeMath.analyzePursuit(trace, saccades: [], frequencyHz: 0.4) else { fputs("FAIL: pursuit analysis\n", stderr); exit(1) }
check(abs(pursuit.gain - 1) < 0.02 && abs(pursuit.lagMs) < 5, "pursuit gain and phase from known trace")
let hold = times.map { t in TraceSample(t: t, eyeXDeg: 5, eyeYDeg: 0, targetXDeg: 5, targetYDeg: 0) }
guard let fixation = GazeMath.analyzeFixation(hold, saccades: []) else { fputs("FAIL: fixation analysis\n", stderr); exit(1) }
check(fixation.stabilityPercent == 100 && fixation.driftDegPerSec == 0, "fixation is compared with target")
let json = try! JSONEncoder().encode(SCAT6TriageResult(athleteId: "qa", athleteName: "QA", overallStatus: .normal,
    pursuitGain: pursuit.gain, latencyLagMs: pursuit.lagMs, fixationStabilityPercent: fixation.stabilityPercent,
    driftVelocity: fixation.driftDegPerSec, correctiveTwitches: 0, biomarkers: [], recommendations: [], recording: nil))
let decoded = try! JSONDecoder().decode(SCAT6TriageResult.self, from: json)
check(decoded.recording == nil && decoded.pursuitGain == pursuit.gain, "results encode measured values")
print("PASS: calibration, failure rejection, pursuit, target fixation and result serialization")
