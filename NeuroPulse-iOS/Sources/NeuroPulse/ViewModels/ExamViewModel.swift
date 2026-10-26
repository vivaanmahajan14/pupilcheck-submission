import Foundation
import CoreGraphics
import Combine

/// State machine driving the experimental eye-movement recording.
/// Complete pipeline:
/// 1. Position Phone (reticle centering & reference head pose lock)
/// 2. One guided setup with fit targets, held-out checks and a center drift check
/// 4. 3-2-1 Countdown
/// 5. Follow Moving Dot (10s smooth pursuit with display-linked timing)
/// 6. Look at Stationary Dot (5s Right & 5s Left lateral eccentric hold)
/// 7. Saccadic twitch detection & plain-language quality synthesis
public final class ExamViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published public var currentPhase: TestPhase = .idle
    @Published public var stimulusTarget: CGPoint = CGPoint(x: 0.5, y: 0.5)

    /// Fit and independent check targets share a single guided sequence.
    @Published public var calibrationPoints: [CalibrationPoint] = AppConstants.CalibrationGrid.guidedPoints
    @Published public var activeCalibrationIndex: Int = 0

    @Published public var calibrationHoldProgress: Double = 0.0
    @Published public var calibrationHint: String = "Look at the bright dot. Small movements are okay; it moves on when ready."
    @Published public var isGazeLockedOnTarget: Bool = false
    @Published public var isHeadMovementDetected: Bool = false
    @Published public private(set) var cameraPrompt: String?
    @Published public private(set) var recordingHint: String?
    @Published public private(set) var isRecoveringTracking = false
    @Published public private(set) var awaitingTaskStart = false
    @Published public var countdownRemaining: Int = 3
    @Published public var examProgressPercent: Double = 0.0
    @Published public var triageResult: SCAT6TriageResult?
    @Published public var isBaselineMode: Bool = false
    @Published public var selectedAthlete: AthleteProfile
    @Published public var canvasSize: CGSize = CGSize(width: 380, height: 480)

    // MARK: - Head Pose Reference & Tracking Stability
    public private(set) var referenceHeadPose: HeadPoseReference? = nil
    private var baselineCenterYaw: Double? = nil
    private var baselineCenterPitch: Double? = nil
    private var lastFrameTimestamp: TimeInterval? = nil

    // MARK: - Calibration & Validation Sample Buffers
    private var currentDotSamples: [CalibrationSample] = []
    private var calibrationSamplesPerDot: [[CalibrationSample]] = []
    private var dotUsableDuration: TimeInterval = 0
    private var dotInterruptionStartedAt: TimeInterval?
    public private(set) var bestValidationReport: ValidationReport? = nil

    // MARK: - Quality Metadata Buffers
    private var excludedSamplesCount: Int = 0
    private var excludedReasons: Set<String> = []

    // MARK: - Dependencies
    public let tracker: any GazeTrackerProtocol
    public let haptics: HapticFeedbackManager
    public let baselineManager: BaselineManager

    // MARK: - Trace Buffers
    private var pursuitTrace: [TraceSample] = []
    private var holdRightTrace: [TraceSample] = []
    private var holdLeftTrace: [TraceSample] = []

    private var timer: Timer?
    private var phaseStartTime: TimeInterval = 0
    private let clock: () -> TimeInterval
    private let schedulesTimer: Bool
    private var dotFrameTimestamp: TimeInterval?
    private var alignmentFrameTimestamp: TimeInterval?
    private var recordingFrameTimestamp: TimeInterval?
    private var trackingLossStartedAt: TimeInterval?
    private var recoveryStableSince: TimeInterval?
    private var phaseRetryCount = 0
    private var pendingCameraPrompt: String?
    private var cameraPromptChangedAt: TimeInterval = 0

    // MARK: - Init
    public init(
        athlete: AthleteProfile,
        isBaselineMode: Bool = false,
        tracker: (any GazeTrackerProtocol)? = nil,
        haptics: HapticFeedbackManager = .shared,
        baselineManager: BaselineManager = .shared,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedulesTimer: Bool = true
    ) {
        self.clock = clock
        self.schedulesTimer = schedulesTimer
        self.selectedAthlete = athlete
        self.isBaselineMode = isBaselineMode
        self.tracker = tracker ?? ARFaceGazeTracker()
        self.haptics = haptics
        self.baselineManager = baselineManager
    }

    // MARK: - Start / Cancel Examination
    public func startExam() {
        resetExamState()
        tracker.startTracking()
        if let error = tracker.trackingError {
            tracker.stopTracking()
            currentPhase = .invalid(reason: error)
            return
        }
        currentPhase = .alignmentAndDistanceCheck
        startLoop()
    }

    /// A new phone/head position requires new calibration; never reuse old traces.
    public func restartEyeCalibration() {
        guard isRecoveringTracking || awaitingTaskStart else { return }
        cancelExam()
        startExam()
    }

    /// Numeric diagnostics only; no camera images are retained.
    public var calibrationCheckDiagnostics: [String] {
        guard let map = tracker.calibrationMap else { return [] }
        return Array(calibrationSamplesPerDot.dropFirst(AppConstants.CalibrationGrid.fittingPointCount)).enumerated().compactMap { index, samples in
            let filtered = GazeMath.filterSamplesMAD(samples)
            guard let first = filtered.first,
                  let x = GazeMath.median(filtered.map(\.rawX)),
                  let y = GazeMath.median(filtered.map(\.rawY)) else { return nil }
            let estimate = map.apply(rawX: x, rawY: y)
            return String(format: "Check %d: target (%.0f, %.0f), estimate (%.0f, %.0f)",
                index + 1, first.screenX * 100, first.screenY * 100, Double(estimate.x) * 100, Double(estimate.y) * 100)
        }
    }

    public func beginPreparedTask() {
        guard awaitingTaskStart else { return }
        awaitingTaskStart = false
        phaseStartTime = clock()
        lastFrameTimestamp = nil
        recordingFrameTimestamp = nil
    }

    public func cancelExam() {
        timer?.invalidate()
        timer = nil
        tracker.stopTracking()
        currentPhase = .idle
    }

    private func resetExamState() {
        awaitingTaskStart = false
        pursuitTrace.removeAll()
        holdRightTrace.removeAll()
        holdLeftTrace.removeAll()
        triageResult = nil
        cameraPrompt = nil
        pendingCameraPrompt = nil
        cameraPromptChangedAt = clock()
        activeCalibrationIndex = 0
        calibrationHoldProgress = 0.0
        isGazeLockedOnTarget = false
        isHeadMovementDetected = false
        referenceHeadPose = nil
        baselineCenterYaw = nil
        baselineCenterPitch = nil
        lastFrameTimestamp = nil
        dotFrameTimestamp = nil
        alignmentFrameTimestamp = nil
        resetRecordingCapture()
        currentDotSamples.removeAll()
        calibrationSamplesPerDot.removeAll()
        dotUsableDuration = 0
        dotInterruptionStartedAt = nil
        bestValidationReport = nil
        excludedSamplesCount = 0
        excludedReasons.removeAll()
        countdownRemaining = 3
        examProgressPercent = 0.0

        for i in 0..<calibrationPoints.count {
            calibrationPoints[i].isCompleted = false
        }
        tracker.resetCalibration()
    }

    // MARK: - Main Execution Loop (60 FPS Clock)
    private func startLoop() {
        phaseStartTime = clock()
        timer?.invalidate()
        guard schedulesTimer else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    public func tick() {
        if let error = tracker.trackingError {
            tracker.stopTracking()
            timer?.invalidate()
            currentPhase = .invalid(reason: error)
            return
        }
        guard !awaitingTaskStart else { return }
        let now = clock()
        let elapsed = now - phaseStartTime
        let dist = tracker.faceDistanceCm
        let metrics = tracker.currentMetrics
        let frameAge = now - metrics.timestamp
        let frameFresh = frameAge >= 0 && frameAge <= AppConstants.Norms.maxCameraGapSeconds

        // Measure gaps between camera frames, not between UI timer ticks.
        if frameFresh, lastFrameTimestamp == nil || metrics.timestamp > lastFrameTimestamp! {
            if let last = lastFrameTimestamp,
               metrics.timestamp - last > AppConstants.Norms.maxCameraGapSeconds {
                excludedSamplesCount += 1
                excludedReasons.insert("Camera frame drop exceeded 250ms")
            }
            lastFrameTimestamp = metrics.timestamp
        }

        // Check head stability relative to established reference pose
        if let ref = referenceHeadPose, tracker.currentMetrics.isUsable {
            let isCalibrating: Bool
            if case .calibration = currentPhase { isCalibrating = true } else { isCalibrating = false }
            let isStable = ref.isStable(metrics: tracker.currentMetrics,
                maxRotDeg: isCalibrating ? AppConstants.CalibrationGrid.maxSetupRotationShiftDeg : AppConstants.Norms.maxHeadRotationShiftDeg,
                maxDistCm: isCalibrating ? AppConstants.CalibrationGrid.maxSetupDistanceShiftCm : AppConstants.Norms.maxHeadDistanceShiftCm)
            self.isHeadMovementDetected = !isStable
        } else {
            self.isHeadMovementDetected = false
        }

        updateCameraPrompt(now: now, frameFresh: frameFresh)

        switch currentPhase {
        case .idle:
            break

        // MARK: - Stage 1: Position your phone
        case .alignmentAndDistanceCheck:
            if tracker.isFaceDetected && tracker.isDistanceOptimal && metrics.isUsable && frameFresh {
                guard alignmentFrameTimestamp != metrics.timestamp else { return }
                let dt = alignmentFrameTimestamp.map { metrics.timestamp - $0 } ?? 0
                alignmentFrameTimestamp = metrics.timestamp
                if dt < 0 || dt > AppConstants.Norms.maxCameraGapSeconds {
                    calibrationHoldProgress = 0
                } else {
                    calibrationHoldProgress += dt / AppConstants.Timing.alignmentHoldSeconds
                }
                if calibrationHoldProgress >= 1.0 {
                    referenceHeadPose = HeadPoseReference(
                        distanceCm: dist,
                        headYawDeg: tracker.currentMetrics.headYawDeg,
                        headPitchDeg: tracker.currentMetrics.headPitchDeg,
                        headRollDeg: tracker.currentMetrics.headRollDeg
                    )
                    baselineCenterYaw = tracker.currentMetrics.eyeYawDeg
                    baselineCenterPitch = tracker.currentMetrics.eyePitchDeg
                    haptics.calibrationLockSuccess()
                    calibrationHoldProgress = 0.0
                    transitionToCalibration(pointIndex: 0)
                }
            } else {
                calibrationHoldProgress = 0
                alignmentFrameTimestamp = nil
            }

        // MARK: - One guided calibration and check sequence
        case .calibration(let index):
            guard index < calibrationPoints.count else { return }
            let target = calibrationPoints[index].screenPosition
            stimulusTarget = target
            let trackingGood = tracker.isFaceDetected && tracker.isDistanceOptimal
                && !isHeadMovementDetected && metrics.isUsable && frameFresh
            updateCalibrationHint(frameFresh: frameFresh)
            isGazeLockedOnTarget = trackingGood

            if !trackingGood {
                if dotInterruptionStartedAt == nil { dotInterruptionStartedAt = now }
                if now - dotInterruptionStartedAt! >= AppConstants.CalibrationGrid.briefInterruptionSeconds {
                    currentDotSamples.removeAll()
                    dotUsableDuration = 0
                    calibrationHoldProgress = 0
                }
                return
            }
            guard dotFrameTimestamp == nil || metrics.timestamp > dotFrameTimestamp! else { return }
            if let interruption = dotInterruptionStartedAt,
               now - interruption >= AppConstants.CalibrationGrid.briefInterruptionSeconds {
                currentDotSamples.removeAll()
                dotUsableDuration = 0
                calibrationHoldProgress = 0
            }
            let dt = dotFrameTimestamp.map { metrics.timestamp - $0 } ?? 0
            if dt > AppConstants.CalibrationGrid.briefInterruptionSeconds {
                currentDotSamples.removeAll()
                dotUsableDuration = 0
                calibrationHoldProgress = 0
            }
            // A blink pauses collection; it never counts as usable dwell time.
            if dotInterruptionStartedAt == nil, dt >= 0, dt <= AppConstants.Norms.maxCameraGapSeconds {
                dotUsableDuration += dt
            }
            dotInterruptionStartedAt = nil
            dotFrameTimestamp = metrics.timestamp
            let totalTargetTime = AppConstants.Timing.calibrationSettleSeconds + AppConstants.Timing.calibrationDwellSeconds
            if dotUsableDuration >= AppConstants.Timing.calibrationSettleSeconds {
                currentDotSamples.append(CalibrationSample(rawX: metrics.rawGazeX, rawY: metrics.rawGazeY,
                    screenX: Double(target.x), screenY: Double(target.y), distanceCm: dist))
            }
            calibrationHoldProgress = min(0.99, dotUsableDuration / totalTargetTime,
                Double(currentDotSamples.count) / Double(AppConstants.Timing.calibrationMinUsableFramesPerDot))
            if dotUsableDuration >= totalTargetTime,
               currentDotSamples.count >= AppConstants.Timing.calibrationMinUsableFramesPerDot {
                haptics.calibrationLockSuccess()
                calibrationPoints[index].isCompleted = true
                calibrationSamplesPerDot.append(currentDotSamples)
                if index + 1 < calibrationPoints.count {
                    transitionToCalibration(pointIndex: index + 1)
                } else {
                    finalizeCalibrationAndProceed()
                }
            }

        // MARK: - Countdown Stage
        case .countdown(let rem):
            let countdownElapsed = elapsed
            let currentSec = 3 - Int(countdownElapsed)
            if currentSec != rem && currentSec > 0 {
                countdownRemaining = currentSec
                currentPhase = .countdown(remaining: currentSec)
                haptics.countdownTick()
            } else if countdownElapsed >= 3.0 {
                haptics.examStart()
                transitionToSmoothPursuit()
            }

        // MARK: - Stage 4: Follow the moving dot (Smooth Pursuit)
        case .smoothPursuit:
            let pursuitElapsed = elapsed
            let totalExamTime = AppConstants.Timing.totalTestSeconds
            if !isRecoveringTracking { examProgressPercent = min((pursuitElapsed / totalExamTime) * 100.0, 100.0) }

            // Sinusoidal horizontal stimulus trajectory
            let stimX = 0.5 + AppConstants.Timing.smoothPursuitAmplitude * sin(2.0 * .pi * AppConstants.Timing.smoothPursuitFrequencyHz * pursuitElapsed)
            let stimY = 0.5
            stimulusTarget = isRecoveringTracking ? CGPoint(x: 0.5, y: 0.5) : CGPoint(x: stimX, y: stimY)

            guard let sample = captureRecordingSample(now: now, frameFresh: frameFresh, targetX: { time in
                0.5 + AppConstants.Timing.smoothPursuitAmplitude * sin(2 * .pi * AppConstants.Timing.smoothPursuitFrequencyHz * time)
            }) else { return }
            pursuitTrace.append(sample)

            if sample.t >= AppConstants.Timing.smoothPursuitDurationSeconds {
                if retryIfNeeded(trace: pursuitTrace) { return }
                transitionToLateralHold(side: .right)
            }

        // MARK: - Stage 5: Look at the stationary dot (Lateral Hold)
        case .lateralHold(let side, _):
            let holdElapsed = elapsed
            let baseTime = AppConstants.Timing.smoothPursuitDurationSeconds + (side == .right ? 0.0 : AppConstants.Timing.lateralHoldDurationSeconds)
            if !isRecoveringTracking { examProgressPercent = min(((baseTime + holdElapsed) / AppConstants.Timing.totalTestSeconds) * 100, 100) }
            let targetX = side == .right ? AppConstants.Timing.lateralHoldRightX : AppConstants.Timing.lateralHoldLeftX
            stimulusTarget = CGPoint(x: targetX, y: 0.5)
            guard let sample = captureRecordingSample(now: now, frameFresh: frameFresh, targetX: { _ in targetX }) else { return }
            if side == .right { holdRightTrace.append(sample) }
            else { holdLeftTrace.append(sample) }

            if sample.t >= AppConstants.Timing.lateralHoldDurationSeconds {
                if retryIfNeeded(trace: side == .right ? holdRightTrace : holdLeftTrace) { return }
                if side == .right { transitionToLateralHold(side: .left) }
                else { finishExam() }
            }

        case .completed, .invalid:
            break
        }
    }

    // MARK: - Recording frame capture and recovery
    private func resetRecordingCapture() {
        recordingFrameTimestamp = nil
        trackingLossStartedAt = nil
        recoveryStableSince = nil
        recordingHint = nil
        isRecoveringTracking = false
        phaseRetryCount = 0
    }

    private func recordingProblem(frameFresh: Bool) -> (reason: String, hint: String)? {
        let metrics = tracker.currentMetrics
        if !frameFresh { return ("No fresh camera frames", "Waiting for new camera frames. Keep the app open.") }
        if !tracker.isFaceDetected { return ("Face tracking lost", "Bring your whole face back into the preview.") }
        if metrics.isBlinking { return ("Eyes closed or unreadable", "Blink normally, then look at the bright target in even lighting.") }
        if !metrics.isUsable { return ("Eye estimate unavailable", "Face the camera in even lighting so both eyes are readable.") }
        if let ref = referenceHeadPose, !ref.isStable(metrics: metrics) {
            if abs(metrics.faceDistanceCm - ref.distanceCm) > AppConstants.Norms.maxHeadDistanceShiftCm {
                return ("Phone distance changed", "Phone distance: \(String(format: "%.0f", metrics.faceDistanceCm)) cm. Return to about \(String(format: "%.0f", ref.distanceCm)) cm, then hold steady.")
            }
            return ("Head angle changed", "Return to your starting head and phone angle. Move only your eyes.")
        }
        return nil
    }

    private func beginRecordingRecovery(hint: String) {
        isRecoveringTracking = true
        recoveryStableSince = nil
        recordingHint = hint + " Only this task will restart when tracking is steady."
        if case .smoothPursuit = currentPhase { stimulusTarget = CGPoint(x: 0.5, y: 0.5) }
    }

    private func restartCurrentRecordingTask(now: TimeInterval) {
        switch currentPhase {
        case .smoothPursuit:
            pursuitTrace.removeAll()
            currentPhase = .smoothPursuit(elapsed: 0)
        case .lateralHold(let side, _):
            if side == .right { holdRightTrace.removeAll() } else { holdLeftTrace.removeAll() }
            currentPhase = .lateralHold(side: side, elapsed: 0)
        default: return
        }
        phaseStartTime = now
        recordingFrameTimestamp = nil
        trackingLossStartedAt = nil
        recoveryStableSince = nil
        recordingHint = nil
        isRecoveringTracking = false
        phaseRetryCount += 1
    }

    private func captureRecordingSample(now: TimeInterval, frameFresh: Bool, targetX: (Double) -> Double) -> TraceSample? {
        let metrics = tracker.currentMetrics
        let problem = recordingProblem(frameFresh: frameFresh)
        if let problem {
            recordingHint = problem.hint
            recoveryStableSince = nil
            if trackingLossStartedAt == nil { trackingLossStartedAt = now }
            if isRecoveringTracking || now - (trackingLossStartedAt ?? now) >= 0.5 {
                beginRecordingRecovery(hint: problem.hint)
                return nil
            }
        } else {
            trackingLossStartedAt = nil
            if !isRecoveringTracking { recordingHint = nil }
        }

        // A UI timer tick is not a camera sample. Frozen, duplicate and out-of-order frames cannot fill a recording.
        guard frameFresh, recordingFrameTimestamp == nil || metrics.timestamp > recordingFrameTimestamp! else { return nil }
        recordingFrameTimestamp = metrics.timestamp
        if isRecoveringTracking {
            guard problem == nil else { return nil }
            recordingHint = "Position recovered. Hold steady while this task restarts."
            if recoveryStableSince == nil { recoveryStableSince = metrics.timestamp }
            if metrics.timestamp - (recoveryStableSince ?? metrics.timestamp) >= 0.5 {
                restartCurrentRecordingTask(now: now)
            }
            return nil
        }

        let time = metrics.timestamp - phaseStartTime
        guard time >= 0 else { return nil }
        let distance = metrics.faceDistanceCm > 0 ? metrics.faceDistanceCm : (referenceHeadPose?.distanceCm ?? 0)
        guard let targetDegrees = GazeMath.visualAngleDeg(normalized: targetX(time), axisLengthPoints: Double(canvasSize.width), distanceCm: distance) else { return nil }
        var eyeX: Double?
        var eyeY: Double?
        if let problem {
            excludedSamplesCount += 1
            excludedReasons.insert(problem.reason)
        } else if let x = metrics.gazeX, let y = metrics.gazeY {
            eyeX = GazeMath.visualAngleDeg(normalized: x, axisLengthPoints: Double(canvasSize.width), distanceCm: distance)
            eyeY = GazeMath.visualAngleDeg(normalized: y, axisLengthPoints: Double(canvasSize.height), distanceCm: distance)
        } else {
            eyeX = metrics.eyeYawDeg - (baselineCenterYaw ?? 0)
            eyeY = metrics.eyePitchDeg - (baselineCenterPitch ?? 0)
        }
        return TraceSample(t: time, eyeXDeg: eyeX, eyeYDeg: eyeY, targetXDeg: targetDegrees, targetYDeg: 0)
    }

    private func recordingQuality(traces: [[TraceSample]]) -> (usableFraction: Double, frameRate: Double) {
        let samples = traces.flatMap { $0 }
        let usable = samples.filter { $0.eyeXDeg?.isFinite == true && $0.eyeYDeg?.isFinite == true }.count
        let duration = traces.reduce(0.0) { $0 + max(0, ($1.last?.t ?? 0) - ($1.first?.t ?? 0)) }
        let intervals = traces.reduce(0) { $0 + max(0, $1.count - 1) }
        return (samples.isEmpty ? 0 : Double(usable) / Double(samples.count),
                duration > 0 ? Double(intervals) / duration : 0)
    }

    /// Recover an incomplete task before advancing, rather than discard the whole session at the end.
    private func retryIfNeeded(trace: [TraceSample]) -> Bool {
        let quality = recordingQuality(traces: [trace])
        guard quality.usableFraction < AppConstants.Norms.minValidSampleFraction || quality.frameRate < AppConstants.Norms.minObservedFps else { return false }
        let hint = quality.frameRate < AppConstants.Norms.minObservedFps
            ? "The camera captured too few new frames. Keep the app open and reduce other phone activity."
            : "This task had too many tracking gaps. Keep the phone steady and both eyes visible."
        if phaseRetryCount >= 2 {
            tracker.stopTracking()
            timer?.invalidate()
            currentPhase = .invalid(reason: hint + " \(Int(quality.usableFraction * 100))% usable at \(String(format: "%.1f", quality.frameRate)) frames/sec. Camera interruptions: \(excludedReasons.sorted().joined(separator: "; ")).")
        } else {
            beginRecordingRecovery(hint: hint)
        }
        return true
    }

    // MARK: - Calibration synthesis; check targets are never used to fit the map.
    private func finalizeCalibrationAndProceed() {
        let fitCount = AppConstants.CalibrationGrid.fittingPointCount
        guard let map = GazeMath.fitRobustCalibration(samplesPerDot: Array(calibrationSamplesPerDot.prefix(fitCount))) else {
            tracker.stopTracking()
            timer?.invalidate()
            currentPhase = .invalid(reason: "Eye setup couldn't finish. Rest the phone on a support, look at each dot, and try again.")
            return
        }
        let checks = Array(calibrationSamplesPerDot.dropFirst(fitCount))
        bestValidationReport = GazeMath.evaluateIndependentValidation(map: map,
            checkSamplesPerDot: Array(checks.dropLast()), repeatCenterSamples: checks.last, canvasSize: canvasSize)
        tracker.setCalibrationMap(map, errorDeg: 0.0)
        // Start recording from the final center position, not the earlier alignment pose.
        let metrics = tracker.currentMetrics
        referenceHeadPose = HeadPoseReference(distanceCm: metrics.faceDistanceCm,
            headYawDeg: metrics.headYawDeg, headPitchDeg: metrics.headPitchDeg, headRollDeg: metrics.headRollDeg)
        baselineCenterYaw = metrics.eyeYawDeg
        baselineCenterPitch = metrics.eyePitchDeg
        transitionToCountdown()
    }

    private func updateCalibrationHint(frameFresh: Bool) {
        if !tracker.isFaceDetected {
            calibrationHint = "Bring your whole face into the camera preview."
        } else if !frameFresh {
            calibrationHint = "Waiting for fresh camera frames…"
        } else if !tracker.isDistanceOptimal {
            calibrationHint = tracker.faceDistanceCm < AppConstants.minOptimalDistanceCm
                ? "Move the phone farther away until the distance indicator shows ready."
                : "Move the phone closer until the distance indicator shows ready."
        } else if isHeadMovementDetected {
            calibrationHint = "Pause here and return to a comfortable, forward-facing position."
        } else if tracker.currentMetrics.isBlinking {
            calibrationHint = "Blink normally. Your progress waits for you."
        } else if !tracker.currentMetrics.isUsable {
            calibrationHint = "Eyes are not readable yet. Face the camera in even lighting."
        } else {
            calibrationHint = "Look at the bright dot. Small movements are okay; it moves on when ready."
        }
    }

    private func updateCameraPrompt(now: TimeInterval, frameFresh: Bool) {
        let next: String?
        switch currentPhase {
        case .idle, .completed, .invalid:
            cameraPrompt = nil
            pendingCameraPrompt = nil
            return
        default:
            if !tracker.isFaceDetected {
                next = "Center your face in the camera"
            } else if !tracker.isDistanceOptimal {
                next = tracker.faceDistanceCm < AppConstants.minOptimalDistanceCm
                    ? "Move the phone farther away" : "Bring the phone closer"
            } else if !frameFresh {
                next = "Waiting for the camera"
            } else if isHeadMovementDetected {
                next = "Face forward and steady the phone"
            } else if tracker.currentMetrics.isBlinking {
                next = "Open your eyes when ready"
            } else if !tracker.currentMetrics.isUsable {
                next = "Keep both eyes visible"
            } else if isRecoveringTracking {
                next = "Hold steady to resume"
            } else {
                next = nil
            }
        }
        if next != pendingCameraPrompt {
            pendingCameraPrompt = next
            cameraPromptChangedAt = now
        }
        // Brief blinks and distance-boundary jitter should not flash instructions.
        let delay: TimeInterval = next == nil ? 0.35 : 0.65
        if now - cameraPromptChangedAt >= delay, cameraPrompt != next { cameraPrompt = next }
    }

    // MARK: - Phase Transitions
    private func transitionToCalibration(pointIndex: Int) {
        phaseStartTime = clock()
        dotFrameTimestamp = nil
        dotUsableDuration = 0
        dotInterruptionStartedAt = nil
        activeCalibrationIndex = pointIndex
        calibrationHoldProgress = 0.0
        currentDotSamples.removeAll()
        isGazeLockedOnTarget = false
        currentPhase = .calibration(pointIndex: pointIndex)
    }

    private func transitionToCountdown() {
        awaitingTaskStart = true
        phaseStartTime = clock()
        countdownRemaining = 3
        currentPhase = .countdown(remaining: 3)
        haptics.countdownTick()
    }

    private func transitionToSmoothPursuit() {
        resetRecordingCapture()
        phaseStartTime = clock()
        currentPhase = .smoothPursuit(elapsed: 0.0)
    }

    private func transitionToLateralHold(side: HoldSide) {
        awaitingTaskStart = true
        resetRecordingCapture()
        phaseStartTime = clock()
        currentPhase = .lateralHold(side: side, elapsed: 0.0)
    }

    // MARK: - Evaluation & Saccadic Twitch Analysis
    private func finishExam() {
        timer?.invalidate()
        timer = nil
        tracker.stopTracking()
        currentPhase = .completed
        haptics.examComplete()

        // 1. Data Validity & Frame Quality Checks
        let quality = recordingQuality(traces: [pursuitTrace, holdRightTrace, holdLeftTrace])
        let validFraction = quality.usableFraction
        let measuredFps = quality.frameRate
        guard validFraction >= AppConstants.Norms.minValidSampleFraction else {
            currentPhase = .invalid(reason: "The camera could not capture enough readable eye samples (\(Int(validFraction * 100))% usable). Tracking interruptions: \(excludedReasons.sorted().joined(separator: "; ")). Keep the phone steady and both eyes visible, then retry.")
            return
        }

        guard measuredFps >= AppConstants.Norms.minObservedFps else {
            currentPhase = .invalid(reason: "Recording quality too low—try again: Frame rate dropped below required threshold (\(String(format: "%.1f", measuredFps)) FPS, minimum 20 FPS required).")
            return
        }

        // 2. Detect Saccadic Twitches in Smooth Pursuit
        let pursuitSaccades = GazeMath.detectSaccades(in: pursuitTrace)
        guard let pursuitAnalysis = GazeMath.analyzePursuit(
            pursuitTrace,
            saccades: pursuitSaccades,
            frequencyHz: AppConstants.Timing.smoothPursuitFrequencyHz
        ) else {
            currentPhase = .invalid(reason: "Recording couldn't finish: Smooth pursuit signal could not be resolved. Please maintain steady gaze on the moving target.")
            return
        }

        // 3. Detect Nystagmus Intrusions in Lateral Holds
        let holdRightSaccades = GazeMath.detectSaccades(in: holdRightTrace)
        guard let holdRightAnalysis = GazeMath.analyzeFixation(holdRightTrace, saccades: holdRightSaccades) else {
            currentPhase = .invalid(reason: "Recording couldn't finish: Right lateral fixation could not be resolved.")
            return
        }

        let holdLeftSaccades = GazeMath.detectSaccades(in: holdLeftTrace)
        guard let holdLeftAnalysis = GazeMath.analyzeFixation(holdLeftTrace, saccades: holdLeftSaccades) else {
            currentPhase = .invalid(reason: "Recording couldn't finish: Left lateral fixation could not be resolved.")
            return
        }

        // 4. Genuine Measured Metrics (Zero Default Fallbacks)
        let gain = pursuitAnalysis.gain
        let lag = pursuitAnalysis.lagMs
        let compositeStability = (holdRightAnalysis.stabilityPercent + holdLeftAnalysis.stabilityPercent) / 2.0
        let compositeDrift = (holdRightAnalysis.driftDegPerSec + holdLeftAnalysis.driftDegPerSec) / 2.0
        let totalTwitches = pursuitSaccades.count + holdRightAnalysis.intrusions + holdLeftAnalysis.intrusions

        // 5. Versioned Quality Metadata
        let qualityMeta = RecordingQualityMetadata(
            protocolVersion: AppConstants.CalibrationGrid.protocolVersion,
            canvasRmsErrorPercent: bestValidationReport?.canvasRmsErrorPercent ?? 0.0,
            worstTargetErrorPercent: bestValidationReport?.worstTargetErrorPercent ?? 0.0,
            centerDriftPercent: bestValidationReport?.centerDriftPercent ?? 0.0,
            excludedSamplesCount: excludedSamplesCount,
            excludedReasons: Array(excludedReasons),
            referenceHeadPose: referenceHeadPose
        )

        let recording = ExamRecording(
            pursuit: pursuitTrace,
            pursuitSaccades: pursuitSaccades,
            holdRight: holdRightTrace,
            holdRightSaccades: holdRightSaccades,
            holdLeft: holdLeftTrace,
            holdLeftSaccades: holdLeftSaccades,
            calibrationErrorDeg: tracker.measuredCalibrationErrorDeg,
            meanDistanceCm: tracker.faceDistanceCm,
            validSampleFraction: validFraction,
            measuredFrameRate: measuredFps,
            qualityMetadata: qualityMeta
        )

        let result = GazeMath.evaluateTriage(
            athleteId: selectedAthlete.id,
            athleteName: selectedAthlete.name,
            pursuitGain: gain,
            latencyLagMs: lag,
            fixationStabilityPercent: compositeStability,
            driftVelocity: compositeDrift,
            correctiveTwitches: totalTwitches,
            baseline: baselineManager.getBaseline(athleteId: selectedAthlete.id),
            isBaselineMode: isBaselineMode,
            recording: recording
        )

        self.triageResult = result
        baselineManager.recordTriageResult(athleteId: selectedAthlete.id, result: result)
    }
}
