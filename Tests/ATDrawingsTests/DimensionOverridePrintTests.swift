@testable import ATDrawings
import ATContracts
import Foundation
import Testing

private func cottage() throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/rect-cottage.json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

private let view = ViewTransform(scale: .quarterInch, modelOrigin: Point2(x: .feet(-1), y: .feet(-1)),
                                 paperOrigin: Point2(x: .millimeters(100), y: .millimeters(100)))

private func overrides(_ items: [DisplayItem]) -> [String] {
    items.compactMap { if case let .dimension(_, _, _, text) = $0.primitive { return text }; return nil }
}

@Test func roomOverridesPrintOnInteriorStrings() throws {
    var document = try cottage()
    let living = document.rooms[0].id.rawValue
    _ = try document.perform(SetDimensionOverrideCommand(elementID: living, face: .width, text: "14'-0\" CLR").erased)
    let items = DimensionChains.interiorItems(document: document, storey: document.storeys[0].id, view: view)
    let livingTexts = items.filter { $0.elementID == living }.map { item -> String? in
        if case let .dimension(_, _, _, text) = item.primitive { return text }; return nil
    }
    #expect(livingTexts == ["14'-0\" CLR", nil])
    #expect(overrides(items) == ["14'-0\" CLR"])
}

@Test func wallOverridesPrintOnlyOnASegmentThatIsExactlyThatWall() throws {
    var document = try cottage()
    let southWall = document.walls[0].id.rawValue
    let westWall = document.walls[3].id.rawValue
    _ = try document.perform(SetDimensionOverrideCommand(elementID: southWall, face: .south, text: "38'-0\" VIF").erased)
    // A partition's segment is not one wall on its own, so this override stays unprinted.
    _ = try document.perform(SetDimensionOverrideCommand(elementID: document.walls[4].id.rawValue, face: .south,
                                                         text: "NOT PRINTED").erased)
    // The west wall spans the whole west face too, but its override is for the west face only.
    _ = try document.perform(SetDimensionOverrideCommand(elementID: westWall, face: .south, text: "WRONG FACE").erased)
    let items = DimensionChains.items(document: document, storey: document.storeys[0].id, view: view)
    #expect(overrides(items) == ["38'-0\" VIF"])
    let segment = try #require(items.first {
        if case .dimension(_, _, _, "38'-0\" VIF") = $0.primitive { return true }; return false
    })
    guard case let .dimension(from, to, _, _) = segment.primitive else { return }
    #expect(to.x.ticks - from.x.ticks == DrawingScale.quarterInch.paper(.feet(38)).ticks)
}

@Test func openingWidthOverridesPrintInTheScheduleNotOnTheChain() throws {
    var document = try cottage()
    let frontDoor = document.openings[0].id.rawValue
    _ = try document.perform(SetDimensionOverrideCommand(elementID: frontDoor, face: .width, text: "3'-0\" RO").erased)
    let chains = DimensionChains.items(document: document, storey: document.storeys[0].id, view: view)
    #expect(overrides(chains).isEmpty)
    let doors = try #require(ScheduleView.table(.doors, document: document, style: .feetInchesFractions, areas: [:]))
    #expect(doors.rows[0][2] == "3'-0\" RO")
    #expect(doors.rows[1][2] == "3'-0\"")
}

@Test func clearingAnOverridePrintsTheMeasuredValueAgain() throws {
    var document = try cottage()
    let living = document.rooms[0].id.rawValue
    _ = try document.perform(SetDimensionOverrideCommand(elementID: living, face: .depth, text: "VERIFY").erased)
    _ = try document.perform(ClearDimensionOverrideCommand(elementID: living, face: .depth).erased)
    let items = DimensionChains.interiorItems(document: document, storey: document.storeys[0].id, view: view)
    #expect(overrides(items).isEmpty)
}
