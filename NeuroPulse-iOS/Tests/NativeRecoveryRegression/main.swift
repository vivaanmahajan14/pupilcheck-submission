import Foundation
import Combine

// Never touch participant defaults or write test preferences outside the workspace.
final class MemoryDefaults: UserDefaults {
    override func data(forKey key: String) -> Data? { nil }
    override func bool(forKey key: String) -> Bool { true }
    override func set(_ value: Any?, forKey key: String) {}
}
final class FrameTracker: GazeTrackerProtocol {
    var currentMetrics = EyeMetrics.zero
    var faceDistanceCm: Double { currentMetrics.faceDistanceCm }
    var isDistanceOptimal: Bool { (12...24).contains(faceDistanceCm) }
    var isFaceDetected: Bool { currentMetrics.isTrackingActive }
    var isTracking = false
    var calibrationMap: GazeCalibrationMap?
    var isCalibrated: Bool { calibrationMap != nil }
    var trackingError: String?
    var onFrame: ((EyeMetrics) -> Void)?
    var resets = 0
    func startTracking() { isTracking = true }
    func stopTracking() { isTracking = false }
    func resetCalibration() { calibrationMap = nil; resets += 1 }
    func setCalibrationMap(_ map: GazeCalibrationMap, errorDeg: Double) { calibrationMap = map }
    func registerCalibrationPoint(screenPoint: CGPoint, at index: Int) {}
}
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }; checks += 1
}
var now = 100.0
var validationOffset = 0.0
let tracker = FrameTracker()
let model = ExamViewModel(athlete: AthleteProfile(id: "recovery-qa", name: "QA", jerseyNumber: "", sport: ""),
    tracker: tracker, baselineManager: BaselineManager(userDefaults: MemoryDefaults()), clock: { now }, schedulesTimer: false)
func frames(_ count: Int, distance: Double = 16, blink: Double = 0) {
    for _ in 0..<count {
        let isChecking: Bool
        if case .calibration(let index) = model.currentPhase { isChecking = index >= AppConstants.CalibrationGrid.fittingPointCount } else { isChecking = false }
        now += 1.0 / 60
        tracker.currentMetrics = EyeMetrics(timestamp: now, isTrackingActive: true, faceDistanceCm: distance,
            rawGazeX: (Double(model.stimulusTarget.x) + (isChecking ? validationOffset : 0) - 0.5) / 17.5,
            rawGazeY: (Double(model.stimulusTarget.y) - 0.5) / (50.0 / 3),
            gazeX: Double(model.stimulusTarget.x), gazeY: Double(model.stimulusTarget.y),
            leftEyeYawDeg: 0, leftEyePitchDeg: 0, rightEyeYawDeg: 0, rightEyePitchDeg: 0,
            eyeBlinkLeft: blink, eyeBlinkRight: blink)
        model.tick()
    }
}
model.startExam()
frames(150)
check(model.referenceHeadPose != nil, "Alignment establishes original pose")
model.currentPhase = .lateralHold(side: .right, elapsed: 0)
frames(45, distance: 20)
check(model.isRecoveringTracking, "A distance change pauses lateral hold even inside the broad setup range")
check(model.recordingHint?.contains("16 cm") == true, "Recovery identifies original distance")
frames(10)
check(model.isRecoveringTracking, "A brief return is not enough to restart")
frames(35)
check(!model.isRecoveringTracking, "Sustained return automatically restarts hold")
check(model.currentPhase == .lateralHold(side: .right, elapsed: 0), "Recovery retains the current side")
frames(45, distance: 20)
check(model.isRecoveringTracking, "Later movement can pause again")
let resets = tracker.resets
model.restartEyeCalibration()
check(model.currentPhase == .alignmentAndDistanceCheck, "Explicit recalibration returns to alignment")
check(model.referenceHeadPose == nil && model.bestValidationReport == nil, "Old calibration reference and validation cleared")
check(!model.isRecoveringTracking && model.recordingHint == nil, "Recovery UI cleared")
check(tracker.resets == resets + 1 && tracker.isTracking, "Tracker calibration reset and tracking restarted")
check(model.triageResult == nil && model.examProgressPercent == 0, "No incomplete result presented")
model.restartEyeCalibration()
check(tracker.resets == resets + 1, "Restart action ignored outside recovery")
model.cancelExam()
model.startExam()
for _ in 0..<3000 {
    frames(1)
    if model.awaitingTaskStart { break }
}
check(model.awaitingTaskStart, "Calibration ends at an explicit moving-dot instruction screen")
let waitingPhase = model.currentPhase
frames(600)
check(model.currentPhase == waitingPhase && model.awaitingTaskStart, "Reading instructions never consumes test time")
model.beginPreparedTask()
check(!model.awaitingTaskStart, "Ready starts the countdown")
for _ in 0..<1200 {
    frames(1)
    if model.awaitingTaskStart { break }
}
check(model.awaitingTaskStart && model.currentPhase == .lateralHold(side: .right, elapsed: 0), "Right gaze hold waits for consent to start")
frames(600)
check(model.currentPhase == .lateralHold(side: .right, elapsed: 0), "Side hold does not expire while reading")
model.beginPreparedTask()
for _ in 0..<600 {
    frames(1)
    if model.awaitingTaskStart { break }
}
check(model.awaitingTaskStart && model.currentPhase == .lateralHold(side: .left, elapsed: 0), "Left gaze hold has its own instruction pause")
model.cancelExam()
validationOffset = 0.46
model.startExam()
for _ in 0..<3000 {
    frames(1)
    if model.awaitingTaskStart { break }
}
check(model.awaitingTaskStart && model.bestValidationReport?.isAcceptable == false, "Large check error pauses before recording")
check(model.calibrationCheckDiagnostics.count == 3, "All check positions are available for diagnosis of tracking")
let badReport = model.bestValidationReport
model.beginPreparedTask()
check(model.bestValidationReport == badReport, "Continuing does not erase failed quality report")
model.cancelExam()
model.startExam()
for _ in 0..<3000 {
    frames(1)
    if model.awaitingTaskStart { break }
}
model.restartEyeCalibration()
check(model.currentPhase == .alignmentAndDistanceCheck && model.bestValidationReport == nil, "Failed calibration can retry before recording")
check(model.calibrationCheckDiagnostics.isEmpty, "Retry clears previous check diagnostics")
model.cancelExam()
validationOffset = 0
model.startExam()
while model.currentPhase == .alignmentAndDistanceCheck { frames(1) }
frames(50)
let beforeBlink = model.calibrationHoldProgress
check(beforeBlink > 0, "Guided dot accumulates usable dwell")
frames(15, blink: 1)
check(model.calibrationHoldProgress == beforeBlink, "Brief blink preserves progress without advancing")
frames(1)
check(model.calibrationHoldProgress >= beforeBlink, "Collection resumes after brief blink")
frames(60, blink: 1)
check(model.calibrationHoldProgress == 0, "Long eye closure resets current dot")
check(model.currentPhase == .calibration(pointIndex: 0), "Blink never skips a target")
check(model.calibrationPoints.count == 8, "Merged protocol presents exactly eight targets")
model.cancelExam()
model.startExam()
for _ in 0..<5000 {
    if model.awaitingTaskStart { model.beginPreparedTask() }
    frames(1)
    if model.currentPhase == .completed { break }
}
check(model.currentPhase == .completed, "Merged eight-dot setup completes both eye tasks")
check(model.triageResult?.overallStatus == .recorded, "Full eye flow produces neutral recorded status")
check(model.triageResult?.recording?.qualityMetadata?.protocolVersion == AppConstants.CalibrationGrid.protocolVersion, "Results retain the new calibration protocol")
check(model.triageResult.map { RecordingOverview.items(eye: $0, motor: nil).filter(\.hasUsableData).count == 2 } == true, "Good simulated eye data stays usable in the merged summary")
model.cancelExam()
// Exercise actual reference storage with in-memory defaults, without touching app data.
let storage = BaselineManager(userDefaults: MemoryDefaults())
storage.athletes = [model.selectedAthlete]
var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(model.triageResult!)) as! [String: Any]
payload["isBaselineTest"] = true
let goodBaseline = try JSONDecoder().decode(SCAT6TriageResult.self, from: JSONSerialization.data(withJSONObject: payload))
storage.recordTriageResult(athleteId: model.selectedAthlete.id, result: goodBaseline)
let savedReference = storage.getBaseline(athleteId: model.selectedAthlete.id)
check(savedReference != nil, "Usable baseline saved")
var recording = payload["recording"] as! [String: Any]
var quality = recording["qualityMetadata"] as! [String: Any]
quality["canvasRmsErrorPercent"] = 46.0
recording["qualityMetadata"] = quality
payload["recording"] = recording
payload["timestamp"] = goodBaseline.timestamp.addingTimeInterval(60).timeIntervalSinceReferenceDate
let badBaseline = try JSONDecoder().decode(SCAT6TriageResult.self, from: JSONSerialization.data(withJSONObject: payload))
storage.recordTriageResult(athleteId: model.selectedAthlete.id, result: badBaseline)
check(storage.getBaseline(athleteId: model.selectedAthlete.id) == savedReference, "Failed calibration does not replace usable reference")
check(storage.athletes[0].triageHistory.count == 2, "Failed attempt remains in history")
let legacyBadReference = BaselineBiometrics(athleteId: model.selectedAthlete.id, recordedAt: badBaseline.timestamp,
    pursuitGain: 1, latencyLagMs: 0, fixationStabilityPercent: 100, driftVelocity: 0, twitchesCount: 0)
storage.saveBaseline(athleteId: model.selectedAthlete.id, baseline: legacyBadReference)
check(storage.getBaseline(athleteId: model.selectedAthlete.id) == nil, "Legacy reference from failed check is excluded")
print("PASS: \(checks) eye recovery and instruction regression checks")
