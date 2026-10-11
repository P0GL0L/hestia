#if canImport(SceneKit) && canImport(AppKit)
import AppKit
import ATContracts
import Foundation
import SceneKit
import Testing
@testable import HestiaApp

/// A box `width` by `height` by `length`, centered on its node.
private func box(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat) -> SCNNode {
    SCNNode(geometry: SCNBox(width: width, height: height, length: length, chamferRadius: 0))
}

private func close(_ a: SCNVector3, _ b: SCNVector3) -> Bool {
    abs(a.x - b.x) < 1e-4 && abs(a.y - b.y) < 1e-4 && abs(a.z - b.z) < 1e-4
}

@Suite("Live look models")
struct LiveLookTests {
    @Test("Hidden parts, and everything under a hidden part, are left out of a model's size")
    @MainActor
    func hiddenParts() throws {
        let model = SCNNode()
        model.addChildNode(box(2, 2, 2))
        let hidden = box(100, 100, 100)
        hidden.isHidden = true
        model.addChildNode(hidden)
        let parent = SCNNode()
        parent.isHidden = true
        let underHidden = box(50, 50, 50)
        underHidden.position = SCNVector3(40, 0, 0)
        parent.addChildNode(underHidden)
        model.addChildNode(parent)
        let bounds = try #require(LiveLook.bounds(of: model))
        #expect(close(bounds.low, SCNVector3(-1, -1, -1)) && close(bounds.high, SCNVector3(1, 1, 1)))
    }

    @Test("Turned, moved, and mirrored parts are measured where they end up")
    @MainActor
    func transforms() throws {
        let model = SCNNode()
        let arm = SCNNode()
        arm.position = SCNVector3(10, 0, 0)
        arm.eulerAngles = SCNVector3(0, CGFloat.pi / 2, 0)
        let part = box(2, 1, 4)
        part.position = SCNVector3(1, 0, 0)
        arm.addChildNode(part)
        model.addChildNode(arm)
        // A quarter turn about y takes the part's +x to -z: it lies 4 wide in x and 2 deep in z, at z = -1.
        let turned = try #require(LiveLook.bounds(of: model))
        #expect(close(turned.low, SCNVector3(8, -0.5, -2)) && close(turned.high, SCNVector3(12, 0.5, 0)))

        let mirrored = SCNNode()
        let flipped = box(2, 2, 2)
        flipped.position = SCNVector3(5, 0, 0)
        let mirror = SCNNode()
        mirror.scale = SCNVector3(-1, 1, 1)
        mirror.addChildNode(flipped)
        mirrored.addChildNode(mirror)
        let bounds = try #require(LiveLook.bounds(of: mirrored))
        #expect(close(bounds.low, SCNVector3(-6, -1, -1)) && close(bounds.high, SCNVector3(-4, 1, 1)))
    }

    @Test("A model with no finite, visible size is refused")
    @MainActor
    func nonFinite() {
        let model = SCNNode()
        let part = box(1, 1, 1)
        part.scale = SCNVector3(CGFloat.infinity, 1, 1)
        model.addChildNode(part)
        #expect(LiveLook.bounds(of: model) == nil)
        #expect(LiveLook.bounds(of: SCNNode()) == nil, "nothing to measure")
        let flat = SCNNode()
        flat.addChildNode(box(1, 0, 1))
        #expect(LiveLook.bounds(of: flat) == nil, "no height")
    }

    @Test("Two catalog items sharing one model load it once, and its materials become physically based")
    @MainActor
    func sharedModel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hestia-live-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("models"),
                                                withIntermediateDirectories: true)
        let scene = SCNScene()
        let part = box(1.6, 0.8, 0.7)
        // Saved Blinn, as some programs write models; loading makes it physically based.
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = NSColor(srgbRed: 0.6, green: 0.5, blue: 0.4, alpha: 1)
        part.geometry?.materials = [material]
        part.position = SCNVector3(0, 0.4, 0)
        scene.rootNode.addChildNode(part)
        #expect(scene.write(to: root.appendingPathComponent("models/Couch.scn"), options: nil, delegate: nil,
                            progressHandler: nil))
        let json = """
        {"version": 1, "models": {
          "hestia.sofa": {"asset": "Couch", "file": "models/Couch.scn", "fit": "footprint", "turn": 0,
                          "size": [1.6, 0.8, 0.7]},
          "hestia.loveseat": {"asset": "Couch", "file": "models/Couch.scn", "fit": "footprint", "turn": 0,
                              "size": [1.6, 0.8, 0.7]}}}
        """
        try Data(json.utf8).write(to: root.appendingPathComponent("library.json"))
        let look = LiveLook(library: try AssetLibrary.load(root))

        var session = EditSession(model: try HestiaModel.blank())
        try session.addRectangleRoom(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(20, 15), named: "Living")
        for (id, x) in [("hestia.sofa", 5.0), ("hestia.loveseat", 14.0)] {
            let item = try #require(Furniture.item(CatalogItemID(rawValue: id)))
            _ = try session.place(item, at: PlanOverlay.point(x, 7), degrees: 0)
        }
        let house = look.houseScene(document: session.model.document, meshes: session.model.meshes)
        #expect(Set(house.models.map(\.catalogID)) == ["hestia.sofa", "hestia.loveseat"])
        let content = SCNNode()
        look.fill(content, with: house)
        let placed = content.childNodes.filter { $0.childNodes.count == 1 && $0.geometry == nil }
        #expect(placed.count == 2, "one node per placed item")
        let shapes = placed.compactMap { place -> SCNGeometry? in
            var found: SCNGeometry?
            place.enumerateHierarchy { node, stop in
                if let geometry = node.geometry {
                    found = geometry
                    stop.pointee = true
                }
            }
            return found
        }
        #expect(shapes.count == 2 && shapes[0] === shapes[1], "both copies share the one loaded model")
        #expect(shapes.allSatisfy { $0.materials.first?.lightingModel == .physicallyBased })
        #expect(shapes.allSatisfy { $0.materials.first?.diffuse.contents != nil })
    }

    @Test("Every walk meters from the same starting exposure, never the last walk's")
    @MainActor
    func walkExposureStartsAfresh() throws {
        let model = try HestiaModel.blank()
        let view = HouseSCNView()
        view.scene = SCNScene()
        let start = Walker.start(in: model.document, storey: model.document.storeys.first?.id)
        view.startWalking(start)
        let camera = try #require(view.walkCamera)
        // Metering, or a darker house, left the last walk four stops over.
        camera.exposureOffset = LiveLook.insideExposure + 4
        view.stopWalking()
        view.startWalking(start)
        if LiveLook.shared == nil {
            #expect(view.walkCamera?.exposureOffset == LiveLook.insideExposure)
        } else {
            // With a library the walk then meters, starting from there; it never keeps the four stops.
            #expect(abs((view.walkCamera?.exposureOffset ?? 99) - (LiveLook.insideExposure + 4)) > 0.01)
        }
        view.stopWalking()
    }
}
#endif
