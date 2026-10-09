import ATContracts
import ATGeometry
import Foundation
import Testing

private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
private func ft(_ f: Int64) -> Length { .feet(f) }
private let storey = StoreyID(uuid(3))
private let wall = WallID(uuid(10))

/// One 20' wall along x, 6" thick and 8' high, with the given openings as (offset, width, sill, height) in feet.
private func plan(_ openings: [(Int64, Int64, Int64, Int64, OpeningKind)]) throws -> [ClassifiedOutline] {
    var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(uuid(1)), name: "Wall"),
                                 buildings: [], storeys: [], walls: [], openings: [], rooms: [])
    var commands: [AnyCommand] = [
        AddBuildingCommand(buildingID: BuildingID(uuid(2)), name: "Wall").erased,
        AddStoreyCommand(storeyID: storey, buildingID: BuildingID(uuid(2)), name: "Ground", elevation: ft(0)).erased,
        AddWallCommand(wallID: wall, storeyID: storey, start: Point2(x: ft(0), y: ft(0)),
                       end: Point2(x: ft(20), y: ft(0)), thickness: .inches(6), height: ft(8)).erased,
    ]
    for (i, o) in openings.enumerated() {
        let swing: DoorSwing? = o.4.isDoor ? DoorSwing(hinge: .nearStart, opensToward: .left) : nil
        commands.append(AddOpeningCommand(openingID: OpeningID(uuid(20 + i)), wallID: wall, offsetAlongWall: ft(o.0),
                                          width: ft(o.1), height: ft(o.3), sillHeight: ft(o.2), kind: o.4,
                                          swing: swing).erased)
    }
    _ = try document.perform(batch: commands)
    // The engine's default cut is 4'-0".
    return try HestiaGeometryEngine().planView(of: document, storey: storey).filter { $0.kind == .wall }
}

/// Each piece as its classification and its extent along the wall, in whole feet, west to east.
private func spans(_ outlines: [ClassifiedOutline]) -> [(OutlineClassification, Int64, Int64)] {
    let foot = Length.feet(1).ticks
    return outlines.map { outline in
        let xs: [Int64] = outline.polygon.map(\.x.ticks)
        let low: Int64 = xs.min() ?? 0, high: Int64 = xs.max() ?? 0
        // Round outward to the foot: the wall's ends stick out by half its thickness past 0' and 20'.
        return (outline.classification, (low + foot / 2) / foot, (high + foot / 2) / foot)
    }.sorted { $0.1 < $1.1 }
}

private func same(_ a: [(OutlineClassification, Int64, Int64)], _ b: [(OutlineClassification, Int64, Int64)]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
}

@Test func aWindowTheCutPassesThroughStillLeavesAGap() throws {
    // Sill 3', head 7': the 4' cut crosses it.
    let pieces = spans(try plan([(8, 4, 3, 4, .window)]))
    #expect(same(pieces, [(.cut, 0, 8), (.cut, 12, 20)]))
}

@Test func aWindowAboveTheCutSplitsTheWallAndIsSeenBeyond() throws {
    // Sill 5', head 7'.
    let pieces = spans(try plan([(8, 4, 5, 2, .window)]))
    #expect(same(pieces, [(.cut, 0, 8), (.beyond, 8, 12), (.cut, 12, 20)]))
}

@Test func aSillExactlyAtTheCutCountsAsAbove() throws {
    let pieces = spans(try plan([(8, 4, 4, 3, .window)]))
    #expect(same(pieces, [(.cut, 0, 8), (.beyond, 8, 12), (.cut, 12, 20)]))
}

@Test func anOpeningWhollyBelowTheCutLeavesTheWallWhole() throws {
    // Sill 1', head exactly at the 4' cut.
    let pieces = spans(try plan([(8, 4, 1, 3, .window)]))
    #expect(same(pieces, [(.cut, 0, 20)]))
}

@Test func aDoorAndAHighWindowOnOneWall() throws {
    let pieces = spans(try plan([(2, 3, 0, 7, .singleDoor), (10, 4, 5, 2, .window)]))
    #expect(same(pieces, [(.cut, 0, 2), (.cut, 5, 10), (.beyond, 10, 14), (.cut, 14, 20)]))
}
