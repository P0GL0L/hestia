import ATContracts
import ATGeometry
import Foundation
import Testing

private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
private let storey = StoreyID(uuid(3))
private let room = RoomID(uuid(9))
private func ft(_ f: Int64, _ i: Int64 = 0) -> Length { .feet(f, inchCount: i) }
private func p(_ x: Length, _ y: Length) -> Point2 { Point2(x: x, y: y) }

/// A box 10' by 12' clear inside 6" walls (centerlines 3" out), its south side either whole or split around a
/// 3' gap from 4' to 7'. `order` names the walls the room lists, in order.
private struct Box {
    var southThicknesses: (Length, Length) = (.inches(6), .inches(6))
    var reversed = false

    func walls() -> [String: (Point2, Point2, Length)] {
        let lo = Length.inches(-3), east = ft(10, 3), north = ft(12, 3)
        var s1 = (p(lo, lo), p(ft(4), lo)), s2 = (p(ft(7), lo), p(east, lo))
        if reversed { s1 = (s1.1, s1.0); s2 = (s2.1, s2.0) }
        return [
            "S": (p(lo, lo), p(east, lo), .inches(6)),
            "S1": (s1.0, s1.1, southThicknesses.0),
            "S2": (s2.0, s2.1, southThicknesses.1),
            "E": (p(east, lo), p(east, north), .inches(6)),
            "N": (p(east, north), p(lo, north), .inches(6)),
            "W": (p(lo, north), p(lo, lo), .inches(6)),
        ]
    }

    func area(_ order: [String]) throws -> Area? {
        var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(uuid(1)), name: "Box"),
                                     buildings: [], storeys: [], walls: [], openings: [], rooms: [])
        var commands: [AnyCommand] = [
            AddBuildingCommand(buildingID: BuildingID(uuid(2)), name: "Box").erased,
            AddStoreyCommand(storeyID: storey, buildingID: BuildingID(uuid(2)), name: "Ground", elevation: ft(0)).erased,
        ]
        var ids: [String: WallID] = [:]
        for (index, key) in order.enumerated() {
            guard let wall = walls()[key] else { continue }
            let id = WallID(uuid(20 + index))
            ids[key] = id
            commands.append(AddWallCommand(wallID: id, storeyID: storey, start: wall.0, end: wall.1,
                                           thickness: wall.2, height: ft(8)).erased)
        }
        commands.append(AddRoomCommand(roomID: room, storeyID: storey, name: "Room",
                                       boundaryWallIDs: order.compactMap { ids[$0] }).erased)
        _ = try document.perform(batch: commands)
        return try HestiaGeometryEngine().roomAreas(of: document, storey: storey)[room]
    }
}

private let tenByTwelve: Int64 = ft(10).ticks * ft(12).ticks

@Test func aWholeBoxKeepsItsArea() throws {
    let area = try #require(try Box().area(["S", "E", "N", "W"]))
    #expect(area.tickSquares == tenByTwelve)
}

@Test func aSideSplitAroundAnOpeningStillGetsTheArea() throws {
    let area = try #require(try Box().area(["S1", "S2", "E", "N", "W"]))
    #expect(area.tickSquares == tenByTwelve)
}

@Test func aSplitSideThatWrapsFromLastToFirstIsOneSide() throws {
    let area = try #require(try Box().area(["S2", "E", "N", "W", "S1"]))
    #expect(area.tickSquares == tenByTwelve)
}

@Test func splitPiecesDrawnTheOtherWayAreStillOneSide() throws {
    let area = try #require(try Box(reversed: true).area(["S1", "S2", "E", "N", "W"]))
    #expect(area.tickSquares == tenByTwelve)
}

@Test func aRoomThatDoesNotCloseStillGetsNoArea() throws {
    let area: Area? = try Box().area(["S1", "S2", "E", "N"])
    #expect(area == nil)
}

@Test func collinearPiecesOfDifferentThicknessGetNoArea() throws {
    let box = Box(southThicknesses: (.inches(6), .inches(4)))
    let area: Area? = try box.area(["S1", "S2", "E", "N", "W"])
    #expect(area == nil)
}
