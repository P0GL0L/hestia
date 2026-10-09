@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

// A view too big for its sheet at the sheet's scale is drawn at the largest standard scale that fits, and its
// title says so, instead of running over the title block and off the page (audit DRW-2).

private func cottage() throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/rect-cottage.json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

private let oneInch = DrawingScale(label: "1\" = 1'-0\"", modelUnitsPerPaperUnit: 12)

private func texts(_ sheet: SheetDrawing) -> [String] {
    sheet.content.items.compactMap {
        if case let .text(_, string, _, _, _) = $0.primitive { return string }; return nil
    }
}

@Test func anOversizePlanStaysOnItsSheet() throws {
    var document = try cottage()
    let index = try #require(document.sheets.firstIndex { $0.number == "A-101" })
    // At 1" = 1'-0" the 38'-0" cottage is 38" wide; ARCH D is 36".
    document.sheets[index].scale = oneInch
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let plan = try #require(sheets.first { $0.number == "A-101" })
    let bounds = try #require(plan.content.bounds)
    #expect(bounds.min.x.ticks >= 0 && bounds.min.y.ticks >= 0)
    #expect(bounds.max.x.ticks <= plan.paper.width.ticks && bounds.max.y.ticks <= plan.paper.height.ticks)
    // The walls stay inside the drawing area, clear of the title block.
    let area = SheetFrame.drawingArea(for: plan.paper)
    let walls = plan.content.items.filter { $0.style.layer == "A-WALL" }
    let wallBounds = try #require(DisplayList(items: walls).bounds)
    #expect(wallBounds.min.x.ticks >= area.minX && wallBounds.max.x.ticks <= area.maxX)
    #expect(wallBounds.min.y.ticks >= area.minY && wallBounds.max.y.ticks <= area.maxY)
    // The sheet keeps its stored scale; the view title prints the scale the plan is drawn at.
    #expect(plan.scale == oneInch)
    #expect(!texts(plan).contains("SCALE: \(oneInch.label)"))
    #expect(texts(plan).contains { $0.hasPrefix("SCALE: ") })
}

@Test func aViewThatFitsKeepsTheSheetScale() throws {
    let document = try cottage()
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let plan = try #require(sheets.first { $0.number == "A-101" })
    #expect(texts(plan).contains("SCALE: \(DrawingScale.quarterInch.label)"))
}
