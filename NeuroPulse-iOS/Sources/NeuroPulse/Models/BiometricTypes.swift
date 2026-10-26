import Foundation
import CoreGraphics

// MARK: - Gaze Point
public struct GazePoint: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let x: Double
    public let y: Double
    public let confidence: Double

    public init(timestamp: TimeInterval, x: Double, y: Double, confidence: Double = 1.0) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.confidence = confidence
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

// MARK: - Eye Metrics Telemetry (one ARKit TrueDepth frame)
/// Every field is measured directly from an `ARFrame` / `ARFaceAnchor`. Nothing is estimated or defaulted:
/// when no face is tracked, `isTrackingActive` is false and the gaze fields are nil.
public struct EyeMetrics: Codable, Equatable, Sendable {
    /// ARFrame capture timestamp (seconds, same clock as `ProcessInfo.systemUptime`).
    public let timestamp: TimeInterval
    /// True only when an `ARFaceAnchor` is present and `isTracked` for this frame.
    public let isTrackingActive: Bool
    /// Camera-to-eye-midpoint distance in centimetres (TrueDepth), 0 when untracked.
    public let faceDistanceCm: Double
    /// Binocular gaze ray ∩ device (camera z = 0) plane, metres, camera coordinates. Input to calibration.
    public let rawGazeX: Double
    public let rawGazeY: Double
    /// Calibrated point of regard on the exam canvas, normalised 0…1. Nil until calibrated or when untracked.
    public let gazeX: Double?
    public let gazeY: Double?
    /// Eye-in-head rotation from `leftEyeTransform` / `rightEyeTransform` (deg). +yaw = toward screen right, +pitch = up.
    public let leftEyeYawDeg: Double
    public let leftEyePitchDeg: Double
    public let rightEyeYawDeg: Double
    public let rightEyePitchDeg: Double
    /// ARKit `eyeBlinkLeft` / `eyeBlinkRight` blend-shape coefficients (0 open … 1 closed).
    public let eyeBlinkLeft: Double
    public let eyeBlinkRight: Double
    /// Head rotation relative to camera in degrees (yaw, pitch, roll) from faceAnchor.transform.
    public let headYawDeg: Double
    public let headPitchDeg: Double
    public let headRollDeg: Double

    public init(
        timestamp: TimeInterval,
        isTrackingActive: Bool,
        faceDistanceCm: Double,
        rawGazeX: Double,
        rawGazeY: Double,
        gazeX: Double?,
        gazeY: Double?,
        leftEyeYawDeg: Double,
        leftEyePitchDeg: Double,
        rightEyeYawDeg: Double,
        rightEyePitchDeg: Double,
        eyeBlinkLeft: Double,
        eyeBlinkRight: Double,
        headYawDeg: Double = 0.0,
        headPitchDeg: Double = 0.0,
        headRollDeg: Double = 0.0
    ) {
        self.timestamp = timestamp
        self.isTrackingActive = isTrackingActive
        self.faceDistanceCm = faceDistanceCm
        self.rawGazeX = rawGazeX
        self.rawGazeY = rawGazeY
        self.gazeX = gazeX
        self.gazeY = gazeY
        self.leftEyeYawDeg = leftEyeYawDeg
        self.leftEyePitchDeg = leftEyePitchDeg
        self.rightEyeYawDeg = rightEyeYawDeg
        self.rightEyePitchDeg = rightEyePitchDeg
        self.eyeBlinkLeft = eyeBlinkLeft
        self.eyeBlinkRight = eyeBlinkRight
        self.headYawDeg = headYawDeg
        self.headPitchDeg = headPitchDeg
        self.headRollDeg = headRollDeg
    }

    /// A frame in which ARKit did not report a tracked face.
    public static func untracked(at timestamp: TimeInterval) -> EyeMetrics {
        EyeMetrics(
            timestamp: timestamp, isTrackingActive: false, faceDistanceCm: 0,
            rawGazeX: 0, rawGazeY: 0, gazeX: nil, gazeY: nil,
            leftEyeYawDeg: 0, leftEyePitchDeg: 0, rightEyeYawDeg: 0, rightEyePitchDeg: 0,
            eyeBlinkLeft: 0, eyeBlinkRight: 0,
            headYawDeg: 0, headPitchDeg: 0, headRollDeg: 0
        )
    }

    public static let zero = EyeMetrics.untracked(at: 0)

    public var isBlinking: Bool { max(eyeBlinkLeft, eyeBlinkRight) > 0.55 }
    public var eyeYawDeg: Double { (leftEyeYawDeg + rightEyeYawDeg) / 2 }
    public var eyePitchDeg: Double { (leftEyePitchDeg + rightEyePitchDeg) / 2 }
    /// Usable for gaze measurement: tracked face, eyes open.
    public var isUsable: Bool { isTrackingActive && !isBlinking && timestamp.isFinite && faceDistanceCm.isFinite
        && faceDistanceCm > 0 && rawGazeX.isFinite && rawGazeY.isFinite }
}

// MARK: - Calibration
public struct CalibrationPoint: Identifiable, Equatable, Sendable {
    public let id: Int
    public let label: String
    public let screenPosition: CGPoint
    public var isCompleted: Bool

    public init(id: Int, label: String, screenPosition: CGPoint, isCompleted: Bool = false) {
        self.id = id
        self.label = label
        self.screenPosition = screenPosition
        self.isCompleted = isCompleted
    }
}

/// One raw ARKit gaze measurement paired with the canvas position the athlete was fixating.
public struct CalibrationSample: Codable, Equatable, Sendable {
    public let rawX: Double
    public let rawY: Double
    public let screenX: Double
    public let screenY: Double
    public let distanceCm: Double

    public init(rawX: Double, rawY: Double, screenX: Double, screenY: Double, distanceCm: Double) {
        self.rawX = rawX
        self.rawY = rawY
        self.screenX = screenX
        self.screenY = screenY
        self.distanceCm = distanceCm
    }
}

/// Least-squares affine map from raw ARKit gaze-plane coordinates (m) to normalised canvas coordinates.
/// Affine fitting absorbs ARKit's camera-axis orientation, front-camera mirroring and per-person eye scale.
public struct GazeCalibrationMap: Codable, Equatable, Sendable {
    public let ax: Double, bx: Double, cx: Double
    public let ay: Double, by: Double, cy: Double

    public init(ax: Double, bx: Double, cx: Double, ay: Double, by: Double, cy: Double) {
        self.ax = ax; self.bx = bx; self.cx = cx
        self.ay = ay; self.by = by; self.cy = cy
    }

    public func apply(rawX: Double, rawY: Double) -> CGPoint {
        CGPoint(x: ax * rawX + bx * rawY + cx, y: ay * rawX + by * rawY + cy)
    }
}

// MARK: - Recorded Eye Movement Traces
/// One frame of an exam recording, in degrees of visual angle from canvas centre.
public struct TraceSample: Codable, Equatable, Sendable {
    public let t: Double
    /// Nil when the face was not tracked or the athlete blinked (a genuine gap, not interpolated).
    public let eyeXDeg: Double?
    public let eyeYDeg: Double?
    public let targetXDeg: Double
    public let targetYDeg: Double

    public init(t: Double, eyeXDeg: Double?, eyeYDeg: Double?, targetXDeg: Double, targetYDeg: Double) {
        self.t = t
        self.eyeXDeg = eyeXDeg
        self.eyeYDeg = eyeYDeg
        self.targetXDeg = targetXDeg
        self.targetYDeg = targetYDeg
    }
}

/// A detected saccade ("twitch"): rapid eye jump exceeding the velocity threshold.
public struct SaccadeEvent: Codable, Equatable, Sendable {
    public let startTime: Double
    public let endTime: Double
    public let amplitudeDeg: Double
    public let peakVelocityDegPerSec: Double

    public init(startTime: Double, endTime: Double, amplitudeDeg: Double, peakVelocityDegPerSec: Double) {
        self.startTime = startTime
        self.endTime = endTime
        self.amplitudeDeg = amplitudeDeg
        self.peakVelocityDegPerSec = peakVelocityDegPerSec
    }
}

/// Camera-relative reference head pose established during alignment setup.
public struct HeadPoseReference: Codable, Equatable, Sendable {
    public let distanceCm: Double
    public let headYawDeg: Double
    public let headPitchDeg: Double
    public let headRollDeg: Double

    public init(distanceCm: Double, headYawDeg: Double, headPitchDeg: Double, headRollDeg: Double) {
        self.distanceCm = distanceCm
        self.headYawDeg = headYawDeg
        self.headPitchDeg = headPitchDeg
        self.headRollDeg = headRollDeg
    }

    /// Validates if an incoming frame's head pose is within stability tolerances.
    public func isStable(metrics: EyeMetrics, maxRotDeg: Double = AppConstants.Norms.maxHeadRotationShiftDeg, maxDistCm: Double = AppConstants.Norms.maxHeadDistanceShiftCm) -> Bool {
        isStable(distanceCm: metrics.faceDistanceCm, headYawDeg: metrics.headYawDeg, headPitchDeg: metrics.headPitchDeg, headRollDeg: metrics.headRollDeg, maxRotDeg: maxRotDeg, maxDistCm: maxDistCm)
    }

    public func isStable(distanceCm: Double, headYawDeg: Double, headPitchDeg: Double, headRollDeg: Double, maxRotDeg: Double = AppConstants.Norms.maxHeadRotationShiftDeg, maxDistCm: Double = AppConstants.Norms.maxHeadDistanceShiftCm) -> Bool {
        guard [distanceCm, headYawDeg, headPitchDeg, headRollDeg,
               self.distanceCm, self.headYawDeg, self.headPitchDeg, self.headRollDeg,
               maxRotDeg, maxDistCm].allSatisfy({ $0.isFinite }),
              distanceCm > 0, maxRotDeg >= 0, maxDistCm >= 0 else { return false }
        func angularDifference(_ a: Double, _ b: Double) -> Double {
            let delta = abs((a - b).truncatingRemainder(dividingBy: 360))
            return min(delta, 360 - delta)
        }
        return angularDifference(headYawDeg, self.headYawDeg) <= maxRotDeg
            && angularDifference(headPitchDeg, self.headPitchDeg) <= maxRotDeg
            && angularDifference(headRollDeg, self.headRollDeg) <= maxRotDeg
            && abs(distanceCm - self.distanceCm) <= maxDistCm
    }
}

/// Independent validation report evaluating accuracy on held-out check targets and post-calibration drift.
public struct ValidationReport: Codable, Equatable, Sendable {
    public let canvasRmsErrorPercent: Double
    public let worstTargetErrorPercent: Double
    public let centerDriftPercent: Double
    public let isAcceptable: Bool
    public let failureReason: String?

    public init(
        canvasRmsErrorPercent: Double,
        worstTargetErrorPercent: Double,
        centerDriftPercent: Double,
        isAcceptable: Bool,
        failureReason: String? = nil
    ) {
        self.canvasRmsErrorPercent = canvasRmsErrorPercent
        self.worstTargetErrorPercent = worstTargetErrorPercent
        self.centerDriftPercent = centerDriftPercent
        self.isAcceptable = isAcceptable
        self.failureReason = failureReason
    }
}

/// Versioned recording-quality metadata describing calibration accuracy and sample exclusions.
public struct RecordingQualityMetadata: Codable, Equatable, Sendable {
    public let protocolVersion: String
    public let canvasRmsErrorPercent: Double
    public let worstTargetErrorPercent: Double
    public let centerDriftPercent: Double
    public let excludedSamplesCount: Int
    public let excludedReasons: [String]
    public let referenceHeadPose: HeadPoseReference?

    public init(
        protocolVersion: String = "2.5.0-9point",
        canvasRmsErrorPercent: Double = 0.0,
        worstTargetErrorPercent: Double = 0.0,
        centerDriftPercent: Double = 0.0,
        excludedSamplesCount: Int = 0,
        excludedReasons: [String] = [],
        referenceHeadPose: HeadPoseReference? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.canvasRmsErrorPercent = canvasRmsErrorPercent
        self.worstTargetErrorPercent = worstTargetErrorPercent
        self.centerDriftPercent = centerDriftPercent
        self.excludedSamplesCount = excludedSamplesCount
        self.excludedReasons = excludedReasons
        self.referenceHeadPose = referenceHeadPose
    }

    public var isAcceptableQuality: Bool {
        canvasRmsErrorPercent <= AppConstants.CalibrationGrid.maxValidationCanvasRmsPercent &&
        worstTargetErrorPercent <= AppConstants.CalibrationGrid.maxValidationWorstTargetPercent
    }
}

/// Full eye-movement recording kept with each result so the twitches can be reviewed afterwards.
public struct ExamRecording: Codable, Equatable, Sendable {
    public let pursuit: [TraceSample]
    public let pursuitSaccades: [SaccadeEvent]
    public let holdRight: [TraceSample]
    public let holdRightSaccades: [SaccadeEvent]
    public let holdLeft: [TraceSample]
    public let holdLeftSaccades: [SaccadeEvent]
    public let calibrationErrorDeg: Double
    public let meanDistanceCm: Double
    public let validSampleFraction: Double
    public let measuredFrameRate: Double
    public let qualityMetadata: RecordingQualityMetadata?

    public init(
        pursuit: [TraceSample], pursuitSaccades: [SaccadeEvent],
        holdRight: [TraceSample], holdRightSaccades: [SaccadeEvent],
        holdLeft: [TraceSample], holdLeftSaccades: [SaccadeEvent],
        calibrationErrorDeg: Double, meanDistanceCm: Double,
        validSampleFraction: Double, measuredFrameRate: Double,
        qualityMetadata: RecordingQualityMetadata? = nil
    ) {
        self.pursuit = pursuit
        self.pursuitSaccades = pursuitSaccades
        self.holdRight = holdRight
        self.holdRightSaccades = holdRightSaccades
        self.holdLeft = holdLeft
        self.holdLeftSaccades = holdLeftSaccades
        self.calibrationErrorDeg = calibrationErrorDeg
        self.meanDistanceCm = meanDistanceCm
        self.validSampleFraction = validSampleFraction
        self.measuredFrameRate = measuredFrameRate
        self.qualityMetadata = qualityMetadata
    }
}

// MARK: - Test Phases
public enum HoldSide: String, Codable, Sendable {
    case left = "Left"
    case right = "Right"
}

public enum TestPhase: Equatable, Sendable {
    case idle
    case alignmentAndDistanceCheck
    case calibration(pointIndex: Int)
    case countdown(remaining: Int)
    case smoothPursuit(elapsed: Double)
    case lateralHold(side: HoldSide, elapsed: Double)
    case completed
    /// The exam could not produce trustworthy measurements; no score is generated.
    case invalid(reason: String)

    public var title: String {
        switch self {
        case .idle:
            return "Ready to Start"
        case .alignmentAndDistanceCheck:
            return "Position your phone"
        case .calibration(let index):
            return "Eye setup (\(index + 1)/\(AppConstants.CalibrationGrid.guidedPoints.count))"
        case .countdown(let rem):
            return "Starting in \(rem)..."
        case .smoothPursuit:
            return "Follow the moving dot"
        case .lateralHold(let side, _):
            return "Look at the stationary dot (\(side.rawValue))"
        case .completed:
            return "Recording Complete"
        case .invalid:
            return "Recording couldn't finish"
        }
    }
}
// MARK: - Experimental Measurement Status
public enum TriageStatus: String, Codable, Sendable, CaseIterable {
    case recorded = "MEASUREMENTS RECORDED"
    case normal = "NOMINAL RANGE"
    case borderline = "ATYPICAL VARIANCE"
    case elevatedRisk = "ELEVATED DEVIATION"
    case criticalAlert = "MARKED DEVIATION"
    public var badgeText: String {
        switch self {
        case .normal, .recorded: return "MEASUREMENTS RECORDED"
        case .borderline: return "REVIEW MEASUREMENTS"
        case .elevatedRisk: return "INCOMPLETE RECORDING"
        case .criticalAlert: return "DEVICE ERROR"
        }
    }
    public var level: Int { 0 }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if let status = Self(rawValue: value) { self = status; return }
        switch value {
        case "MEASUREMENTS RECORDED": self = .recorded
        case "REVIEW MEASUREMENTS": self = .borderline
        case "INCOMPLETE RECORDING": self = .elevatedRisk
        case "DEVICE ERROR": self = .criticalAlert
        default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown recording status"))
        }
    }
}

// MARK: - Biomarker Card Data
public struct BiomarkerCardData: Identifiable, Codable, Equatable, Sendable {
    public var id: String { title }
    public let title: String
    public let measuredValue: Double
    public let unit: String
    public let normativeTarget: String
    public let baselineValue: Double?
    public let deltaPercent: Double?
    public let status: TriageStatus
    public let interpretation: String
    public let comparisonNote: String?

    public init(
        title: String,
        measuredValue: Double,
        unit: String,
        normativeTarget: String,
        baselineValue: Double? = nil,
        deltaPercent: Double? = nil,
        status: TriageStatus,
        interpretation: String,
        comparisonNote: String? = nil
    ) {
        self.title = title
        self.measuredValue = measuredValue
        self.unit = unit
        self.normativeTarget = normativeTarget
        self.baselineValue = baselineValue
        self.deltaPercent = deltaPercent
        self.status = status
        self.interpretation = interpretation
        self.comparisonNote = comparisonNote
    }
}

// MARK: - Baseline Biometrics
public struct BaselineBiometrics: Codable, Equatable, Sendable {
    public let athleteId: String
    public let recordedAt: Date
    public let pursuitGain: Double
    public let latencyLagMs: Double
    public let fixationStabilityPercent: Double
    public let driftVelocity: Double
    public let twitchesCount: Int
    public let protocolVersion: String?

    public init(
        athleteId: String,
        recordedAt: Date = Date(),
        pursuitGain: Double,
        latencyLagMs: Double,
        fixationStabilityPercent: Double,
        driftVelocity: Double,
        twitchesCount: Int,
        protocolVersion: String? = AppConstants.CalibrationGrid.protocolVersion
    ) {
        self.athleteId = athleteId
        self.recordedAt = recordedAt
        self.pursuitGain = pursuitGain
        self.latencyLagMs = latencyLagMs
        self.fixationStabilityPercent = fixationStabilityPercent
        self.driftVelocity = driftVelocity
        self.twitchesCount = twitchesCount
        self.protocolVersion = protocolVersion
    }
}

// MARK: - SCAT6 Triage Result
public struct SCAT6TriageResult: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let athleteId: String
    public let athleteName: String
    public let timestamp: Date
    public let overallStatus: TriageStatus
    public let isBaselineTest: Bool
    public let pursuitGain: Double
    public let latencyLagMs: Double
    public let fixationStabilityPercent: Double
    public let driftVelocity: Double
    public let correctiveTwitches: Int
    public let rciScore: Double?
    public let biomarkers: [BiomarkerCardData]
    public let recommendations: [String]
    public let emergencyFlags: [String]
    /// Raw eye-movement traces + detected saccades backing every number above.
    public let recording: ExamRecording?

    public init(
        id: UUID = UUID(),
        athleteId: String,
        athleteName: String,
        timestamp: Date = Date(),
        overallStatus: TriageStatus,
        isBaselineTest: Bool = false,
        pursuitGain: Double,
        latencyLagMs: Double,
        fixationStabilityPercent: Double,
        driftVelocity: Double,
        correctiveTwitches: Int,
        rciScore: Double? = nil,
        biomarkers: [BiomarkerCardData],
        recommendations: [String],
        emergencyFlags: [String] = [],
        recording: ExamRecording? = nil
    ) {
        self.id = id
        self.athleteId = athleteId
        self.athleteName = athleteName
        self.timestamp = timestamp
        self.overallStatus = overallStatus
        self.isBaselineTest = isBaselineTest
        self.pursuitGain = pursuitGain
        self.latencyLagMs = latencyLagMs
        self.fixationStabilityPercent = fixationStabilityPercent
        self.driftVelocity = driftVelocity
        self.correctiveTwitches = correctiveTwitches
        self.rciScore = rciScore
        self.biomarkers = biomarkers
        self.recommendations = recommendations
        self.emergencyFlags = emergencyFlags
        self.recording = recording
    }
}

// MARK: - Descriptive recording summaries
extension SCAT6TriageResult {
    public var hasCompatibleBaseline: Bool { biomarkers.contains { $0.baselineValue != nil } }
    public var concussionRiskLabel: String { isBaselineTest ? "BASELINE SAVED" : "RECORDING COMPLETE" }
    public var concussionBadgeText: String { isBaselineTest ? "BASELINE" : "RECORDED" }
    public var concussionHeadline: String { isBaselineTest ? "Personal reference saved" : "Your eye-movement recording" }
    public var sidelineActionGuidance: String {
        "These experimental measurements cannot diagnose or rule out concussion or clear a player to return to play. If a concussion is suspected, stop activity and seek assessment by a qualified healthcare professional."
    }
}

// MARK: - Athlete Profile
public struct AthleteProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var jerseyNumber: String
    public var sport: String
    public var school: String
    public var teamId: String?
    public var baseline: BaselineBiometrics?
    public var motorHistory: [MotorTestSession]? = nil
    public var reactionReference: MotorReference? = nil
    public var balanceReference: MotorReference? = nil
    public var triageHistory: [SCAT6TriageResult]

    public init(
        id: String,
        name: String,
        jerseyNumber: String,
        sport: String,
        school: String = "",
        teamId: String? = nil,
        baseline: BaselineBiometrics? = nil,
        triageHistory: [SCAT6TriageResult] = []
    ) {
        self.id = id
        self.name = name
        self.jerseyNumber = jerseyNumber
        self.sport = sport
        self.school = school
        self.teamId = teamId
        self.baseline = baseline
        self.triageHistory = triageHistory
    }
}

/// A locally stored coach-created team. Legacy athletes have no team and appear under Unassigned.
public struct TeamProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var sport: String

    public init(id: String = UUID().uuidString, name: String, sport: String = "") {
        self.id = id
        self.name = name
        self.sport = sport
    }
}

public struct MotorMeasurement: Codable, Equatable, Sendable {
    public let status: String
    public let reason: String?
    public let metrics: [String: Double]
    public init(status: String, reason: String? = nil, metrics: [String: Double] = [:]) {
        self.status = status; self.reason = reason; self.metrics = metrics
    }
}

public struct MotorTestSession: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let eyeResultID: UUID?
    public let reaction: MotorMeasurement
    public let balance: MotorMeasurement
    public var isBaseline: Bool? = nil
    public var reactionReference: MotorReference? = nil
    public var balanceReference: MotorReference? = nil
    public init(id: UUID = UUID(), date: Date = Date(), eyeResultID: UUID? = nil, reaction: MotorMeasurement, balance: MotorMeasurement, isBaseline: Bool? = nil, reactionReference: MotorReference? = nil, balanceReference: MotorReference? = nil) {
        self.id = id; self.date = date; self.eyeResultID = eyeResultID; self.reaction = reaction; self.balance = balance
        self.isBaseline = isBaseline; self.reactionReference = reactionReference; self.balanceReference = balanceReference
    }
}

public struct MotorReference: Codable, Equatable, Sendable {
    public let recordedAt: Date
    public let measurement: MotorMeasurement
    public let protocolVersion: String
    public init(recordedAt: Date, measurement: MotorMeasurement, protocolVersion: String = "motor-1") {
        self.recordedAt = recordedAt; self.measurement = measurement; self.protocolVersion = protocolVersion
    }
}

extension MotorMeasurement {
    public var canBeReference: Bool {
        status == "measured" && !metrics.isEmpty && metrics.values.allSatisfy(\.isFinite)
    }
    public func difference(for key: String, from reference: MotorReference?) -> Double? {
        guard canBeReference, let reference, reference.protocolVersion == "motor-1",
              reference.measurement.canBeReference,
              let value = metrics[key], let baseline = reference.measurement.metrics[key] else { return nil }
        let difference = value - baseline
        return difference.isFinite ? difference : nil
    }
}

public struct MotorResult: Codable, Equatable, Sendable {
    public let reactionTimesMs: [Double]
    public let falseStarts: Int
    public let missedTrials: Int
    public let tapTimes: [Double]
    public let tappingDuration: Double
    public let repeatedPadTaps: Int
    public var medianReactionMs: Double? {
        reactionTimesMs.isEmpty ? nil : GazeMath.median(reactionTimesMs)
    }
    public var tappingHz: Double { Double(tapTimes.count) / tappingDuration }
}

public struct MotionSample: Codable, Equatable, Sendable {
    public let t: Double
    public let ax: Double, ay: Double, az: Double
    public let rx: Double, ry: Double, rz: Double
}
public struct BalanceResult: Codable, Equatable, Sendable {
    public let samples: [MotionSample]
    /// Gravity-removed acceleration magnitude; no integration into invented displacement.
    public let accelerationRMSG: Double
    public let rotationRMSRadS: Double
    public let duration: Double
    public let measuredFrameRate: Double
}


struct MotorCaptureState {
    enum Stage { case intro, reaction, cadenceSetup, cadence, balanceSetup, eyesOpen, eyesClosed, results }
    enum InterruptedTest { case reaction, balance }
    var stage: Stage = .intro
    var tonePlayed = false
    var heardTone = false

    var soundConfirmed: Bool { tonePlayed && heardTone }

    mutating func resetSound() {
        tonePlayed = false
        heardTone = false
    }

    /// Never resume a partial recording after leaving the active scene.
    mutating func interrupt() -> InterruptedTest? {
        resetSound()
        switch stage {
        case .reaction, .cadence:
            stage = .intro
            return .reaction
        case .eyesOpen, .eyesClosed:
            stage = .balanceSetup
            return .balance
        default:
            return nil
        }
    }
}

extension GazeCalibrationMap {
    public func rawPoint(for screen: CGPoint) -> CGPoint? {
        let determinant = ax * by - bx * ay
        guard determinant.isFinite, abs(determinant) > 1e-9 else { return nil }
        let u = Double(screen.x) - cx, v = Double(screen.y) - cy
        let x = (u * by - bx * v) / determinant
        let y = (ax * v - u * ay) / determinant
        guard x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: x, y: y)
    }
}



/// Descriptive summaries only: no clinical thresholds, risk score, or clearance.
public struct TestOverviewItem: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let hasUsableData: Bool
    public let explanation: String
}

public enum RecordingOverview {
    public static func canUseEyeReference(_ eye: SCAT6TriageResult) -> Bool {
        items(eye: eye, motor: nil).prefix(2).allSatisfy(\.hasUsableData)
    }

    public static func items(eye: SCAT6TriageResult, motor: MotorTestSession?) -> [TestOverviewItem] {
        let recording = eye.recording
        let quality = recording?.qualityMetadata
        let eyeQualityOK = quality.map {
            $0.canvasRmsErrorPercent.isFinite && $0.worstTargetErrorPercent.isFinite && $0.isAcceptableQuality
        } ?? false
        let fraction = recording?.validSampleFraction ?? 0
        let fps = recording?.measuredFrameRate ?? 0
        let usableEyes = eyeQualityOK && (AppConstants.Norms.minValidSampleFraction...1).contains(fraction)
            && fps.isFinite && fps >= AppConstants.Norms.minObservedFps
        let pursuitOK = usableEyes && !(recording?.pursuit.isEmpty ?? true)
            && eye.pursuitGain.isFinite && eye.pursuitGain >= 0 && eye.latencyLagMs.isFinite
        let holdOK = usableEyes && !(recording?.holdLeft.isEmpty ?? true) && !(recording?.holdRight.isEmpty ?? true)
            && (0...100).contains(eye.fixationStabilityPercent) && eye.driftVelocity.isFinite && eye.driftVelocity >= 0
        let eyeCaution: String
        if quality == nil {
            eyeCaution = "This recording has no calibration quality report. Repeat the eye tests to check measurement quality."
        } else if !eyeQualityOK {
            eyeCaution = "The calibration check did not meet this prototype's accuracy limits. The tasks finished, but the gaze estimates are not reliable enough for comparison. Recalibrate with the phone supported, your head still, and both eyes visible. See Recording quality for the check errors."
        } else if !(AppConstants.Norms.minValidSampleFraction...1).contains(fraction) {
            eyeCaution = "Too few readable eye samples were captured. Repeat with both eyes visible and the phone steady."
        } else if !fps.isFinite || fps < AppConstants.Norms.minObservedFps {
            eyeCaution = "Camera sampling was too slow for a usable estimate. Repeat the eye recording with the app kept open."
        } else {
            eyeCaution = "An eye trace or calculated measurement is missing or invalid. Repeat the eye tests; no comparison is available."
        }
        let pursuit = pursuitOK
            ? "Eye speed range was \(number(eye.pursuitGain, digits: 2))× the dot's range (1.00× means matching ranges). The eye trace \(eye.latencyLagMs < 0 ? "led" : "followed") the dot by \(number(abs(eye.latencyLagMs), digits: 1)) ms. Camera delay affects this estimate. These differences have no validated injury cutoff; small changes may be measurement variation."
                + eyeComparison(eye, unit: "ratio", name: "Speed ratio", digits: 2)
                + eyeComparison(eye, unit: "ms", name: "Timing offset", digits: 1)
            : eyeCaution
        let hold = holdOK
            ? "Estimated gaze was near the side dot for \(number(eye.fixationStabilityPercent, digits: 1))% of usable samples. Inward drift was \(number(eye.driftVelocity, digits: 2))°/s. Calibration offset can affect both values. A change alone cannot establish injury or recovery."
                + eyeComparison(eye, unit: "%", name: "Time near the dot", digits: 1)
                + eyeComparison(eye, unit: "°/s", name: "Inward drift", digits: 2)
                + eyeComparison(eye, unit: "events", name: "Quick movement count", digits: 0)
            : eyeCaution
        // Never combine a different eye recording's motor results with this one.
        let linked = motor?.eyeResultID == eye.id ? motor : nil
        return [
            TestOverviewItem(id: 1, title: "Eye tracking", hasUsableData: pursuitOK, explanation: pursuit),
            TestOverviewItem(id: 2, title: "Side gaze hold", hasUsableData: holdOK, explanation: hold),
            motorItem(linked?.reaction, reference: linked?.reactionReference, baseline: eye.isBaselineTest, reaction: true),
            motorItem(linked?.balance, reference: linked?.balanceReference, baseline: eye.isBaselineTest, reaction: false)
        ]
    }

    public static func compatibleReference(_ reference: MotorReference?, reaction: Bool) -> MotorReference? {
        let keys = reaction ? ["median_reaction_ms", "alternations_per_second"] : ["phone_acceleration_rms_m_s2", "phone_tilt_rms_deg"]
        guard let reference, reference.protocolVersion == "motor-1", reference.measurement.canBeReference,
              keys.allSatisfy({ key in reference.measurement.metrics[key].map { $0.isFinite && $0 >= 0 } ?? false }) else { return nil }
        return reference
    }

    public static func motorItem(_ measurement: MotorMeasurement?, reference: MotorReference?, baseline: Bool, reaction: Bool) -> TestOverviewItem {
        let id = reaction ? 3 : 4
        let title = reaction ? "Reaction & tapping" : "Standing phone movement"
        guard let measurement else {
            return TestOverviewItem(id: id, title: title, hasUsableData: false, explanation: "Not recorded for this session. Complete this test to include its measurements.")
        }
        let keys = reaction ? ["median_reaction_ms", "alternations_per_second"] : ["phone_acceleration_rms_m_s2", "phone_tilt_rms_deg"]
        guard measurement.canBeReference, keys.allSatisfy({ key in measurement.metrics[key].map { $0.isFinite && $0 >= 0 } ?? false }) else {
            let status = measurement.status == "measured" ? "Incomplete measurements" : measurement.status.replacingOccurrences(of: "_", with: " ").capitalized
            return TestOverviewItem(id: id, title: title, hasUsableData: false,
                explanation: "\(status). \(measurement.reason ?? "No usable result is available; repeat when the setup is ready.") No comparison is made for this test.")
        }
        let validReference = compatibleReference(reference, reaction: reaction)
        let value = measurement.metrics[keys[0]]!
        let secondary = measurement.metrics[keys[1]]!
        var text = reaction
            ? "Typical response: \(number(value, digits: 0)) ms from cue to tap. You alternated \(number(secondary, digits: 1)) times per second."
            : "Phone movement: \(number(value, digits: 3)) m/s² acceleration and \(number(secondary, digits: 2))° typical tilt. More movement can reflect grip or placement as well as the stance."
        if baseline {
            text += " This baseline attempt provides a personal reference when saved; it does not establish a healthy range."
        } else if let delta = measurement.difference(for: keys[0], from: validReference), let cadenceDelta = measurement.difference(for: keys[1], from: validReference) {
            if reaction {
                text += " " + change(delta, digits: 0, unit: "ms", subject: "Reaction", higher: "slower", lower: "faster")
                text += " " + change(cadenceDelta, digits: 1, unit: "alternations/sec", subject: "Tapping", higher: "faster", lower: "slower")
            } else {
                text += " " + change(delta, digits: 3, unit: "m/s²", subject: "Phone acceleration", higher: "higher", lower: "lower")
                text += " " + change(cadenceDelta, digits: 2, unit: "°", subject: "Phone tilt", higher: "higher", lower: "lower")
            }
        } else {
            text += " No compatible personal baseline is available for these measurements. Save a baseline before comparing changes."
        }
        return TestOverviewItem(id: id, title: title, hasUsableData: true, explanation: text)
    }

    private static func eyeComparison(_ eye: SCAT6TriageResult, unit: String, name: String, digits: Int) -> String {
        let firstMeasure = unit == "ratio" || unit == "%"
        if eye.isBaselineTest { return firstMeasure ? " This is a personal reference, not a healthy-range assessment." : "" }
        guard let metric = eye.biomarkers.first(where: { $0.unit == unit }), let baseline = metric.baselineValue,
              baseline.isFinite, metric.measuredValue.isFinite else {
            return firstMeasure ? " No compatible personal baseline is available for this test." : ""
        }
        return " " + eyeMeasurementComparison(value: metric.measuredValue, baseline: baseline, unit: unit)
    }

    /// Describes the direction of a measured change, never its clinical significance.
    public static func eyeMeasurementComparison(value: Double, baseline: Double, unit: String) -> String {
        let delta = value - baseline
        guard value.isFinite, baseline.isFinite, delta.isFinite else { return "Baseline comparison unavailable." }
        let digits = unit == "events" ? 0 : (unit == "ms" || unit == "%" ? 1 : 2)
        let amount = number(abs(delta), digits: digits)
        if amount == number(0, digits: digits) { return "No change from baseline at the displayed precision." }
        switch unit {
        case "ratio":
            let matchChange = abs(value - 1) - abs(baseline - 1)
            let meaning = number(abs(matchChange), digits: 2) == number(0, digits: 2)
                ? "Both are equally far from matching the dot's speed range."
                : (matchChange < 0 ? "The eye and dot speed ranges were closer to matching this time." : "The eye and dot speed ranges were farther from matching this time.")
            return "Tracking speed ratio changed from \(number(baseline, digits: 2)) to \(number(value, digits: 2)). \(meaning) This does not measure how smooth tracking was."
        case "ms":
            return "Your recorded eye-movement pattern occurred \(amount) ms \(delta > 0 ? "later" : "earlier") relative to the dot than in your baseline. Camera timing can also affect this difference; it is not a tap reaction time."
        case "%":
            return "Your estimated gaze stayed near the side dot for \(amount) percentage points \(delta > 0 ? "more" : "less") of the recording than in your baseline. Calibration accuracy can affect this."
        case "°/s":
            return "During the side holds, estimated drift back toward the center was \(amount)°/s \(delta > 0 ? "faster" : "slower") than in your baseline. This describes \(delta > 0 ? "more" : "less") inward drift, not an injury finding."
        case "events":
            return "The recording contained \(amount) \(delta > 0 ? "more" : "fewer") detected quick eye movements than your baseline. Ordinary eye corrections and camera noise can contribute."
        default:
            return "\(amount) \(unit) \(delta > 0 ? "higher" : "lower") than baseline."
        }
    }

    private static func change(_ delta: Double, digits: Int, unit: String, subject: String, higher: String, lower: String) -> String {
        let amount = number(abs(delta), digits: digits)
        if amount == number(0, digits: digits) { return "\(subject) matched baseline at the displayed precision." }
        return "\(subject) was \(amount) \(unit) \(delta > 0 ? higher : lower) than baseline."
    }

    private static func number(_ value: Double, digits: Int) -> String {
        String(format: "%.*f", digits, value)
    }
}

