import XCTest
import Combine
@testable import NeuroPulse
#if canImport(ARKit) && os(iOS)
import ARKit
#endif

private final class TestClock {
    var now: TimeInterval = 100
}

private final class FrameTracker: GazeTrackerProtocol {
    var currentMetrics: EyeMetrics = .zero
    var faceDistanceCm: Double { currentMetrics.faceDistanceCm }
    var isDistanceOptimal: Bool { (12...24).contains(faceDistanceCm) }
    var isFaceDetected: Bool { currentMetrics.isTrackingActive }
    var isTracking = false
    var calibrationMap: GazeCalibrationMap?
    var isCalibrated: Bool { calibrationMap != nil }
    var trackingError: String?
    var onFrame: ((EyeMetrics) -> Void)?
    #if canImport(ARKit) && os(iOS)
    var arSession: ARSession? { nil }
    #endif
    func startTracking() { isTracking = true }
    func stopTracking() { isTracking = false }
    func resetCalibration() { calibrationMap = nil }
    func setCalibrationMap(_ map: GazeCalibrationMap, errorDeg: Double) { calibrationMap = map }
    func registerCalibrationPoint(screenPoint: CGPoint, at index: Int) {}
    func send(_ frame: EyeMetrics) { currentMetrics = frame }
}

final class ExamFlowTests: XCTestCase {
    func testFrameGapRestartsAlignmentHold() {
        let clock = TestClock(), tracker = FrameTracker()
        let athlete = AthleteProfile(id: "qa", name: "QA", jerseyNumber: "", sport: "")
        let model = ExamViewModel(athlete: athlete, tracker: tracker, clock: { clock.now }, schedulesTimer: false)
        model.startExam()
        tracker.send(frame(at: clock.now)); model.tick()
        clock.now += 0.9
        tracker.send(frame(at: clock.now)); model.tick()
        clock.now += 0.2
        tracker.send(frame(at: clock.now)); model.tick()
        XCTAssertEqual(model.currentPhase, .alignmentAndDistanceCheck)
        XCTAssertEqual(model.calibrationHoldProgress, 0.2, accuracy: 0.001)
    }

    func testCameraErrorStopsExamWithoutResult() {
        let clock = TestClock(), tracker = FrameTracker()
        tracker.trackingError = "Camera permission denied"
        let athlete = AthleteProfile(id: "qa", name: "QA", jerseyNumber: "", sport: "")
        let model = ExamViewModel(athlete: athlete, tracker: tracker, clock: { clock.now }, schedulesTimer: false)
        model.startExam()
        XCTAssertEqual(model.currentPhase, .invalid(reason: "Camera permission denied"))
        XCTAssertNil(model.triageResult)
        XCTAssertFalse(tracker.isTracking)
    }

    func testCalibrationDeviationDoesNotBlockBaseline() {
        let clock = TestClock(), tracker = FrameTracker()
        let athlete = AthleteProfile(id: "qa", name: "QA", jerseyNumber: "", sport: "")
        let model = ExamViewModel(athlete: athlete, tracker: tracker, clock: { clock.now }, schedulesTimer: false)
        model.startExam()
        var reachedCountdown = false
        for _ in 0..<2400 {
            if model.awaitingTaskStart { model.beginPreparedTask() }
            clock.now += 1.0 / 60
            let isCheck: Bool
            if case .calibration(let index) = model.currentPhase { isCheck = (5..<7).contains(index) } else { isCheck = false }
            let target = isCheck ? CGPoint(x: model.stimulusTarget.x + 0.14, y: model.stimulusTarget.y) : model.stimulusTarget
            tracker.send(frame(at: clock.now, target: target))
            model.tick()
            if case .countdown = model.currentPhase { reachedCountdown = true; break }
            if case .invalid(let reason) = model.currentPhase { return XCTFail(reason) }
        }
        XCTAssertTrue(reachedCountdown, "A 14% check error must not reject calibration")
        XCTAssertTrue(tracker.isCalibrated)
        XCTAssertGreaterThan(model.bestValidationReport?.canvasRmsErrorPercent ?? 0, 8, "Check targets must stay out of the fit")
    }

    func testSingleSetupAt30FPSAllowsSmallMovementAndKeepsRecordingLimits() {
        let clock = TestClock(), tracker = FrameTracker()
        let athlete = AthleteProfile(id: "qa", name: "QA", jerseyNumber: "", sport: "")
        let model = ExamViewModel(athlete: athlete, tracker: tracker, clock: { clock.now }, schedulesTimer: false)
        model.startExam()
        var reachedCountdown = false
        for _ in 0..<900 {
            clock.now += 1.0 / 30
            let setup: Bool
            if case .calibration = model.currentPhase { setup = true } else { setup = false }
            tracker.send(frame(at: clock.now, target: model.stimulusTarget,
                distance: setup ? 18.5 : 16, yaw: setup ? 6 : 0))
            model.tick()
            if case .countdown = model.currentPhase { reachedCountdown = true; break }
            if case .invalid(let reason) = model.currentPhase { return XCTFail(reason) }
        }
        XCTAssertTrue(reachedCountdown)
        XCTAssertEqual(model.calibrationPoints.count, 8)
        XCTAssertTrue(model.calibrationPoints.allSatisfy(\.isCompleted))
        XCTAssertNotNil(model.bestValidationReport)
        XCTAssertEqual(model.referenceHeadPose?.distanceCm, 18.5)
        XCTAssertTrue(model.referenceHeadPose?.isStable(metrics: tracker.currentMetrics) == true)
        XCTAssertFalse(HeadPoseReference(distanceCm: 16, headYawDeg: 0, headPitchDeg: 0, headRollDeg: 0)
            .isStable(metrics: frame(at: clock.now, distance: 18.5, yaw: 6)), "Recording tolerance remains stricter than setup")
    }

    func testBlinkPausesDotAndLongLossRestartsOnlyCurrentDot() {
        let clock = TestClock(), tracker = FrameTracker()
        let athlete = AthleteProfile(id: "qa", name: "QA", jerseyNumber: "", sport: "")
        let model = ExamViewModel(athlete: athlete, tracker: tracker, clock: { clock.now }, schedulesTimer: false)
        model.startExam()
        while model.currentPhase == .alignmentAndDistanceCheck {
            clock.now += 1.0 / 60
            tracker.send(frame(at: clock.now)); model.tick()
            if clock.now > 105 { return XCTFail("Alignment did not finish") }
        }
        for _ in 0..<60 {
            clock.now += 1.0 / 60
            tracker.send(frame(at: clock.now)); model.tick()
        }
        let progress = model.calibrationHoldProgress
        XCTAssertGreaterThan(progress, 0)
        for _ in 0..<12 {
            clock.now += 1.0 / 60
            tracker.send(frame(at: clock.now, blink: 1)); model.tick()
        }
        XCTAssertEqual(model.calibrationHoldProgress, progress)
        XCTAssertEqual(model.currentPhase, .calibration(pointIndex: 0))
        // Replaying one open-eyed frame must not finish the dot.
        tracker.send(frame(at: clock.now)); model.tick()
        let afterBlink = model.calibrationHoldProgress
        for _ in 0..<20 { clock.now += 0.005; model.tick() }
        XCTAssertEqual(model.calibrationHoldProgress, afterBlink)
        // A camera gap also restarts this dot even if the UI timer did not tick during it.
        clock.now += 1
        tracker.send(frame(at: clock.now)); model.tick()
        XCTAssertEqual(model.calibrationHoldProgress, 0)
        for _ in 0..<90 {
            clock.now += 1.0 / 60
            tracker.send(frame(at: clock.now, yaw: 20)); model.tick()
        }
        XCTAssertEqual(model.calibrationHoldProgress, 0)
        XCTAssertEqual(model.currentPhase, .calibration(pointIndex: 0))
        for _ in 0..<110 {
            clock.now += 1.0 / 60
            tracker.send(frame(at: clock.now, target: model.stimulusTarget)); model.tick()
            if model.activeCalibrationIndex == 1 { break }
        }
        XCTAssertEqual(model.activeCalibrationIndex, 1)
        XCTAssertTrue(model.calibrationPoints[0].isCompleted)
    }

    func testCameraPromptsIgnoreJitterAndBriefBlinks() {
        let clock = TestClock(), tracker = FrameTracker()
        let athlete = AthleteProfile(id: "qa", name: "QA", jerseyNumber: "", sport: "")
        let model = ExamViewModel(athlete: athlete, tracker: tracker, clock: { clock.now }, schedulesTimer: false)
        model.startExam()
        for _ in 0..<20 {
            clock.now += 1.0 / 60
            tracker.send(frame(at: clock.now, distance: 30)); model.tick()
        }
        XCTAssertNil(model.cameraPrompt, "Do not flash instructions for a brief distance change")
        for _ in 0..<30 {
            clock.now += 1.0 / 60
            tracker.send(frame(at: clock.now, distance: 30)); model.tick()
        }
        XCTAssertEqual(model.cameraPrompt, "Bring the phone closer")
        for _ in 0..<30 {
            clock.now += 1.0 / 60
            tracker.send(frame(at: clock.now)); model.tick()
        }
        XCTAssertNil(model.cameraPrompt)
        for index in 0..<60 {
            clock.now += 1.0 / 60
            tracker.send(frame(at: clock.now, distance: index.isMultiple(of: 2) ? 23.9 : 24.1)); model.tick()
        }
        XCTAssertNil(model.cameraPrompt, "Distance-boundary jitter must not show a banner")
        for _ in 0..<12 {
            clock.now += 1.0 / 60
            tracker.send(frame(at: clock.now, blink: 1)); model.tick()
        }
        XCTAssertNil(model.cameraPrompt, "Normal blinks must not show an eyes-closed warning")
        for _ in 0..<40 {
            clock.now += 1.0 / 60
            tracker.send(frame(at: clock.now, blink: 1)); model.tick()
        }
        XCTAssertEqual(model.cameraPrompt, "Open your eyes when ready")
        model.startExam()
        XCTAssertNil(model.cameraPrompt, "A new attempt must not inherit an old prompt")
    }

    private func frame(at time: Double, target: CGPoint = CGPoint(x: 0.5, y: 0.5), distance: Double = 16, yaw: Double = 0, blink: Double = 0) -> EyeMetrics {
        EyeMetrics(timestamp: time, isTrackingActive: true, faceDistanceCm: distance,
            rawGazeX: (Double(target.x) - 0.5) / 17.5,
            rawGazeY: (Double(target.y) - 0.5) / (50.0 / 3),
            gazeX: Double(target.x), gazeY: Double(target.y),
            leftEyeYawDeg: 0, leftEyePitchDeg: 0, rightEyeYawDeg: 0, rightEyePitchDeg: 0,
            eyeBlinkLeft: blink, eyeBlinkRight: blink, headYawDeg: yaw)
    }

    func testDuplicateAndStaleFramesCannotAdvanceAlignment() {
        let clock = TestClock(), tracker = FrameTracker()
        let athlete = AthleteProfile(id: "qa", name: "QA", jerseyNumber: "", sport: "")
        let model = ExamViewModel(athlete: athlete, tracker: tracker, clock: { clock.now }, schedulesTimer: false)
        model.startExam()
        tracker.send(frame(at: clock.now)); model.tick()
        clock.now += 1.1
        tracker.send(frame(at: 100)); model.tick()
        tracker.send(frame(at: clock.now - 0.5)); model.tick()
        XCTAssertEqual(model.currentPhase, .alignmentAndDistanceCheck)
        XCTAssertEqual(model.calibrationHoldProgress, 0)
        model.tick()
        XCTAssertEqual(model.currentPhase, .alignmentAndDistanceCheck)
        XCTAssertNil(model.triageResult)
    }

    func testStationaryGazeFailsCalibrationWithoutResult() {
        let clock = TestClock(), tracker = FrameTracker()
        let athlete = AthleteProfile(id: "qa", name: "QA", jerseyNumber: "", sport: "")
        let model = ExamViewModel(athlete: athlete, tracker: tracker, clock: { clock.now }, schedulesTimer: false)
        model.startExam()
        for _ in 0..<2400 {
            if model.awaitingTaskStart { model.beginPreparedTask() }
            clock.now += 1.0 / 60
            model.tick()
            tracker.send(frame(at: clock.now)); model.tick()
            if case .invalid = model.currentPhase { break }
        }
        guard case .invalid(let reason) = model.currentPhase else { return XCTFail("Stationary gaze must fail calibration") }
        XCTAssertTrue(reason.contains("setup couldn't finish"))
        XCTAssertNil(model.triageResult)
        XCTAssertFalse(tracker.isTracking)
    }

    func testCalibratedRecordingCompletesAndPersistsMeasuredTraces() throws {
        let suite = "NeuroPulseFlowTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = BaselineManager(userDefaults: defaults)
        let athlete = storage.addAthlete(name: "QA", jerseyNumber: "", sport: "")
        let clock = TestClock(), tracker = FrameTracker()
        let model = ExamViewModel(athlete: athlete, isBaselineMode: true, tracker: tracker,
            baselineManager: storage, clock: { clock.now }, schedulesTimer: false)
        model.startExam()
        for _ in 0..<5000 {
            if model.awaitingTaskStart { model.beginPreparedTask() }
            clock.now += 1.0 / 60
            tracker.send(frame(at: clock.now, target: model.stimulusTarget))
            model.tick()
            if model.currentPhase == .completed { break }
            if case .invalid(let reason) = model.currentPhase { return XCTFail(reason) }
        }
        XCTAssertEqual(model.currentPhase, .completed)
        let result = try XCTUnwrap(model.triageResult)
        let recording = try XCTUnwrap(result.recording)
        XCTAssertGreaterThan(recording.pursuit.count, 500)
        XCTAssertEqual(recording.measuredFrameRate, 60, accuracy: 0.1)
        XCTAssertEqual(recording.validSampleFraction, 1, accuracy: 0.001)
        XCTAssertEqual(result.pursuitGain, 1, accuracy: 0.02)
        XCTAssertEqual(result.fixationStabilityPercent, 100, accuracy: 0.1)
        XCTAssertFalse(tracker.isTracking)
        let reloaded = BaselineManager(userDefaults: defaults)
        XCTAssertEqual(reloaded.athletes.first?.triageHistory.first, result)
        XCTAssertEqual(reloaded.athletes.first?.baseline?.pursuitGain, result.pursuitGain)
    }
}
