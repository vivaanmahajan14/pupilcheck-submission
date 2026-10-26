import Foundation
var checks = 0
func check(_ ok: @autoclosure () -> Bool, _ name: String) {
    guard ok() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    checks += 1
}
func reaction(_ ms: Double = 340, _ taps: Double = 3) -> MotorMeasurement {
    MotorMeasurement(status: "measured", metrics: ["median_reaction_ms": ms, "alternations_per_second": taps])
}
func motion(_ acceleration: Double = 0.2, _ tilt: Double = 2) -> MotorMeasurement {
    MotorMeasurement(status: "measured", metrics: ["phone_acceleration_rms_m_s2": acceleration, "phone_tilt_rms_deg": tilt])
}
let reference = MotorReference(recordedAt: Date(), measurement: reaction(300, 4))
let movementReference = MotorReference(recordedAt: Date(), measurement: motion(0.1, 1))
func describe(_ measurement: MotorMeasurement?, _ ref: MotorReference? = reference, baseline: Bool = false, isReaction: Bool = true) -> TestOverviewItem {
    RecordingOverview.motorItem(measurement, reference: ref, baseline: baseline, reaction: isReaction)
}
check(describe(reaction()).explanation.contains("40 ms slower"), "slower reaction direction")
check(describe(reaction()).explanation.contains("1.0 alternations/sec slower"), "lower tapping direction")
check(describe(reaction(260, 5)).explanation.contains("40 ms faster"), "faster reaction direction")
check(describe(reaction(260, 5)).explanation.contains("1.0 alternations/sec faster"), "higher tapping direction")
check(describe(reaction(300, 4)).explanation.contains("matched baseline at the displayed precision"), "equal values not a health assessment")
check(describe(reaction(300.1, 4)).explanation.contains("matched baseline at the displayed precision"), "rounding avoids zero slower claim")
check(describe(reaction(), nil).explanation.contains("No compatible"), "no baseline explained")
check(describe(reaction(), baseline: true).explanation.contains("when saved"), "baseline draft not marked saved")
check(!describe(reaction(), baseline: true).explanation.contains("slower than baseline"), "baseline not compared to older reference")
let incompatible = MotorReference(recordedAt: Date(), measurement: reaction(300, 4), protocolVersion: "future")
check(describe(reaction(), incompatible).explanation.contains("No compatible"), "protocol mismatch excluded")
let invalidReference = MotorReference(recordedAt: Date(), measurement: MotorMeasurement(status: "insufficient_quality", metrics: ["median_reaction_ms": 300]))
check(describe(reaction(), invalidReference).explanation.contains("No compatible"), "invalid reference excluded")
check(!describe(nil).hasUsableData, "missing test not counted")
for state in ["skipped", "interrupted", "insufficient_quality", "unavailable"] {
    let item = describe(MotorMeasurement(status: state, reason: "Original reason", metrics: reaction().metrics))
    check(!item.hasUsableData && item.explanation.contains("Original reason") && !item.explanation.contains("slower"), "\(state) not interpreted")
}
check(!describe(reaction(.nan)).hasUsableData, "NaN excluded")
check(!describe(reaction(.infinity)).hasUsableData, "infinity excluded")
check(!describe(reaction(-1)).hasUsableData, "negative duration excluded")
check(!describe(MotorMeasurement(status: "measured", metrics: ["early_taps": 1])).hasUsableData, "missing primary measurements excluded")
let movement = describe(motion(), movementReference, isReaction: false)
check(movement.explanation.contains("0.100 m/s² higher") && movement.explanation.contains("1.00 ° higher"), "more phone movement explained")
check(describe(motion(0.05, 0.5), movementReference, isReaction: false).explanation.contains("0.050 m/s² lower"), "less movement explained")

let trace = [TraceSample(t: 0, eyeXDeg: 1, eyeYDeg: 0, targetXDeg: 1, targetYDeg: 0)]
func eye(quality: RecordingQualityMetadata? = RecordingQualityMetadata(), fraction: Double = 1, biomarkers: [BiomarkerCardData] = []) -> SCAT6TriageResult {
    let recording = ExamRecording(pursuit: trace, pursuitSaccades: [], holdRight: trace, holdRightSaccades: [], holdLeft: trace, holdLeftSaccades: [], calibrationErrorDeg: 1, meanDistanceCm: 16, validSampleFraction: fraction, measuredFrameRate: 60, qualityMetadata: quality)
    return SCAT6TriageResult(athleteId: "test", athleteName: "Test player", overallStatus: .normal, pursuitGain: 0.9, latencyLagMs: 15, fixationStabilityPercent: 80, driftVelocity: 1, correctiveTwitches: 2, biomarkers: biomarkers, recommendations: [], recording: recording)
}
let eyes = eye()
let complete = MotorTestSession(eyeResultID: eyes.id, reaction: reaction(), balance: motion(), reactionReference: reference, balanceReference: movementReference)
let all = RecordingOverview.items(eye: eyes, motor: complete)
check(all.map(\.id) == [1,2,3,4], "every test represented in order")
check(all.filter(\.hasUsableData).count == 4, "both motor tests included in usable count")
check(RecordingOverview.items(eye: eyes, motor: nil).filter(\.hasUsableData).count == 2, "eye-only session remains incomplete")
let skipped = MotorTestSession(eyeResultID: eyes.id, reaction: reaction(), balance: MotorMeasurement(status: "skipped"))
check(RecordingOverview.items(eye: eyes, motor: skipped).filter(\.hasUsableData).count == 3, "skipped balance reduces usable count")
let wrong = MotorTestSession(eyeResultID: UUID(), reaction: reaction(), balance: motion())
check(RecordingOverview.items(eye: eyes, motor: wrong).filter(\.hasUsableData).count == 2, "different session cannot be combined")
check(!RecordingOverview.items(eye: eye(quality: nil), motor: nil)[0].hasUsableData, "legacy missing quality not treated as validated")
check(!RecordingOverview.items(eye: eye(quality: RecordingQualityMetadata(canvasRmsErrorPercent: 50)), motor: nil)[1].hasUsableData, "poor calibration withheld")
check(!RecordingOverview.items(eye: eye(fraction: .infinity), motor: nil)[0].hasUsableData, "invalid coverage excluded")
check(describe(reaction(), MotorReference(recordedAt: Date(), measurement: reaction(-300, 4))).explanation.contains("No compatible"), "negative baseline excluded")
check(RecordingOverview.compatibleReference(incompatible, reaction: true) == nil, "charts and text share compatibility gate")
check(RecordingOverview.items(eye: eye(quality: nil), motor: nil)[0].explanation.contains("no calibration quality report"), "missing quality explained specifically")
check(RecordingOverview.items(eye: eye(quality: RecordingQualityMetadata(canvasRmsErrorPercent: 50)), motor: nil)[0].explanation.contains("calibration check"), "failed calibration explained specifically")
check(RecordingOverview.items(eye: eye(), motor: nil)[2].explanation.hasPrefix("Not recorded"), "pending motor task distinct from failed recording")
let eyeMetrics = [("ratio", 0.9, 1.0), ("ms", 15.0, 10.0), ("%", 80.0, 90.0), ("°/s", 1.0, 0.5), ("events", 2.0, 1.0)].map { unit, value, baseline in
    BiomarkerCardData(title: unit, measuredValue: value, unit: unit, normativeTarget: "", baselineValue: baseline, status: .normal, interpretation: "")
}
let comparedEyes = RecordingOverview.items(eye: eye(biomarkers: eyeMetrics), motor: nil)
check(comparedEyes[0].explanation.contains("5.0 ms later relative to the dot"), "final summary includes timing baseline difference")
check(comparedEyes[1].explanation.contains("drift back toward the center was 0.50°/s faster"), "final summary includes drift baseline difference")
check(comparedEyes[1].explanation.contains("1 more detected quick eye movements"), "final summary includes movement baseline difference")
let recorded = GazeMath.evaluateTriage(athleteId: "test", athleteName: "Test", pursuitGain: 1, latencyLagMs: 0, fixationStabilityPercent: 100, driftVelocity: 0, correctiveTwitches: 0)
check(recorded.overallStatus == .recorded, "sensor results never assign a normal medical status")
let restoredStatus = try JSONDecoder().decode(TriageStatus.self, from: JSONEncoder().encode(TriageStatus.recorded))
check(restoredStatus == .recorded, "recorded status survives persistence")
check(RecordingOverview.eyeMeasurementComparison(value: 1.2, baseline: 1, unit: "ratio").contains("farther from matching"), "higher gain is not automatically better")
check(RecordingOverview.eyeMeasurementComparison(value: 1, baseline: 0.8, unit: "ratio").contains("closer to matching"), "gain explained relative to matching")
check(RecordingOverview.eyeMeasurementComparison(value: -10, baseline: -20, unit: "ms").contains("10.0 ms later"), "less lead is described as later, not slower reaction")
check(RecordingOverview.eyeMeasurementComparison(value: -20, baseline: 10, unit: "ms").contains("30.0 ms earlier"), "timing sign crossing described correctly")
check(RecordingOverview.eyeMeasurementComparison(value: 0.1, baseline: 0.15, unit: "°/s").contains("0.05°/s slower"), "lower drift described plainly")
check(RecordingOverview.eyeMeasurementComparison(value: 0.1001, baseline: 0.1, unit: "°/s").contains("No change"), "rounding does not imply change")
check(RecordingOverview.eyeMeasurementComparison(value: .nan, baseline: 1, unit: "ratio").contains("unavailable"), "invalid comparison withheld")
print("PASS: \(checks) four-test summary regression checks")
