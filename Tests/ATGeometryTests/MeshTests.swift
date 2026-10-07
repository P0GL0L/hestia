@testable import ATGeometry
import ATContracts
import Foundation
import Testing

private func fixture(_ name: String) throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/\(name).json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

private func triangles(_ mesh: Mesh) -> [(Point3, Point3, Point3)] {
    stride(from: 0, to: mesh.indices.count, by: 3).map {
        (mesh.positions[Int(mesh.indices[$0])], mesh.positions[Int(mesh.indices[$0 + 1])],
         mesh.positions[Int(mesh.indices[$0 + 2])])
    }
}

private func d(_ p: Point3) -> (Double, Double, Double) { (Double(p.x.ticks), Double(p.y.ticks), Double(p.z.ticks)) }

/// Signed volume of a closed mesh, by the divergence theorem.
private func volume(_ mesh: Mesh) -> Double {
    var total: Double = 0
    for t in triangles(mesh) {
        let a = d(t.0), b = d(t.1), c = d(t.2)
        let x: Double = a.0 * (b.1 * c.2 - b.2 * c.1)
        let y: Double = a.1 * (b.0 * c.2 - b.2 * c.0)
        let z: Double = a.2 * (b.0 * c.1 - b.1 * c.0)
        total += (x - y + z) / 6
    }
    return total
}

/// Plan area of the upward-facing triangles.
private func upwardPlanArea(_ mesh: Mesh) -> Double {
    var total: Double = 0
    for t in triangles(mesh) {
        let a = d(t.0), b = d(t.1), c = d(t.2)
        let p: Double = (b.0 - a.0) * (c.1 - a.1)
        let q: Double = (b.1 - a.1) * (c.0 - a.0)
        total += max(p - q, 0) / 2
    }
    return total
}

private let footTicks = Double(Length.feet(1).ticks)

@Test func everyMeshIsValidAndTagged() throws {
    for name in ["rect-cottage", "l-house"] {
        let document = try fixture(name)
        let meshes = try HestiaGeometryEngine().meshes(of: document)
        #expect(!meshes.isEmpty)
        for mesh in meshes { try mesh.validate() }
        let tagged = Set(meshes.compactMap(\.elementID))
        let expected = Set(document.walls.map(\.id.rawValue) + document.slabs.map(\.id.rawValue)
                           + document.stairs.map(\.id.rawValue) + document.roofs.map(\.id.rawValue))
        #expect(tagged == expected, "\(name)")
    }
}

@Test func wallSolidsLoseExactlyTheOpenings() throws {
    let document = try fixture("rect-cottage")
    let south = document.walls[0]
    let footprint = try #require(try WallFootprints().footprints(for: document.walls)[south.id])
    let openings = document.openings.filter { $0.wallID == south.id }
    let meshes = try ElementMeshes.wall(south, footprint: footprint, openings: openings, base: 0)
    let solid = try #require(meshes.first { $0.materialID == MaterialID("wall") })
    let twice: Double = PolygonMath.twiceSignedArea(footprint.map(Vec.init))
    let footprintArea: Double = abs(twice) / 2
    let thickness = Double(south.thickness.ticks)
    var holes: Double = 0
    for opening in openings {
        let face: Double = Double(opening.width.ticks) * Double(opening.height.ticks)
        holes += face * thickness
    }
    let expected: Double = footprintArea * Double(south.height.ticks) - holes
    let error: Double = abs(volume(solid) - expected)
    #expect(error / expected < 1e-9)
    #expect(meshes.contains { $0.materialID == MaterialID("glass") })
    #expect(meshes.contains { $0.materialID == MaterialID("door") })
}

@Test func cottageHipRoofRisesFromTheOuterEaveToTheRidge() throws {
    let document = try fixture("rect-cottage")
    let roof = try #require(ElementMeshes.roof(document.roofs[0], base: 0).first)
    let zs = roof.positions.map(\.z.ticks)
    #expect(zs.min() == Length.feet(8).ticks)
    #expect(zs.max() == Length.feet(14, inchCount: 3).ticks)
    // The roof covers the footprint plus the 1'-0" overhang all round: 39'-6" by 25'-0".
    let squareFoot: Double = footTicks * footTicks
    let squareFeet: Double = upwardPlanArea(roof) / squareFoot
    let expected: Double = 987.5
    #expect(abs(squareFeet - expected) < 0.01)
}

@Test func lHouseHipRoofCoversTheWholeL() throws {
    let document = try fixture("l-house")
    let upper = try #require(document.storeys.last)
    let roof = try #require(ElementMeshes.roof(document.roofs[0], base: Double(upper.elevation.ticks)).first)
    try roof.validate()
    let mm = Double(Length.ticksPerMillimeter)
    // 10 m by 6 m plus 5 m by 4 m: 80 m².
    let squareMillimeters: Double = 80_000_000
    let outline: Double = squareMillimeters * mm * mm
    // Overlapping rectangle roofs cover at least the L itself.
    #expect(upwardPlanArea(roof) >= outline)
    // The highest ridge is the 6 m deep south wing's: 6.9 m with its 450 mm overhangs, half of that at 6:12.
    let eave = Double(upper.elevation.ticks + document.roofs[0].eaveHeight.ticks)
    let ridge = Double(roof.positions.map(\.z.ticks).max()!)
    let rise: Double = (ridge - eave) / mm
    #expect(abs(rise - 1_725) < 1)
}

@Test func gableEndsAreClosed() throws {
    let storey = StoreyID(UUID())
    let mm = { (x: Int64, y: Int64) in Point2(x: .millimeters(x), y: .millimeters(y)) }
    let roof = Roof(id: RoofID(UUID()), storeyID: storey,
                    footprint: [mm(0, 0), mm(10_000, 0), mm(10_000, 6_000), mm(0, 6_000)],
                    eaveHeight: .millimeters(2_400),
                    planes: [RoofPlane(pitchRisePer12: .inches(6), overhang: .millimeters(0)),
                             RoofPlane(pitchRisePer12: nil, overhang: .millimeters(0)),
                             RoofPlane(pitchRisePer12: .inches(6), overhang: .millimeters(0)),
                             RoofPlane(pitchRisePer12: nil, overhang: .millimeters(0))])
    let mesh = try #require(ElementMeshes.roof(roof, base: 0).first)
    try mesh.validate()
    let vertical = mesh.normals.filter { abs($0.z) < 1e-6 }
    #expect(!vertical.isEmpty)
    // Ridge 1.5 m above the eave along the full 10 m.
    let ridgeHeight = Length.millimeters(3_900)
    let ridge: [Point3] = mesh.positions.filter { $0.z == ridgeHeight }
    let ends: Set<Length> = [.millimeters(0), .millimeters(10_000)]
    #expect(Set(ridge.map(\.x)) == ends)
}

@Test func stairStepsUpOneRiserPerTread() throws {
    let document = try fixture("rect-cottage")
    let stair = try #require(ElementMeshes.stair(document.stairs[0], base: 0))
    // 12 risers: 11 tread blocks, the top one 11 x 8" high; the last riser lands on the floor above.
    #expect(stair.positions.map(\.z.ticks).max() == Length.inches(88).ticks)
    #expect(stair.triangleCount == 11 * 12)
}

@Test func earClippingHandlesAnL() {
    let l = [Vec(0, 0), Vec(10, 0), Vec(10, 6), Vec(5, 6), Vec(5, 10), Vec(0, 10)]
    let triangles = Triangulation.earClip(l)
    #expect(triangles.count == 4)
    var area: Double = 0
    for t in triangles {
        let cross: Double = (l[t.1] - l[t.0]).cross(l[t.2] - l[t.0])
        area += abs(cross) / 2
    }
    #expect(area == 80)
}
