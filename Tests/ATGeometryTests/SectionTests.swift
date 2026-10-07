@testable import ATGeometry
import ATContracts
import Foundation
import Testing

private func fixture(_ name: String) throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/\(name).json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

private func feet(_ x: Int64, _ y: Int64) -> Point2 { Point2(x: .feet(x), y: .feet(y)) }

/// (left, right, bottom, top) of an outline, in ticks.
private func bounds(_ outline: ClassifiedOutline) -> [Int64] {
    let xs: [Int64] = outline.polygon.map(\.x.ticks)
    let ys: [Int64] = outline.polygon.map(\.y.ticks)
    return [xs.min()!, xs.max()!, ys.min()!, ys.max()!]
}

/// The (bottom, top) bands of an element's cut outlines, lowest first.
private func bands(_ outlines: [ClassifiedOutline], _ id: UUID) -> [[Int64]] {
    let mine = outlines.filter { $0.elementID == id && $0.classification == .cut }
    let pairs: [[Int64]] = mine.map { outline in
        let b = bounds(outline)
        return [b[2], b[3]]
    }
    return pairs.sorted { $0[0] < $1[0] }
}

private func inches(_ n: Int64) -> Int64 { Length.inches(n).ticks }

@Test func longSectionCutsTheCrossWallsAndSeesTheMiddleWallBeyond() throws {
    let document = try fixture("rect-cottage")
    let line = SectionLine(start: feet(-2, 6), end: feet(40, 6))
    let outlines = try HestiaGeometryEngine().section(of: document, along: line)
    let cutWalls = Set(outlines.filter { $0.kind == .wall && $0.classification == .cut }.map(\.elementID))
    let crossIndices = [3, 4, 5, 1]
    let crossWalls = Set(crossIndices.map { document.walls[$0].id.rawValue })
    #expect(cutWalls == crossWalls)
    // The west wall is 6" thick on the -3" line, 1'-6" to 2'-0" along a line starting at -2'-0".
    let west = outlines.first { $0.elementID == document.walls[3].id.rawValue }!
    #expect(bounds(west)[0] == inches(18))
    #expect(bounds(west)[1] == inches(24))
    // Its window runs from 3'-0" to 7'-0" where the line crosses it, leaving a sill and a head.
    let westBands: [[Int64]] = [[0, inches(36)], [inches(84), inches(96)]]
    #expect(bands(outlines, document.walls[3].id.rawValue) == westBands)
    // The middle wall is seen beyond with its three doors; the north wall behind it is hidden.
    let middle = document.walls[6].id.rawValue
    #expect(outlines.contains { $0.elementID == middle && $0.classification == .beyond })
    let doorsBeyond: [ClassifiedOutline] = outlines.filter { $0.kind == .opening }
    #expect(doorsBeyond.count == 3)
    #expect(doorsBeyond.allSatisfy { $0.classification == .beyond })
    #expect(!outlines.contains { $0.elementID == document.walls[2].id.rawValue })
    // The roof is cut along the south slope: 8'-0" at the outer eave, and 7'-3" in from it at 6:12 it is
    // 3'-7 1/2" higher, 11'-7 1/2".
    let roof = try #require(outlines.first { $0.kind == .roof })
    let halfInch: Int64 = inches(1) / 2
    #expect(bounds(roof)[3] == inches(139) + halfInch)
    let thickness = Length.millimeters(250).ticks
    #expect(bounds(roof)[2] == Length.feet(8).ticks - thickness)
    let slabs: [ClassifiedOutline] = outlines.filter { $0.kind == .slab }
    #expect(slabs.count == 1)
}

@Test func crossSectionCutsWindowsAndDoorsWhereTheLinePasses() throws {
    let document = try fixture("rect-cottage")
    let line = SectionLine(start: feet(18, -3), end: feet(18, 26))
    let outlines = try HestiaGeometryEngine().section(of: document, along: line)
    // South wall: the kitchen window, sill 3'-0", head 7'-0".
    let southBands: [[Int64]] = [[0, inches(36)], [inches(84), inches(96)]]
    #expect(bands(outlines, document.walls[0].id.rawValue) == southBands)
    // North wall: the bath window, sill 4'-6", head 6'-6".
    let northBands: [[Int64]] = [[0, inches(54)], [inches(78), inches(96)]]
    #expect(bands(outlines, document.walls[2].id.rawValue) == northBands)
    // Middle wall: the pocket door leaves only its head above 6'-8".
    let middleBands: [[Int64]] = [[inches(80), inches(96)]]
    #expect(bands(outlines, document.walls[6].id.rawValue) == middleBands)
    // Looking west, the nearest partition shows beyond with its door; the west wall behind it is hidden.
    #expect(outlines.contains { $0.elementID == document.walls[4].id.rawValue && $0.classification == .beyond })
    let openings: [ClassifiedOutline] = outlines.filter { $0.kind == .opening }
    #expect(openings.count == 1)
    #expect(!outlines.contains { $0.elementID == document.walls[3].id.rawValue })
    // The hip roof peaks at the 14'-3" ridge over the middle of the 23'-0" depth.
    let roof = try #require(outlines.first { $0.kind == .roof })
    let peak = try #require(roof.polygon.max { $0.y.ticks < $1.y.ticks })
    #expect(peak.y == .feet(14, inchCount: 3))
}

@Test func stairIsCutToItsSteps() throws {
    let document = try fixture("rect-cottage")
    // Up the stair's run, from the south wall's inner face.
    let line = SectionLine(start: feet(27, 0), end: feet(27, 12))
    let outlines = try HestiaGeometryEngine().section(of: document, along: line)
    let stairs = outlines.filter { $0.kind == .stair }
    #expect(stairs.count == 1)
    let stair = try #require(stairs.first)
    // 11 treads of 10" from 1'-0", each 8" higher: a bottom edge and two corners per tread.
    let expectedPoints: Int = 24
    #expect(stair.polygon.count == expectedPoints)
    let stairBounds: [Int64] = [inches(12), inches(122), 0, inches(88)]
    #expect(bounds(stair) == stairBounds)
    #expect(stair.polygon.contains(Point2(x: .inches(22), y: .inches(16))))
}

@Test func upperStoreySitsOnItsElevation() throws {
    let document = try fixture("l-house")
    let line = SectionLine(start: Point2(x: .millimeters(-1000), y: .millimeters(2000)),
                           end: Point2(x: .millimeters(11000), y: .millimeters(2000)))
    let outlines = try HestiaGeometryEngine().section(of: document, along: line)
    let upper = try #require(document.storeys.last)
    let upperWalls = Set(document.walls.filter { $0.storeyID == upper.id }.map(\.id.rawValue))
    let upperCuts = outlines.filter { upperWalls.contains($0.elementID) && $0.classification == .cut }
    #expect(upperCuts.count >= 3)
    for outline in upperCuts { #expect(bounds(outline)[2] >= upper.elevation.ticks) }
    let slabs: [ClassifiedOutline] = outlines.filter { $0.kind == .slab }
    #expect(slabs.count == 2)
    // Parallel to the south wing's ridge, the roof is level where the south slope is the lowest plane.
    let roof = try #require(outlines.first { $0.kind == .roof })
    let mm = Length.ticksPerMillimeter
    let eave: Int64 = upper.elevation.ticks + document.roofs[0].eaveHeight.ticks
    // 2 m in from the south wall plus the 450 mm overhang, at 6:12: 1225 mm above the eave.
    let rise: Int64 = 1_225 * mm
    #expect(bounds(roof)[3] == eave + rise)
}

@Test func gableRoofIsCutToItsTriangle() throws {
    let storey = StoreyID(UUID())
    let mm = { (x: Int64, y: Int64) in Point2(x: .millimeters(x), y: .millimeters(y)) }
    let pitched = RoofPlane(pitchRisePer12: .inches(6), overhang: .millimeters(0))
    let gable = RoofPlane(pitchRisePer12: nil, overhang: .millimeters(0))
    let roof = Roof(id: RoofID(UUID()), storeyID: storey,
                    footprint: [mm(0, 0), mm(10_000, 0), mm(10_000, 6_000), mm(0, 6_000)],
                    eaveHeight: .millimeters(2_400), planes: [pitched, gable, pitched, gable])
    let building = BuildingID(UUID())
    let ground = Storey(id: storey, buildingID: building, name: "Ground", elevation: .millimeters(0))
    let document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(UUID()), name: "Gable"),
                                 buildings: [], storeys: [ground], walls: [], openings: [], rooms: [],
                                 roofs: [roof])
    let across = SectionLine(start: mm(5_000, -1_000), end: mm(5_000, 7_000))
    let cut = try #require(try HestiaGeometryEngine().section(of: document, along: across).first)
    #expect(cut.polygon.contains(mm(4_000, 3_900)))
    #expect(cut.polygon.contains(mm(1_000, 2_400)))
    #expect(cut.polygon.contains(mm(7_000, 2_400)))
    // Along the ridge the cut is level and stops square at both gable ends.
    let along = SectionLine(start: mm(-1_000, 3_000), end: mm(11_000, 3_000))
    let ridge = try #require(try HestiaGeometryEngine().section(of: document, along: along).first)
    let ridgeBox: Set<Point2> = [mm(1_000, 3_650), mm(11_000, 3_650), mm(11_000, 3_900), mm(1_000, 3_900)]
    #expect(Set(ridge.polygon) == ridgeBox)
}

@Test func emptyAndDegenerateLinesHaveNoSection() throws {
    let document = try fixture("rect-cottage")
    let engine = HestiaGeometryEngine()
    let point = feet(5, 5)
    #expect(try engine.section(of: document, along: SectionLine(start: point, end: point)).isEmpty)
    let far = SectionLine(start: feet(100, 100), end: feet(120, 100))
    #expect(try engine.section(of: document, along: far).isEmpty)
}
