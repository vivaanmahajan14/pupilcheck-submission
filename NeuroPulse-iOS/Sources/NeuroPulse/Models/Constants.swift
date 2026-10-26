import Foundation
import SwiftUI

/// App-wide constants, clinical thresholds, and design tokens for NeuroPulse.
public enum AppConstants {
    // MARK: - App Identity
    public static let appName = "NeuroPulse"
    public static let appSubtitle = "Sideline Response Guide & Experimental Movement Tests"
    public static let appVersion = "2.4.0"
    public static let districtTarget = "AR-03 (Arkansas District 3)"

    // MARK: - Distance Constancy (Front TrueDepth Camera)
    /// Close range: at 12–24 cm (sweet spot 15–16 cm) the TrueDepth sensor resolves
    /// each eye with high pixel density, so small catch-up saccades and nystagmus beats are measurable.
    public static let minOptimalDistanceCm: Double = 12.0
    public static let maxOptimalDistanceCm: Double = 24.0
    public static let targetDistanceCm: Double = 16.0

    /// Physical display density. Every Face ID iPhone since iPhone X (incl. iPhone 17)
    /// renders @3x at 458–460 ppi → ≈ 6.04 points per millimetre.
    public static let pointsPerMillimeter: Double = 460.0 / 3.0 / 25.4

    // MARK: - Clinical Normative Thresholds (SCAT6 / VOMS)
    /// All angular quantities are degrees of visual angle measured from ARKit gaze rays.
    public enum Norms {
        /// Desaccaded smooth pursuit velocity gain (eye velocity / target velocity). Normal: >= 0.85
        public static let pursuitGainNormal: Double = 0.85
        public static let pursuitGainBorderline: Double = 0.72

        /// Pursuit phase lag behind the sinusoidal target in milliseconds. Normal: <= 25 ms
        public static let latencyLagNormalMs: Double = 25.0
        public static let latencyLagBorderlineMs: Double = 45.0

        /// Percentage of eccentric-hold samples within `fixationRadiusDeg` of the fixation centre.
        public static let fixationStabilityNormal: Double = 85.0
        public static let fixationStabilityBorderline: Double = 72.0
        public static let fixationRadiusDeg: Double = 2.0

        /// Centripetal slow-phase drift velocity during eccentric hold (deg/s). Normal: <= 1.5 °/s
        public static let driftVelocityNormal: Double = 1.5
        public static let driftVelocityBorderline: Double = 3.0

        /// Saccadic twitches: catch-up saccades during pursuit + saccadic intrusions during holds.
        public static let twitchesNormalMax: Int = 3
        public static let twitchesBorderlineMax: Int = 6

        /// Velocity-threshold saccade detector (I-VT with hysteresis).
        public static let saccadeOnsetVelocityDegPerSec: Double = 40.0
        public static let saccadeOffsetVelocityDegPerSec: Double = 20.0
        public static let saccadeMinAmplitudeDeg: Double = 0.8

        /// Maximum acceptable calibration residual before the exam refuses to continue.
        public static let maxCalibrationErrorDeg: Double = 4.5

        /// Engineering limits for independent validation in normalized canvas coordinates (%)
        public static let maxValidationCanvasRmsPercent: Double = 8.0
        public static let maxValidationWorstTargetPercent: Double = 12.0

        /// Minimum fraction of frames that must contain a tracked, open-eyed face (>= 75%).
        public static let minValidSampleFraction: Double = 0.75
        /// Minimum observed frame rate required for valid signal processing.
        public static let minObservedFps: Double = 20.0

        /// Head stability thresholds relative to calibrated reference pose.
        public static let maxHeadRotationShiftDeg: Double = 5.0
        public static let maxHeadDistanceShiftCm: Double = 1.5
        public static let maxCameraGapSeconds: Double = 0.25 // 250 ms

        /// Standard error of difference for Reliable Change Index (RCI)
        public static let defaultSEDiff: Double = 0.08

        // MARK: - Personal Baseline Deviation Thresholds (SCAT6 / CRT6 Reliable Change Index & Deltas)
        /// Tracking speed drop: >= 15% drop or RCI <= -1.96 (Severe/Abnormal); >= 8% drop (Borderline)
        public static let baselineGainSevereDropPercent: Double = 15.0
        public static let baselineGainBorderlineDropPercent: Double = 8.0
        public static let baselineGainSevereRCI: Double = -1.96

        /// Timing lag increase: >= 20 ms increase or >= 35% increase (Severe); >= 10 ms increase (Borderline)
        public static let baselineLagSevereDeltaMs: Double = 20.0
        public static let baselineLagBorderlineDeltaMs: Double = 10.0

        /// Fixation stability drop: >= 10 percentage points drop (Severe); >= 5 percentage points drop (Borderline)
        public static let baselineStabilitySevereDropPoints: Double = 10.0
        public static let baselineStabilityBorderlineDropPoints: Double = 5.0

        /// Centripetal drift increase: >= 1.0 deg/s increase (Severe); >= 0.5 deg/s increase (Borderline)
        public static let baselineDriftSevereDeltaDegPerSec: Double = 1.0
        public static let baselineDriftBorderlineDeltaDegPerSec: Double = 0.5

        /// Corrective twitches increase: >= 4 twitches increase (Severe); >= 2 twitches increase (Borderline)
        public static let baselineTwitchesSevereDelta: Int = 4
        public static let baselineTwitchesBorderlineDelta: Int = 2
    }

    // MARK: - Guided calibration geometry and independent check targets
    public enum CalibrationGrid {
        public static let protocolVersion: String = "2.7.0-guided-calibration"
        public static let maxValidationCanvasRmsPercent: Double = AppConstants.Norms.maxValidationCanvasRmsPercent
        public static let maxValidationWorstTargetPercent: Double = AppConstants.Norms.maxValidationWorstTargetPercent
        public static let minValidSampleFraction: Double = AppConstants.Norms.minValidSampleFraction
        public static let minObservedFps: Double = AppConstants.Norms.minObservedFps

        /// 9 targets: Center, 4 Edges, 4 Corners
        public static let ninePoints: [CalibrationPoint] = [
            CalibrationPoint(id: 0, label: "Center", screenPosition: CGPoint(x: 0.50, y: 0.50)),
            CalibrationPoint(id: 1, label: "Left Edge", screenPosition: CGPoint(x: 0.12, y: 0.50)),
            CalibrationPoint(id: 2, label: "Right Edge", screenPosition: CGPoint(x: 0.88, y: 0.50)),
            CalibrationPoint(id: 3, label: "Top Edge", screenPosition: CGPoint(x: 0.50, y: 0.15)),
            CalibrationPoint(id: 4, label: "Bottom Edge", screenPosition: CGPoint(x: 0.50, y: 0.85)),
            CalibrationPoint(id: 5, label: "Top-Left", screenPosition: CGPoint(x: 0.15, y: 0.18)),
            CalibrationPoint(id: 6, label: "Top-Right", screenPosition: CGPoint(x: 0.85, y: 0.18)),
            CalibrationPoint(id: 7, label: "Bottom-Left", screenPosition: CGPoint(x: 0.15, y: 0.82)),
            CalibrationPoint(id: 8, label: "Bottom-Right", screenPosition: CGPoint(x: 0.85, y: 0.82))
        ]

        /// One continuous setup: five fit targets, two held-out checks, then a center drift check.
        public static let guidedPoints: [CalibrationPoint] = (
            Array(ninePoints.prefix(5)) + [validationPoints[0], validationPoints[3], validationPoints[4]]
        ).enumerated().map { index, point in
            CalibrationPoint(id: index, label: point.label, screenPosition: point.screenPosition)
        }
        public static let fittingPointCount = 5
        public static let maxSetupRotationShiftDeg: Double = 8
        public static let maxSetupDistanceShiftCm: Double = 3
        public static let briefInterruptionSeconds: Double = 0.75

        /// 5-point subset for comparative algorithm evaluation
        public static let fivePointIndices = [0, 1, 2, 3, 4]

        /// 4 Independent validation check points excluded from fitting + 1 repeat center point for drift detection
        public static let validationPoints: [CalibrationPoint] = [
            CalibrationPoint(id: 0, label: "Upper Left", screenPosition: CGPoint(x: 0.30, y: 0.35)),
            CalibrationPoint(id: 1, label: "Upper Right", screenPosition: CGPoint(x: 0.70, y: 0.35)),
            CalibrationPoint(id: 2, label: "Lower Left", screenPosition: CGPoint(x: 0.30, y: 0.65)),
            CalibrationPoint(id: 3, label: "Lower Right", screenPosition: CGPoint(x: 0.70, y: 0.65)),
            CalibrationPoint(id: 4, label: "Center (Drift Check)", screenPosition: CGPoint(x: 0.50, y: 0.50))
        ]
    }

    // MARK: - Exam Timing & Stimulus Geometry
    public enum Timing {
        public static let countdownSeconds: Int = 3
        public static let alignmentHoldSeconds: Double = 1.0

        /// Time allowed for the eyes to reach each dot before collecting samples
        public static let calibrationSettleSeconds: Double = 0.7
        /// Minimum duration of stable sample collection per dot
        public static let calibrationDwellSeconds: Double = 0.8
        /// Minimum usable camera frames required per calibration dot
        public static let calibrationMinUsableFramesPerDot: Int = 24
        public static let calibrationSamplesPerDot: Int = 35

        public static let smoothPursuitDurationSeconds: Double = 10.0
        public static let smoothPursuitFrequencyHz: Double = 0.4
        /// Half peak-to-peak horizontal excursion of the pursuit target (fraction of canvas width).
        public static let smoothPursuitAmplitude: Double = 0.42
        public static let lateralHoldDurationSeconds: Double = 5.0
        /// Eccentric hold target positions (fraction of canvas width).
        public static let lateralHoldRightX: Double = 0.92
        public static let lateralHoldLeftX: Double = 0.08
        /// Time allowed for the saccade onto the hold target before stability is scored.
        public static let lateralHoldSettleSeconds: Double = 0.5

        public static var totalTestSeconds: Double {
            smoothPursuitDurationSeconds + 2 * lateralHoldDurationSeconds
        }
    }
}

/// Clinical Dark Ops & Official Pantone Color Trio Palette
public enum NeuroPulseColor {
    // Official Pantone Trio
    public static let pantoneBlue = Color(hex: "004789") // Pantone P 105-8 C (Rich Blue)
    public static let pantoneRed = Color(hex: "D62E2F") // Pantone P 488-8 C (Vibrant Crimson Red)
    public static let pantoneYellow = Color(hex: "FCEEA8") // Pantone 938 C (Warm Yellowish Cream)
    public static let pantoneYellowCanvas = Color(hex: "FAF6E8") // Warm porcelain canvas
    public static let cardWhite = Color(hex: "FFFDF5") // Crisp warm ivory card surface
    public static let pantoneBlueDark = Color(hex: "004789")
    public static let pantoneBlueLight = Color(hex: "004789")
    public static let pantoneBlueSurface = Color(hex: "FCEEA8")

    // Semantic Status Colors
    public static let statusNormal = Color(hex: "004789") // Blue
    public static let statusBorderline = Color(hex: "004789") // Blue
    public static let statusElevated = Color(hex: "D62E2F") // Vibrant Crimson Red
    public static let statusNormalSurface = Color(hex: "FAF6E8") // Cream
    public static let statusBorderlineSurface = Color(hex: "FAF6E8") // Cream
    public static let statusElevatedSurface = Color(hex: "FAF6E8") // Cream

    // UI Dark Ops and Canvas Tokens
    public static let obsidianBase = Color(hex: "004789") // Focus field matches pantoneBlueDark
    public static let cardSlate = Color(hex: "004789") // Dark card surface matches pantoneBlue
    public static let borderSlate = Color(hex: "004789")
    public static let mutedSlate = Color(hex: "FCEEA8")
    public static let clinicalWhite = Color(hex: "FFFDF5")
    public static let trackingAccent = Color(hex: "FCEEA8") // High-contrast target matches pantoneYellow
    public static let emerald = Color(hex: "FCEEA8") // High-contrast cream distance indicator
    public static let amber = Color(hex: "FCEEA8")
    public static let scarlet = Color(hex: "D62E2F") // Matches pantoneRed
    public static let accentBlue = Color(hex: "004789") // Matches pantoneBlue
}

// MARK: - Color Hex Extension
extension Color {
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
