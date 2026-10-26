import SwiftUI

#if canImport(ARKit) && os(iOS)
import ARKit
import SceneKit
import UIKit

/// Live 60 FPS front-camera viewport powered by Apple ARKit TrueDepth.
/// Integrates a dedicated SceneKit coordinator that renders and updates `ARSCNFaceGeometry`
/// with a subtle cyan wireframe face mesh, bright eye rings, and directional gaze rays.
public struct ARCameraPreviewView: UIViewRepresentable {
    public let session: ARSession
    public var showsWireframe: Bool

    public init(session: ARSession, showsWireframe: Bool = true) {
        self.session = session
        self.showsWireframe = showsWireframe
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(showsWireframe: showsWireframe)
    }

    public func makeUIView(context: Context) -> ARSCNView {
        let scnView = ARSCNView(frame: .zero)
        scnView.session = session
        scnView.delegate = context.coordinator
        context.coordinator.scnView = scnView
        scnView.automaticallyUpdatesLighting = true
        scnView.autoenablesDefaultLighting = true
        scnView.rendersContinuously = true
        scnView.backgroundColor = UIColor(NeuroPulseColor.pantoneBlue)
        return scnView
    }

    public func updateUIView(_ uiView: ARSCNView, context: Context) {
        if uiView.session !== session {
            uiView.session = session
        }
        context.coordinator.showsWireframe = showsWireframe
    }

    public class Coordinator: NSObject, ARSCNViewDelegate {
        weak var scnView: ARSCNView?
        var showsWireframe: Bool

        private var faceGeometry: ARSCNFaceGeometry?
        private var faceNode: SCNNode?
        private var leftEyeNode: SCNNode?
        private var rightEyeNode: SCNNode?

        public init(showsWireframe: Bool) {
            self.showsWireframe = showsWireframe
            super.init()
        }

        // MARK: - ARSCNViewDelegate
        public func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard let faceAnchor = anchor as? ARFaceAnchor,
                  let metalDevice = renderer.device,
                  let geometry = ARSCNFaceGeometry(device: metalDevice) else {
                return nil
            }

            self.faceGeometry = geometry

            // 1. Subtle Face Wireframe
            let faceMaterial = SCNMaterial()
            faceMaterial.fillMode = .lines
            faceMaterial.diffuse.contents = UIColor(NeuroPulseColor.pantoneYellow).withAlphaComponent(0.25)
            faceMaterial.lightingModel = .constant
            geometry.materials = [faceMaterial]

            let rootFaceNode = SCNNode(geometry: geometry)
            rootFaceNode.name = "NeuroPulseFaceRoot"
            self.faceNode = rootFaceNode

            // 2. Left Eye Tracking Visualizer
            let lEye = createEyeVisualizerNode()
            lEye.simdTransform = faceAnchor.leftEyeTransform
            rootFaceNode.addChildNode(lEye)
            self.leftEyeNode = lEye

            // 3. Right Eye Tracking Visualizer
            let rEye = createEyeVisualizerNode()
            rEye.simdTransform = faceAnchor.rightEyeTransform
            rootFaceNode.addChildNode(rEye)
            self.rightEyeNode = rEye

            rootFaceNode.isHidden = !showsWireframe || !faceAnchor.isTracked
            return rootFaceNode
        }

        public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let faceAnchor = anchor as? ARFaceAnchor else { return }

            // Immediately hide when face tracking is lost
            if !faceAnchor.isTracked || !showsWireframe {
                node.isHidden = true
                return
            }

            node.isHidden = false

            // Update face mesh geometry topology from current ARFaceAnchor
            faceGeometry?.update(from: faceAnchor.geometry)

            // Update eye nodes with Apple ARKit eye transforms
            leftEyeNode?.simdTransform = faceAnchor.leftEyeTransform
            rightEyeNode?.simdTransform = faceAnchor.rightEyeTransform
        }

        public func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
            node.isHidden = true
        }

        // MARK: - Eye Node Construction
        private func createEyeVisualizerNode() -> SCNNode {
            let container = SCNNode()

            // A. Bright Cyan Eye Wireframe Ring
            let ringGeometry = SCNTorus(ringRadius: 0.011, pipeRadius: 0.0014)
            let ringMaterial = SCNMaterial()
            ringMaterial.diffuse.contents = UIColor(NeuroPulseColor.pantoneYellow)
            ringMaterial.lightingModel = .constant
            ringGeometry.materials = [ringMaterial]

            let ringNode = SCNNode(geometry: ringGeometry)
            ringNode.eulerAngles = SCNVector3(x: Float.pi / 2.0, y: 0, z: 0)
            container.addChildNode(ringNode)

            // B. Short Forward-Pointing Gaze Ray (5 cm)
            let rayLength: CGFloat = 0.05
            let rayGeometry = SCNCylinder(radius: 0.0011, height: rayLength)
            let rayMaterial = SCNMaterial()
            rayMaterial.diffuse.contents = UIColor(NeuroPulseColor.pantoneYellow)
            rayMaterial.lightingModel = .constant
            rayGeometry.materials = [rayMaterial]

            let rayNode = SCNNode(geometry: rayGeometry)
            // Rotate from Y-axis default to +Z forward gaze direction
            rayNode.eulerAngles = SCNVector3(x: Float.pi / 2.0, y: 0, z: 0)
            rayNode.position = SCNVector3(x: 0, y: 0, z: Float(rayLength / 2.0))
            container.addChildNode(rayNode)

            return container
        }
    }
}
#else
public struct ARCameraPreviewView: View {
    public var showsWireframe: Bool = true

    public init(session: Any? = nil, showsWireframe: Bool = true) {
        self.showsWireframe = showsWireframe
    }

    public var body: some View {
        NeuroPulseColor.pantoneBlue
    }
}
#endif
