import ATContracts
import Foundation
import Testing

extension Sample {
    static let rooms: [AnyCommand] = [
        AddRoomCommand(roomID: newRoom, storeyID: storey, name: "Hall", boundaryWallIDs: [wallSpare], index: 0).erased,
        RenameRoomCommand(roomID: room, newName: "Lounge").erased,
        SetRoomBoundaryCommand(roomID: room, boundaryWallIDs: [wallSouth, wallSpare, wallEast]).erased,
        RemoveRoomCommand(roomID: room).erased,
    ]
}

@Test func roomBoundariesMustBeValid() throws {
    expectRefused(.roomBoundaryInvalid, SetRoomBoundaryCommand(roomID: Sample.room, boundaryWallIDs: []))
    expectRefused(.roomBoundaryInvalid,
                  SetRoomBoundaryCommand(roomID: Sample.room, boundaryWallIDs: [Sample.wallEast, Sample.wallEast]))
    expectRefused(.wallNotFound(Sample.newWall),
                  SetRoomBoundaryCommand(roomID: Sample.room, boundaryWallIDs: [Sample.newWall]))

    var document = Sample.document()
    _ = try AddWallCommand(
        wallID: Sample.newWall, storeyID: Sample.emptyStorey, start: Sample.point(0, 0), end: Sample.point(1000, 0),
        thickness: .millimeters(100), height: .millimeters(2400)
    ).apply(to: &document)
    #expect(throws: CommandValidationError.wallOnOtherStorey(Sample.newWall)) {
        try SetRoomBoundaryCommand(roomID: Sample.room, boundaryWallIDs: [Sample.newWall]).validate(against: document)
    }
}

@Test func roomIDsAndNamesAreChecked() {
    expectRefused(.duplicateID(Sample.room.rawValue), AddRoomCommand(
        roomID: Sample.room, storeyID: Sample.storey, name: "Copy", boundaryWallIDs: [Sample.wallEast]
    ))
    expectRefused(.nameEmpty, RenameRoomCommand(roomID: Sample.room, newName: "   "))
    expectRefused(.roomNotFound(Sample.newRoom), RemoveRoomCommand(roomID: Sample.newRoom))
}

@Test func wallBoundingARoomCannotBeRemoved() {
    expectRefused(.hasDependents(Sample.wallEast.rawValue), RemoveWallCommand(wallID: Sample.wallEast))
}

/// The order an agent must use to delete a wall that hosts a door and bounds a room, undone in one step.
@Test func batchRemovesWallWithItsDependentsAndUndoes() throws {
    let original = Sample.document()
    var document = original
    let inverse = try document.perform(batch: [
        RemoveOpeningCommand(openingID: Sample.door).erased,
        SetRoomBoundaryCommand(roomID: Sample.room, boundaryWallIDs: [Sample.wallEast]).erased,
        RemoveWallCommand(wallID: Sample.wallSouth).erased,
    ])
    #expect(document.walls.map(\.id) == [Sample.wallSpare, Sample.wallEast])
    #expect(document.openings.isEmpty)
    _ = try document.perform(batch: inverse)
    #expect(document == original)
}

@Test func batchRefusedPartWayLeavesDocumentUnchanged() throws {
    let original = Sample.document()
    var document = original
    #expect(throws: CommandValidationError.hasDependents(Sample.wallSouth.rawValue)) {
        try document.perform(batch: [
            RenameRoomCommand(roomID: Sample.room, newName: "Den").erased,
            RemoveWallCommand(wallID: Sample.wallSouth).erased,
        ])
    }
    #expect(document == original)
}
