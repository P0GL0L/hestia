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

private func sheet(_ number: String, of document: ModelDocument) throws -> SheetDrawing {
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    return try #require(sheets.first { $0.number == number })
}

private func items(_ sheet: SheetDrawing, layer: String, element: UUID) -> [DisplayItem] {
    sheet.content.items.filter { $0.style.layer == layer && $0.elementID == element }
}

private func lineCount(_ items: [DisplayItem], pen: PenWeight) -> Int {
    items.filter { item in
        guard item.style.pen == pen, case .line = item.primitive else { return false }
        return true
    }.count
}

private func hasUpLabel(_ items: [DisplayItem]) -> Bool {
    items.contains { item in
        if case let .text(_, string, _, _, _) = item.primitive { return string == "UP" }
        return false
    }
}

@Test func cottagePlanDrawsItsStairWithTreadsAndAnUpArrow() throws {
    let document = try fixture("rect-cottage")
    let stair = try #require(document.stairs.first)
    let plan = try sheet("A-101", of: document)
    let drawn = items(plan, layer: "A-FLOR-STRS", element: stair.id.rawValue)
    let outlines = drawn.filter { item in
        if case .polyline(_, true) = item.primitive { return true }
        return false
    }
    #expect(outlines.count == 1)
    // 12 risers: 11 treads, so 10 nosing lines between the first and last risers.
    #expect(lineCount(drawn, pen: .thin) == 10)
    // The arrow: a shaft and two barbs.
    #expect(lineCount(drawn, pen: .fine) == 3)
    #expect(hasUpLabel(drawn))
    // A one-storey cottage has nothing above, so no floor opening anywhere.
    #expect(!plan.content.items.contains { $0.style.layer == "A-FLOR-OPNG" })
}

@Test func lHouseHallStairIsOnTheGroundPlanAndAnOpeningAbove() throws {
    let document = try fixture("l-house")
    let stair = try #require(document.stairs.first)
    let ground = try sheet("A-101", of: document)
    let drawn = items(ground, layer: "A-FLOR-STRS", element: stair.id.rawValue)
    // 16 risers: 15 treads, so 14 nosing lines.
    #expect(lineCount(drawn, pen: .thin) == 14)
    #expect(hasUpLabel(drawn))
    #expect(!ground.content.items.contains { $0.style.layer == "A-FLOR-OPNG" })

    let upper = try sheet("A-102", of: document)
    // Above, the same footprint dashed as an opening, and no second stair.
    #expect(items(upper, layer: "A-FLOR-STRS", element: stair.id.rawValue).isEmpty)
    let openings = items(upper, layer: "A-FLOR-OPNG", element: stair.id.rawValue)
    #expect(openings.count == 1)
    let opening = try #require(openings.first)
    #expect(opening.style.pattern == .dashed)
    let groundOutline = drawn.first { item in
        if case .polyline(_, true) = item.primitive { return true }
        return false
    }
    // Both plans are placed the same way, so the opening lands exactly on the stair below.
    #expect(opening.primitive == groundOutline?.primitive)
}

@Test func upLabelSitsBeyondTheBottomRiser() {
    let bottom = Point2(x: .millimeters(100), y: .millimeters(100))
    let up = StairPlan.upLabelPosition(from: bottom, toward: Point2(x: .millimeters(100), y: .millimeters(200)))
    #expect(up.x == bottom.x)
    #expect(up.y.ticks == bottom.y.ticks - mmTicks(4))
    let east = StairPlan.upLabelPosition(from: bottom, toward: Point2(x: .millimeters(200), y: .millimeters(100)))
    #expect(east.x.ticks == bottom.x.ticks - mmTicks(3))
}

@Test func onlyTheNextStoreyUpGetsTheOpening() throws {
    var document = try fixture("l-house")
    let building = try #require(document.buildings.first)
    let attic = StoreyID(UUID())
    _ = try AddStoreyCommand(storeyID: attic, buildingID: building.id, name: "Attic",
                             elevation: .millimeters(5600)).apply(to: &document)
    let upper = try #require(document.storeys.first { $0.name == "Upper Floor" })
    #expect(SchematicDrawingSet.storey(below: attic, in: document)?.id == upper.id)
    #expect(SchematicDrawingSet.storey(below: document.storeys[0].id, in: document) == nil)
}
