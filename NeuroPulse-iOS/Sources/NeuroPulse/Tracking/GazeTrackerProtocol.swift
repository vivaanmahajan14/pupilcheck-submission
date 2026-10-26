import Foundation
import CoreGraphics
import Combine

#if canImport(ARKit) && os(iOS)
import ARKit
#endif

/// Unified interface for Apple eye-tracking models (ARKit TrueDepth).
public protocol GazeTrackerProtocol: ObservableObject {
    /// Latest eye telemetry (gaze vector, angular rotation, blendshapes)
    var currentMetrics: EyeMetrics { get }

    /// Distance from front camera sensor to athlete's face in centimeters
    var faceDistanceCm: Double { get }

    /// Whether face distance is strictly within the 20–30 cm optimal clinical testing zone
    var isDistanceOptimal: Bool { get }

    /// Whether a face is actively detected and locked in front camera frame
    var isFaceDetected: Bool { get }

    /// Whether the tracker is actively capturing frames
    var isTracking: Bool { get }
    var trackingError: String? { get }

    /// Whether optical calibration is completed
    var isCalibrated: Bool { get }

    /// Calibrated affine mapping from raw TrueDepth coordinates to normalized screen coordinates
    var calibrationMap: GazeCalibrationMap? { get }

    /// Measured RMS angular calibration error in degrees
    var measuredCalibrationErrorDeg: Double { get }

    #if canImport(ARKit) && os(iOS)
    /// Direct underlying ARSession for live 60 FPS TrueDepth camera preview
    var arSession: ARSession? { get }
    #endif

    /// Starts camera stream and eye-tracking model inference
    func startTracking()

    /// Stops camera stream and releases hardware sessions
    func stopTracking()

    /// Records a calibration sample when athlete fixates a specific target point
    func recordCalibrationSample(targetPoint: CGPoint) -> Bool

    /// Finalizes calibration by computing affine mapping from collected samples
    func finalizeCalibration() -> GazeCalibrationMap?

    /// Calibrates coordinate mapping for the specified normalized screen position
    func registerCalibrationPoint(screenPoint: CGPoint, at index: Int)

    /// Sets a precomputed calibration map and associated error
    func setCalibrationMap(_ map: GazeCalibrationMap, errorDeg: Double)

    /// Resets calibration matrices to identity/default
    func resetCalibration()
}

extension GazeTrackerProtocol {
    public var trackingError: String? { nil }
    public var calibrationMap: GazeCalibrationMap? { nil }
    public var measuredCalibrationErrorDeg: Double { 0.0 }

    public func setCalibrationMap(_ map: GazeCalibrationMap, errorDeg: Double = 0.0) {}

    public func recordCalibrationSample(targetPoint: CGPoint) -> Bool {
        return false
    }

    public func finalizeCalibration() -> GazeCalibrationMap? {
        return nil
    }

    #if canImport(ARKit) && os(iOS)
    public var arSession: ARSession? { nil }
    #endif
}
