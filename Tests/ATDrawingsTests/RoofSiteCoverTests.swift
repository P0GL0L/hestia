@testable import ATDrawings
import ATContracts
import Foundation
import Testing

private func cottageWithMoreSheets() throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/rect-cottage.json")
    var document = try ModelDocument.decode(from: Data(contentsOf: url))
    document.sheets.insert(Sheet(id: SheetID(UUID()), number: "A-001", title: "Cover", paper: .archD, scale: nil,
                                 views: [.cover]), at: 0)
    document.sheets.append(Sheet(id: SheetID(UUID()), number: "A-102", title: "Roof Plan", paper: .archD,
                                 scale: .quarterInch, views: [.roofPlan]))
    document.sheets.append(Sheet(id: SheetID(UUID()), number: "A-002", title: "Site Plan", paper: .archD,
                                 scale: nil, views: [.sitePlan]))
    document.terrainPatches.append(TerrainPatch(
        id: TerrainPatchID(UUID()), name: "Lot",
        boundary: [Point2(x: .feet(-20), y: .feet(-30)), Point2(x: .feet(60), y: .feet(-30)),
                   Point2(x: .feet(60), y: .feet(70)), Point2(x: .feet(-20), y: .feet(70))],
        surveyPoints: []))
    return document
}

private func texts(_ items: [DisplayItem]) -> [String] {
    items.compactMap { if case let .text(_, s, _, _, _) = $0.primitive { return s }; return nil }
}

@Test func coverListsEverySheetAndSaysNotForConstruction() throws {
    let document = try cottageWithMoreSheets()
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: MockGeometryEngine())
    let cover = texts(sheets[0].content.items)
    for sheet in document.sheets {
        #expect(cover.contains(sheet.number))
        #expect(cover.contains(sheet.title))
    }
    #expect(cover.contains { $0.contains("NOT A PERMIT SET") })
    #expect(cover.contains("RECT COTTAGE"))
}

@Test func roofPlanDrawsHipLinesAndPitch() throws {
    let document = try cottageWithMoreSheets()
    let view = ViewTransform(scale: .quarterInch, modelOrigin: Point2(x: .feet(-2), y: .feet(-2)),
                             paperOrigin: Point2(x: .millimeters(50), y: .millimeters(50)))
    let items = RoofPlanView.items(document, view: view)
    let roofID = document.roofs[0].id.rawValue
    let roofLines = items.filter { $0.elementID == roofID && $0.style.layer == "A-ROOF" }
    // Eave outline, ridge, four hips.
    #expect(roofLines.count == 6)
    #expect(texts(items).filter { $0 == "6:12" }.count == 2)
    #expect(items.filter { $0.style.pattern == .hidden }.count == document.walls.count + 1)
    let boxes = try #require(RoofPlanView.boxes(document.roofs[0]))
    #expect(boxes.outer.0 == boxes.inner.0 - Length.feet(1).ticks)
}

private func pitchMark(at point: Point2, down: (Double, Double) = (1, 0)) -> [DisplayItem] {
    [RoofPlanView.label("6:12", at: point)] + RoofPlanView.slopeArrow(at: point, down: down)
}

private func pitchPosition(_ items: [DisplayItem]) -> Point2? {
    items.compactMap { item -> Point2? in
        guard case let .text(position, string, _, _, _) = item.primitive, string == "6:12" else { return nil }
        return position
    }.first
}

@Test func roofPitchMarkUsesAnAlternateWhenItsArrowCrossesRoofLineworkAndOmitsWhenNoneClear() {
    let blockedAt = Point2(x: .millimeters(50), y: .millimeters(50))
    let clearAt = Point2(x: .millimeters(70), y: .millimeters(50))
    let obstacle = DisplayItem(.line(start: Point2(x: .millimeters(50), y: .millimeters(45)),
                                     end: Point2(x: .millimeters(50), y: .millimeters(47))),
                               style: RoofPlanView.lineStyle)
    let room = PaperRect(minX: 0, minY: 0, width: mmTicks(100), height: mmTicks(100))
    var space = LabelSpace([obstacle], scale: nil)
    let placed = RoofPlanView.placePitch([pitchMark(at: blockedAt), pitchMark(at: clearAt)],
                                         in: &space, room: room)
    #expect(pitchPosition(placed) == clearAt)

    var blocked = LabelSpace([obstacle], scale: nil)
    #expect(RoofPlanView.placePitch([pitchMark(at: blockedAt)], in: &blocked, room: room).isEmpty)
}

@Test func roofPitchMarkIsOmittedWhenItsArrowWouldLeaveTheView() {
    let room = PaperRect(minX: 0, minY: 0, width: mmTicks(100), height: mmTicks(100))
    let at = Point2(x: .millimeters(50), y: .millimeters(5))
    var space = LabelSpace([], scale: nil)
    #expect(RoofPlanView.placePitch([pitchMark(at: at, down: (0, 1))], in: &space, room: room).isEmpty)
}

@Test func sitePlanShowsLotBuildingAndNorth() throws {
    let document = try cottageWithMoreSheets()
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: MockGeometryEngine())
    let site = try #require(sheets.first { $0.number == "A-002" })
    let items = site.content.items
    #expect(items.contains { $0.style.layer == "C-PROP" })
    #expect(items.contains { if case .symbol("north-arrow", _, _, _) = $0.primitive { return true }; return false })
    #expect(texts(items).contains("LOT"))
    #expect(texts(items).contains { $0.hasPrefix("SCALE: ") })
    let bounds = try #require(site.content.bounds)
    #expect(bounds.max.x <= site.paper.width && bounds.max.y <= site.paper.height)
}
