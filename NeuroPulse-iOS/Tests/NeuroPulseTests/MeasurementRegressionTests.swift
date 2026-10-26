import XCTest
@testable import NeuroPulse

final class MeasurementRegressionTests: XCTestCase {
    func testNonfiniteGeometryIsRejected() {
        XCTAssertNil(GazeMath.visualAngleDeg(normalized: .nan, axisLengthPoints: 390, distanceCm: 25))
        XCTAssertNil(GazeMath.visualAngleDeg(normalized: 0.5, axisLengthPoints: 390, distanceCm: .infinity))
        XCTAssertNil(GazeMath.visualAngleDeg(normalized: 0.5, axisLengthPoints: .infinity, distanceCm: 25))
    }
    func testNonfiniteDerivativeBecomesGap() {
        let derivative = GazeMath.derivative([0, .nan, 1, 2, 3], times: [0, 0.02, 0.04, 0.06, 0.08])
        XCTAssertNil(derivative[1]); XCTAssertNil(derivative[2])
    }
    func testGapsAndNonmonotonicTimesAreNotDifferentiated() {
        XCTAssertNil(GazeMath.derivative([0, nil, 2, 3, 4], times: [0, 0.02, 0.04, 0.06, 0.08])[2])
        XCTAssertNil(GazeMath.derivative([0, 1, 2, 3, 4], times: [0, 0.02, 0.01, 0.06, 0.08])[2])
    }
    func testLookingAtCenterDoesNotPassPeripheralTargetHold() throws {
        let trace = (0..<300).map { TraceSample(t: Double($0) / 60, eyeXDeg: 0, eyeYDeg: 0, targetXDeg: 7, targetYDeg: 0) }
        XCTAssertEqual(try XCTUnwrap(GazeMath.analyzeFixation(trace, saccades: [])).stabilityPercent, 0)
    }
    func testStationaryGazeIsNotAcceptedAsCalibration() {
        let sample = CalibrationSample(rawX: 0, rawY: 0, screenX: 0.5, screenY: 0.5, distanceCm: 25)
        XCTAssertNil(GazeMath.fitCalibration(Array(repeating: sample, count: 5)))
    }
    func testCollinearCalibrationCannotMapBothScreenAxes() {
        let samples = (0..<5).map { i in
            CalibrationSample(rawX: Double(i) * 0.01, rawY: 0, screenX: Double(i) / 4, screenY: 0.5, distanceCm: 25)
        }
        XCTAssertNil(GazeMath.fitCalibration(samples))
    }
    func testCalibrationRejectsNonfiniteSamples() {
        let samples = [
            CalibrationSample(rawX: 0, rawY: 0, screenX: 0.5, screenY: 0.5, distanceCm: 25),
            CalibrationSample(rawX: -0.02, rawY: 0, screenX: 0.15, screenY: 0.5, distanceCm: 25),
            CalibrationSample(rawX: 0.02, rawY: 0, screenX: 0.85, screenY: 0.5, distanceCm: 25),
            CalibrationSample(rawX: .nan, rawY: 0.01, screenX: 0.5, screenY: 0.75, distanceCm: 25)
        ]
        XCTAssertNil(GazeMath.fitCalibration(samples))
    }
    func testCalibrationInverseReturnsOriginalPoint() throws {
        let samples = [
            CalibrationSample(rawX: -0.02, rawY: -0.015, screenX: 0.15, screenY: 0.25, distanceCm: 25),
            CalibrationSample(rawX: 0.02, rawY: -0.015, screenX: 0.85, screenY: 0.25, distanceCm: 25),
            CalibrationSample(rawX: -0.02, rawY: 0.015, screenX: 0.15, screenY: 0.75, distanceCm: 25),
            CalibrationSample(rawX: 0.02, rawY: 0.015, screenX: 0.85, screenY: 0.75, distanceCm: 25),
            CalibrationSample(rawX: 0, rawY: 0, screenX: 0.5, screenY: 0.5, distanceCm: 25)
        ]
        let map = try XCTUnwrap(GazeMath.fitCalibration(samples))
        let raw = try XCTUnwrap(map.rawPoint(for: CGPoint(x: 0.3, y: 0.4)))
        let mapped = map.apply(rawX: raw.x, rawY: raw.y)
        XCTAssertEqual(mapped.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 0.4, accuracy: 0.001)
    }
    func testHoldStabilityIsScoredAgainstTargetRatherThanItsOwnMedian() throws {
        let trace = (0..<300).map { i in TraceSample(t: Double(i) / 60, eyeXDeg: 3, eyeYDeg: 0, targetXDeg: 7, targetYDeg: 0) }
        XCTAssertEqual(try XCTUnwrap(GazeMath.analyzeFixation(trace, saccades: [])).stabilityPercent, 0)
    }
    func testRecordingQualityRejectsShortSparseAndGappedTraces() {
        let short = (0..<10).map { TraceSample(t: Double($0) / 30, eyeXDeg: 0, eyeYDeg: 0, targetXDeg: 0, targetYDeg: 0) }
        XCTAssertNil(GazeMath.quality(short, duration: 5))
        let gapped = [0.0, 0.03, 0.06, 0.5, 0.53].map { TraceSample(t: $0, eyeXDeg: 0, eyeYDeg: 0, targetXDeg: 0, targetYDeg: 0) }
        XCTAssertNil(GazeMath.quality(gapped, duration: 0.5))
    }
    func testRecordingQualityReportsActualFrameRateAndValidFraction() throws {
        let trace = (0..<151).map { i in TraceSample(t: Double(i) / 30, eyeXDeg: i % 10 == 0 ? nil : 0, eyeYDeg: 0, targetXDeg: 0, targetYDeg: 0) }
        let result = try XCTUnwrap(GazeMath.quality(trace, duration: 5))
        XCTAssertEqual(result.fps, 30, accuracy: 0.01)
        XCTAssertEqual(result.fraction, 0.894, accuracy: 0.002)
    }
    func testGazeAngleRejectsInvalidDistance() {
        let map = GazeCalibrationMap(ax: 10, bx: 0, cx: 0.5, ay: 0, by: 10, cy: 0.5)
        XCTAssertNil(GazeMath.gazeAngles(raw: CGPoint(x: 0.01, y: 0), map: map, distanceCm: 0))
        XCTAssertNil(GazeMath.gazeAngles(raw: CGPoint(x: 0.01, y: 0), map: map, distanceCm: .nan))
    }
    func testTriagePayloadNeverClaimsDiagnosisFromEyeMeasurements() {
        let result = GazeMath.evaluateTriage(athleteId: "a", athleteName: "Athlete",
            pursuitGain: 0.1, latencyLagMs: 900, fixationStabilityPercent: 0,
            driftVelocity: 10, correctiveTwitches: 80)
        XCTAssertEqual(result.overallStatus.badgeText, "MEASUREMENTS RECORDED")
        XCTAssertTrue(result.recommendations.contains { $0.localizedCaseInsensitiveContains("cannot diagnose") })
    }
    func testNewRosterContainsNoInventedAthleteOrBaseline() {
        let suite = "NeuroPulseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(BaselineManager(userDefaults: defaults).athletes.isEmpty)
    }
    func testEyeMetricsWithNonfiniteCoordinatesAreNotUsable() {
        let metrics = EyeMetrics(timestamp: 1, isTrackingActive: true, faceDistanceCm: 25,
            rawGazeX: .nan, rawGazeY: 0, gazeX: nil, gazeY: nil,
            leftEyeYawDeg: 0, leftEyePitchDeg: 0, rightEyeYawDeg: 0, rightEyePitchDeg: 0,
            eyeBlinkLeft: 0, eyeBlinkRight: 0)
        XCTAssertFalse(metrics.isUsable)
    }
    func testUntrackedFramesAndBlinkFramesAreNotUsable() {
        XCTAssertFalse(EyeMetrics.untracked(at: 1).isUsable)
        let blink = EyeMetrics(timestamp: 1, isTrackingActive: true, faceDistanceCm: 25,
            rawGazeX: 0, rawGazeY: 0, gazeX: nil, gazeY: nil,
            leftEyeYawDeg: 0, leftEyePitchDeg: 0, rightEyeYawDeg: 0, rightEyePitchDeg: 0,
            eyeBlinkLeft: 0.8, eyeBlinkRight: 0)
        XCTAssertFalse(blink.isUsable)
    }

    func testFiveReactionTrialsUseAllSamplesForMedian() {
        let taps = [MotorTap(t: 0.2, side: 0), MotorTap(t: 0.4, side: 1), MotorTap(t: 1, side: 0), MotorTap(t: 1.4, side: 1)]
        let result = MotorTestAnalysis.reaction(times: [0.2, 0.3, 0.4, 0.5, 0.6], early: 0, missed: 0,
            taps: taps, duration: 5, maxFrameGap: 0.016)
        XCTAssertEqual(result.status, "measured")
        XCTAssertEqual(result.metrics["median_reaction_ms"], 400)
        XCTAssertEqual(result.metrics["reaction_trial_5_ms"], 600)
    }

    func testMotorReactionRequiresValidTrialsAlternationsAndTiming() {
        let taps = [MotorTap(t: 0.2, side: 0), MotorTap(t: 0.4, side: 1), MotorTap(t: 1.0, side: 0), MotorTap(t: 1.4, side: 1)]
        let result = MotorTestAnalysis.reaction(times: [0.3, 0.4, 0.5], early: 1, missed: 2, taps: taps, duration: 5, maxFrameGap: 0.016)
        XCTAssertEqual(result.status, "measured")
        XCTAssertEqual(result.metrics["median_reaction_ms"], 400)
        XCTAssertEqual(result.metrics["alternations"], 3)
        XCTAssertEqual(MotorTestAnalysis.reaction(times: [0.3, 0.4], early: 0, missed: 0, taps: taps, duration: 5, maxFrameGap: 0.016).status, "insufficient_quality")
        XCTAssertEqual(MotorTestAnalysis.reaction(times: [0.3, 0.4, 0.5], early: 0, missed: 0, taps: taps, duration: 5, maxFrameGap: 0.2).status, "insufficient_quality")
        XCTAssertEqual(MotorTestAnalysis.reaction(times: [0.3, 0.4, 0.5], early: 0, missed: 0, taps: taps, duration: 5, maxFrameGap: 0.016, multiTouch: true).status, "insufficient_quality")
    }

    func testMotorBalanceRequiresContinuousTenSecondSamples() {
        let samples = (0...200).map { i in
            MotorMotionSample(t: Double(i) / 20, acceleration: (0.1, 0, 0), gravity: (0, 0, 9.80665), rotation: (0, 0, 0))
        }
        let result = MotorTestAnalysis.balance(samples: samples)
        XCTAssertEqual(result.status, "measured")
        XCTAssertEqual(result.metrics["phone_tilt_peak_deg"], 0)
        XCTAssertEqual(result.metrics["sample_count"], 201)
        XCTAssertEqual(MotorTestAnalysis.balance(samples: Array(samples.dropLast(20))).status, "insufficient_quality")
    }

    func testMotorResultsPersistUnderTheirPlayerAndOlderProfilesStillDecode() throws {
        let oldProfile = AthleteProfile(id: "athlete", name: "Player", jerseyNumber: "4", sport: "Soccer")
        let decodedOldProfile = try JSONDecoder().decode(AthleteProfile.self, from: JSONEncoder().encode(oldProfile))
        XCTAssertNil(decodedOldProfile.motorHistory)

        let suite = "NeuroPulseMotorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = BaselineManager(userDefaults: defaults)
        let player = manager.addAthlete(name: "Player", jerseyNumber: "4", sport: "Soccer")
        let session = MotorTestSession(
            reaction: MotorMeasurement(status: "measured", metrics: ["median_reaction_ms": 320]),
            balance: MotorMeasurement(status: "measured", metrics: ["phone_tilt_rms_deg": 1.2]))
        manager.athletes[0].motorHistory = [session]
        manager.saveToStorage()
        XCTAssertEqual(BaselineManager(userDefaults: defaults).getAthlete(id: player.id)?.motorHistory?.first, session)
    }
}
