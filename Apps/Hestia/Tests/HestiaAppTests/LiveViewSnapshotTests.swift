#if canImport(SceneKit) && canImport(AppKit)
import AppKit
import ATContracts
import Foundation
import SceneKit
import Testing
@testable import HestiaApp

/// Stills of the live 3D view with the asset library, checked by their pixels. Runs only when asked, on a Mac
/// with Metal:
///
///     HESTIA_LIBRARY=<built library> HESTIA_SNAPSHOT_DIR=<folder> swift test --filter LiveViewSnapshotTests
///
/// It writes outside.png (orbit view from the south-east), street.png (eye height from the south-east),
/// garden.png (eye height from the south-west, the shaded side), sky.png (from well clear of the house, looking
/// at the library's sun), inside.png and inside-1 to inside-3.png (walking, four headings from where the walk
/// starts), door/door-00.png to door-13.png (walking in through the front door), and sky-mapping.txt (where
/// SceneKit shows, and lights with, each column and row of a sky image).
@Suite("Live view snapshots")
struct LiveViewSnapshotTests {
    static let folder = ProcessInfo.processInfo.environment["HESTIA_SNAPSHOT_DIR"]
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    @Test("SceneKit shows and lights with the sky image the way the library lays it out",
          .enabled(if: LiveViewSnapshotTests.folder != nil))
    @MainActor
    func skyMapping() throws {
        let output = URL(fileURLWithPath: try #require(Self.folder), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // A sky whose red channel is its column and whose green channel is its row, so a pixel says where it
        // came from: u = red / 255 and v = green / 255.
        let (width, height) = (256, 128)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let index = (row * width + column) * 4
                bytes[index] = UInt8(column)
                bytes[index + 1] = UInt8(row * 2)
                bytes[index + 2] = 0
            }
        }
        let sky = try #require(Self.image(bytes, width: width, height: height))
        let turn = SCNMatrix4MakeRotation(LiveLook.skyTurn, 0, 1, 0)
        // The library's layout (sky/sky.png): column u looks toward bearing (u - 0.75) * 360 clockwise from north
        // (view -z), and row v looks up at (0.5 - v) * 180 degrees. Directions are kept off the column seam,
        // where filtering blends its two edges.
        func expected(bearing: Double, up: Double) -> (u: Double, v: Double) {
            ((0.75 + bearing / 360).truncatingRemainder(dividingBy: 1), 0.5 - up / 180)
        }
        func reading(_ world: SCNScene, at eye: SCNVector3, toward: SCNVector3) throws -> (u: Double, v: Double) {
            let camera = SCNCamera()
            camera.fieldOfView = 4
            camera.wantsHDR = false
            let node = SCNNode()
            node.camera = camera
            node.position = eye
            world.rootNode.addChildNode(node)
            node.look(at: toward)
            defer { node.removeFromParentNode() }
            let shot = try #require(LiveLook.snapshot(world, from: node, size: CGSize(width: 16, height: 16)))
            let pixels = try #require(Self.pixels(shot))
            let center = pixels.rgb(x: pixels.width / 2, y: pixels.height / 2)
            return (Double(center.0) / 255, Double(center.1) / 255)
        }
        var report = ""
        var wrong: [String] = []
        func compare(_ name: String, _ got: (u: Double, v: Double), _ want: (u: Double, v: Double),
                     tolerance: Double) {
            report += "\(name): u \(got.u) (want \(want.u)), v \(got.v) (want \(want.v))\n"
            let du = abs(got.u - want.u)
            if min(du, 1 - du) > tolerance || abs(got.v - want.v) > tolerance { wrong.append(name) }
        }

        // The background.
        let shown = SCNScene()
        shown.background.contents = sky
        shown.background.contentsTransform = turn
        let origin = SCNVector3(0, 0, 0)
        for (name, toward, bearing, up) in [("north", SCNVector3(0, 0, -1), 0.0, 0.0),
                                            ("north-east", SCNVector3(1, 0, -1), 45, 0),
                                            ("south-west", SCNVector3(-1, 0, 1), 225, 0),
                                            ("north-west, 45 up", SCNVector3(-1.0, 1.414, -1.0), 315, 45)] {
            compare("background \(name)", try reading(shown, at: origin, toward: toward),
                    expected(bearing: bearing, up: up), tolerance: 0.03)
        }
        // The sun lamp's direction: looking along it lands on the library's sun bearing and elevation.
        let sun = LiveLook.towardSun(azimuth: 150, elevation: 48)
        compare("background toward the sun lamp", try reading(shown, at: origin,
                                                               toward: SCNVector3(sun.x, sun.y, sun.z)),
                expected(bearing: 150, up: 48), tolerance: 0.03)

        // The light: a mirror shows the sky behind the viewer, as image-based light reflects it.
        let lit = SCNScene()
        lit.background.contents = NSColor.black
        lit.lightingEnvironment.contents = sky
        lit.lightingEnvironment.contentsTransform = turn
        let mirror = SCNMaterial()
        mirror.lightingModel = .physicallyBased
        mirror.diffuse.contents = NSColor.white
        mirror.metalness.contents = NSNumber(value: 1.0)
        mirror.roughness.contents = NSNumber(value: 0.0)
        for (name, at, facing, toward, bearing) in [
            ("south", SCNVector3(0, 0, -5), CGFloat(0), SCNVector3(0, 0, -1), 180.0),
            ("west", SCNVector3(5, 0, 0), -CGFloat.pi / 2, SCNVector3(1, 0, 0), 270.0),
        ] {
            let plane = SCNPlane(width: 8, height: 8)
            plane.materials = [mirror]
            let node = SCNNode(geometry: plane)
            node.position = at
            node.eulerAngles = SCNVector3(0, facing, 0)
            lit.rootNode.addChildNode(node)
            defer { node.removeFromParentNode() }
            compare("light from the \(name)", try reading(lit, at: origin, toward: toward),
                    expected(bearing: bearing, up: 0), tolerance: 0.06)
        }
        try report.write(to: output.appendingPathComponent("sky-mapping.txt"), atomically: true, encoding: .utf8)
        #expect(wrong.isEmpty, "SceneKit lays the sky out differently from the library:\n\(report)")
    }

    @Test("The sample house renders with the asset library", .enabled(if: LiveViewSnapshotTests.folder != nil))
    @MainActor
    func snapshots() throws {
        let output = URL(fileURLWithPath: try #require(Self.folder), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let library = try #require(AssetLibrary.standard(), "set HESTIA_LIBRARY to a built asset library")
        let look = LiveLook(library: library)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repo.appendingPathComponent("fixtures/rect-cottage.json"))
        let document = SampleSite.decorate(try JSONDecoder().decode(ModelDocument.self, from: data))
        let model = try HestiaModel(document: document)
        let world = SCNScene()
        _ = look.light(world)
        let content = SCNNode()
        world.rootNode.addChildNode(content)
        let scene = look.houseScene(document: model.document, meshes: model.meshes)
        look.fill(content, with: scene)
        #expect(scene.models.count >= 20, "the sample's furniture and planting come from the library")
        #expect(scene.models.allSatisfy { library.model($0.catalogID) != nil })

        let center = SCNVector3(CGFloat(scene.center.x), CGFloat(scene.center.y), CGFloat(scene.center.z))
        let span = CGFloat(scene.span)
        show(content, ceilings: false)
        let outside = try save(world, eye: SCNVector3(center.x + span * 0.95, center.y + span * 0.8,
                                                      center.z + span * 1.3),
                               target: center, look: look, inside: false, name: "outside", in: output)
        let street = try save(world, eye: SCNVector3(center.x + span * 0.7, 5.5, center.z + span * 1.0),
                              target: SCNVector3(center.x, 7, center.z), look: look, inside: false, name: "street",
                              in: output)
        let garden = try save(world, eye: SCNVector3(center.x - span * 0.75, 5.5, center.z + span * 0.9),
                              target: SCNVector3(center.x, 7, center.z), look: look, inside: false, name: "garden",
                              in: output)
        for (name, shot) in [("outside", outside), ("street", street), ("garden", garden)] {
            // Shaded walls keep the sky's light: almost nothing in an outdoor view is black.
            let black = shot.share { $0 < 10 }
            #expect(black < 0.03, "\(name) has black areas: \(black)")
        }

        // From well clear of the house and above its roof, looking where the sun lamp shines from: the photo's
        // sun should be at the middle of the frame.
        let sun = LiveLook.towardSun(azimuth: library.sky?.sunAzimuth ?? 150,
                                     elevation: library.sky?.sunElevation ?? 40)
        let away = SCNVector3(center.x - sun.x * span * 4, span * 0.6, center.z - sun.z * span * 4)
        let sky = try save(world, eye: away, target: SCNVector3(away.x + sun.x * 100, away.y + sun.y * 100,
                                                                away.z + sun.z * 100),
                           look: look, inside: false, name: "sky", in: output)
        let ground = sky.share { $0 < 60 }
        // Where the sun is, skyMapping checks against a coded sky; a cloudy photo has no reliable bright point.
        #expect(ground < 0.02, "the sky shot sees something other than sky: \(ground)")

        show(content, ceilings: true)
        world.lightingEnvironment.intensity = LiveLook.insideSky
        let lights = SCNNode()
        look.roomLights(model.document).forEach(lights.addChildNode)
        world.rootNode.addChildNode(lights)
        let walker = Walker.start(in: model.document, storey: model.planStorey)
        let eye = walker.eye
        for turn in 0..<4 {
            let heading = walker.heading + Double(turn) * .pi / 2
            let ahead = (x: sin(heading), z: -cos(heading))
            let shot = try save(world, eye: SCNVector3(CGFloat(eye.x), CGFloat(eye.y), CGFloat(eye.z)),
                                target: SCNVector3(CGFloat(Double(eye.x) + ahead.x * 10), CGFloat(eye.y) - 0.8,
                                                   CGFloat(Double(eye.z) + ahead.z * 10)),
                                look: look, inside: true, name: turn == 0 ? "inside" : "inside-\(turn)", in: output)
            let black = shot.share { $0 < 10 }
            let (red, green, blue) = shot.meanColor
            let cast = max(red, green, blue) / max(min(red, green, blue), 1)
            #expect(black < 0.15, "inside, turn \(turn), is dark: \(black)")
            #expect(shot.mean > 60 && shot.mean < 175, "inside, turn \(turn), mean \(shot.mean)")
            #expect(cast < 1.3, "inside, turn \(turn), has a color cast: \(red), \(green), \(blue)")
        }
    }

    @Test("A walk through the front door sees the room past the open leaf, never the inside of the door",
          .enabled(if: LiveViewSnapshotTests.folder != nil))
    @MainActor
    func walkThroughTheFrontDoor() throws {
        let output = URL(fileURLWithPath: try #require(Self.folder), isDirectory: true)
            .appendingPathComponent("door", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let library = try #require(AssetLibrary.standard(), "set HESTIA_LIBRARY to a built asset library")
        let look = LiveLook(library: library)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repo.appendingPathComponent("fixtures/rect-cottage.json"))
        let model = try HestiaModel(document: SampleSite.decorate(try JSONDecoder().decode(ModelDocument.self,
                                                                                           from: data)))
        let world = SCNScene()
        _ = look.light(world)
        let content = SCNNode()
        world.rootNode.addChildNode(content)
        look.fill(content, with: look.houseScene(document: model.document, meshes: model.meshes))
        show(content, ceilings: true)
        world.lightingEnvironment.intensity = LiveLook.insideSky
        look.roomLights(model.document).forEach(world.rootNode.addChildNode)

        // The first door with floor on one side only: the way in from outside.
        func plan(_ point: (x: Double, y: Double)) -> Point2 {
            Point2(x: Length(ticks: Int64((point.x / HouseScene.feetPerTick).rounded())),
                   y: Length(ticks: Int64((point.y / HouseScene.feetPerTick).rounded())))
        }
        let storey = try #require(model.planStorey)
        let doors = OpeningDetail.details(model.document, storey: storey)
            .filter { $0.pieces.contains { $0.part == .leaf } }
        let (frame, outside) = try #require(doors.lazy.compactMap { door -> (OpeningDetail.Frame, Double)? in
            let reach = door.frame.wallThickness / 2 + 3
            let left = model.onFloor(plan(door.frame.point(door.frame.middle, reach)), storey: storey)
            let right = model.onFloor(plan(door.frame.point(door.frame.middle, -reach)), storey: storey)
            return left == right ? nil : (door.frame, left ? -1 : 1)
        }.first, "the cottage has a door to the outside")

        // Walk in square to the wall, from three feet outside to three feet inside, as the walk moves.
        let barriers = WalkBarriers(document: model.document, storey: storey)
        let start = frame.point(frame.middle, outside * (frame.wallThickness / 2 + 3))
        let inward = (x: -(start.x - frame.point(frame.middle).x), y: -(start.y - frame.point(frame.middle).y))
        var walker = Walker(x: start.x, y: start.y, floor: frame.sill)
        walker.heading = atan2(inward.x, inward.y)
        for step in 0..<28 {
            if step.isMultiple(of: 2) {
                let eye = walker.eye
                let ahead = Walker(x: walker.x + walker.forward.x * 10, y: walker.y + walker.forward.y * 10,
                                   floor: walker.floor).eye
                let shot = try save(world, eye: SCNVector3(CGFloat(eye.x), CGFloat(eye.y), CGFloat(eye.z)),
                                    target: SCNVector3(CGFloat(ahead.x), CGFloat(ahead.y) - 0.8, CGFloat(ahead.z)),
                                    look: look, inside: true, name: String(format: "door-%02d", step / 2),
                                    in: output)
                let black = shot.share { $0 < 10 }
                #expect(black < 0.15, "step \(step) through the door is dark: \(black)")
            }
            walker.step(WalkInput(forward: 1), seconds: 0.05, barriers: barriers)
        }
        let end = frame.point(frame.middle, -outside * (frame.wallThickness / 2 + 2))
        #expect(((walker.x - end.x) * inward.x + (walker.y - end.y) * inward.y) > 0, "the walk got inside")
    }

    @MainActor
    private func show(_ content: SCNNode, ceilings: Bool) {
        for child in content.childNodes where child.name == "ceiling" {
            child.isHidden = !ceilings
        }
    }

    @MainActor
    private func save(_ world: SCNScene, eye: SCNVector3, target: SCNVector3, look: LiveLook, inside: Bool,
                      name: String, in folder: URL) throws -> Pixels {
        let camera = SCNCamera()
        camera.zNear = 0.3
        camera.zFar = 4000
        camera.fieldOfView = inside ? 70 : 50
        look.tune(camera, inside: inside)
        let node = SCNNode()
        node.camera = camera
        node.position = eye
        world.rootNode.addChildNode(node)
        node.look(at: target)
        defer { node.removeFromParentNode() }
        // Inside, the camera meters its exposure first, as a walk does in the app.
        if inside {
            LiveLook.meter(world, from: node)
        }
        let image = try #require(LiveLook.snapshot(world, from: node, size: CGSize(width: 1600, height: 900)))
        let data = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?
            .representation(using: .png, properties: [:]))
        try data.write(to: folder.appendingPathComponent(name + ".png"))
        return try #require(Self.pixels(image))
    }

    /// An image's pixels as 8-bit RGBA, rows from the top.
    struct Pixels {
        var width: Int
        var height: Int
        var bytes: [UInt8]

        func rgb(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let index = (y * width + x) * 4
            return (bytes[index], bytes[index + 1], bytes[index + 2])
        }

        func luminance(x: Int, y: Int) -> Double {
            let (r, g, b) = rgb(x: x, y: y)
            return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
        }

        /// The share of sampled pixels whose luminance (0 to 255) passes the test.
        func share(_ test: (Double) -> Bool) -> Double {
            var hits = 0, count = 0
            for y in stride(from: 0, to: height, by: 6) {
                for x in stride(from: 0, to: width, by: 6) {
                    count += 1
                    if test(luminance(x: x, y: y)) { hits += 1 }
                }
            }
            return count == 0 ? 0 : Double(hits) / Double(count)
        }

        /// The mean red, green, and blue of the sampled pixels, 0 to 255.
        var meanColor: (Double, Double, Double) {
            var sums = (0.0, 0.0, 0.0), count = 0.0
            for y in stride(from: 0, to: height, by: 6) {
                for x in stride(from: 0, to: width, by: 6) {
                    let (r, g, b) = rgb(x: x, y: y)
                    sums = (sums.0 + Double(r), sums.1 + Double(g), sums.2 + Double(b))
                    count += 1
                }
            }
            return count == 0 ? (0, 0, 0) : (sums.0 / count, sums.1 / count, sums.2 / count)
        }

        var mean: Double {
            var sum = 0.0, count = 0
            for y in stride(from: 0, to: height, by: 6) {
                for x in stride(from: 0, to: width, by: 6) {
                    sum += luminance(x: x, y: y)
                    count += 1
                }
            }
            return count == 0 ? 0 : sum / Double(count)
        }
    }

    static func pixels(_ image: NSImage) -> Pixels? {
        guard let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let (width, height) = (picture.width, picture.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: srgb,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Pixels(width: width, height: height, bytes: bytes) : nil
    }

    static func image(_ bytes: [UInt8], width: Int, height: Int) -> NSImage? {
        var copy = bytes
        let picture = copy.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: srgb,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        return picture.map { NSImage(cgImage: $0, size: NSSize(width: width, height: height)) }
    }
}
#endif
