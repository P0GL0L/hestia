import ATContracts
import Foundation
import Testing

extension Sample {
    static let finishes: [AnyCommand] = [
        SetRoomFinishCommand(roomID: room, surface: .floor, finish: "Oak strip flooring").erased,
        SetRoomFinishCommand(roomID: room, surface: .wall, finish: "").erased,
        SetRoomFinishCommand(roomID: room, surface: .ceiling, finish: "Gypsum board, flat paint").erased,
    ]
}

@Test func finishesAreSetTrimmedAndClearedByEmptyText() throws {
    var document = Sample.document()
    _ = try document.perform(SetRoomFinishCommand(roomID: Sample.room, surface: .floor, finish: "  Tile ").erased)
    #expect(document.rooms[0].floorFinish == "Tile")
    _ = try document.perform(SetRoomFinishCommand(roomID: Sample.room, surface: .wall, finish: "   ").erased)
    #expect(document.rooms[0].wallFinish == nil)
    #expect(document.rooms[0].finish(.floor) == "Tile")
    #expect(document.rooms[0].finish(.ceiling) == nil)
}

@Test func unknownRoomIsRefused() {
    expectRefused(.roomNotFound(Sample.newRoom),
                  SetRoomFinishCommand(roomID: Sample.newRoom, surface: .floor, finish: "Tile"))
}

@Test func removingARoomUndoesWithItsFinishes() throws {
    var document = Sample.document()
    _ = try document.perform(SetRoomFinishCommand(roomID: Sample.room, surface: .floor, finish: "Tile").erased)
    let before = document
    let inverse = try document.perform(RemoveRoomCommand(roomID: Sample.room).erased)
    _ = try document.perform(inverse)
    #expect(document == before)
}

@Test func roomsWithoutFinishesStillDecodeAndEncodeWithoutThem() throws {
    let json = Data(#"{"id": "00000000-0000-4000-8000-000000000040", "storeyID": "00000000-0000-4000-8000-000000000010", "name": "Den", "boundaryWallIDs": []}"#.utf8)
    let room = try JSONDecoder().decode(Room.self, from: json)
    #expect(room.floorFinish == nil && room.wallFinish == nil && room.ceilingFinish == nil)
    let encoded = String(decoding: try ModelDocument.makeJSONEncoder().encode(room), as: UTF8.self)
    #expect(!encoded.contains("Finish"))
}
