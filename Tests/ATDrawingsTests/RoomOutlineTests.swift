import ATContracts
import ATDrawings
import Foundation
import Testing

private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
private func pt(_ x: Int64, _ y: Int64) -> Point2 { Point2(x: .feet(x), y: .feet(y)) }

/// A 20' by 15' box of 6" walls, with one room bounded by `boundary` (indices into south, east, north, west).
private func box(_ boundary: [Int]) throws -> (ModelDocument, Room) {
    var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(uuid(1)), name: "Box"),
                                 buildings: [], storeys: [], walls: [], openings: [], rooms: [])
    let corners: [Point2] = [pt(0, 0), pt(20, 0), pt(20, 15), pt(0, 15)]
    var commands: [AnyCommand] = [
        AddBuildingCommand(buildingID: BuildingID(uuid(2)), name: "Box").erased,
        AddStoreyCommand(storeyID: StoreyID(uuid(3)), buildingID: BuildingID(uuid(2)), name: "Ground",
                         elevation: .feet(0)).erased,
    ]
    for i in 0..<4 {
        commands.append(AddWallCommand(wallID: WallID(uuid(10 + i)), storeyID: StoreyID(uuid(3)), start: corners[i],
                                       end: corners[(i + 1) % 4], thickness: .inches(6), height: .feet(8)).erased)
    }
    commands.append(AddRoomCommand(roomID: RoomID(uuid(4)), storeyID: StoreyID(uuid(3)), name: "Room",
                                   boundaryWallIDs: boundary.map { WallID(uuid(10 + $0)) }).erased)
    _ = try document.perform(batch: commands)
    return (document, try #require(document.rooms.first))
}

@Test func aClosedRoomsOutlineIsItsCenterlineCorners() throws {
    // Stored south, north, east, west: the outline still walks around the room.
    let (document, room) = try box([0, 2, 1, 3])
    let outline = try #require(RoomOutline.centerline(of: room, in: document))
    #expect(Set(outline) == Set([pt(0, 0), pt(20, 0), pt(20, 15), pt(0, 15)]))
    #expect(outline.count == 4)
}

@Test func aRoomThatDoesNotCloseHasNoOutline() throws {
    let (document, room) = try box([0, 1, 2])
    #expect(RoomOutline.centerline(of: room, in: document) == nil)
}
