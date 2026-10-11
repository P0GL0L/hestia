import AppKit
import ATContracts
import Metal
import SceneKit

/// The live 3D view's finished look, built from the asset library: photographed materials on every surface,
/// finished furniture and planting models in place of the stand-in shapes, and the sky photo as both the
/// background and the light, with a sun that casts soft shadows and a camera that tone-maps like a photograph.
///
/// The library does the heavy work ahead of time (`tools/blender/hestia_library.py`), so the view only loads
/// textures and models once and places copies of them; nothing is modeled or converted while you work.
@MainActor
final class LiveLook {
    /// The live look over the default library, when the app has one.
    static let shared: LiveLook? = AssetLibrary.standard().map { LiveLook(library: $0) }

    let library: AssetLibrary
    private var templates: [Look: SCNMaterial] = [:]
    private var prototypes: [String: SCNNode] = [:]
    private var modelBounds: [String: (low: SCNVector3, high: SCNVector3)] = [:]
    private var broken: Set<String> = []
    private var skyImage: NSImage?

    /// How far to turn the sky photo about +y. None: the library lays its sky out as SceneKit reads it, north
    /// three quarters across (LiveViewSnapshotTests measures this on Metal).
    static let skyTurn: CGFloat = 0
    /// The sky's light outside, and inside while walking, where it is turned down because image-based light
    /// reaches through walls.
    /// Where the camera's exposure starts, in stops: fixed outside, under the sky photo's steady light; the start
    /// of metering inside, each time a walk begins.
    static let outsideExposure: CGFloat = -0.2
    static let insideExposure: CGFloat = -0.5
    static let outsideSky: CGFloat = 1.2
    static let insideSky: CGFloat = 0.6

    init(library: AssetLibrary) {
        self.library = library
    }

    // MARK: - Scene

    /// The house with every placed item that has a working library model left for that model to draw.
    func houseScene(document: ModelDocument, meshes: [Mesh]) -> HouseScene {
        let wanted = Set(document.placements.map(\.catalogItemID.rawValue))
        let drawn = wanted.filter { prototype(for: $0) != nil }
        return HouseScene(document: document, meshes: meshes, leaving: drawn)
    }

    /// Replaces the content's children with the house's solids in finished materials and its placed models.
    func fill(_ content: SCNNode, with scene: HouseScene) {
        for child in content.childNodes {
            child.removeFromParentNode()
        }
        for solid in scene.solids where !solid.indices.isEmpty {
            content.addChildNode(node(for: solid))
        }
        for placed in scene.models {
            if let node = modelNode(for: placed) {
                content.addChildNode(node)
            }
        }
    }

    /// The sky photo as background and light, and a sun standing where the photo's sun is.
    func light(_ world: SCNScene) -> SCNNode {
        if let sky = library.sky, let image = sky.image(cache: &skyImage) {
            world.background.contents = image
            world.lightingEnvironment.contents = image
            let turn = SCNMatrix4MakeRotation(Self.skyTurn, 0, 1, 0)
            world.background.contentsTransform = turn
            world.lightingEnvironment.contentsTransform = turn
        }
        world.lightingEnvironment.intensity = Self.outsideSky
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1700
        sun.temperature = 5600
        sun.castsShadow = true
        // Forward shadows take away only the sun's own light, so shade keeps the sky's; deferred shadows darken
        // the whole picture in shade, which turned shaded walls and every room black.
        sun.shadowMode = .forward
        sun.shadowColor = NSColor.black
        sun.shadowSampleCount = 16
        sun.shadowRadius = 2.5
        sun.shadowMapSize = CGSize(width: 4096, height: 4096)
        sun.shadowCascadeCount = 3
        sun.automaticallyAdjustsShadowProjection = true
        sun.maximumShadowDistance = 300
        let node = SCNNode()
        node.name = "sun"
        node.light = sun
        let toward = Self.towardSun(azimuth: library.sky?.sunAzimuth ?? 150, elevation: library.sky?.sunElevation ?? 40)
        node.position = SCNVector3(toward.x * 200, toward.y * 200, toward.z * 200)
        node.look(at: SCNVector3(0, 0, 0))
        world.rootNode.addChildNode(node)
        return node
    }

    /// A unit vector toward the sun in view space (y up, north -z, east +x) from its bearing clockwise from
    /// north and its elevation, in degrees.
    nonisolated static func towardSun(azimuth: Double, elevation: Double) -> (x: CGFloat, y: CGFloat, z: CGFloat) {
        let (bearing, height) = (azimuth * .pi / 180, elevation * .pi / 180)
        return (CGFloat(sin(bearing) * cos(height)), CGFloat(sin(height)), CGFloat(-cos(bearing) * cos(height)))
    }

    /// A camera that sees like a photograph: high dynamic range with a filmic shoulder, ambient occlusion in
    /// corners and under furniture, a little bloom on bright sky, and a soft vignette.
    func tune(_ camera: SCNCamera, inside: Bool) {
        camera.wantsHDR = true
        // SceneKit's own adaptation overshot on Metal and washed rooms out. Outside, the sky photo sets a steady
        // light and a fixed exposure suits it; inside, this is only where metering starts (see `meter`).
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = inside ? Self.insideExposure : Self.outsideExposure
        camera.averageGray = 0.18
        camera.whitePoint = 1.6
        camera.minimumExposure = -15
        camera.maximumExposure = 15
        camera.bloomIntensity = 0.25
        camera.bloomThreshold = 0.9
        camera.bloomBlurRadius = 6
        camera.screenSpaceAmbientOcclusionIntensity = inside ? 1.4 : 1.0
        camera.screenSpaceAmbientOcclusionRadius = 1.6
        camera.screenSpaceAmbientOcclusionBias = 0.05
        camera.vignettingIntensity = 0.35
        camera.vignettingPower = 0.6
        camera.saturation = 1.05
        camera.contrast = 0.08
    }

    /// Warm ceiling lights, one per room, for walking inside: the sky lights everything as if outdoors, so inside
    /// it is turned down and the rooms are lit as a house is.
    func roomLights(_ document: ModelDocument) -> [SCNNode] {
        HouseScene.roomCeilings(document).map { room in
            let lamp = SCNLight()
            lamp.type = .omni
            // Neutral warm white, low in the room and falling off gently, so the ceiling shows no hot spot and
            // the walls keep their color.
            lamp.temperature = 4000
            lamp.intensity = CGFloat(min(300 + room.area * 3, 1200))
            lamp.attenuationStartDistance = 0
            lamp.attenuationEndDistance = CGFloat(max(room.reach * 2.5, 16))
            lamp.attenuationFalloffExponent = 1
            lamp.castsShadow = false
            let node = SCNNode()
            node.name = "room light"
            node.light = lamp
            node.position = SCNVector3(CGFloat(room.middle.x), CGFloat(room.middle.y) - 2.5, CGFloat(room.middle.z))
            return node
        }
    }

    // MARK: - Materials

    private func node(for solid: Solid) -> SCNNode {
        let positions = solid.positions.map { SCNVector3(CGFloat($0.x), CGFloat($0.y), CGFloat($0.z)) }
        let normals = solid.normals.map { SCNVector3(CGFloat($0.x), CGFloat($0.y), CGFloat($0.z)) }
        var sources = [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)]
        if let surface = library.surface(solid.look) {
            let coordinates = SurfaceMapping.coordinates(solid, tile: surface.tile)
            sources.append(SCNGeometrySource(textureCoordinates: coordinates.map { CGPoint(x: CGFloat($0.u),
                                                                                           y: CGFloat($0.v)) }))
            sources.append(Self.tangents(solid))
        }
        let data = solid.indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: solid.indices.count / 3,
                                         bytesPerIndex: MemoryLayout<UInt32>.size)
        let geometry = SCNGeometry(sources: sources, elements: [element])
        let material = template(for: solid.look).copy() as? SCNMaterial ?? SCNMaterial()
        material.isDoubleSided = solid.group != .ceiling
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = HouseView.name(solid.group)
        node.castsShadow = solid.group != .ceiling && solid.group != .site && solid.look != .glass
        return node
    }

    /// Each vertex's tangent: the direction texture u runs along its face.
    private static func tangents(_ solid: Solid) -> SCNGeometrySource {
        var values: [Float] = []
        values.reserveCapacity(solid.normals.count * 3)
        for normal in solid.normals {
            let tangent = SurfaceMapping.tangent(normal: normal)
            values += [tangent.x, tangent.y, tangent.z]
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: .tangent, vectorCount: solid.normals.count,
                                 usesFloatComponents: true, componentsPerVector: 3,
                                 bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                 dataStride: MemoryLayout<Float>.size * 3)
    }

    private func template(for look: Look) -> SCNMaterial {
        if let made = templates[look] { return made }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        let (roughness, metalness) = Self.finish(look)
        material.metalness.contents = NSNumber(value: metalness)
        material.roughness.contents = NSNumber(value: roughness)
        material.diffuse.contents = Self.color(linear: Self.linear(look.rgb))
        if let surface = library.surface(look) {
            if let paint = surface.paint {
                material.diffuse.contents = Self.color(linear: (paint[0], paint[1], paint[2]))
            } else if let diffuse = surface.diffuse.flatMap(NSImage.init(contentsOf:)) {
                material.diffuse.contents = diffuse
                Self.repeating(material.diffuse)
            }
            if let tint = surface.tint {
                material.multiply.contents = Self.color(linear: (tint[0], tint[1], tint[2]))
            }
            if let normal = surface.normal.flatMap(NSImage.init(contentsOf:)) {
                material.normal.contents = normal
                material.normal.intensity = 0.8
                Self.repeating(material.normal)
            }
            if let rough = surface.rough.flatMap(NSImage.init(contentsOf:)) {
                material.roughness.contents = rough
                Self.repeating(material.roughness)
            }
        }
        if look.opacity < 1 {
            material.transparency = CGFloat(look.opacity)
            material.transparencyMode = .dualLayer
        }
        templates[look] = material
        return material
    }

    private static func repeating(_ property: SCNMaterialProperty) {
        property.wrapS = .repeat
        property.wrapT = .repeat
        property.mipFilter = .linear
        property.maxAnisotropy = 8
    }

    /// Roughness and metalness for surfaces without a texture.
    private static func finish(_ look: Look) -> (Double, Double) {
        switch look {
        case .glass, .water: return (0.05, 0)
        case .metal: return (0.35, 1)
        case .porcelain: return (0.2, 0)
        case .white, .trim, .ceiling: return (0.6, 0)
        default: return (0.75, 0)
        }
    }

    /// The look's display color as linear light (the library's paint and tint are already linear).
    private static func linear(_ rgb: (red: Double, green: Double, blue: Double)) -> (Double, Double, Double) {
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return (channel(rgb.red), channel(rgb.green), channel(rgb.blue))
    }

    /// A color from linear light, written as sRGB so SceneKit turns it back into the same linear light.
    private static func color(linear rgb: (Double, Double, Double)) -> NSColor {
        func channel(_ value: Double) -> CGFloat {
            let clamped = min(max(value, 0), 1)
            return CGFloat(clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055)
        }
        return NSColor(srgbRed: channel(rgb.0), green: channel(rgb.1), blue: channel(rgb.2), alpha: 1)
    }

    // MARK: - Models

    /// The library model for a catalog item, loaded once, or nil when the library has none or it will not load.
    private func prototype(for catalogID: String) -> SCNNode? {
        guard let model = library.model(catalogID), !broken.contains(model.asset) else { return nil }
        if let loaded = prototypes[model.asset] { return loaded }
        guard let scene = try? SCNScene(url: model.file, options: nil) else {
            broken.insert(model.asset)
            return nil
        }
        let holder = SCNNode()
        for child in scene.rootNode.childNodes {
            holder.addChildNode(child)
        }
        holder.enumerateHierarchy { child, _ in
            for material in child.geometry?.materials ?? [] {
                material.lightingModel = .physicallyBased
            }
        }
        guard let bounds = Self.bounds(of: holder) else {
            broken.insert(model.asset)
            return nil
        }
        prototypes[model.asset] = holder
        modelBounds[model.asset] = bounds
        return holder
    }

    /// The box around every visible geometry at or under a node, in the node's own space. Hidden nodes and
    /// everything under them (alternate parts, helpers) are left out. Nil when nothing visible has a finite,
    /// non-empty extent, so a model that would fit to nothing or to infinity is never placed.
    static func bounds(of node: SCNNode) -> (low: SCNVector3, high: SCNVector3)? {
        var low = SCNVector3(CGFloat.infinity, .infinity, .infinity)
        var high = SCNVector3(-CGFloat.infinity, -.infinity, -.infinity)
        var finite = true
        func visit(_ child: SCNNode) {
            guard !child.isHidden, child.opacity > 0 else { return }
            if let geometry = child.geometry {
                let (min, max) = geometry.boundingBox
                for x in [min.x, max.x] {
                    for y in [min.y, max.y] {
                        for z in [min.z, max.z] {
                            let point = child.convertPosition(SCNVector3(x, y, z), to: node)
                            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else {
                                finite = false
                                continue
                            }
                            low = SCNVector3(Swift.min(low.x, point.x), Swift.min(low.y, point.y),
                                             Swift.min(low.z, point.z))
                            high = SCNVector3(Swift.max(high.x, point.x), Swift.max(high.y, point.y),
                                              Swift.max(high.z, point.z))
                        }
                    }
                }
            }
            for grandchild in child.childNodes {
                visit(grandchild)
            }
        }
        visit(node)
        let extent = [high.x - low.x, high.y - low.y, high.z - low.z]
        guard finite, extent.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return (low, high)
    }

    /// A copy of the item's model, fitted to its size and set in its place.
    private func modelNode(for placed: PlacedModel) -> SCNNode? {
        guard let model = library.model(placed.catalogID), let prototype = prototype(for: placed.catalogID),
              let (low, high) = modelBounds[model.asset] else {
            return nil
        }
        let size = (x: Double(high.x - low.x), y: Double(high.y - low.y), z: Double(high.z - low.z))
        let scale = ModelFit.scale(fit: model.fit, model: size, width: placed.width, depth: placed.depth,
                                   height: placed.height)
        let copy = prototype.clone()
        let factor = CGFloat(scale)
        copy.scale = SCNVector3(factor, factor, factor)
        copy.position = SCNVector3(-(low.x + high.x) / 2 * factor, -low.y * factor, -(low.z + high.z) / 2 * factor)
        let place = SCNNode()
        place.name = placed.outdoor ? "site" : "house"
        place.position = SCNVector3(CGFloat(placed.position.x), CGFloat(placed.position.y),
                                    CGFloat(placed.position.z))
        place.eulerAngles = SCNVector3(0, CGFloat(placed.turn + model.turn * .pi / 180), 0)
        place.addChildNode(copy)
        return place
    }

    // MARK: - Exposure

    /// Meters an inside camera: draws what `node` sees as a small picture and moves its exposure, by at most
    /// `largest` stops a round, until the picture's mean brightness is near `Exposure.target`, or `rounds` run
    /// out. Starting a walk meters fully; walking on meters a gentle round now and then, so the exposure follows
    /// the rooms without jumping.
    /// `renderer`, when given, is reused, as a walk does every half second; otherwise one is made.
    static func meter(_ world: SCNScene, from node: SCNNode, rounds: Int = 6, largest: Double = 3,
                      renderer given: SCNRenderer? = nil) {
        guard let camera = node.camera, let renderer = given ?? meteringRenderer() else { return }
        renderer.scene = world
        renderer.pointOfView = node
        for _ in 0..<rounds {
            let picture = renderer.snapshot(atTime: 0, with: CGSize(width: 160, height: 90), antialiasingMode: .none)
            guard let mean = pixels(picture).flatMap(Exposure.mean),
                  let step = Exposure.step(mean: mean, largest: largest) else { return }
            camera.exposureOffset = min(max(camera.exposureOffset + CGFloat(step), -8), 4)
        }
    }

    /// A renderer to meter with, on the system's GPU; nil without one.
    static func meteringRenderer() -> SCNRenderer? {
        MTLCreateSystemDefaultDevice().map { SCNRenderer(device: $0, options: nil) }
    }

    /// A picture's pixels as 8-bit sRGB RGBA.
    static func pixels(_ image: NSImage) -> [UInt8]? {
        guard let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let (width, height) = (picture.width, picture.height)
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }

    // MARK: - Snapshots

    /// A still of the scene from a camera, for checking the look without opening the app.
    static func snapshot(_ world: SCNScene, from camera: SCNNode, size: CGSize) -> NSImage? {
        guard let renderer = meteringRenderer() else { return nil }
        renderer.scene = world
        renderer.pointOfView = camera
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }
}

private extension AssetLibrary.Sky {
    func image(cache: inout NSImage?) -> NSImage? {
        if let cache { return cache }
        cache = NSImage(contentsOf: file)
        return cache
    }
}
