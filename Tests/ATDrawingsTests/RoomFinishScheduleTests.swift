@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

private func cottage() throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/rect-cottage.json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

@Test func finishScheduleListsEveryRoomWithDashesForUnrecordedFinishes() throws {
    let document = try cottage()
    let table = try #require(ScheduleView.table(.roomFinishes, document: document, style: .feetInchesFractions,
                                                areas: [:]))
    #expect(table.columns.map(\.name) == ["ROOM", "STOREY", "FLOOR", "WALLS", "CEILING"])
    #expect(table.rows.count == 6)
    #expect(table.rows.allSatisfy { Array($0.suffix(3)) == ["-", "-", "-"] })
}

@Test func finishScheduleShowsRecordedFinishes() throws {
    var document = try cottage()
    let bath = try #require(document.rooms.first { $0.name == "Bath" }).id
    _ = try document.perform(batch: [
        SetRoomFinishCommand(roomID: bath, surface: .floor, finish: "Porcelain tile").erased,
        SetRoomFinishCommand(roomID: bath, surface: .wall, finish: "Tile wainscot, paint above").erased,
    ])
    let table = try #require(ScheduleView.table(.roomFinishes, document: document, style: .metric, areas: [:]))
    let row = try #require(table.rows.first { $0[0] == "Bath" })
    #expect(row == ["Bath", "Ground Floor", "Porcelain tile", "Tile wainscot, paint above", "-"])
}

@Test func finishScheduleSheetIsDrawnAndStamped() throws {
    var document = try cottage()
    document.sheets = [Sheet(id: SheetID(UUID()), number: "A-602", title: "Finishes", paper: .archD, scale: nil,
                             views: [.schedule(kind: .roomFinishes)])]
    let sheet = try SchematicDrawingSet().sheets(for: document, geometry: MockGeometryEngine())[0]
    let text = sheet.content.items.compactMap { item -> String? in
        if case let .text(_, s, _, _, _) = item.primitive { return s }; return nil
    }
    #expect(text.contains("ROOM FINISH SCHEDULE"))
    #expect(text.contains("NOT FOR CONSTRUCTION"))
    #expect(!text.contains { $0.contains("not generated") })
}

@Test func defaultSetSchedulesAreasAndFinishesOnlyWhenNamed() throws {
    var document = try cottage()
    document.sheets = []
    func schedules(_ document: ModelDocument) throws -> [String] {
        let sheets = try SchematicDrawingSet().sheets(for: document, geometry: MockGeometryEngine())
        let schedule = try #require(sheets.first { $0.number == "A-601" })
        return schedule.content.items.compactMap { item -> String? in
            if case let .text(_, s, _, _, _) = item.primitive, s.hasSuffix("SCHEDULE") { return s }; return nil
        }
    }
    // Rooms always get an area schedule; no room names a finish yet, so there is no finish schedule.
    #expect(try schedules(document) == ["DOOR SCHEDULE", "WINDOW SCHEDULE", "AREA SCHEDULE"])
    let bath = try #require(document.rooms.first { $0.name == "Bath" }).id
    _ = try document.perform(SetRoomFinishCommand(roomID: bath, surface: .floor, finish: "Porcelain tile").erased)
    #expect(try schedules(document) == ["DOOR SCHEDULE", "WINDOW SCHEDULE", "AREA SCHEDULE", "ROOM FINISH SCHEDULE"])
}

@Test func roomsWithoutOpeningsStillGetTheAreaSchedule() throws {
    var document = try cottage()
    document.sheets = []
    for opening in document.openings {
        _ = try document.perform(RemoveOpeningCommand(openingID: opening.id).erased)
    }
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: MockGeometryEngine())
    let schedule = try #require(sheets.first { $0.number == "A-601" })
    #expect(schedule.content.items.contains { item in
        if case let .text(_, s, _, _, _) = item.primitive { return s == "AREA SCHEDULE" }; return false
    })
}

/// The rows A-601 prints, worked out by hand from the cottage's walls: each room's area inside its 6" walls'
/// faces (the Living room's centrelines are 14'-6" by 12'-6", so 14' by 12' inside, 168 SF), and the one floor
/// finish named.
@Test func areaAndFinishRowsPrintEachRoomsFigures() throws {
    var document = try cottage()
    document.sheets = []
    let bath = try #require(document.rooms.first { $0.name == "Bath" }).id
    _ = try document.perform(SetRoomFinishCommand(roomID: bath, surface: .floor, finish: "Porcelain tile").erased)
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let schedule = try #require(sheets.first { $0.number == "A-601" })
    var texts: [String] = []
    for item in schedule.content.items {
        if case let .text(_, text, _, _, _) = item.primitive { texts.append(text) }
    }
    let areas = try #require(texts.firstIndex(of: "AREA SCHEDULE"))
    let finishes = try #require(texts.firstIndex(of: "ROOM FINISH SCHEDULE"))
    let areaRows = Array(texts[(areas + 4)..<finishes])
    #expect(areaRows == [
        "Living", "Ground Floor", "168 SF", "Kitchen", "Ground Floor", "120 SF",
        "Utility", "Ground Floor", "144 SF", "Bedroom", "Ground Floor", "140 SF",
        "Bath", "Ground Floor", "100 SF", "Bedroom 2", "Ground Floor", "120 SF",
    ])
    let finishRows = Array(texts[(finishes + 6)...].prefix(30))
    let bathRow = try #require(finishRows.firstIndex(of: "Bath"))
    #expect(Array(finishRows[bathRow..<(bathRow + 5)]) == ["Bath", "Ground Floor", "Porcelain tile", "-", "-"])
    #expect(finishRows.filter { $0 == "Porcelain tile" }.count == 1)
}
