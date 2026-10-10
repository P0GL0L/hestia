import ATContracts
import ATDrawings
import Foundation

/// What a terrain patch is, read from its name: a patch named "Driveway" or "Driveway 2" is a driveway. Only the
/// kind's own name, alone or followed by a number, counts, so "Lotus Garden" is not a lot. Any other name is
/// lawn.
enum SiteKind: String, CaseIterable, Sendable {
    case lot = "Lot"
    case lawn = "Lawn"
    case driveway = "Driveway"
    case path = "Path"
    case patio = "Patio"
    case deck = "Deck"
    case gravel = "Gravel"
    case pond = "Pond"
    case gardenBed = "Garden bed"

    init(patchName name: String) {
        self = Self.exact(name) ?? .lawn
    }

    /// The kind a name was generated for: the kind's name alone, or followed by a space and a number.
    static func exact(_ name: String) -> SiteKind? {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        return allCases.first { kind in
            let base = kind.rawValue.lowercased()
            guard trimmed.hasPrefix(base) else { return false }
            let rest = trimmed.dropFirst(base.count)
            if rest.isEmpty { return true }
            guard rest.first == " " else { return false }
            let number = rest.dropFirst()
            return !number.isEmpty && number.allSatisfy(\.isNumber)
        }
    }

    var look: Look {
        switch self {
        case .lot: return .lawn
        case .lawn: return .lawn
        case .driveway: return .concrete
        case .path, .patio: return .paving
        case .deck: return .deck
        case .gravel: return .gravel
        case .pond: return .water
        case .gardenBed: return .mulch
        }
    }

    /// The surface's height in feet above the storey floor's zero. Ground sits just below the house floor, and
    /// hardscape sits on the lawn; a deck stands a foot up.
    var surface: Double {
        switch self {
        case .lot: return -0.06
        case .lawn: return -0.05
        case .pond: return -0.045
        case .driveway, .path, .patio, .gravel, .gardenBed: return -0.03
        case .deck: return 1
        }
    }

    /// Which patches draw first in the plan and 3D: the lot under everything.
    var order: Int {
        switch self {
        case .lot: return 0
        case .lawn: return 1
        case .pond, .gardenBed, .gravel: return 2
        case .driveway, .path, .patio: return 3
        case .deck: return 4
        }
    }
}

/// Everything the 3D view shows, in view space (feet, y up): the engine's walls, stairs, and roofs; trimmed
/// doors and windows (`OpeningDetail`); a floor and a ceiling in each room; placed furniture and planting; and
/// the ground, lot, and paving.
struct HouseScene: Equatable, Sendable {
    var solids: [Solid]
    /// The middle of the house, in view space, for the camera to look at.
    var center: ScenePoint
    /// The house's largest extent in feet, at least 10.
    var span: Float

    static let feetPerTick = 1 / Double(Length.feet(1).ticks)

    static func feet(_ length: Length) -> Double { Double(length.ticks) * feetPerTick }

    init(document: ModelDocument, meshes: [Mesh]) {
        var house: [Look: Solid] = [:]
        var outdoor: [Look: Solid] = [:]
        Self.addEngineMeshes(meshes, to: &house)
        OpeningDetail.add(document, to: &house)
        Self.addRooms(document, to: &house)
        for placement in document.placements {
            let item = Furniture.item(placement.catalogItemID) ?? Furniture.placeholder(placement.catalogItemID)
            let floor = document.storeys.first { $0.id == placement.storeyID }.map { Self.feet($0.elevation) } ?? 0
            let turn = Double(placement.rotation.microDegrees) / 1_000_000 * .pi / 180
            let (x, y) = (Self.feet(placement.position.x), Self.feet(placement.position.y))
            let base = floor + Self.feet(placement.elevation)
            // Outdoor items belong to the site, so the camera frames the house and not the trees.
            if item.category == .outdoor {
                item.addSolids(to: &outdoor, cx: x, cy: y, floor: base, turn: turn, group: .site)
            } else {
                item.addSolids(to: &house, cx: x, cy: y, floor: base, turn: turn)
            }
        }
        let built = house.values.sorted { $0.look.rawValue < $1.look.rawValue }
        (center, span) = Self.extent(of: built.filter { $0.group != .site }, fallback: document)
        solids = built + Self.site(document, around: center, span: span)
            + outdoor.values.sorted { $0.look.rawValue < $1.look.rawValue }
    }

    // MARK: - House

    private static func look(for material: MaterialID) -> (Look, SolidGroup) {
        switch material.rawValue {
        case "wall": return (.wall, .house)
        case "glass": return (.glass, .house)
        case "door": return (.door, .house)
        case "roof": return (.roof, .roof)
        case "slab": return (.slab, .house)
        case "stair": return (.stair, .house)
        default: return (.structure, .house)
        }
    }

    /// The engine's meshes, merged into one solid per look and turned from z up to y up.
    private static func addEngineMeshes(_ meshes: [Mesh], to solids: inout [Look: Solid]) {
        // Doors and glass come from `OpeningDetail` instead: the engine's are flat panes with no thickness.
        let replaced: Set<String> = ["door", "glass"]
        for mesh in meshes where !mesh.indices.isEmpty && !replaced.contains(mesh.materialID.rawValue) {
            let (look, group) = look(for: mesh.materialID)
            var solid = solids[look] ?? Solid(look: look, group: group)
            let base = UInt32(solid.positions.count)
            for point in mesh.positions {
                solid.positions.append(.plan(feet(point.x), feet(point.y), feet(point.z)))
            }
            if mesh.normals.count == mesh.positions.count {
                solid.normals += mesh.normals.map { ScenePoint($0.x, $0.z, -$0.y) }
            } else {
                solid.normals += Array(repeating: ScenePoint(0, 1, 0), count: mesh.positions.count)
            }
            solid.indices += mesh.indices.map { base + $0 }
            solids[look] = solid
        }
    }

    /// A floor and a ceiling in each room, from its centerline outline. A storey with walls but no rooms and no
    /// slabs gets one floor under its walls, so the house never stands on bare ground.
    private static func addRooms(_ document: ModelDocument, to solids: inout [Look: Solid]) {
        let walls = Dictionary(document.walls.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ceiling = solids[.ceiling] ?? Solid(look: .ceiling, group: .ceiling)
        for storey in document.storeys {
            let base = feet(storey.elevation)
            let rooms = document.rooms.filter { $0.storeyID == storey.id }
            for room in rooms {
                guard let outline = RoomOutline.centerline(of: room, in: document) else { continue }
                let plan = outline.map { (x: feet($0.x), y: feet($0.y)) }
                let look = floorLook(room)
                var floor = solids[look] ?? Solid(look: look)
                Shapes.flat(&floor, plan, height: base + 0.02)
                solids[look] = floor
                let heights = room.boundaryWallIDs.compactMap { walls[$0].map { feet($0.height) } }
                Shapes.flat(&ceiling, plan, height: base + (heights.min() ?? 8) - 0.02, facingUp: false)
            }
            let storeyWalls = document.walls.filter { $0.storeyID == storey.id }
            let hasSlab = document.slabs.contains { $0.storeyID == storey.id }
            if rooms.isEmpty, !hasSlab, let box = wallBox(storeyWalls) {
                var floor = solids[.woodFloor] ?? Solid(look: .woodFloor)
                Shapes.flat(&floor, [(box.x0, box.y0), (box.x1, box.y0), (box.x1, box.y1), (box.x0, box.y1)],
                            height: base + 0.02)
                solids[.woodFloor] = floor
            }
        }
        if !ceiling.indices.isEmpty { solids[.ceiling] = ceiling }
    }

    /// The room's floor finish, when it names one; otherwise tile in kitchens, baths, and laundries, carpet in
    /// bedrooms, and wood elsewhere.
    static func floorLook(_ room: Room) -> Look {
        let words = ((room.floorFinish ?? "") + " " + room.name).lowercased()
        let tiled = ["tile", "kitchen", "bath", "laundry", "mud", "powder", "wc", "shower"]
        if tiled.contains(where: { words.contains($0) }) {
            return .tileFloor
        }
        if ["carpet", "bed", "nursery", "guest"].contains(where: { words.contains($0) }) { return .carpet }
        return .woodFloor
    }

    private static func wallBox(_ walls: [Wall]) -> (x0: Double, y0: Double, x1: Double, y1: Double)? {
        guard !walls.isEmpty else { return nil }
        let xs = walls.flatMap { [feet($0.start.x), feet($0.end.x)] }
        let ys = walls.flatMap { [feet($0.start.y), feet($0.end.y)] }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max(), x1 > x0, y1 > y0 else {
            return nil
        }
        return (x0, y0, x1, y1)
    }

    /// The middle and largest extent of the house. With nothing built, the middle of the terrain patches, or
    /// the origin.
    private static func extent(of solids: [Solid], fallback document: ModelDocument) -> (ScenePoint, Float) {
        var low = ScenePoint(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
        var high = ScenePoint(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
        for point in solids.flatMap(\.positions) {
            low = ScenePoint(min(low.x, point.x), min(low.y, point.y), min(low.z, point.z))
            high = ScenePoint(max(high.x, point.x), max(high.y, point.y), max(high.z, point.z))
        }
        guard low.x <= high.x else {
            let corners = document.terrainPatches.flatMap(\.boundary)
            guard !corners.isEmpty else { return (ScenePoint(0, 4, 0), 30) }
            let xs = corners.map { feet($0.x) }, ys = corners.map { feet($0.y) }
            let (x0, x1, y0, y1) = (xs.min() ?? 0, xs.max() ?? 0, ys.min() ?? 0, ys.max() ?? 0)
            let middle = ScenePoint.plan((x0 + x1) / 2, (y0 + y1) / 2, 4)
            return (middle, Float(max(x1 - x0, y1 - y0, 30)))
        }
        let middle = ScenePoint((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2)
        return (middle, max(high.x - low.x, high.y - low.y, high.z - low.z, 10))
    }

    // MARK: - Site

    /// The ground all around, then each terrain patch on it, lot first.
    private static func site(_ document: ModelDocument, around center: ScenePoint, span: Float) -> [Solid] {
        var ground = Solid(look: .grass, group: .site)
        let half = Double(max(span * 6, 300))
        let (cx, cy) = (Double(center.x), Double(-center.z))
        Shapes.flat(&ground, [(cx - half, cy - half), (cx + half, cy - half), (cx + half, cy + half),
                              (cx - half, cy + half)], height: -0.1)
        var solids: [Look: Solid] = [:]
        let patches = document.terrainPatches.sorted {
            SiteKind(patchName: $0.name).order < SiteKind(patchName: $1.name).order
        }
        for patch in patches {
            let kind = SiteKind(patchName: patch.name)
            let outline = patch.boundary.map { (x: feet($0.x), y: feet($0.y)) }
            var solid = solids[kind.look] ?? Solid(look: kind.look, group: .site)
            if kind == .deck {
                addDeck(&solid, outline)
            } else {
                Shapes.flat(&solid, outline, height: kind.surface)
            }
            solids[kind.look] = solid
        }
        return [ground] + solids.values.sorted { $0.look.rawValue < $1.look.rawValue }
    }

    /// A deck: the outline raised a foot, with its edges closed down to the ground.
    private static func addDeck(_ solid: inout Solid, _ outline: [(x: Double, y: Double)]) {
        let ring = Triangulation.counterclockwise(outline)
        let top = SiteKind.deck.surface
        Shapes.flat(&solid, ring, height: top)
        for index in ring.indices {
            let a = ring[index], b = ring[(index + 1) % ring.count]
            let (dx, dy) = (b.x - a.x, b.y - a.y)
            let length = max((dx * dx + dy * dy).squareRoot(), 1e-9)
            solid.addFan([(a.x, a.y, -0.1), (b.x, b.y, -0.1), (b.x, b.y, top), (a.x, a.y, top)],
                         normal: Solid.planNormal(dy / length, -dx / length, 0))
        }
    }
}
