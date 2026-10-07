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

private func mm(_ value: Int64) -> Int64 { Length.millimeters(value).ticks }

/// Horizontal edges at height z that overlap the stretch from a to b.
private func horizontal(_ edges: [((Int64, Int64), (Int64, Int64))], at z: Int64, over a: Int64, _ b: Int64) -> Int {
    edges.filter { edge in
        let (p, q) = edge
        guard p.1 == z, q.1 == z else { return false }
        return min(p.0, q.0) < b && max(p.0, q.0) > a
    }.count
}

@Test func upperSlabEdgeFillsTheBandUnderTheUpperFloor() throws {
    let document = try fixture("l-house")
    let upperSlab = try #require(document.slabs.first { $0.storeyID == document.storeys[1].id })
    let meshes = try HestiaGeometryEngine().meshes(of: document)
    let slabMeshes = meshes.filter { $0.elementID == upperSlab.id.rawValue }
    let bands = ElevationView.slabBands(document, .south, slabMeshes: slabMeshes, above: 0)
    #expect(bands.count == 1)
    let band = try #require(bands.first)
    // The model's slab: 250 mm under the 2800 mm floor, over its outline from x = 0 to 10 000 mm.
    let expected: [Int64] = [0, mm(10_000), mm(2_550), mm(2_800)]
    #expect([band.h0, band.h1, band.z0, band.z1] == expected)

    // The ground wall stops at the band: no 2700 mm top line runs through it.
    let ground = ElevationView.wallEdges(h0: -mm(150), h1: mm(10_150), base: 0, top: mm(2_700), bands: bands)
    #expect(horizontal(ground, at: mm(2_700), over: 0, mm(10_000)) == 0)
    #expect(horizontal(ground, at: mm(2_550), over: 0, mm(10_000)) == 0)
    // The upper wall's foot is the band's top edge, drawn once by the band.
    let upper = ElevationView.wallEdges(h0: -mm(150), h1: mm(10_150), base: mm(2_800), top: mm(5_500), bands: bands)
    #expect(horizontal(upper, at: mm(2_800), over: 0, mm(10_000)) == 0)
    // Beyond the slab's outline the walls keep their own edges.
    #expect(horizontal(ground, at: mm(2_700), over: -mm(150), 0) == 1)
    #expect(horizontal(upper, at: mm(5_500), over: -mm(150), mm(10_150)) == 1)
}

@Test func elevationSheetDrawsTheSlabEdgeOnlyAboveGrade() throws {
    var house = try fixture("l-house")
    house.sheets = [Sheet(id: SheetID(UUID()), number: "A-201", title: "South", paper: .archD, scale: .quarterInch,
                          views: [.elevation(direction: .south)])]
    let sheet = try #require(try SchematicDrawingSet().sheets(for: house, geometry: HestiaGeometryEngine()).first)
    let slabItems = sheet.content.items.filter { $0.style.layer == "A-ELEV-SLAB" }
    let upperSlab = try #require(house.slabs.first { $0.storeyID == house.storeys[1].id })
    // One hatched, outlined band, for the upper slab; the ground slab sits at grade and is left out.
    #expect(slabItems.count == 2)
    #expect(slabItems.allSatisfy { $0.elementID == upperSlab.id.rawValue })

    let cottage = try fixture("rect-cottage")
    let sheets = try SchematicDrawingSet().sheets(for: cottage, geometry: HestiaGeometryEngine())
    let elevations = try #require(sheets.first { $0.number == "A-201" })
    #expect(!elevations.content.items.contains { $0.style.layer == "A-ELEV-SLAB" })
}
