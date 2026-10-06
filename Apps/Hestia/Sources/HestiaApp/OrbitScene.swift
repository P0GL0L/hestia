import ATContracts
import ATGeometry
import AppKit
import SceneKit
import SwiftUI

struct OrbitScene: NSViewRepresentable {
    var cottage: SixRoomCottage

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {}

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let root = scene.rootNode
        if let outlines = try? StraightWallOutlines().outlines(for: cottage.walls) {
            for polygon in outlines.values {
                root.addChildNode(wallNode(polygon))
            }
        }
        for plane in cottage.roof.planes {
            root.addChildNode(roofNode(plane))
        }
        root.addChildNode(stairNode())

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zFar = 2000
        camera.position = SCNVector3(feet(cottage.exteriorMax.x) + 30, feet(cottage.exteriorMin.y) - 36, 28)
        camera.look(at: SCNVector3(20, 12, 6))
        root.addChildNode(camera)
        return scene
    }

    private func wallNode(_ polygon: ClosedPolygon2) -> SCNNode {
        let path = NSBezierPath()
        guard let first = polygon.vertices.first else { return SCNNode() }
        path.move(to: NSPoint(x: feet(first.x), y: feet(first.y)))
        for vertex in polygon.vertices.dropFirst() {
            path.line(to: NSPoint(x: feet(vertex.x), y: feet(vertex.y)))
        }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: feet(cottage.wallHeight))
        shape.chamferRadius = 0
        shape.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.82, alpha: 1)
        let node = SCNNode(geometry: shape)
        node.position = SCNVector3(0, 0, feet(cottage.wallHeight) / 2)
        return node
    }

    private func roofNode(_ polygon: ClosedPolygon3) -> SCNNode {
        let node = SCNNode(geometry: triangleFan(polygon.vertices))
        node.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.45, green: 0.28, blue: 0.22, alpha: 1)
        node.geometry?.firstMaterial?.isDoubleSided = true
        return node
    }

    private func stairNode() -> SCNNode {
        let parent = SCNNode()
        let cut = cottage.slabCut
        let tread = cottage.stair.treadRun.ticks
        let rise = cottage.stair.riserRise.ticks
        let width = cut.maxY.ticks - cut.minY.ticks
        let steps = max(cottage.stair.riserCount - 1, 1)
        for index in 0..<steps {
            let box = SCNBox(
                width: feet(tread),
                height: feet(width),
                length: feet(rise),
                chamferRadius: 0
            )
            box.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.72, green: 0.55, blue: 0.32, alpha: 1)
            let node = SCNNode(geometry: box)
            let x = cut.minX.ticks + tread * Int64(index) + tread / 2
            let y = cut.minY.ticks + width / 2
            let z = rise * Int64(index) + rise / 2
            node.position = SCNVector3(feet(x), feet(y), feet(z))
            parent.addChildNode(node)
        }
        return parent
    }

    private func triangleFan(_ vertices: [Point3]) -> SCNGeometry {
        guard vertices.count >= 3 else { return SCNGeometry() }
        let positions = vertices.map { SCNVector3(feet($0.x), feet($0.y), feet($0.z)) }
        var indices: [Int32] = []
        for index in 1..<(vertices.count - 1) {
            indices.append(0)
            indices.append(Int32(index))
            indices.append(Int32(index + 1))
        }
        let source = SCNGeometrySource(vertices: positions)
        let data = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: data,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        return SCNGeometry(sources: [source], elements: [element])
    }

    private func feet(_ length: Length) -> CGFloat {
        CGFloat(length.ticks) / CGFloat(Length.feet(1).ticks)
    }

    private func feet(_ ticks: Int64) -> CGFloat {
        CGFloat(ticks) / CGFloat(Length.feet(1).ticks)
    }
}
