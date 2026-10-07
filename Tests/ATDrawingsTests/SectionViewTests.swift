@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

private func cottage() throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/rect-cottage.json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

/// East-west through the south rooms, 6'-0" north of the south wall line, looking north.
private let cut = SectionLine(start: Point2(x: .feet(-2), y: .feet(6)), end: Point2(x: .feet(40), y: .feet(6)))

@Test func engineSectionCutsWallsSlabAndRoof() throws {
    let document = try cottage()
    let outlines = try HestiaGeometryEngine().section(of: document, along: cut)
    let cutWalls: [ClassifiedOutline] = outlines.filter { $0.kind == .wall && $0.classification == .cut }
    // West wall split by its window (below the sill, above the head), plus two partitions and the east wall.
    #expect(cutWalls.count == 5)
    let crossIndices = [3, 4, 5, 1]
    let crossWalls = Set(crossIndices.map { document.walls[$0].id.rawValue })
    #expect(Set(cutWalls.map(\.elementID)) == crossWalls)
    let west = cutWalls.filter { $0.elementID == document.walls[3].id.rawValue }
    let westTops: [Int64] = west.map { $0.polygon.map(\.y.ticks).max()! }.sorted()
    let sillAndTop: [Int64] = [Length.feet(3).ticks, Length.feet(8).ticks]
    #expect(westTops == sillAndTop)
    // Only the middle wall shows beyond, with its doors; the north wall is hidden behind it.
    let beyond: [ClassifiedOutline] = outlines.filter { $0.classification == .beyond && $0.kind == .wall }
    let beyondWalls = Set(beyond.map(\.elementID))
    #expect(beyondWalls == [document.walls[6].id.rawValue])
    let slab = try #require(outlines.first { $0.kind == .slab })
    #expect(slab.polygon.map(\.y.ticks).max() == 0)
    #expect(slab.polygon.map(\.y.ticks).min() == -Length.inches(4).ticks)
    let roof = try #require(outlines.first { $0.kind == .roof })
    // 7'-3" in from the outer south eave (6'-3" to the wall line plus the 1'-0" overhang) at 6:12 rises
    // 3'-7 1/2" above the 8'-0" eave, matching the elevation's rule.
    let slope: Int64 = Length.inches(139).ticks + Length.sixtyFourthInches(32).ticks
    #expect(roof.polygon.map(\.y.ticks).max() == slope)
    // The outer eave itself sits at the eave height, with the roof band 250 mm deep below it.
    let eaveBottom: Int64 = Length.feet(8).ticks - Length.millimeters(250).ticks
    #expect(roof.polygon.map(\.y.ticks).min() == eaveBottom)
}

@Test func sectionSheetDrawsTheCutStampedAndTitled() throws {
    var document = try cottage()
    document.sheets = [Sheet(id: SheetID(UUID()), number: "A-301", title: "Building Section", paper: .archD,
                             scale: .quarterInch, views: [.section(line: cut)])]
    let sheet = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())[0]
    let layers = Set(sheet.content.items.map(\.style.layer))
    #expect(layers.isSuperset(of: ["A-SECT-MCUT", "A-SECT-PATT", "A-SECT-BYND", "A-ELEV-GRND"]))
    let text = sheet.content.items.compactMap { item -> String? in
        if case let .text(_, s, _, _, _) = item.primitive { return s }; return nil
    }
    #expect(text.contains("BUILDING SECTION"))
    #expect(text.contains("NOT FOR CONSTRUCTION"))
    #expect(text.contains("GROUND FLOOR 0'-0\""))
    let bounds = try #require(sheet.content.bounds)
    #expect(bounds.max.x <= sheet.paper.width && bounds.max.y <= sheet.paper.height)
}

@Test func sheetDrawsExactlyTheEngineCut() throws {
    var document = try cottage()
    document.sheets = [Sheet(id: SheetID(UUID()), number: "A-301", title: "Section", paper: .archD,
                             scale: .quarterInch, views: [.section(line: cut)])]
    let marker = UUID()
    let six = Length.inches(6), eight = Length.feet(8), zero = Length.millimeters(0)
    let box = [Point2(x: zero, y: zero), Point2(x: six, y: zero), Point2(x: six, y: eight), Point2(x: zero, y: eight)]
    let engineCut = ClassifiedOutline(elementID: marker, kind: .wall, classification: .cut, polygon: box)
    let sheet = try SchematicDrawingSet().sheets(for: document, geometry: MockGeometryEngine(sectionOutlines: [engineCut]))[0]
    let ids = Set(sheet.content.items.compactMap(\.elementID))
    #expect(ids == [marker])
}

@Test func lineThroughNothingSaysSo() throws {
    var document = try cottage()
    let far = SectionLine(start: Point2(x: .feet(100), y: .feet(100)), end: Point2(x: .feet(120), y: .feet(100)))
    document.sheets = [Sheet(id: SheetID(UUID()), number: "A-301", title: "Section", paper: .archD,
                             scale: .quarterInch, views: [.section(line: far)])]
    let sheet = try SchematicDrawingSet().sheets(for: document, geometry: MockGeometryEngine())[0]
    #expect(sheet.content.items.contains {
        if case let .text(_, s, _, _, _) = $0.primitive { return s == "Section line crosses nothing: not generated in this version" }
        return false
    })
}

@Test func sectionAndElevationAgreeOnTheRidge() throws {
    let document = try cottage()
    let ridgeElevation = try #require(ElevationView.roofOutlines(document, .south).first?.map(\.y.ticks).max())
    // A north-south cut through the middle meets the hip ridge.
    let middle = SectionLine(start: Point2(x: .feet(18), y: .feet(-3)), end: Point2(x: .feet(18), y: .feet(26)))
    let outlines = try HestiaGeometryEngine().section(of: document, along: middle)
    let roof = try #require(outlines.first { $0.kind == .roof })
    let ridgeSection = try #require(roof.polygon.map(\.y.ticks).max())
    #expect(abs(ridgeSection - ridgeElevation) <= Length.inches(1).ticks)
    #expect(ridgeElevation == Length.feet(14, inchCount: 3).ticks)
}
