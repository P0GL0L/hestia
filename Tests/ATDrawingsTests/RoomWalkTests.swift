@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

private func fixture(_ name: String) throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/\(name).json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

private func ft(_ feet: Int64) -> Length { .feet(feet) }
private func pt(_ x: Int64, _ y: Int64) -> Point2 { Point2(x: ft(x), y: ft(y)) }
private func wallID(_ n: Int) -> WallID { WallID(UUID(uuidString: "00000000-0000-4000-8000-0000000000\(10 + n)")!) }

private let project = ProjectID(UUID(uuidString: "00000000-0000-4000-8000-000000000001")!)
private let building = BuildingID(UUID(uuidString: "00000000-0000-4000-8000-000000000002")!)
private let storey = StoreyID(UUID(uuidString: "00000000-0000-4000-8000-000000000003")!)
private let room = RoomID(UUID(uuidString: "00000000-0000-4000-8000-000000000004")!)

/// A 20' by 15' box of 6" walls, south, east, north, west, with one room bounded by `boundary` (indices into
/// that list) in the order given.
private func box(_ boundary: [Int]) throws -> ModelDocument {
    var document = ModelDocument(schemaVersion: 1, project: Project(id: project, name: "Box"),
                                 buildings: [], storeys: [], walls: [], openings: [], rooms: [])
    let corners: [Point2] = [pt(0, 0), pt(20, 0), pt(20, 15), pt(0, 15)]
    var commands: [AnyCommand] = [
        AddBuildingCommand(buildingID: building, name: "Box").erased,
        AddStoreyCommand(storeyID: storey, buildingID: building, name: "Ground Floor", elevation: ft(0)).erased,
    ]
    for i in 0..<4 {
        commands.append(AddWallCommand(wallID: wallID(i), storeyID: storey, start: corners[i],
                                       end: corners[(i + 1) % 4], thickness: .inches(6), height: ft(8)).erased)
    }
    commands.append(AddRoomCommand(roomID: room, storeyID: storey, name: "Room",
                                   boundaryWallIDs: boundary.map { wallID($0) }).erased)
    _ = try document.perform(batch: commands)
    return document
}

/// The room's tag and area label on the plan sheet, as (text, position).
private func tags(_ document: ModelDocument) throws -> [(String, Point2)] {
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let plan = try #require(sheets.first { $0.number == "A-101" })
    return plan.content.items.compactMap { item in
        guard item.elementID == room.rawValue, case let .text(position, string, _, _, _) = item.primitive else {
            return nil
        }
        return (string, position)
    }
}

@Test func aBoxStoredSouthNorthEastWestGetsItsTagAndArea() throws {
    // South, north, east, west: no wall touches the next, so the stored order meets parallel lines.
    let mixed = try tags(box([0, 2, 1, 3]))
    let walked = try tags(box([0, 1, 2, 3]))
    let mixedText: [String] = mixed.map(\.0)
    // Name, clear size (20' x 15' less 3" at each face), and area.
    #expect(mixedText == ["ROOM", "19'-6\" x 14'-6\"", "283 SF"])
    let walkedText: [String] = walked.map(\.0)
    #expect(mixedText == walkedText)
    // The same place as the box picked in order.
    let mixedPlaces: [Point2] = mixed.map(\.1)
    let walkedPlaces: [Point2] = walked.map(\.1)
    #expect(mixedPlaces == walkedPlaces)
}

@Test func theStoredBoundaryIsNotRewritten() throws {
    let document = try box([0, 2, 1, 3])
    _ = try tags(document)
    let stored: [WallID] = try #require(document.rooms.first).boundaryWallIDs
    #expect(stored == [wallID(0), wallID(2), wallID(1), wallID(3)])
}

@Test func aRoomThatDoesNotCloseStillGetsNoTag() throws {
    // South, east, north: the west side is open.
    let open = try tags(box([0, 1, 2]))
    #expect(open.isEmpty)
    let shuffled = try tags(box([2, 0, 1]))
    #expect(shuffled.isEmpty)
}

@Test func fixtureRoomsAlreadyWalkInTheirStoredOrder() throws {
    // So every tag that drew before draws in the same place.
    for name in ["rect-cottage", "l-house"] {
        let document = try fixture(name)
        var walls: [WallID: Wall] = [:]
        for wall in document.walls { walls[wall.id] = wall }
        for room in document.rooms {
            let boundary: [Wall] = room.boundaryWallIDs.compactMap { walls[$0] }
            let walk: [Wall]? = RoomWalk.ordered(boundary)
            let ids: [WallID]? = walk?.map(\.id)
            #expect(ids == room.boundaryWallIDs, "\(name) \(room.name)")
        }
    }
}

@Test func wallsMeetWhenOneStopsAtTheOthersFace() throws {
    let long = Wall(id: wallID(0), storeyID: storey, start: pt(0, 0), end: pt(20, 0), thickness: .inches(6),
                    height: ft(8))
    // A partition ending 3" short of the long wall's centerline, at its face.
    let face = Wall(id: wallID(1), storeyID: storey, start: Point2(x: ft(10), y: .inches(3)), end: pt(10, 10),
                    thickness: .inches(4), height: ft(8))
    #expect(RoomWalk.touches(long, face))
    let apart = Wall(id: wallID(2), storeyID: storey, start: pt(10, 1), end: pt(10, 10), thickness: .inches(4),
                     height: ft(8))
    #expect(!RoomWalk.touches(long, apart))
}
