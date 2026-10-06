@testable import ATDrawings
import ATContracts
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
