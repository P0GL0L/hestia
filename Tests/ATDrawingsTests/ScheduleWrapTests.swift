@testable import ATDrawings
import ATContracts
import Testing

@Test func aLongScheduleContinuesInColumnsInsideItsHeight() throws {
    let rows = (1...60).map { ["W\($0)", "Window", "3'-0\"", "4'-0\"", "2'-6\""] }
    let table = ScheduleView.Table(title: "Window schedule",
                                   columns: [("MARK", mmTicks(15)), ("TYPE", mmTicks(40)), ("WIDTH", mmTicks(20)),
                                             ("HEIGHT", mmTicks(20)), ("SILL", mmTicks(20))],
                                   rows: rows)
    let top = mmTicks(400), height = mmTicks(200)
    let items = ScheduleView.items(table, at: paperPoint(mmTicks(20), top), height: height)
    let texts: [(String, Point2)] = items.compactMap { item in
        guard case let .text(position, string, _, _, _) = item.primitive else { return nil }
        return (string, position)
    }
    // Every row is drawn once, and nothing falls below the height given.
    for row in rows {
        #expect(texts.filter { $0.0 == row[0] }.count == 1, "\(row[0]) is drawn once")
    }
    #expect(texts.allSatisfy { $0.1.y.ticks >= top - height })
    // It took more than one column, each headed again, under one title.
    #expect(texts.filter { $0.0 == "MARK" }.count >= 2)
    #expect(texts.filter { $0.0 == "WINDOW SCHEDULE" }.count == 1)
    // Without a height, it stays one column.
    let single = ScheduleView.items(table, at: paperPoint(mmTicks(20), top))
    #expect(single.filter { if case .text(_, "MARK", _, _, _) = $0.primitive { return true }; return false }.count == 1)
}
