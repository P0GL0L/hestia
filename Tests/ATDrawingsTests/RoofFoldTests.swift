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

private func roofMeshes(_ document: ModelDocument) throws -> [Mesh] {
    try HestiaGeometryEngine().meshes(of: document).filter { $0.elementID == document.roofs[0].id.rawValue }
}

private func folds(_ document: ModelDocument, _ direction: ElevationDirection, _ meshes: [Mesh]) -> [(Point2, Point2)] {
    let outlines = ElevationView.roofOutlines(document, direction, roofMeshes: meshes)
    return ElevationView.folds(of: document.roofs[0], direction, roofMeshes: meshes, outlines: outlines)
}

/// Whether a drawn line runs from one (h, z) point to the other, in millimetres, to within a millimetre.
private func runs(_ line: (Point2, Point2), _ a: (Int64, Int64), _ b: (Int64, Int64)) -> Bool {
    func near(_ p: Point2, _ q: (Int64, Int64)) -> Bool {
        let tolerance = Length.millimeters(1).ticks
        let dh: Int64 = abs(p.x.ticks - Length.millimeters(q.0).ticks)
        let dz: Int64 = abs(p.y.ticks - Length.millimeters(q.1).ticks)
        return dh <= tolerance && dz <= tolerance
    }
    return (near(line.0, a) && near(line.1, b)) || (near(line.0, b) && near(line.1, a))
}

@Test func rectangularHipGainsNoInternalLines() throws {
    let document = try fixture("rect-cottage")
    let meshes = try roofMeshes(document)
    for direction in [ElevationDirection.south, .north, .east, .west] {
        #expect(folds(document, direction, meshes).isEmpty, "\(direction)")
    }
}

@Test func lHouseValleyIsFoundWhereTheWingsMeet() throws {
    let document = try fixture("l-house")
    let planes = RoofFolds.planes(of: try roofMeshes(document))
    // Two wings' coplanar south and west slopes count once each: six planes, not eight.
    #expect(planes.count == 6)
    let mm = Double(Length.millimeters(1).ticks)
    // From the inner eave corner at 5500 mm up to where it meets the hall wing's ridge at 6975 mm.
    let valley = RoofFolds.folds(planes).first { fold in
        let starts: Bool = abs(fold.x0 - 5450 * mm) < mm && abs(fold.y0 - 6450 * mm) < mm
        let ends: Bool = abs(fold.x1 - 2500 * mm) < mm && abs(fold.y1 - 3500 * mm) < mm
        let reversed: Bool = abs(fold.x1 - 5450 * mm) < mm && abs(fold.x0 - 2500 * mm) < mm
        return (starts && ends) || reversed
    }
    let found = try #require(valley)
    let low: Double = min(found.z0, found.z1), high: Double = max(found.z0, found.z1)
    #expect(abs(low - 5500 * mm) < mm)
    #expect(abs(high - 6975 * mm) < mm)
}

@Test func lHouseValleyShowsOnlyWhereItIsSeen() throws {
    let document = try fixture("l-house")
    let meshes = try roofMeshes(document)
    // Seen from the north (h = -x) and the east (h = y), the line where the wings meet rises from the
    // 5500 mm eave to 6975 mm.
    let north = folds(document, .north, meshes)
    #expect(north.count == 1)
    #expect(north.contains { runs($0, (-5450, 5500), (-2500, 6975)) })
    let east = folds(document, .east, meshes)
    #expect(east.count == 1)
    #expect(east.contains { runs($0, (6450, 5500), (3500, 6975)) })
    // From the south and the west the wings' slopes are single planes and the valley is behind them.
    #expect(folds(document, .south, meshes).isEmpty)
    #expect(folds(document, .west, meshes).isEmpty)
}

@Test func elevationSheetDrawsTheFoldThin() throws {
    var document = try fixture("l-house")
    document.sheets = [Sheet(id: SheetID(UUID()), number: "A-201", title: "East", paper: .archD, scale: .quarterInch,
                             views: [.elevation(direction: .east)])]
    let sheet = try #require(try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine()).first)
    let foldItems = sheet.content.items.filter { $0.style == ElevationView.foldStyle }
    #expect(foldItems.count == 1)
    #expect(foldItems.allSatisfy { $0.elementID == document.roofs[0].id.rawValue })
    // Without a roof mesh there are no folds to draw.
    let mock = try #require(try SchematicDrawingSet().sheets(for: document, geometry: MockGeometryEngine()).first)
    #expect(!mock.content.items.contains { $0.style == ElevationView.foldStyle })
}
