@testable import ATDrawings
import ATContracts
import Foundation
import Testing

private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
private func ft(_ f: Int64) -> Length { .feet(f) }
private let wallID = WallID(uuid(10))
private let view = ViewTransform(scale: .quarterInch, modelOrigin: Point2(x: ft(0), y: ft(0)),
                                 paperOrigin: Point2(x: ft(0), y: ft(0)))

/// A wall along x from 0, 6" thick and 8' high.
private func wall(_ feet: Int64) -> Wall {
    Wall(id: wallID, storeyID: StoreyID(uuid(3)), start: Point2(x: ft(0), y: ft(0)), end: Point2(x: ft(feet), y: ft(0)),
         thickness: .inches(6), height: ft(8))
}

private func opening(at offset: Int64, width: Int64 = 3, _ kind: OpeningKind, swing: DoorSwing? = nil) -> Opening {
    Opening(id: OpeningID(uuid(20)), wallID: wallID, offsetAlongWall: ft(offset), width: ft(width),
            height: .feet(6, inchCount: 8), sillHeight: ft(0), kind: kind, swing: swing)
}

private func lines(_ items: [DisplayItem]) -> [(Point2, Point2)] {
    items.compactMap { if case let .line(start, end) = $0.primitive { return (start, end) } else { return nil } }
}

private func polylines(_ items: [DisplayItem]) -> [[Point2]] {
    items.compactMap { if case let .polyline(points, true) = $0.primitive { return points } else { return nil } }
}

/// A model point along the wall's centerline and across it, on paper.
private func paper(_ along: Length, _ across: Length) -> Point2 { view.paper(Point2(x: along, y: across)) }

@Test func aPocketDoorDrawsItsLeafInThePocketTowardTheWallStart() throws {
    let items = FloorPlanView.symbol(for: opening(at: 6, .pocketDoor), in: wall(20), view: view)
    // Two jambs, and no slide line down the middle.
    let jambs = lines(items)
    #expect(jambs.count == 2)
    #expect(jambs.allSatisfy { $0.0.x == $0.1.x })
    // One closed rectangle from 3' to 6', 1 1/2" in from each 3" face.
    let inset: Int64 = Length.sixtyFourthInches(96).ticks
    let leaf = try #require(polylines(items).first)
    #expect(polylines(items).count == 1)
    let expected: [Point2] = [paper(ft(3), Length(ticks: -inset)), paper(ft(6), Length(ticks: -inset)),
                              paper(ft(6), Length(ticks: inset)), paper(ft(3), Length(ticks: inset))]
    #expect(leaf == expected)
    #expect(items.allSatisfy { $0.style.layer == "A-DOOR" })
}

@Test func aPocketDoorNearTheWallStartPutsItsLeafTowardTheEnd() throws {
    // From 1' to 4': three feet toward the start would pass it, so the pocket runs 4' to 7'.
    let items = FloorPlanView.symbol(for: opening(at: 1, .pocketDoor), in: wall(20), view: view)
    let leaf = try #require(polylines(items).first)
    let xs: Set<Int64> = Set(leaf.map(\.x.ticks))
    #expect(xs == [paper(ft(4), ft(0)).x.ticks, paper(ft(7), ft(0)).x.ticks])
}

@Test func aPocketDoorWithNoRoomOnEitherSideDrawsOnlyItsJambs() throws {
    // A 5' wall with a 3' opening at 1': 2' would be left toward the start, 1' toward the end.
    let items = FloorPlanView.symbol(for: opening(at: 1, .pocketDoor), in: wall(5), view: view)
    #expect(polylines(items).isEmpty)
    #expect(lines(items).count == 2)
    #expect(FloorPlanView.pocketRun(opening: (1, 4), wallLength: 5) == nil)
}

@Test func otherDoorsKeepTheirSymbols() throws {
    // A sliding door keeps its center slide line.
    let sliding = FloorPlanView.symbol(for: opening(at: 6, .slidingDoor), in: wall(20), view: view)
    #expect(lines(sliding).count == 3)
    #expect(polylines(sliding).isEmpty)
    // A hinged door keeps its leaf and swing.
    let hinged = FloorPlanView.symbol(for: opening(at: 6, .singleDoor, swing: DoorSwing(hinge: .nearStart,
                                                                                        opensToward: .left)),
                                      in: wall(20), view: view)
    #expect(hinged.contains { if case .arc = $0.primitive { return true } else { return false } })
    #expect(polylines(hinged).isEmpty)
    // A cased opening stays two jambs.
    let cased = FloorPlanView.symbol(for: opening(at: 6, .casedOpening), in: wall(20), view: view)
    #expect(cased.count == 2)
}
