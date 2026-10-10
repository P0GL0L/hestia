import ATContracts
import ATDrawings
import Foundation

/// The house as an OpenUSD text file (`.usda`), for Blender, Maya, 3ds Max, Houdini, and the renderers they
/// drive (Cycles, Arnold, V-Ray, RenderMan).
///
/// Layout: `/Hestia/Building` holds the walls, openings, stairs, roof, floors, and ceilings, one mesh per surface
/// look; `/Hestia/Site` holds the ground and the terrain patches; `/Hestia/Items` holds one Xform per placed
/// item, moved and turned into place, carrying its catalog ID (`hestia:catalogItem`) so a renderer can swap the
/// simple stand-in shape for a finished model of the same size; `/Hestia/Materials` holds one
/// `UsdPreviewSurface` per look; and the stage has a sun and a camera looking at the house from the south-east.
/// Units are feet (`metersPerUnit` 0.3048), y up, as in the 3D view.
enum HouseUSD {
    static func export(document: ModelDocument, meshes: [Mesh]) -> String {
        var empty = document
        empty.placements = []
        let shell = HouseScene(document: empty, meshes: meshes)
        let full = HouseScene(document: document, meshes: meshes)
        var looks = Set(shell.solids.map(\.look))
        var items: [String] = []
        var counts: [String: Int] = [:]
        for placement in document.placements {
            let item = Furniture.item(placement.catalogItemID) ?? Furniture.placeholder(placement.catalogItemID)
            var solids: [Look: Solid] = [:]
            item.addSolids(to: &solids, cx: 0, cy: 0, floor: 0, turn: 0)
            looks.formUnion(solids.keys)
            let base = name(item.id)
            counts[base, default: 0] += 1
            let storey = document.storeys.first { $0.id == placement.storeyID }
            let floor = storey.map { HouseScene.feet($0.elevation) } ?? 0
            let at = ScenePoint.plan(HouseScene.feet(placement.position.x), HouseScene.feet(placement.position.y),
                                     floor + HouseScene.feet(placement.elevation))
            let degrees = Double(placement.rotation.microDegrees) / 1_000_000
            items.append(xform("\(base)_\(counts[base] ?? 1)", item: item.id, at: at, degrees: degrees,
                               solids: solids.values.sorted { $0.look.rawValue < $1.look.rawValue }, indent: 2))
        }
        var text = """
        #usda 1.0
        (
            defaultPrim = "Hestia"
            metersPerUnit = 0.3048
            upAxis = "Y"
            doc = "Hestia house model. Schematic: not for construction."
        )

        def Xform "Hestia" (
            kind = "assembly"
        )
        {
            def Scope "Materials"
            {

        """
        for look in looks.sorted(by: { $0.rawValue < $1.rawValue }) {
            text += material(look)
        }
        text += "    }\n\n    def Xform \"Building\"\n    {\n"
        for solid in shell.solids where solid.group != .site {
            text += mesh(solid.look.rawValue, solid, indent: 2)
        }
        text += "    }\n\n    def Xform \"Site\"\n    {\n"
        for solid in shell.solids where solid.group == .site {
            text += mesh(solid.look.rawValue, solid, indent: 2)
        }
        text += "    }\n\n    def Xform \"Items\"\n    {\n" + items.joined() + "    }\n\n"
        text += rooms(document)
        text += sunAndCamera(full)
        text += "}\n"
        return text
    }

    /// A prim name from any text: letters, digits, and underscores, not starting with a digit.
    static func name(_ text: String) -> String {
        let cleaned = String(text.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        let trimmed = cleaned.hasPrefix("hestia_") ? String(cleaned.dropFirst(7)) : cleaned
        guard let first = trimmed.first, !first.isNumber else { return "_" + trimmed }
        return trimmed
    }

    private static func number(_ value: Float) -> String {
        let rounded = (Double(value) * 10_000).rounded() / 10_000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    private static func tuple(_ point: ScenePoint) -> String {
        "(\(number(point.x)), \(number(point.y)), \(number(point.z)))"
    }

    private static func material(_ look: Look) -> String {
        let color = look.rgb
        let roughness: Double
        switch look {
        case .glass, .water: roughness = 0.05
        case .metal: roughness = 0.35
        case .porcelain, .stone: roughness = 0.25
        default: roughness = 0.75
        }
        let metallic = look == .metal ? 1 : 0
        return """
                def Material "\(look.rawValue)"
                {
                    token outputs:surface.connect = </Hestia/Materials/\(look.rawValue)/Surface.outputs:surface>

                    def Shader "Surface"
                    {
                        uniform token info:id = "UsdPreviewSurface"
                        color3f inputs:diffuseColor = (\(color.red), \(color.green), \(color.blue))
                        float inputs:roughness = \(roughness)
                        float inputs:metallic = \(metallic)
                        float inputs:opacity = \(look.opacity)
                        token outputs:surface
                    }
                }


        """
    }

    private static func mesh(_ name: String, _ solid: Solid, indent: Int) -> String {
        let pad = String(repeating: "    ", count: indent)
        let points = solid.positions.map(tuple).joined(separator: ", ")
        let normals = solid.normals.map(tuple).joined(separator: ", ")
        let counts = Array(repeating: "3", count: solid.indices.count / 3).joined(separator: ", ")
        let indices = solid.indices.map(String.init).joined(separator: ", ")
        return """
        \(pad)def Mesh "\(name)" (
        \(pad)    prepend apiSchemas = ["MaterialBindingAPI"]
        \(pad))
        \(pad){
        \(pad)    uniform bool doubleSided = \(solid.group == .ceiling ? "false" : "true")
        \(pad)    uniform token subdivisionScheme = "none"
        \(pad)    point3f[] points = [\(points)]
        \(pad)    normal3f[] normals = [\(normals)] (
        \(pad)        interpolation = "vertex"
        \(pad)    )
        \(pad)    int[] faceVertexCounts = [\(counts)]
        \(pad)    int[] faceVertexIndices = [\(indices)]
        \(pad)    rel material:binding = </Hestia/Materials/\(solid.look.rawValue)>
        \(pad)}

        """
    }

    private static func xform(_ name: String, item: String, at point: ScenePoint, degrees: Double, solids: [Solid],
                              indent: Int) -> String {
        let pad = String(repeating: "    ", count: indent)
        var text = """
        \(pad)def Xform "\(name)"
        \(pad){
        \(pad)    custom string hestia:catalogItem = "\(item)"
        \(pad)    double3 xformOp:translate = \(tuple(point))
        \(pad)    float xformOp:rotateY = \(degrees)
        \(pad)    uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateY"]

        """
        for solid in solids {
            text += mesh(solid.look.rawValue, solid, indent: indent + 1)
        }
        return text + "\(pad)}\n\n"
    }

    /// One Xform per room at the middle of its ceiling, with its name, use, and floor size, so a renderer can
    /// light each room and a pipeline tool can find it.
    private static func rooms(_ document: ModelDocument) -> String {
        let walls = Dictionary(document.walls.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var text = "    def Scope \"Rooms\"\n    {\n"
        var counts: [String: Int] = [:]
        for room in document.rooms {
            guard let outline = RoomOutline.centerline(of: room, in: document) else { continue }
            let plan = outline.map { (x: HouseScene.feet($0.x), y: HouseScene.feet($0.y)) }
            guard let middle = Walker.centroid(plan) else { continue }
            let floor = document.storeys.first { $0.id == room.storeyID }.map { HouseScene.feet($0.elevation) } ?? 0
            let heights = room.boundaryWallIDs.compactMap { walls[$0].map { HouseScene.feet($0.height) } }
            let ceiling = floor + (heights.min() ?? 8)
            let xs = plan.map(\.x), ys = plan.map(\.y)
            let width = (xs.max() ?? 0) - (xs.min() ?? 0), depth = (ys.max() ?? 0) - (ys.min() ?? 0)
            let base = name(room.name)
            counts[base, default: 0] += 1
            let prim = counts[base] == 1 ? base : "\(base)_\(counts[base] ?? 1)"
            let label = room.name.replacingOccurrences(of: "\"", with: "'")
            text += """
                    def Xform "\(prim)"
                    {
                        custom string hestia:room = "\(label)"
                        custom string hestia:floorLook = "\(HouseScene.floorLook(room).rawValue)"
                        custom float2 hestia:size = (\(number(Float(width))), \(number(Float(depth))))
                        double3 xformOp:translate = \(tuple(.plan(middle.x, middle.y, ceiling)))
                        uniform token[] xformOpOrder = ["xformOp:translate"]
                    }


            """
        }
        return text + "    }\n\n"
    }

    /// An afternoon sun from the south-west and a camera on the house from the south-east.
    private static func sunAndCamera(_ scene: HouseScene) -> String {
        let center = scene.center, span = scene.span
        let eye = ScenePoint(center.x + span * 0.95, center.y + span * 0.55, center.z + span * 1.3)
        let (dx, dy, dz) = (Double(center.x - eye.x), Double(center.y - eye.y), Double(center.z - eye.z))
        // Camera looks down its -z: turn about y to face the house, then tilt down about x.
        let yaw = atan2(-dx, -dz) * 180 / .pi
        let pitch = atan2(dy, (dx * dx + dz * dz).squareRoot()) * 180 / .pi
        return """
            def DistantLight "Sun"
            {
                float inputs:intensity = 3
                float inputs:angle = 0.53
                color3f inputs:color = (1, 0.96, 0.9)
                float3 xformOp:rotateXYZ = (-40, -35, 0)
                uniform token[] xformOpOrder = ["xformOp:rotateXYZ"]
            }

            def Camera "Camera"
            {
                # Lens and film in tenths of a scene unit (feet): a 28 mm lens on 36 by 20.25 mm film.
                float focalLength = 0.9186
                float horizontalAperture = 1.1811
                float verticalAperture = 0.6644
                float2 clippingRange = (0.5, \(number(span * 60)))
                double3 xformOp:translate = \(tuple(eye))
                float xformOp:rotateY = \(yaw)
                float xformOp:rotateX = \(pitch)
                uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateY", "xformOp:rotateX"]
            }

        """
    }
}
