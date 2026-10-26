#if canImport(XCTest)
import XCTest
@testable import NeuroPulse

final class BiometricTypesTests: XCTestCase {
    func testMotorReferencesPersistAndOldComparisonsDoNotChange() throws {
        let suite = "MotorReferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = BaselineManager(userDefaults: defaults)
        let player = manager.addAthlete(name: "Demo player")
        let reaction = MotorMeasurement(status: "measured", metrics: ["median_reaction_ms": 240])
        let balance = MotorMeasurement(status: "measured", metrics: ["phone_acceleration_rms_m_s2": 0])
        let baseline = MotorTestSession(reaction: reaction, balance: balance, isBaseline: true)
        manager.recordMotorSession(athleteId: player.id, session: baseline)
        func eye(_ baseline: Bool = false) -> SCAT6TriageResult {
            SCAT6TriageResult(athleteId: player.id, athleteName: player.name, overallStatus: .normal,
                isBaselineTest: baseline, pursuitGain: 1, latencyLagMs: 0, fixationStabilityPercent: 90,
                driftVelocity: 0, correctiveTwitches: 0, biomarkers: [], recommendations: [])
        }
        let eyeResult = eye()
        let repeatSession = manager.motorSession(for: eyeResult,
            reaction: MotorMeasurement(status: "measured", metrics: ["median_reaction_ms": 270]),
            balance: MotorMeasurement(status: "measured", metrics: ["phone_acceleration_rms_m_s2": 0.2]))
        manager.recordMotorSession(athleteId: player.id, session: repeatSession)
        manager.recordMotorSession(athleteId: player.id, session: repeatSession)
        XCTAssertEqual(manager.getAthlete(id: player.id)?.motorHistory?.count, 2)
        manager.recordMotorSession(athleteId: player.id, session: MotorTestSession(
            reaction: MotorMeasurement(status: "measured", metrics: ["median_reaction_ms": 200]),
            balance: MotorMeasurement(status: "skipped"), isBaseline: true))
        let restored = BaselineManager(userDefaults: defaults)
        let saved = try XCTUnwrap(restored.motorSession(athleteId: player.id, eyeResultID: eyeResult.id))
        XCTAssertEqual(saved.reaction.difference(for: "median_reaction_ms", from: saved.reactionReference), 30)
        XCTAssertEqual(saved.balance.difference(for: "phone_acceleration_rms_m_s2", from: saved.balanceReference), 0.2)
        XCTAssertEqual(restored.getAthlete(id: player.id)?.reactionReference?.measurement.metrics["median_reaction_ms"], 200)
        XCTAssertEqual(restored.getAthlete(id: player.id)?.balanceReference?.measurement.metrics["phone_acceleration_rms_m_s2"], 0)
        XCTAssertNil(restored.motorSession(athleteId: "other-player", eyeResultID: eyeResult.id))
        XCTAssertNil(manager.motorSession(for: eye(true), reaction: reaction, balance: balance).reactionReference)
    }

    func testLegacyMotorSessionDecodesWithoutInventedReferences() throws {
        let session = MotorTestSession(reaction: MotorMeasurement(status: "measured", metrics: ["median_reaction_ms": 240]), balance: MotorMeasurement(status: "skipped"))
        let decoded = try JSONDecoder().decode(MotorTestSession.self, from: JSONEncoder().encode(session))
        XCTAssertNil(decoded.isBaseline)
        XCTAssertNil(decoded.reactionReference)
        XCTAssertNil(decoded.balanceReference)
    }

    func testMotorComparisonRejectsMissingInvalidAndIncompatibleData() {
        let measured = MotorMeasurement(status: "measured", metrics: ["value": 1])
        XCTAssertNil(measured.difference(for: "value", from: nil))
        XCTAssertNil(measured.difference(for: "missing", from: MotorReference(recordedAt: Date(), measurement: measured)))
        XCTAssertNil(measured.difference(for: "value", from: MotorReference(recordedAt: Date(), measurement: measured, protocolVersion: "future")))
        XCTAssertFalse(MotorMeasurement(status: "interrupted", metrics: ["value": 1]).canBeReference)
        XCTAssertFalse(MotorMeasurement(status: "measured", metrics: ["value": .nan]).canBeReference)
        XCTAssertFalse(MotorMeasurement(status: "measured").canBeReference)
    }

    func testGazePointSerialization() throws {
        let point = GazePoint(timestamp: 100.5, x: 0.45, y: 0.55, confidence: 0.98)
        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(GazePoint.self, from: data)

        XCTAssertEqual(decoded.timestamp, 100.5)
        XCTAssertEqual(decoded.x, 0.45)
        XCTAssertEqual(decoded.y, 0.55)
        XCTAssertEqual(decoded.confidence, 0.98)
        XCTAssertEqual(decoded.cgPoint.x, 0.45)
        XCTAssertEqual(decoded.cgPoint.y, 0.55)
    }

    func testEyeMetricsDefaults() {
        let metrics = EyeMetrics.zero
        XCTAssertFalse(metrics.isTrackingActive)
        XCTAssertEqual(metrics.faceDistanceCm, 0.0)
        XCTAssertNil(metrics.gazeX)
        XCTAssertNil(metrics.gazeY)
    }

    func testMeasurementStatusesDescribeDeviceStateNotConcussionRisk() {
        XCTAssertEqual(TriageStatus.normal.badgeText, "MEASUREMENTS RECORDED")
        XCTAssertEqual(TriageStatus.borderline.badgeText, "REVIEW MEASUREMENTS")
        XCTAssertEqual(TriageStatus.elevatedRisk.badgeText, "INCOMPLETE RECORDING")
        XCTAssertEqual(TriageStatus.criticalAlert.badgeText, "DEVICE ERROR")
    }

    func testAthleteProfileWithBaseline() throws {
        let baseline = BaselineBiometrics(
            athleteId: "ath-101",
            pursuitGain: 0.92,
            latencyLagMs: 18.0,
            fixationStabilityPercent: 91.0,
            driftVelocity: 0.12,
            twitchesCount: 0
        )
        let profile = AthleteProfile(
            id: "ath-101",
            name: "John Doe",
            jerseyNumber: "12",
            sport: "Football",
            school: "Bentonville High School",
            baseline: baseline
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: data)

        XCTAssertEqual(decoded.id, "ath-101")
        XCTAssertEqual(decoded.baseline?.pursuitGain, 0.92)
        XCTAssertEqual(decoded.baseline?.latencyLagMs, 18.0)
    }

    func testRosterMigrationPreservesPlayersAndDoesNotRestoreDeletedPlayers() throws {
        let suite = "RosterMigration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var old = AthleteProfile(id: "old", name: "Earlier Player", jerseyNumber: "Maheshwari", sport: "")
        old.motorHistory = [MotorTestSession(reaction: MotorMeasurement(status: "measured"), balance: MotorMeasurement(status: "skipped"))]
        let current = AthleteProfile(id: "new", name: "Current Player", jerseyNumber: "7", sport: "")
        defaults.set(try JSONEncoder().encode([old]), forKey: "neuropulse_athlete_roster_v2")
        defaults.set(try JSONEncoder().encode([current]), forKey: "neuropulse_athlete_roster_v3")
        let manager = BaselineManager(userDefaults: defaults)
        XCTAssertEqual(Set(manager.athletes.map(\.id)), Set(["old", "new"]))
        XCTAssertEqual(manager.getAthlete(id: "old")?.motorHistory?.count, 1)
        manager.deleteAthlete(id: "old")
        XCTAssertEqual(BaselineManager(userDefaults: defaults).athletes.map(\.id), ["new"])
    }

    func testRecentlyInstalledStatusEncodingRemainsReadable() throws {
        let data = Data("\"MEASUREMENTS RECORDED\"".utf8)
        XCTAssertEqual(try JSONDecoder().decode(TriageStatus.self, from: data), .recorded)
        XCTAssertEqual(try JSONDecoder().decode(TriageStatus.self, from: Data("\"NOMINAL RANGE\"".utf8)), .normal)
    }

    func testPursuitLagAndHoldCardsHaveDistinctAccurateLabels() {
        func card(_ title: String, unit: String, value: Double) -> BiomarkerCardView {
            BiomarkerCardView(data: BiomarkerCardData(title: title, measuredValue: value, unit: unit,
                normativeTarget: "No validated clinical cutoff", baselineValue: nil,
                deltaPercent: nil, status: .normal, interpretation: ""))
        }
        XCTAssertEqual(card("Pursuit gain", unit: "ratio", value: 1).displayTitle, "Tracking speed ratio")
        XCTAssertEqual(card("Pursuit phase lag", unit: "ms", value: 117.2).displayTitle, "Timing offset")
        let hold = card("Time near hold target", unit: "%", value: 0)
        XCTAssertEqual(hold.displayTitle, "Time near the hold dot")
        XCTAssertTrue(hold.explanation.contains("0% means none"))
    }

    func testAppConstantsDistanceGuidance() {
        XCTAssertEqual(AppConstants.minOptimalDistanceCm, 12.0)
        XCTAssertEqual(AppConstants.maxOptimalDistanceCm, 24.0)
    }
}
#endif
