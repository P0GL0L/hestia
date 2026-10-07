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

private func imperial(_ length: Length) -> String { LengthFormatting.format(length, style: .feetInchesFractions) }

@Test func cottageElevationsMarkTheEaveAndRidge() throws {
    let document = try fixture("rect-cottage")
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let elevations = try #require(sheets.first { $0.number == "A-201" })
    let lines = texts(elevations)
    let eave = "EAVE " + imperial(.feet(8))
    let ridge = "RIDGE " + imperial(.feet(14, inchCount: 3))
    // Four elevations on the sheet, each with one eave and one ridge mark.
    let eaves: [String] = lines.filter { $0 == eave }
    let ridges: [String] = lines.filter { $0 == ridge }
    #expect(eaves.count == 4)
    #expect(ridges.count == 4)
    // The wall top is also 8'-0", and it is not printed as a second string at that height.
    let atEightFeet: [String] = lines.filter { $0.hasSuffix(" " + imperial(.feet(8))) }
    #expect(atEightFeet.count == 4)
}

@Test func marksReadTheDrawnSilhouetteInProjectUnits() throws {
    var document = try fixture("l-house")
    document.sheets.append(Sheet(id: SheetID(UUID()), number: "A-201", title: "South", paper: .archD,
                                 scale: .quarterInch, views: [.elevation(direction: .south)]))
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let south = try #require(sheets.first { $0.number == "A-201" })
    let roof = try #require(document.roofs.first)
    let upper = try #require(document.storeys.first { $0.id == roof.storeyID })
    let outline = try #require(ElevationView.roofOutline(roof, base: upper.elevation.ticks, .south))
    let top = try #require(outline.map(\.y.ticks).max())
    let lines = texts(south)
    #expect(lines.contains("EAVE " + LengthFormatting.format(.millimeters(5500), style: .metric)))
    #expect(lines.contains("RIDGE " + LengthFormatting.format(Length(ticks: top), style: .metric)))
    // Every level mark is metric; only the scale labels carry feet and inches.
    let marks: [String] = lines.filter { $0.hasPrefix("EAVE") || $0.hasPrefix("RIDGE") || $0.contains("FLOOR ") }
    #expect(marks.count == 4)
    #expect(marks.allSatisfy { $0.hasSuffix(" mm") })
}

@Test func aHeightAlreadyMarkedIsNotMarkedAgain() throws {
    var document = try fixture("rect-cottage")
    // A loft floor exactly at the 8'-0" eave keeps its own name; the eave adds nothing there.
    let building = try #require(document.buildings.first)
    _ = try AddStoreyCommand(storeyID: StoreyID(UUID()), buildingID: building.id, name: "Loft",
                             elevation: .feet(8)).apply(to: &document)
    let levels = ElevationView.levels(document, .south)
    let names: [String] = levels.map(\.name)
    #expect(names == ["GROUND FLOOR", "LOFT", "RIDGE"])
}

@Test func aFlatRoofHasAnEaveButNoRidge() throws {
    var document = try fixture("rect-cottage")
    let flat = RoofPlane(pitchRisePer12: nil, overhang: .inches(12))
    document.roofs[0].planes = Array(repeating: flat, count: document.roofs[0].planes.count)
    let levels = ElevationView.levels(document, .east)
    let names: [String] = levels.map(\.name)
    #expect(names == ["GROUND FLOOR", "EAVE"])
}
