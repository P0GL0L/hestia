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
    document.sheets = [Sheet(id: SheetID(UUID()), number: "A-201", title: "South", paper: .archD,
                             scale: .quarterInch, views: [.elevation(direction: .south)])]
    let engine = HestiaGeometryEngine()
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: engine)
    let south = try #require(sheets.first { $0.number == "A-201" })
    // The roof drawn is the engine's: the 5500 mm eave plus the south wing's 1725 mm rise.
    let roofMeshes = try engine.meshes(of: document).filter { $0.elementID == document.roofs[0].id.rawValue }
    let outlines = ElevationView.roofOutlines(document, .south, roofMeshes: roofMeshes)
    let top = try #require(outlines.flatMap { $0.map(\.y.ticks) }.max())
    #expect(top == Length.millimeters(7225).ticks)
    let lines = texts(south)
    #expect(lines.contains("EAVE " + LengthFormatting.format(.millimeters(5500), style: .metric)))
    #expect(lines.contains("RIDGE " + LengthFormatting.format(.millimeters(7225), style: .metric)))
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

@Test func cottageRoofFromItsMeshKeepsTheHipBox() throws {
    let document = try fixture("rect-cottage")
    let meshes = try HestiaGeometryEngine().meshes(of: document).filter { $0.elementID == document.roofs[0].id.rawValue }
    let outlines = ElevationView.roofOutlines(document, .south, roofMeshes: meshes)
    #expect(outlines.count == 1)
    let outline = try #require(outlines.first)
    // The same trapezoid the box rule drew: 39'-6" of eave at 8'-0", the ridge at 14'-3".
    #expect(outline.count == 4)
    let zs: [Int64] = outline.map(\.y.ticks)
    #expect(zs.min() == Length.feet(8).ticks)
    #expect(zs.max() == Length.feet(14, inchCount: 3).ticks)
    let hs: [Int64] = outline.map(\.x.ticks)
    let span: Int64 = hs.max()! - hs.min()!
    #expect(span == Length.feet(39, inchCount: 6).ticks)
}

@Test func silhouetteMergesOverlapsAndSplitsAtGaps() {
    typealias P = MeshSilhouette.Point
    // Two triangles sharing the stretch 4...6 with a peak each, and one apart from them.
    let left: [P] = [(0, 0), (6, 0), (3, 3)]
    let right: [P] = [(4, 0), (10, 0), (7, 3)]
    let apart: [P] = [(20, 0), (22, 0), (21, 1)]
    let outlines = MeshSilhouette.outlines([left, right, apart])
    #expect(outlines.count == 2)
    let merged = outlines.first { $0.contains(paperPoint(0, 0)) }
    // Up to the first peak, down to where the slopes cross at (5, 1), up to the second peak, and back.
    let expected = [paperPoint(0, 0), paperPoint(3, 3), paperPoint(5, 1), paperPoint(7, 3), paperPoint(10, 0)]
    #expect(merged == expected)
}
