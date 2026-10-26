import SwiftUI

/// Alignment reticle; readable guidance is displayed by the camera overlay.
public struct OcularReticleView: View {
    public let gazeMetrics: EyeMetrics
    public let faceDistanceCm: Double
    public let isDistanceOptimal: Bool
    public let isFaceDetected: Bool
    public var reticleSize: CGFloat = 260

    public init(
        gazeMetrics: EyeMetrics,
        faceDistanceCm: Double,
        isDistanceOptimal: Bool,
        isFaceDetected: Bool,
        reticleSize: CGFloat = 260
    ) {
        self.gazeMetrics = gazeMetrics
        self.faceDistanceCm = faceDistanceCm
        self.isDistanceOptimal = isDistanceOptimal
        self.isFaceDetected = isFaceDetected
        self.reticleSize = reticleSize
    }

    public var body: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (isDistanceOptimal ? NeuroPulseColor.trackingAccent : NeuroPulseColor.amber).opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: reticleSize * 0.55
                    )
                )
                .frame(width: reticleSize * 1.1, height: reticleSize * 1.1)

            // Outer Dashed Guide Ring
            Circle()
                .stroke(
                    isDistanceOptimal ? NeuroPulseColor.trackingAccent.opacity(0.4) : NeuroPulseColor.borderSlate,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
                )
                .frame(width: reticleSize, height: reticleSize)

            // Target Alignment Ring
            Circle()
                .stroke(
                    isDistanceOptimal ? NeuroPulseColor.trackingAccent : NeuroPulseColor.mutedSlate.opacity(0.4),
                    lineWidth: 2
                )
                .frame(width: reticleSize * 0.78, height: reticleSize * 0.78)

            // Crosshair ticks
            ForEach([0, 90, 180, 270], id: \.self) { angle in
                Rectangle()
                    .fill(isDistanceOptimal ? NeuroPulseColor.trackingAccent : NeuroPulseColor.mutedSlate)
                    .frame(width: 1.5, height: 16)
                    .offset(y: -(reticleSize * 0.39))
                    .rotationEffect(.degrees(Double(angle)))
            }

            // Tracked gaze indicator
            if isFaceDetected {
                let currentGx = gazeMetrics.gazeX ?? min(max(0.5 + gazeMetrics.eyeYawDeg / 40.0, 0.05), 0.95)
                let currentGy = gazeMetrics.gazeY ?? min(max(0.5 - gazeMetrics.eyePitchDeg / 40.0, 0.05), 0.95)
                let pupilOffset = CGPoint(
                    x: (currentGx - 0.5) * Double(reticleSize * 0.5),
                    y: (currentGy - 0.5) * Double(reticleSize * 0.5)
                )

                ZStack {
                    Circle()
                        .stroke(NeuroPulseColor.trackingAccent, lineWidth: 2)
                        .frame(width: 40, height: 40)
                        .shadow(color: NeuroPulseColor.trackingAccent, radius: 8)

                    Circle()
                        .fill(NeuroPulseColor.pantoneYellow)
                        .frame(width: 12, height: 12)
                }
                .offset(x: pupilOffset.x, y: pupilOffset.y)
                .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.82), value: currentGx)
            } else {
                Text("ALIGN FACE")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(NeuroPulseColor.mutedSlate)
            }


        }
        .frame(width: reticleSize, height: reticleSize)
    }

}
