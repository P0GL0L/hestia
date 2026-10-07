import ATContracts
import AppKit
import SceneKit
import SwiftUI

/// The geometry engine's meshes in an orbit view: walls, glass, doors, slabs, structure, stairs, and roofs.
///
/// An edit changes the meshes but not the session, so only the model's node is refilled and the camera stays
/// where the person left it. New and Open start another session, and the view starts over with the default
/// camera.
struct OrbitScene: NSViewRepresentable {
    var meshes: [Mesh]
    /// The edit session the meshes come from.
    var sessionID: UUID

    /// What the view's scene was built from, and the node that holds the model's meshes.
    final class Coordinator {
        var meshes: [Mesh]
        var sessionID: UUID
        var content = SCNNode()
        /// Whether the scene has the default camera yet. A scene built empty gets it with its first meshes.
        var hasCamera = false

        init(meshes: [Mesh], sessionID: UUID) {
            self.meshes = meshes
            self.sessionID = sessionID
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(meshes: meshes, sessionID: sessionID)
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1)
        start(view, context.coordinator)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.sessionID != sessionID {
            // Another model: start over, default camera included.
            coordinator.sessionID = sessionID
            coordinator.meshes = meshes
            start(view, coordinator)
            return
        }
        guard coordinator.meshes != meshes else { return }
        // The same model, edited: refill the model node and leave the camera alone.
        coordinator.meshes = meshes
        fill(coordinator.content)
        if !coordinator.hasCamera, let camera = defaultCamera() {
            view.scene?.rootNode.addChildNode(camera)
            view.pointOfView = camera
            coordinator.hasCamera = true
        }
    }

    /// A new scene holding the meshes, with the default camera when there is anything to look at.
    private func start(_ view: SCNView, _ coordinator: Coordinator) {
        let scene = SCNScene()
        let content = SCNNode()
        scene.rootNode.addChildNode(content)
        coordinator.content = content
        fill(content)
        let camera = defaultCamera()
        if let camera {
            scene.rootNode.addChildNode(camera)
        }
        coordinator.hasCamera = camera != nil
        view.scene = scene
        if let camera {
            view.pointOfView = camera
        }
    }

    /// Replaces the model node's children with a node per mesh.
    private func fill(_ content: SCNNode) {
        for child in content.childNodes {
            child.removeFromParentNode()
        }
        for mesh in meshes where !mesh.indices.isEmpty {
            content.addChildNode(node(for: mesh))
        }
    }

    /// Looks at the middle of the model from the south-east, high enough to see the roof. Nil with no meshes.
    private func defaultCamera() -> SCNNode? {
        var low = (x: CGFloat.greatestFiniteMagnitude, y: CGFloat.greatestFiniteMagnitude,
                   z: CGFloat.greatestFiniteMagnitude)
        var high = (x: -CGFloat.greatestFiniteMagnitude, y: -CGFloat.greatestFiniteMagnitude,
                    z: -CGFloat.greatestFiniteMagnitude)
        for mesh in meshes where !mesh.indices.isEmpty {
            for p in mesh.positions {
                let (x, y, z) = (feet(p.x), feet(p.y), feet(p.z))
                low = (min(low.x, x), min(low.y, y), min(low.z, z))
                high = (max(high.x, x), max(high.y, y), max(high.z, z))
            }
        }
        guard low.x <= high.x else { return nil }
        let center = SCNVector3((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2)
        let span = max(high.x - low.x, high.y - low.y, high.z - low.z, 1)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zFar = Double(span * 20)
        camera.position = SCNVector3(center.x + span * 0.9, center.y - span * 1.2, center.z + span * 0.7)
        camera.look(at: center, up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
        return camera
    }

    private func node(for mesh: Mesh) -> SCNNode {
        let positions = mesh.positions.map { SCNVector3(feet($0.x), feet($0.y), feet($0.z)) }
        var sources = [SCNGeometrySource(vertices: positions)]
        if mesh.normals.count == mesh.positions.count {
            sources.append(SCNGeometrySource(normals: mesh.normals.map {
                SCNVector3(CGFloat($0.x), CGFloat($0.y), CGFloat($0.z))
            }))
        }
        let data = mesh.indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: mesh.indices.count / 3,
                                         bytesPerIndex: MemoryLayout<UInt32>.size)
        let geometry = SCNGeometry(sources: sources, elements: [element])
        let material = SCNMaterial()
        let look = appearance(mesh.materialID.rawValue)
        material.diffuse.contents = look.color
        material.transparency = look.opacity
        material.isDoubleSided = true
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    /// A schematic color per engine material.
    private func appearance(_ material: String) -> (color: NSColor, opacity: CGFloat) {
        switch material {
        case "wall": return (NSColor(calibratedWhite: 0.85, alpha: 1), 1)
        case "glass": return (NSColor(calibratedRed: 0.55, green: 0.75, blue: 0.9, alpha: 1), 0.45)
        case "door": return (NSColor(calibratedRed: 0.55, green: 0.38, blue: 0.24, alpha: 1), 1)
        case "roof": return (NSColor(calibratedRed: 0.45, green: 0.28, blue: 0.22, alpha: 1), 1)
        case "slab": return (NSColor(calibratedWhite: 0.6, alpha: 1), 1)
        case "stair": return (NSColor(calibratedRed: 0.72, green: 0.55, blue: 0.32, alpha: 1), 1)
        default: return (NSColor(calibratedWhite: 0.7, alpha: 1), 1)
        }
    }

    private func feet(_ length: Length) -> CGFloat {
        CGFloat(length.ticks) / CGFloat(Length.feet(1).ticks)
    }
}
