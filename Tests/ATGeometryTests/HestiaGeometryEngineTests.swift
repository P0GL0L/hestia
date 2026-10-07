@testable import ATGeometry
import ATContracts
import Foundation
import Testing

private let storey = StoreyID(UUID(uuidString: "00000000-0000-4000-8000-0000000000aa")!)

private func mm(_ x: Int64, _ y: Int64) -> Point2 {
    Point2(x: .millimeters(x), y: .millimeters(y))
}

private func wall(_ n: Int, _ a: Point2, _ b: Point2, thickness: Int64 = 200) -> Wall {
    Wall(id: WallID(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!), storeyID: storey,
         start: a, end: b, thickness: .millimeters(thickness), height: .millimeters(2400))
}

private func fixture(_ name: String) throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/\(name).json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

private func area(_ polygon: [Point2]) -> Double {
    abs(PolygonMath.twiceSignedArea(polygon.map(Vec.init))) / 2
}

/// Area two convex polygons share, by clipping one against the other's edges.
private func overlap(_ a: [Point2], _ b: [Point2]) -> Double {
    var clipped = a.map(Vec.init)
    let edges = b.map(Vec.init)
    let ccw: Double = PolygonMath.twiceSignedArea(edges) >= 0 ? 1 : -1
    for (p, q) in zip(edges, edges.dropFirst() + edges.prefix(1)) {
        let d = q - p
        clipped = PolygonMath.clip(clipped, keepingBelow: 0) { -ccw * d.cross($0 - p) }
    }
    return abs(PolygonMath.twiceSignedArea(clipped)) / 2
}

private let mmTicks = Double(Length.ticksPerMillimeter)
private let mm2 = mmTicks * mmTicks

@Test func lCornerIsMitred() throws {
    let a = wall(1, mm(0, 0), mm(4000, 0)), b = wall(2, mm(4000, 0), mm(4000, 3000))
    let footprints = try WallFootprints().footprints(for: [a, b])
    #expect(footprints[a.id] == [mm(0, -100), mm(4100, -100), mm(3900, 100), mm(0, 100)])
    #expect(footprints[b.id] == [mm(4100, -100), mm(4100, 3000), mm(3900, 3000), mm(3900, 100)])
}

@Test func tBranchStopsAtTheThroughWallFace() throws {
    let through = wall(1, mm(0, 0), mm(4000, 0)), branch = wall(2, mm(2000, 0), mm(2000, 3000), thickness: 100)
    let footprints = try WallFootprints().footprints(for: [through, branch])
    #expect(footprints[through.id] == [mm(0, -100), mm(4000, -100), mm(4000, 100), mm(0, 100)])
    #expect(footprints[branch.id] == [mm(2050, 100), mm(2050, 3000), mm(1950, 3000), mm(1950, 100)])
}

@Test func fourEndsMeetingFillTheCrossWithoutOverlap() throws {
    let arms = [mm(3000, 0), mm(0, 3000), mm(-3000, 0), mm(0, -3000)].enumerated().map { wall($0 + 1, mm(0, 0), $1) }
    let footprints = try WallFootprints().footprints(for: arms).values.map { $0 }
    let areas: [Double] = footprints.map(area)
    let sum: Double = areas.reduce(0, +)
    let total: Double = sum / mm2
    // Two 6 m by 200 mm bars crossing, counted once where they cross: 2 * 6000 * 200 - 200 * 200.
    let expected: Double = 2_360_000
    let error: Double = abs(total - expected)
    #expect(error < 1.0)
    for i in footprints.indices {
        for j in footprints.indices where i < j {
            let shared = overlap(footprints[i], footprints[j]) / mm2
            #expect(shared < 1.0)
        }
    }
}

@Test func obliqueCornersShareTheirMitre() throws {
    let a = wall(1, mm(0, 0), mm(4000, 0))
    // 30 degrees off the first wall.
    let b = wall(2, mm(4000, 0), mm(4000 + 3464, 2000))
    let footprints = try WallFootprints().footprints(for: [a, b])
    let pa = try #require(footprints[a.id]), pb = try #require(footprints[b.id])
    #expect(pa[1] == pb[0] && pa[2] == pb[3])
    #expect(overlap(pa, pb) / mm2 < 1.0)
    #expect(!PolygonValidation.hasSelfIntersection(ClosedPolygon2(vertices: pa)))
}

@Test func verySharpAnglesAreBevelled() throws {
    let a = wall(1, mm(0, 0), mm(4000, 0)), b = wall(2, mm(4000, 0), mm(0, 200))
    let footprints = try WallFootprints().footprints(for: [a, b])
    for polygon in footprints.values {
        for point in polygon {
            #expect(point.x.ticks < Length.millimeters(5700).ticks && point.x.ticks > -Length.millimeters(1700).ticks)
        }
    }
}

@Test func cottageWallsTileWithoutOverlapOrNotch() throws {
    let document = try fixture("rect-cottage")
    let footprints = try WallFootprints().footprints(for: document.walls)
    #expect(footprints.count == 7)
    // The two partitions run through the middle wall, so those pairs share their 6" by 6" crossing; every
    // other pair meets edge to edge.
    let crossing: Double = cottageCrossing()
    let throughPairs: Set<Set<WallID>> = [[document.walls[4].id, document.walls[6].id],
                                          [document.walls[5].id, document.walls[6].id]]
    let ids: [WallID] = document.walls.map(\.id)
    for i in ids.indices {
        for j in ids.indices where i < j {
            let pair: Set<WallID> = [ids[i], ids[j]]
            let expected: Double = throughPairs.contains(pair) ? crossing : 0
            let error: Double = overlapError(footprints[ids[i]]!, footprints[ids[j]]!, expected: expected)
            #expect(error < 1.0, "walls \(i) and \(j)")
        }
    }
    // The exterior meets in clean outer corners: the outline box is exactly 38'-0" by 23'-6".
    let points: [Point2] = footprints.values.flatMap { $0 }
    let xs: [Int64] = points.map(\.x.ticks)
    let ys: [Int64] = points.map(\.y.ticks)
    #expect(xs.min() == Length.inches(-6).ticks)
    #expect(xs.max() == Length.feet(37, inchCount: 6).ticks)
    #expect(ys.min() == Length.inches(-6).ticks)
    #expect(ys.max() == Length.feet(23).ticks)
    // Wall area equals the outline minus the six rooms, once the two crossings are counted once.
    let difference: Double = cottageWallAreaError(Array(footprints.values), crossing: crossing)
    #expect(abs(difference) < 1.0)
}

/// The 6" by 6" square where a cottage partition runs through the middle wall, in tick².
private func cottageCrossing() -> Double {
    let sixInches = Double(Length.inches(6).ticks)
    return sixInches * sixInches
}

/// How far, in mm², two footprints' shared area is from `expected` (tick²).
private func overlapError(_ a: [Point2], _ b: [Point2], expected: Double) -> Double {
    let shared: Double = overlap(a, b)
    let delta: Double = abs(shared - expected)
    return delta / mm2
}

/// Wall area less (outline less rooms), in square inches, counting the two crossings once.
private func cottageWallAreaError(_ footprints: [[Point2]], crossing: Double) -> Double {
    let inchTicks = Double(Length.inches(1).ticks)
    let ticksPerSquareInch: Double = inchTicks * inchTicks
    // Rooms are 168, 120, 144, 140, 100 and 120 SF: 792 SF.
    let rooms: Double = 792 * 144
    // Outline 38'-0" by 23'-6".
    let outline: Double = 456 * 282
    let areas: [Double] = footprints.map(area)
    let allWalls: Double = areas.reduce(0, +)
    let walls: Double = allWalls - 2 * crossing
    let wallInches: Double = walls / ticksPerSquareInch
    let open: Double = outline - rooms
    return wallInches - open
}

@Test func lHouseDrawsEveryWallIncludingTheInsideCorner() throws {
    let document = try fixture("l-house")
    let engine = HestiaGeometryEngine()
    for storey in document.storeys {
        let outlines = try engine.planView(of: document, storey: storey.id).filter { $0.kind == .wall }
        let walls = Set(document.walls.filter { $0.storeyID == storey.id }.map(\.id.rawValue))
        #expect(Set(outlines.map(\.elementID)) == walls)
        for outline in outlines { #expect(area(outline.polygon) > 0) }
        for i in outlines.indices { for j in outlines.indices where i < j {
            #expect(overlap(outlines[i].polygon, outlines[j].polygon) / mm2 < 1.0)
        } }
    }
}

@Test func openingsAtThePlanCutSplitTheWall() throws {
    let document = try fixture("rect-cottage")
    let outlines = try HestiaGeometryEngine().planView(of: document, storey: document.storeys[0].id)
    // South wall: front door and kitchen window both cross the 4'-0" cut plane.
    #expect(outlines.filter { $0.elementID == document.walls[0].id.rawValue }.count == 3)
    // North wall: the bath window sill is at 4'-6", above the cut, so only the bedroom window splits it.
    #expect(outlines.filter { $0.elementID == document.walls[2].id.rawValue }.count == 2)
    #expect(outlines.filter { $0.kind == .stair }.count == 1)
    #expect(outlines.filter { $0.kind == .wall }.allSatisfy { $0.classification == .cut })
}

@Test func roomAreasAreMeasuredFaceToFace() throws {
    let document = try fixture("rect-cottage")
    let areas = try HestiaGeometryEngine().roomAreas(of: document, storey: document.storeys[0].id)
    let footTicks = Double(Length.feet(1).ticks)
    let squareFoot = footTicks * footTicks
    func squareFeet(_ name: String) -> Double {
        let id = document.rooms.first { $0.name == name }!.id
        return Double(areas[id]!.tickSquares) / squareFoot
    }
    let living168 = abs(squareFeet("Living") - 168)
    #expect(living168 < 0.001)
    let bath100 = abs(squareFeet("Bath") - 100)
    #expect(bath100 < 0.001)
    let bedroom120 = abs(squareFeet("Bedroom 2") - 120)
    #expect(bedroom120 < 0.001)

    let house = try fixture("l-house")
    let ground = try HestiaGeometryEngine().roomAreas(of: house, storey: house.storeys[0].id)
    #expect(ground.count == 3)
    let living = house.rooms.first { $0.name == "Living" }!.id
    // 5 m by 6 m on centers, less half of each bounding wall (300 mm outside, 100 mm partitions): 4.8 m by 5.8 m.
    let livingArea = Double(ground[living]!.tickSquares) / mm2
    let expectedArea: Double = 4800 * 5800
    #expect(abs(livingArea - expectedArea) < 1.0)
}

@Test func unknownStoreyIsRefused() throws {
    let document = try fixture("rect-cottage")
    let missing = StoreyID(UUID())
    #expect(throws: CommandValidationError.storeyNotFound(missing)) {
        try HestiaGeometryEngine().planView(of: document, storey: missing)
    }
}
