@testable import ATGeometry
import ATContracts
import Foundation
import Testing

private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
private func ft(_ f: Int64) -> Length { .feet(f) }
private let storey = StoreyID(uuid(3))
private let wallID = WallID(uuid(10))

private func opening(_ n: Int, at offset: Int64, width: Int64, height: Length, sill: Int64,
                     _ kind: OpeningKind) -> Opening {
    let swing: DoorSwing? = kind.isDoor ? DoorSwing(hinge: .nearStart, opensToward: .left) : nil
    return Opening(id: OpeningID(uuid(n)), wallID: wallID, offsetAlongWall: ft(offset), width: ft(width),
                   height: height, sillHeight: ft(sill), kind: kind, swing: swing)
}

/// A 20' wall, 6" thick and 8' high, with a door, a window, and a cased opening with a 1' sill.
private let wall = Wall(id: wallID, storeyID: storey, start: Point2(x: ft(0), y: ft(0)),
                        end: Point2(x: ft(20), y: ft(0)), thickness: .inches(6), height: ft(8))
private let door = opening(20, at: 1, width: 3, height: .feet(6, inchCount: 8), sill: 0, .singleDoor)
private let window = opening(21, at: 6, width: 4, height: ft(4), sill: 3, .window)
private let cased = opening(22, at: 12, width: 4, height: ft(6), sill: 1, .casedOpening)

private func meshes(_ openings: [Opening]) throws -> [Mesh] {
    let footprint = try #require(try WallFootprints().footprints(for: [wall])[wallID])
    return try ElementMeshes.wall(wall, footprint: footprint, openings: openings, base: 0)
}

private func material(_ name: String, in meshes: [Mesh]) -> Mesh? {
    meshes.first { $0.materialID == MaterialID(name) }
}

/// Total area of a mesh's triangles, in square ticks.
private func area(_ mesh: Mesh) -> Double {
    var total: Double = 0
    for i in stride(from: 0, to: mesh.indices.count, by: 3) {
        let a = mesh.positions[Int(mesh.indices[i])], b = mesh.positions[Int(mesh.indices[i + 1])]
        let c = mesh.positions[Int(mesh.indices[i + 2])]
        let u = (Double(b.x.ticks - a.x.ticks), Double(b.y.ticks - a.y.ticks), Double(b.z.ticks - a.z.ticks))
        let v = (Double(c.x.ticks - a.x.ticks), Double(c.y.ticks - a.y.ticks), Double(c.z.ticks - a.z.ticks))
        let x: Double = u.1 * v.2 - u.2 * v.1
        let y: Double = u.2 * v.0 - u.0 * v.2
        let z: Double = u.0 * v.1 - u.1 * v.0
        total += (x * x + y * y + z * z).squareRoot() / 2
    }
    return total
}

/// Signed volume of a closed mesh, by the divergence theorem.
private func volume(_ mesh: Mesh) -> Double {
    var total: Double = 0
    for i in stride(from: 0, to: mesh.indices.count, by: 3) {
        let a = mesh.positions[Int(mesh.indices[i])], b = mesh.positions[Int(mesh.indices[i + 1])]
        let c = mesh.positions[Int(mesh.indices[i + 2])]
        let ax = Double(a.x.ticks), ay = Double(a.y.ticks), az = Double(a.z.ticks)
        let bx = Double(b.x.ticks), by = Double(b.y.ticks), bz = Double(b.z.ticks)
        let cx = Double(c.x.ticks), cy = Double(c.y.ticks), cz = Double(c.z.ticks)
        let x: Double = ax * (by * cz - bz * cy)
        let y: Double = ay * (bx * cz - bz * cx)
        let z: Double = az * (bx * cy - by * cx)
        total += (x - y + z) / 6
    }
    return total
}

private func face(_ o: Opening) -> Double { Double(o.width.ticks) * Double(o.height.ticks) }
private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 * max(abs(b), 1) }

@Test func aCasedOpeningGetsNoGlassAndNoLeaf() throws {
    let alone = try meshes([cased])
    #expect(material("glass", in: alone) == nil)
    #expect(material("door", in: alone) == nil)
    #expect(material("wall", in: alone) != nil)
}

@Test func onlyTheWindowIsGlazedAndOnlyTheDoorHasALeaf() throws {
    let all = try meshes([door, window, cased])
    // Each pane is drawn from both sides.
    let glass = try #require(material("glass", in: all))
    #expect(near(area(glass), 2 * face(window)))
    let leaf = try #require(material("door", in: all))
    #expect(near(area(leaf), 2 * face(door)))
}

@Test func theWallStaysAboveTheHeadAndBelowTheSillOfACasedOpening() throws {
    let solid = try #require(material("wall", in: try meshes([door, window, cased])))
    let thickness = Double(wall.thickness.ticks)
    let full: Double = Double(ft(20).ticks) * thickness * Double(wall.height.ticks)
    let holes: Double = (face(door) + face(window) + face(cased)) * thickness
    // The wall's footprint runs the 20' centerline with square ends, so only the three holes come out.
    #expect(near(volume(solid), full - holes))
    // The cased opening alone takes out its 4' by 6' hole and nothing more: 1' of wall below, 1' above.
    let alone = try #require(material("wall", in: try meshes([cased])))
    #expect(near(volume(alone), full - face(cased) * thickness))
}
