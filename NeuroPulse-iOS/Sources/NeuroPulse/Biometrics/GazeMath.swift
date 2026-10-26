import Foundation
import CoreGraphics
import simd

/// Oculomotor signal processing for SCAT6 / VOMS-style biomarkers.
///
/// All angular quantities are degrees of visual angle relative to the exam-canvas centre,
/// derived from ARKit TrueDepth gaze rays. Nothing here substitutes a "typical" value when data
/// is missing: analyses return `nil`, and the exam is reported as invalid instead of scored.
public enum GazeMath {
    /// Face anchors are in world coordinates; measurements must follow the current camera.
    public static func cameraRelativeTransform(face: simd_float4x4, camera: simd_float4x4) -> simd_float4x4 {
        simd_inverse(camera) * face
    }


    // MARK: - Pursuit / Hold Analysis Results
    public struct PursuitAnalysis: Equatable, Sendable {
        /// Desaccaded eye velocity amplitude ÷ target velocity amplitude at the stimulus frequency.
        public let gain: Double
        /// Phase lag of eye velocity behind target velocity, in ms (negative = predictive lead).
        public let lagMs: Double
        public let usableSamples: Int
    }

    public struct FixationAnalysis: Equatable, Sendable {
        /// % of scored samples within `radiusDeg` of the median fixation point.
        public let stabilityPercent: Double
        /// Duration-weighted centripetal slow-phase drift (deg/s), ≥ 0.
        public let driftDegPerSec: Double
        /// Saccadic intrusions / nystagmus fast phases after the settle period.
        public let intrusions: Int
        public let usableSamples: Int
    }

    public struct CalibrationCandidate: Equatable, Sendable {
        public let map: GazeCalibrationMap
        public let report: ValidationReport

        public init(map: GazeCalibrationMap, report: ValidationReport) {
            self.map = map
            self.report = report
        }
    }

    /// Pick the best available map. Validation thresholds remain report diagnostics and do not
    /// prevent an experimental session from continuing with a measured calibration.
    public static func bestCalibrationCandidate(from candidates: [CalibrationCandidate]) -> CalibrationCandidate? {
        candidates.min { lhs, rhs in
            let lhsError = lhs.report.canvasRmsErrorPercent.isFinite ? lhs.report.canvasRmsErrorPercent : .infinity
            let rhsError = rhs.report.canvasRmsErrorPercent.isFinite ? rhs.report.canvasRmsErrorPercent : .infinity
            return lhsError < rhsError
        }
    }

    // MARK: - Screen Geometry
    /// Visual angle (deg) of a normalised canvas coordinate, relative to the canvas centre.
    public static func visualAngleDeg(normalized n: Double, axisLengthPoints: Double, distanceCm: Double) -> Double? {
        guard n.isFinite, axisLengthPoints.isFinite, distanceCm.isFinite, axisLengthPoints > 0, distanceCm > 0 else { return nil }
        let offsetMm = (n - 0.5) * axisLengthPoints / AppConstants.pointsPerMillimeter
        return atan2(offsetMm, distanceCm * 10.0) * 180.0 / .pi
    }

    /// Converts a normalised canvas point into horizontal / vertical visual angle (deg, +y = down).
    public static func canvasPointToDegrees(_ p: CGPoint, canvasSize: CGSize, distanceCm: Double) -> (x: Double, y: Double)? {
        guard let x = visualAngleDeg(normalized: Double(p.x), axisLengthPoints: Double(canvasSize.width), distanceCm: distanceCm),
              let y = visualAngleDeg(normalized: Double(p.y), axisLengthPoints: Double(canvasSize.height), distanceCm: distanceCm)
        else { return nil }
        return (x, y)
    }

    // MARK: - Calibration
    /// Least-squares affine fit: canvas = A · raw + c, solved independently for x and y.
    /// Returns nil if the raw gaze barely moved between dots (eyes didn't track the dots) or the system is singular.
    public static func fitCalibration(_ samples: [CalibrationSample]) -> GazeCalibrationMap? {
        guard samples.count >= 3, samples.allSatisfy({ [$0.rawX, $0.rawY, $0.screenX, $0.screenY, $0.distanceCm].allSatisfy(\.isFinite) }) else { return nil }
        let n = Double(samples.count)
        let mx = samples.map(\.rawX).reduce(0, +) / n
        let my = samples.map(\.rawY).reduce(0, +) / n

        // The gaze-plane intersection must spread by at least ~4 mm across dots, otherwise the
        // athlete was not actually looking at the dots and the map would only amplify noise.
        let spreadX = (samples.map(\.rawX).max() ?? 0) - (samples.map(\.rawX).min() ?? 0)
        let spreadY = (samples.map(\.rawY).max() ?? 0) - (samples.map(\.rawY).min() ?? 0)
        guard max(spreadX, spreadY) > 0.004 else { return nil }

        var sxx = 0.0, sxy = 0.0, syy = 0.0
        var sxu = 0.0, syu = 0.0, su = 0.0
        var sxv = 0.0, syv = 0.0, sv = 0.0
        for s in samples {
            let dx = s.rawX - mx, dy = s.rawY - my
            sxx += dx * dx; sxy += dx * dy; syy += dy * dy
            sxu += dx * s.screenX; syu += dy * s.screenX; su += s.screenX
            sxv += dx * s.screenY; syv += dy * s.screenY; sv += s.screenY
        }
        let det = sxx * syy - sxy * sxy
        let scale = (sxx + syy) * (sxx + syy)
        guard scale > 0, det / scale > 1e-6 else { return nil }

        let ax = (sxu * syy - syu * sxy) / det
        let bx = (syu * sxx - sxu * sxy) / det
        let ay = (sxv * syy - syv * sxy) / det
        let by = (syv * sxx - sxv * sxy) / det
        let cx = su / n - ax * mx - bx * my
        let cy = sv / n - ay * mx - by * my
        return GazeCalibrationMap(ax: ax, bx: bx, cx: cx, ay: ay, by: by, cy: cy)
    }

    /// RMS angular error (deg) between where the map says the athlete looked and where the dot actually was.
    public static func calibrationErrorDeg(map: GazeCalibrationMap, samples: [CalibrationSample], canvasSize: CGSize) -> Double? {
        guard !samples.isEmpty else { return nil }
        var sumSq = 0.0
        for s in samples {
            let predicted = map.apply(rawX: s.rawX, rawY: s.rawY)
            guard let p = canvasPointToDegrees(predicted, canvasSize: canvasSize, distanceCm: s.distanceCm),
                  let t = canvasPointToDegrees(CGPoint(x: s.screenX, y: s.screenY), canvasSize: canvasSize, distanceCm: s.distanceCm)
            else { return nil }
            sumSq += pow(p.x - t.x, 2) + pow(p.y - t.y, 2)
        }
        return sqrt(sumSq / Double(samples.count))
    }

    // MARK: - Robust 9-Point Calibration & MAD Outlier Rejection
    /// Computes median of an array of Doubles.
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 1 {
            return sorted[count / 2]
        } else {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        }
    }

    /// Rejects isolated outliers using Median Absolute Deviation (MAD).
    /// Filters out blinks, camera tracking drops, and momentary saccadic jumps.
    public static func filterSamplesMAD(_ samples: [CalibrationSample]) -> [CalibrationSample] {
        guard samples.count >= 4 else { return samples }
        let xs = samples.map(\.rawX)
        let ys = samples.map(\.rawY)
        guard let medX = median(xs), let medY = median(ys) else { return samples }

        let devX = xs.map { abs($0 - medX) }
        let devY = ys.map { abs($0 - medY) }
        let madX = max(median(devX) ?? 0.001, 0.001)
        let madY = max(median(devY) ?? 0.001, 0.001)

        // Threshold = 3.0 * MAD (standard statistical outlier cutoff)
        return samples.filter { s in
            abs(s.rawX - medX) <= 3.0 * madX &&
            abs(s.rawY - medY) <= 3.0 * madY &&
            s.distanceCm > 0
        }
    }

    /// Robust calibration fit: filters outliers per dot via MAD, calculates one representative
    /// median gaze measurement per dot, and fits affine correction with equal weight per dot.
    public static func fitRobustCalibration(samplesPerDot: [[CalibrationSample]]) -> GazeCalibrationMap? {
        var representativeSamples: [CalibrationSample] = []

        for dotSamples in samplesPerDot {
            let filtered = filterSamplesMAD(dotSamples)
            guard !filtered.isEmpty else { continue }
            let medRawX = median(filtered.map(\.rawX)) ?? filtered[0].rawX
            let medRawY = median(filtered.map(\.rawY)) ?? filtered[0].rawY
            let screenX = filtered[0].screenX
            let screenY = filtered[0].screenY
            let dist = median(filtered.map(\.distanceCm)) ?? filtered[0].distanceCm

            representativeSamples.append(CalibrationSample(
                rawX: medRawX,
                rawY: medRawY,
                screenX: screenX,
                screenY: screenY,
                distanceCm: dist
            ))
        }

        guard representativeSamples.count >= 3 else { return nil }
        return fitCalibration(representativeSamples)
    }

    /// Evaluates calibration accuracy against independent check targets (measured in normalized screen coordinates %)
    /// and checks post-calibration center target drift.
    public static func evaluateIndependentValidation(
        map: GazeCalibrationMap,
        checkSamplesPerDot: [[CalibrationSample]],
        repeatCenterSamples: [CalibrationSample]? = nil,
        canvasSize: CGSize = CGSize(width: 390, height: 844)
    ) -> ValidationReport {
        guard !checkSamplesPerDot.isEmpty else {
            return ValidationReport(
                canvasRmsErrorPercent: 100.0,
                worstTargetErrorPercent: 100.0,
                centerDriftPercent: 100.0,
                isAcceptable: false,
                failureReason: "No validation samples collected."
            )
        }

        var targetErrorsPercent: [Double] = []

        for dotSamples in checkSamplesPerDot {
            let filtered = filterSamplesMAD(dotSamples)
            guard !filtered.isEmpty else { continue }
            let medRawX = median(filtered.map(\.rawX)) ?? filtered[0].rawX
            let medRawY = median(filtered.map(\.rawY)) ?? filtered[0].rawY
            let target = CGPoint(x: filtered[0].screenX, y: filtered[0].screenY)

            let predicted = map.apply(rawX: medRawX, rawY: medRawY)
            let errX = predicted.x - target.x
            let errY = predicted.y - target.y
            let distPercent = sqrt(errX * errX + errY * errY) * 100.0
            targetErrorsPercent.append(distPercent)
        }

        guard !targetErrorsPercent.isEmpty else {
            return ValidationReport(
                canvasRmsErrorPercent: 100.0,
                worstTargetErrorPercent: 100.0,
                centerDriftPercent: 100.0,
                isAcceptable: false,
                failureReason: "Insufficient usable validation samples."
            )
        }

        let meanRms = sqrt(targetErrorsPercent.map { $0 * $0 }.reduce(0, +) / Double(targetErrorsPercent.count))
        let worst = targetErrorsPercent.max() ?? meanRms

        // Center drift calculation
        var driftPercent = 0.0
        if let repCenter = repeatCenterSamples, !repCenter.isEmpty {
            let filteredCenter = filterSamplesMAD(repCenter)
            if !filteredCenter.isEmpty {
                let medX = median(filteredCenter.map(\.rawX)) ?? filteredCenter[0].rawX
                let medY = median(filteredCenter.map(\.rawY)) ?? filteredCenter[0].rawY
                let predictedCenter = map.apply(rawX: medX, rawY: medY)
                let dX = predictedCenter.x - 0.50
                let dY = predictedCenter.y - 0.50
                driftPercent = sqrt(dX * dX + dY * dY) * 100.0
            }
        }

        let limitRms = AppConstants.Norms.maxValidationCanvasRmsPercent
        let limitWorst = AppConstants.Norms.maxValidationWorstTargetPercent

        var isAcceptable = true
        var failureReason: String? = nil

        if meanRms > limitRms {
            isAcceptable = false
            failureReason = "Validation error (\(String(format: "%.1f", meanRms))%) exceeds acceptable limit (8.0%)."
        } else if worst > limitWorst {
            isAcceptable = false
            failureReason = "Worst-target validation error (\(String(format: "%.1f", worst))%) exceeds limit (12.0%)."
        }

        return ValidationReport(
            canvasRmsErrorPercent: meanRms,
            worstTargetErrorPercent: worst,
            centerDriftPercent: driftPercent,
            isAcceptable: isAcceptable,
            failureReason: failureReason
        )
    }

    // MARK: - Velocity
    /// Central-difference derivative that respects gaps: nil wherever a neighbour is missing
    /// or the frames are more than 100 ms apart.
    public static func derivative(_ values: [Double?], times: [Double]) -> [Double?] {
        let n = values.count
        guard n >= 3, times.count == n else { return Array(repeating: nil, count: n) }
        var out = [Double?](repeating: nil, count: n)
        for i in 1..<(n - 1) {
            guard let a = values[i - 1], let middle = values[i], let b = values[i + 1], a.isFinite, middle.isFinite, b.isFinite, times[i - 1].isFinite, times[i].isFinite, times[i + 1].isFinite else { continue }
            let leftInterval = times[i] - times[i - 1]
            let rightInterval = times[i + 1] - times[i]
            let dt = leftInterval + rightInterval
            guard leftInterval > 0, rightInterval > 0,
                  leftInterval < 0.1, rightInterval < 0.1,
                  dt > 0.001, dt < 0.1 else { continue }
            out[i] = (b - a) / dt
        }
        return out
    }

    // MARK: - Saccade ("Twitch") Detection
    /// Velocity-threshold (I-VT) detector with hysteresis. A candidate must exceed the onset speed,
    /// is extended while above the offset speed, and is kept only if the eye actually jumped by
    /// `minAmplitude` (median of 2 frames before vs 2 frames after) — this rejects single-frame noise spikes.
    public static func detectSaccades(
        in trace: [TraceSample],
        onsetVelocity: Double = AppConstants.Norms.saccadeOnsetVelocityDegPerSec,
        offsetVelocity: Double = AppConstants.Norms.saccadeOffsetVelocityDegPerSec,
        minAmplitude: Double = AppConstants.Norms.saccadeMinAmplitudeDeg
    ) -> [SaccadeEvent] {
        let n = trace.count
        guard n >= 5 else { return [] }
        let times = trace.map(\.t)
        let vx = derivative(trace.map(\.eyeXDeg), times: times)
        let vy = derivative(trace.map(\.eyeYDeg), times: times)
        let speed: [Double?] = (0..<n).map { i in
            guard let x = vx[i], let y = vy[i] else { return nil }
            return hypot(x, y)
        }

        func meanPosition(_ indices: [Int]) -> (Double, Double)? {
            let pts = indices.compactMap { i -> (Double, Double)? in
                guard i >= 0, i < n, let x = trace[i].eyeXDeg, let y = trace[i].eyeYDeg else { return nil }
                return (x, y)
            }
            guard !pts.isEmpty else { return nil }
            return (pts.map(\.0).reduce(0, +) / Double(pts.count), pts.map(\.1).reduce(0, +) / Double(pts.count))
        }

        var events: [SaccadeEvent] = []
        var i = 0
        while i < n {
            guard let s = speed[i], s >= onsetVelocity else { i += 1; continue }
            var start = i
            while start > 0, let p = speed[start - 1], p >= offsetVelocity { start -= 1 }
            var end = i
            var peak = s
            while end + 1 < n, let q = speed[end + 1], q >= offsetVelocity {
                end += 1
                peak = max(peak, q)
            }
            if let before = meanPosition([start - 2, start - 1]),
               let after = meanPosition([end + 1, end + 2]) {
                let amplitude = hypot(after.0 - before.0, after.1 - before.1)
                if amplitude >= minAmplitude {
                    let t0 = times[max(start - 1, 0)]
                    let t1 = times[min(end + 1, n - 1)]
                    if let last = events.last, t0 - last.endTime < 0.03 {
                        events[events.count - 1] = SaccadeEvent(
                            startTime: last.startTime, endTime: t1,
                            amplitudeDeg: max(last.amplitudeDeg, amplitude),
                            peakVelocityDegPerSec: max(last.peakVelocityDegPerSec, peak)
                        )
                    } else {
                        events.append(SaccadeEvent(startTime: t0, endTime: t1, amplitudeDeg: amplitude, peakVelocityDegPerSec: peak))
                    }
                }
            }
            i = end + 1
        }
        return events
    }

    // MARK: - Smooth Pursuit Gain & Lag
    /// Fits eye and target horizontal velocity to `a·cos(ωt) + b·sin(ωt) + c` over desaccaded samples.
    /// Gain = eye amplitude / target amplitude; lag = phase difference / ω.
    public static func analyzePursuit(_ trace: [TraceSample], saccades: [SaccadeEvent], frequencyHz: Double) -> PursuitAnalysis? {
        guard trace.count >= 10, frequencyHz > 0 else { return nil }
        let times = trace.map(\.t)
        let vEye = derivative(trace.map(\.eyeXDeg), times: times)
        let vTarget = derivative(trace.map { Optional($0.targetXDeg) }, times: times)
        let guardBand = 0.035

        var rows: [(t: Double, e: Double, g: Double)] = []
        for i in 0..<trace.count {
            guard let e = vEye[i], let g = vTarget[i] else { continue }
            let t = times[i]
            if saccades.contains(where: { t >= $0.startTime - guardBand && t <= $0.endTime + guardBand }) { continue }
            rows.append((t, e, g))
        }
        guard let first = rows.first?.t, let last = rows.last?.t else { return nil }
        // Need at least 1.0 stimulus cycles and ≥ 33 % of frames usable.
        guard last - first >= 1.0 / frequencyHz, rows.count >= max(35, trace.count / 3) else { return nil }

        let w = 2 * Double.pi * frequencyHz
        guard let eyeFit = fitSinusoid(rows.map { ($0.t, $0.e) }, omega: w),
              let tgtFit = fitSinusoid(rows.map { ($0.t, $0.g) }, omega: w)
        else { return nil }

        let eyeAmp = hypot(eyeFit.a, eyeFit.b)
        let tgtAmp = hypot(tgtFit.a, tgtFit.b)
        guard tgtAmp > 1e-6 else { return nil }

        var dPhi = atan2(eyeFit.b, eyeFit.a) - atan2(tgtFit.b, tgtFit.a)
        while dPhi > .pi { dPhi -= 2 * .pi }
        while dPhi <= -.pi { dPhi += 2 * .pi }

        return PursuitAnalysis(gain: eyeAmp / tgtAmp, lagMs: dPhi / w * 1000.0, usableSamples: rows.count)
    }

    // MARK: - Eccentric Fixation (Gaze-Evoked Nystagmus) Analysis
    public static func analyzeFixation(
        _ trace: [TraceSample],
        saccades: [SaccadeEvent],
        settleTime: Double = AppConstants.Timing.lateralHoldSettleSeconds,
        radiusDeg: Double = AppConstants.Norms.fixationRadiusDeg
    ) -> FixationAnalysis? {
        let scored = trace.filter { $0.t >= settleTime && $0.eyeXDeg?.isFinite == true && $0.eyeYDeg?.isFinite == true && $0.targetXDeg.isFinite && $0.targetYDeg.isFinite }
        guard scored.count >= 60 else { return nil }

        let inside = scored.filter { hypot($0.eyeXDeg! - $0.targetXDeg, $0.eyeYDeg! - $0.targetYDeg) <= radiusDeg }.count
        let stability = Double(inside) / Double(scored.count) * 100.0

        // Slow-phase drift: regress position on time within saccade-free, gap-free segments.
        let side: Double = (median(trace.map(\.targetXDeg)) ?? 0) >= 0 ? 1.0 : -1.0
        let guardBand = 0.035
        var segments: [[(Double, Double)]] = []
        var current: [(Double, Double)] = []
        var lastT: Double?
        for s in trace where s.t >= settleTime {
            let inSaccade = saccades.contains { s.t >= $0.startTime - guardBand && s.t <= $0.endTime + guardBand }
            let gap = lastT.map { s.t - $0 > 0.1 } ?? false
            if inSaccade || s.eyeXDeg == nil || gap {
                if !current.isEmpty { segments.append(current); current = [] }
            }
            if !inSaccade, let x = s.eyeXDeg { current.append((s.t, x)) }
            lastT = s.t
        }
        if !current.isEmpty { segments.append(current) }

        var weighted = 0.0, totalDuration = 0.0
        for seg in segments where seg.count >= 9 {
            let duration = seg.last!.0 - seg.first!.0
            guard duration >= 0.15, let slope = linearSlope(seg) else { continue }
            weighted += (-slope * side) * duration   // positive = drifting back toward midline
            totalDuration += duration
        }
        guard totalDuration >= 0.5 else { return nil }

        let intrusions = saccades.filter { $0.startTime >= settleTime }.count
        return FixationAnalysis(
            stabilityPercent: stability,
            driftDegPerSec: max(0, weighted / totalDuration),
            intrusions: intrusions,
            usableSamples: scored.count
        )
    }

    // MARK: - Dynamic Reliable Change Index (RCI)
    /// |RCI| > 1.96 corresponds to p < 0.05.
    public static func computeRCI(
        baseline: Double,
        postInjury: Double,
        standardError: Double = AppConstants.Norms.defaultSEDiff
    ) -> Double {
        guard standardError > 0.0001 else { return 0.0 }
        return (postInjury - baseline) / standardError
    }

    // MARK: - Descriptive Eye Measurements
    public static func evaluateTriage(
        athleteId: String, athleteName: String, pursuitGain: Double, latencyLagMs: Double,
        fixationStabilityPercent: Double, driftVelocity: Double, correctiveTwitches: Int,
        baseline: BaselineBiometrics? = nil, isBaselineMode: Bool = false,
        recording: ExamRecording? = nil
    ) -> SCAT6TriageResult {
        let currentProtocol = recording?.qualityMetadata?.protocolVersion ?? AppConstants.CalibrationGrid.protocolVersion
        let baseline = baseline.flatMap { $0.protocolVersion == currentProtocol ? $0 : nil }
        let rows: [(String, Double, String, Double?)] = [
            ("Pursuit gain", pursuitGain, "ratio", baseline?.pursuitGain),
            ("Pursuit phase lag", latencyLagMs, "ms", baseline?.latencyLagMs),
            ("Time near hold target", fixationStabilityPercent, "%", baseline?.fixationStabilityPercent),
            ("Inward drift estimate", driftVelocity, "°/s", baseline?.driftVelocity),
            ("Rapid movement candidates", Double(correctiveTwitches), "events", baseline.map { Double($0.twitchesCount) })
        ]
        let cards = rows.map { title, value, unit, base in
            BiomarkerCardData(title: title, measuredValue: value, unit: unit,
                normativeTarget: "No validated clinical cutoff", baselineValue: base,
                deltaPercent: nil, status: .recorded,
                interpretation: "Experimental estimate. Compare recordings under the same conditions.")
        }
        return SCAT6TriageResult(athleteId: athleteId, athleteName: athleteName,
            overallStatus: .recorded, isBaselineTest: isBaselineMode, pursuitGain: pursuitGain,
            latencyLagMs: latencyLagMs, fixationStabilityPercent: fixationStabilityPercent,
            driftVelocity: driftVelocity, correctiveTwitches: correctiveTwitches,
            biomarkers: cards, recommendations: [
                "These measurements cannot diagnose or rule out concussion or clear an athlete to play.",
                "If a concussion is suspected, stop sports participation and seek assessment by a qualified healthcare professional."
            ], recording: recording)
    }

    /// Angular estimates from the measured gaze-plane geometry. No assumed screen PPI.
    public static func gazeAngles(raw: CGPoint, map: GazeCalibrationMap, distanceCm: Double) -> CGPoint? {
        guard distanceCm.isFinite, distanceCm > 0, raw.x.isFinite, raw.y.isFinite,
              let center = map.rawPoint(for: CGPoint(x: 0.5, y: 0.5)) else { return nil }
        return CGPoint(x: atan2(Double(raw.x - center.x), distanceCm / 100) * 180 / .pi,
                       y: atan2(Double(raw.y - center.y), distanceCm / 100) * 180 / .pi)
    }

    public static func quality(_ trace: [TraceSample], duration: Double) -> (fraction: Double, fps: Double)? {
        guard trace.count >= 2, duration > 0, let first = trace.first, let last = trace.last,
              first.t >= 0, last.t - first.t >= duration * 0.9 else { return nil }
        let gaps = zip(trace, trace.dropFirst()).map { $1.t - $0.t }
        guard gaps.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 0.25 }) else { return nil }
        let fps = Double(trace.count - 1) / (last.t - first.t)
        let fraction = Double(trace.filter { $0.eyeXDeg?.isFinite == true && $0.eyeYDeg?.isFinite == true }.count) / Double(trace.count)
        guard fps >= 20, fraction >= 0.75 else { return nil }
        return (fraction, fps)
    }

    // MARK: - Private Helpers
    private static func linearSlope(_ pts: [(Double, Double)]) -> Double? {
        let n = Double(pts.count)
        let mt = pts.map(\.0).reduce(0, +) / n
        let mx = pts.map(\.1).reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (t, x) in pts {
            num += (t - mt) * (x - mx)
            den += (t - mt) * (t - mt)
        }
        return den > 1e-9 ? num / den : nil
    }

    /// Least squares for y ≈ a·cos(ωt) + b·sin(ωt) + c.
    private static func fitSinusoid(_ pts: [(Double, Double)], omega: Double) -> (a: Double, b: Double, c: Double)? {
        var m = [[Double]](repeating: [0, 0, 0], count: 3)
        var r = [0.0, 0.0, 0.0]
        for (t, y) in pts {
            let v = [cos(omega * t), sin(omega * t), 1.0]
            for i in 0..<3 {
                r[i] += v[i] * y
                for j in 0..<3 { m[i][j] += v[i] * v[j] }
            }
        }
        guard let s = solve3x3(m, r) else { return nil }
        return (s[0], s[1], s[2])
    }

    private static func solve3x3(_ m: [[Double]], _ r: [Double]) -> [Double]? {
        func det(_ a: [[Double]]) -> Double {
            a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
                - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
                + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        }
        let d = det(m)
        guard abs(d) > 1e-12 else { return nil }
        return (0..<3).map { col in
            var mc = m
            for row in 0..<3 { mc[row][col] = r[row] }
            return det(mc) / d
        }
    }
}
