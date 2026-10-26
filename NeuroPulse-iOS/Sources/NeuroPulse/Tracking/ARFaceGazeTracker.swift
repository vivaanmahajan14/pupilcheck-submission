import Foundation
import CoreGraphics
import Combine

#if canImport(ARKit) && os(iOS)
import ARKit
import AVFoundation
import simd

/// Apple Native ARKit Eye-Tracking Engine.
/// Harnesses TrueDepth front-facing camera to extract 60 FPS 3D gaze rays (`lookAtPoint`),
/// bilateral eye transforms (`leftEyeTransform`, `rightEyeTransform`), and Apple eye blendshapes.
public final class ARFaceGazeTracker: NSObject, ObservableObject, GazeTrackerProtocol, ARSessionDelegate {
    @Published public private(set) var currentMetrics: EyeMetrics = .zero
    @Published public private(set) var faceDistanceCm: Double = 0.0
    @Published public private(set) var isDistanceOptimal: Bool = false
    @Published public private(set) var isFaceDetected: Bool = false
    @Published public private(set) var isTracking: Bool = false
    @Published public private(set) var isCalibrated: Bool = false
    @Published public private(set) var calibrationMap: GazeCalibrationMap?
    @Published public private(set) var measuredCalibrationErrorDeg: Double = 0.0

    public let session = ARSession()
    public var arSession: ARSession? { session }

    private var calibrationSamples: [CalibrationSample] = []

    public override init() {
        super.init()
        session.delegate = self
    }

    @Published public private(set) var trackingError: String?

    public static var isSupported: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    public func startTracking() {
        guard ARFaceTrackingConfiguration.isSupported else {
            trackingError = "Face tracking requires a supported TrueDepth device."
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.runTrackingSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.runTrackingSession()
                    } else {
                        self?.trackingError = "Camera permission denied"
                    }
                }
            }
        case .denied, .restricted:
            trackingError = "Camera permission denied"
        @unknown default:
            self.runTrackingSession()
        }
    }

    private func runTrackingSession() {
        trackingError = nil
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.maximumNumberOfTrackedFaces = 1

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        DispatchQueue.main.async {
            self.isTracking = true
        }
    }

    public func stopTracking() {
        session.pause()
        isTracking = false
        isFaceDetected = false
    }

    // MARK: - Calibration Support
    public func recordCalibrationSample(targetPoint: CGPoint) -> Bool {
        guard isFaceDetected, currentMetrics.isUsable else { return false }
        let sample = CalibrationSample(
            rawX: currentMetrics.rawGazeX,
            rawY: currentMetrics.rawGazeY,
            screenX: Double(targetPoint.x),
            screenY: Double(targetPoint.y),
            distanceCm: faceDistanceCm
        )
        calibrationSamples.append(sample)
        return true
    }

    public func finalizeCalibration() -> GazeCalibrationMap? {
        guard let map = GazeMath.fitCalibration(calibrationSamples) else {
            return nil
        }
        self.calibrationMap = map
        self.isCalibrated = true
        let errorDeg = GazeMath.calibrationErrorDeg(map: map, samples: calibrationSamples, canvasSize: CGSize(width: 390, height: 844)) ?? 0.0
        self.measuredCalibrationErrorDeg = errorDeg
        return map
    }

    public func registerCalibrationPoint(screenPoint: CGPoint, at index: Int) {
        _ = recordCalibrationSample(targetPoint: screenPoint)
        if index >= 2 && calibrationSamples.count >= 3 {
            _ = finalizeCalibration()
        }
    }

    public func setCalibrationMap(_ map: GazeCalibrationMap, errorDeg: Double = 0.0) {
        self.calibrationMap = map
        self.isCalibrated = true
        self.measuredCalibrationErrorDeg = errorDeg
    }

    public func resetCalibration() {
        calibrationSamples.removeAll()
        calibrationMap = nil
        isCalibrated = false
        measuredCalibrationErrorDeg = 0.0
    }

    // MARK: - ARSessionDelegate
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let faceAnchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first, faceAnchor.isTracked else {
            DispatchQueue.main.async {
                self.isFaceDetected = false
                self.currentMetrics = .untracked(at: frame.timestamp)
            }
            return
        }

        let faceInCamera = GazeMath.cameraRelativeTransform(face: faceAnchor.transform, camera: frame.camera.transform)
        // 1. Calculate device-to-face distance in cm (Z-axis translation)
        let zMeters = abs(faceInCamera.columns.3.z)
        let distance = Double(zMeters * 100.0)
        let optimal = distance >= AppConstants.minOptimalDistanceCm && distance <= AppConstants.maxOptimalDistanceCm

        // 2. Compute 3D Gaze Ray intersection with device display plane (camera z = 0)
        // Transform eyes and lookAtPoint from face coordinates to camera coordinates:
        let leftEyeInCamera = faceInCamera * simd_float4(faceAnchor.leftEyeTransform.columns.3.x,
                                                                 faceAnchor.leftEyeTransform.columns.3.y,
                                                                 faceAnchor.leftEyeTransform.columns.3.z, 1.0)
        let rightEyeInCamera = faceInCamera * simd_float4(faceAnchor.rightEyeTransform.columns.3.x,
                                                                  faceAnchor.rightEyeTransform.columns.3.y,
                                                                  faceAnchor.rightEyeTransform.columns.3.z, 1.0)
        let eyeMidpoint = (leftEyeInCamera + rightEyeInCamera) * 0.5

        let lookAtInCamera = faceInCamera * simd_float4(faceAnchor.lookAtPoint.x,
                                                                faceAnchor.lookAtPoint.y,
                                                                faceAnchor.lookAtPoint.z, 1.0)
        let gazeDir = simd_normalize(lookAtInCamera - eyeMidpoint)

        var hitRawX: Double = 0.0
        var hitRawY: Double = 0.0
        if abs(gazeDir.z) > 1e-4 {
            let t = -eyeMidpoint.z / gazeDir.z
            hitRawX = t.isFinite && t > 0 ? Double(eyeMidpoint.x + t * gazeDir.x) : .nan
            hitRawY = t.isFinite && t > 0 ? Double(eyeMidpoint.y + t * gazeDir.y) : .nan
        } else {
            hitRawX = .nan
            hitRawY = .nan
        }

        // 3. Extract Eye-in-Head Rotations (yaw / pitch in degrees)
        let leftYaw = atan2(Double(faceAnchor.leftEyeTransform.columns.2.x),
                            Double(faceAnchor.leftEyeTransform.columns.2.z)) * 180.0 / .pi
        let leftPitch = -asin(Double(min(max(faceAnchor.leftEyeTransform.columns.2.y, -1.0), 1.0))) * 180.0 / .pi

        let rightYaw = atan2(Double(faceAnchor.rightEyeTransform.columns.2.x),
                             Double(faceAnchor.rightEyeTransform.columns.2.z)) * 180.0 / .pi
        let rightPitch = -asin(Double(min(max(faceAnchor.rightEyeTransform.columns.2.y, -1.0), 1.0))) * 180.0 / .pi

        // 4. Extract Apple Eye Blink BlendShapes
        let blendShapes = faceAnchor.blendShapes
        let blinkL = Double(blendShapes[.eyeBlinkLeft]?.floatValue ?? 0.0)
        let blinkR = Double(blendShapes[.eyeBlinkRight]?.floatValue ?? 0.0)

        // 5. Extract Head-in-Camera Rotations (head yaw / pitch / roll in degrees)
        let headYaw = atan2(Double(faceInCamera.columns.2.x),
                            Double(faceInCamera.columns.2.z)) * 180.0 / .pi
        let headPitch = -asin(Double(min(max(faceInCamera.columns.2.y, -1.0), 1.0))) * 180.0 / .pi
        let headRoll = atan2(Double(faceInCamera.columns.0.y),
                             Double(faceInCamera.columns.1.y)) * 180.0 / .pi

        // 6. Apply Calibration Map if available
        var calGazeX: Double? = nil
        var calGazeY: Double? = nil
        if let map = calibrationMap {
            let mapped = map.apply(rawX: hitRawX, rawY: hitRawY)
            calGazeX = min(max(Double(mapped.x), 0.0), 1.0)
            calGazeY = min(max(Double(mapped.y), 0.0), 1.0)
        }

        let metrics = EyeMetrics(
            timestamp: frame.timestamp,
            isTrackingActive: true,
            faceDistanceCm: distance,
            rawGazeX: hitRawX,
            rawGazeY: hitRawY,
            gazeX: calGazeX,
            gazeY: calGazeY,
            leftEyeYawDeg: leftYaw,
            leftEyePitchDeg: leftPitch,
            rightEyeYawDeg: rightYaw,
            rightEyePitchDeg: rightPitch,
            eyeBlinkLeft: blinkL,
            eyeBlinkRight: blinkR,
            headYawDeg: headYaw,
            headPitchDeg: headPitch,
            headRollDeg: headRoll
        )

        DispatchQueue.main.async {
            self.currentMetrics = metrics
            self.faceDistanceCm = distance
            self.isDistanceOptimal = optimal
            self.isFaceDetected = true
        }
    }

    public func session(_ session: ARSession, didFailWithError error: Error) {
        print("❌ ARSession error: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.trackingError = error.localizedDescription
            self.isTracking = false
            self.isFaceDetected = false
        }
    }
}
#else
// Non-iOS / non-ARKit Fallback Stub
public final class ARFaceGazeTracker: ObservableObject, GazeTrackerProtocol {
    @Published public private(set) var currentMetrics: EyeMetrics = .zero
    @Published public private(set) var faceDistanceCm: Double = 0.0
    @Published public private(set) var isDistanceOptimal: Bool = false
    @Published public private(set) var isFaceDetected: Bool = false
    @Published public private(set) var isTracking: Bool = false
    @Published public private(set) var isCalibrated: Bool = false
    @Published public private(set) var calibrationMap: GazeCalibrationMap?
    @Published public private(set) var measuredCalibrationErrorDeg: Double = 0.0

    @Published public private(set) var trackingError: String?

    public static var isSupported: Bool { false }

    public init() {}

    public func startTracking() {
        isTracking = true
    }

    public func stopTracking() {
        isTracking = false
    }

    public func recordCalibrationSample(targetPoint: CGPoint) -> Bool {
        return true
    }

    public func finalizeCalibration() -> GazeCalibrationMap? {
        isCalibrated = true
        return nil
    }

    public func registerCalibrationPoint(screenPoint: CGPoint, at index: Int) {
        isCalibrated = true
    }

    public func setCalibrationMap(_ map: GazeCalibrationMap, errorDeg: Double = 0.0) {
        self.calibrationMap = map
        self.isCalibrated = true
        self.measuredCalibrationErrorDeg = errorDeg
    }

    public func resetCalibration() {
        calibrationMap = nil
        isCalibrated = false
        measuredCalibrationErrorDeg = 0.0
    }
}
#endif
