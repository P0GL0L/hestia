@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

// A printed dimension is the model length in the drawing's units, never the paper length (audit DRW-1). A plan
// sheet with no scale is drawn at a fitted one; its dimensions take their units from the project, else from the
// set's other sheets, else from the paper.

private func fixture(_ name: String) throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/\(name).json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

private func dimensionTexts(_ document: ModelDocument, sheet number: String) throws -> [String] {
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let sheet = try #require(sheets.first { $0.number == number })
    return sheet.content.items.compactMap {
        if case let .dimension(_, _, _, text) = $0.primitive { return text }; return nil
    }
}

private func removingScale(_ document: ModelDocument, from number: String) -> ModelDocument {
    var copy = document
    if let index = copy.sheets.firstIndex(where: { $0.number == number }) { copy.sheets[index].scale = nil }
    return copy
}

@Test func anImperialPlanWithNoScaleTakesItsUnitsFromTheOtherSheets() throws {
    let cottage = try fixture("rect-cottage")
    let scaled = try dimensionTexts(cottage, sheet: "A-101")
    let unscaled = try dimensionTexts(removingScale(cottage, from: "A-101"), sheet: "A-101")
    #expect(unscaled.contains("38'-0\""))
    #expect(unscaled.contains("23'-6\""))
    #expect(!unscaled.contains { $0.hasSuffix(" mm") })
    // The same lengths in the same units as with the scale; only where they sit on the sheet changes.
    #expect(unscaled.sorted() == scaled.sorted())
}

@Test func theProjectsUnitsWinOnAPlanWithNoScale() throws {
    let house = try fixture("l-house")
    #expect(house.project.displayUnits == .metric)
    let scaled = try dimensionTexts(house, sheet: "A-101")
    let unscaled = try dimensionTexts(removingScale(house, from: "A-101"), sheet: "A-101")
    #expect(!unscaled.isEmpty)
    #expect(unscaled.sorted() == scaled.sorted())
    #expect(!unscaled.contains { $0.contains("'") })
}

@Test func aPlanWithNoScaleBesideMetricSheetsPrintsModelMillimetres() throws {
    var cottage = try fixture("rect-cottage")
    for index in cottage.sheets.indices where cottage.sheets[index].scale != nil {
        cottage.sheets[index].scale = .oneTo50
    }
    let unscaled = try dimensionTexts(removingScale(cottage, from: "A-101"), sheet: "A-101")
    #expect(unscaled.contains(DrawingUnits.label(.feet(38), style: .metric)))
    #expect(!unscaled.contains { $0.contains("'") })
}

@Test func withNoScaleAnywhereThePaperDecides() throws {
    var cottage = try fixture("rect-cottage")
    for index in cottage.sheets.indices { cottage.sheets[index].scale = nil }
    let onArch = try dimensionTexts(cottage, sheet: "A-101")
    #expect(onArch.contains("38'-0\""))
    #expect(!onArch.contains { $0.hasSuffix(" mm") })
    for index in cottage.sheets.indices { cottage.sheets[index].paper = .isoA1 }
    let onISO = try dimensionTexts(cottage, sheet: "A-101")
    #expect(onISO.contains(DrawingUnits.label(.feet(38), style: .metric)))
    #expect(!onISO.contains { $0.contains("'") })
}
