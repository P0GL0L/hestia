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

private func texts(_ sheet: SheetDrawing) -> [String] {
    sheet.content.items.compactMap { item -> String? in
        if case let .text(_, string, _, _, _) = item.primitive { return string }
        return nil
    }
}

private func dimensionTexts(_ sheet: SheetDrawing) -> [String?] {
    sheet.content.items.compactMap { item -> String?? in
        if case let .dimension(_, _, _, text) = item.primitive { return .some(text) }
        return nil
    }
}

/// The l-house with a section and the south elevation added, on its own quarter-inch sheets.
private func lHouseWithViews() throws -> ModelDocument {
    var document = try fixture("l-house")
    let line = SectionLine(start: Point2(x: .millimeters(2500), y: .millimeters(-1500)),
                           end: Point2(x: .millimeters(2500), y: .millimeters(11500)))
    let section = Sheet(id: SheetID(UUID()), number: "A-301", title: "Section", paper: .archD, scale: .quarterInch,
                        views: [.section(line: line)])
    let elevation = Sheet(id: SheetID(UUID()), number: "A-201", title: "Elevation", paper: .archD,
                          scale: .quarterInch, views: [.elevation(direction: .south)])
    document.sheets = [section, elevation]
    return document
}

@Test func metricProjectPrintsMetricLevelsOnQuarterInchSheets() throws {
    let document = try lHouseWithViews()
    #expect(document.project.displayUnits == .metric)
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let upper = "UPPER FLOOR " + LengthFormatting.format(.millimeters(2800), style: .metric)
    for number in ["A-301", "A-201"] {
        let sheet = try #require(sheets.first { $0.number == number })
        let lines = texts(sheet)
        #expect(lines.contains(upper), "\(number)")
        #expect(!lines.contains { $0.hasPrefix("UPPER FLOOR 9'") }, "\(number)")
    }
}

@Test func metricProjectLabelsEveryPlanDimension() throws {
    let document = try fixture("l-house")
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let plan = try #require(sheets.first { $0.number == "A-101" })
    let labels = dimensionTexts(plan)
    #expect(!labels.isEmpty)
    #expect(labels.allSatisfy { $0 != nil })
    // The overall south chain runs outer face to outer face: 10 m plus two half walls of 150 mm.
    let overall = LengthFormatting.format(.millimeters(10_300), style: .metric)
    #expect(labels.contains(overall))
    #expect(!labels.contains { $0?.contains("'") == true })
    // Room areas follow too.
    #expect(texts(plan).contains { $0.hasSuffix("SQ M") })
}

@Test func unsetUnitsKeepTheScaleInference() throws {
    var document = try fixture("rect-cottage")
    #expect(document.project.displayUnits == nil)
    let before = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let plan = try #require(before.first { $0.number == "A-101" })
    // No stored overrides on the cottage plan: the printer measures in the scale's units.
    #expect(dimensionTexts(plan).allSatisfy { $0 == nil })
    #expect(DrawingUnits.style(document) == .feetInchesFractions)
    // Setting the units to what the scale implies prints the same lengths, now carried on each dimension.
    _ = try SetProjectUnitsCommand(projectID: document.project.id, units: .feetInchesFractions).apply(to: &document)
    let after = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let set = try #require(after.first { $0.number == "A-101" })
    let printed = dimensionTexts(set).compactMap { $0 }
    #expect(printed.count == dimensionTexts(plan).count)
    #expect(printed.allSatisfy { $0.contains("\"") })
}

@Test func storedOverridesStillWin() throws {
    var document = try fixture("l-house")
    let room = try #require(document.rooms.first { $0.name == "Living" })
    _ = try SetDimensionOverrideCommand(elementID: room.id.rawValue, face: .width, text: "VERIFY").apply(to: &document)
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let plan = try #require(sheets.first { $0.number == "A-101" })
    #expect(dimensionTexts(plan).contains("VERIFY"))
}

@Test func helperRoundsLikeThePrinters() {
    #expect(DrawingUnits.label(.millimeters(2800), style: .metric) == LengthFormatting.format(.millimeters(2800), style: .metric))
    let sixteenth = Length(ticks: Length.ticksPerSixtyFourthInch * 4)
    let nearly = Length(ticks: Length.inches(12).ticks + sixteenth.ticks / 3)
    #expect(DrawingUnits.label(nearly, style: .feetInchesFractions) == LengthFormatting.format(.feet(1), style: .feetInchesFractions))
    #expect(SheetPDF.measuredLabel(paperTicks: Length.millimeters(25).ticks, scale: .oneTo100)
        == DrawingUnits.label(.millimeters(2500), style: .metric))
}
