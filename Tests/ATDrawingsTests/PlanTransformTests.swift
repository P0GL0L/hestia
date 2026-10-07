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

@Test func planTransformIsWhereTheSheetDrewThePlan() throws {
    for name in ["rect-cottage", "l-house"] {
        let document = try fixture(name)
        let engine = HestiaGeometryEngine()
        let sheets = try SchematicDrawingSet().sheets(for: document, geometry: engine)
        for storey in document.storeys {
            let transform = try #require(SchematicDrawingSet().planTransform(for: document, storey: storey.id))
            let number = try #require(document.sheets.first { $0.views.contains(.floorPlan(storeyID: storey.id)) })
            let sheet = try #require(sheets.first { $0.number == number.number })
            // Every wall outline the engine gives, placed by the transform, is a polyline the sheet drew.
            var drawn: Set<[Point2]> = []
            for item in sheet.content.items where item.style.layer == "A-WALL" {
                if case let .polyline(points, true) = item.primitive { drawn.insert(points) }
            }
            let outlines = try engine.planView(of: document, storey: storey.id).filter { $0.kind == .wall }
            #expect(!outlines.isEmpty)
            for outline in outlines {
                let placed: [Point2] = outline.polygon.map(transform.paper)
                #expect(drawn.contains(placed), "\(name) \(storey.name)")
            }
        }
    }
}

@Test func paperPointsComeBackExactlyAndGridPointsToo() throws {
    let document = try fixture("rect-cottage")
    let transform = try #require(SchematicDrawingSet().planTransform(for: document, storey: document.storeys[0].id))
    // Any paper point maps to a model point that maps straight back to it.
    for (x, y) in [(300, 200), (0, 0), (812, 551)] as [(Int64, Int64)] {
        let paper = Point2(x: Length(ticks: Length.millimeters(x).ticks + 7), y: Length(ticks: Length.millimeters(y).ticks - 3))
        #expect(transform.paper(transform.model(paper)) == paper)
    }
    // A model point on the scale's grid comes back unchanged.
    let n: Int64 = transform.scale.modelUnitsPerPaperUnit
    for k in [-5, 0, 17, 1_000] as [Int64] {
        let onGrid = Point2(x: Length(ticks: transform.modelOrigin.x.ticks + k * n),
                            y: Length(ticks: transform.modelOrigin.y.ticks - 3 * k * n))
        #expect(transform.model(transform.paper(onGrid)) == onGrid)
    }
}

@Test func noPlacementForAStoreyWithoutAPlan() throws {
    let document = try fixture("rect-cottage")
    #expect(SchematicDrawingSet().planTransform(for: document, storey: StoreyID(UUID())) == nil)
}
