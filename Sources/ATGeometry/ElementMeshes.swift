import ATContracts
import Foundation

/// 3D meshes for model elements, all in absolute elevations.
enum ElementMeshes {
    // MARK: - Walls

    /// Full-height pieces between openings, sill and head pieces at each opening, and glass or a door leaf
    /// in each opening on the wall's centre plane.
    static func wall(_ wall: Wall, footprint: [Point2], openings: [Opening], base: Double) throws -> [Mesh] {
        let line = try WallLine(wall)
        let polygon = footprint.map(Vec.init)
        let top = base + Double(wall.height.ticks)
        var solid = MeshBuilder()
        for piece in try HestiaGeometryEngine.pieces(of: footprint, wall: wall, cutAt: openings) {
            solid.prism(piece.map(Vec.init), bottom: base, top: top)
        }
        var glass = MeshBuilder()
        var leaf = MeshBuilder()
        for opening in openings {
            let a = Double(opening.offsetAlongWall.ticks), b = a + Double(opening.width.ticks)
            let span = PolygonMath.clip(PolygonMath.clip(polygon, keepingBelow: b) { line.along($0) },
                                        keepingBelow: -a) { -line.along($0) }
            let sill = base + Double(opening.sillHeight.ticks)
            let head = sill + Double(opening.height.ticks)
            solid.prism(span, bottom: base, top: sill)
            solid.prism(span, bottom: head, top: top)
            let p0 = line.origin + line.u * a, p1 = line.origin + line.u * b
            let pane = [(p0.x, p0.y, sill), (p1.x, p1.y, sill), (p1.x, p1.y, head), (p0.x, p0.y, head)]
            let n = line.n
            if opening.kind.isDoor {
                leaf.face(pane, normal: (n.x, n.y, 0))
                leaf.face(pane.reversed(), normal: (-n.x, -n.y, 0))
            } else {
                glass.face(pane, normal: (n.x, n.y, 0))
                glass.face(pane.reversed(), normal: (-n.x, -n.y, 0))
            }
        }
        return [solid.mesh(elementID: wall.id.rawValue, material: "wall"),
                glass.mesh(elementID: wall.id.rawValue, material: "glass"),
                leaf.mesh(elementID: wall.id.rawValue, material: "door")].compactMap { $0 }
    }

    // MARK: - Slabs, columns, beams, stairs

    static func slab(_ slab: Slab, base: Double) -> Mesh? {
        var builder = MeshBuilder()
        let top = base + Double(slab.topOffset.ticks)
        builder.prism(slab.outline.map(Vec.init), bottom: top - Double(slab.thickness.ticks), top: top)
        return builder.mesh(elementID: slab.id.rawValue, material: "slab")
    }

    static func column(_ column: Column, base: Double) -> Mesh? {
        var builder = MeshBuilder()
        builder.prism(HestiaGeometryEngine.columnOutline(column).map(Vec.init), bottom: base,
                      top: base + Double(column.height.ticks))
        return builder.mesh(elementID: column.id.rawValue, material: "column")
    }

    static func beam(_ beam: Beam, base: Double) -> Mesh? {
        let start = Vec(beam.start), end = Vec(beam.end)
        let delta = end - start
        guard delta.length > 0 else { return nil }
        let n = (delta * (1 / delta.length)).leftNormal * (Double(beam.width.ticks) / 2)
        var builder = MeshBuilder()
        let top = base + Double(beam.topOffset.ticks)
        builder.prism([start - n, end - n, end + n, start + n], bottom: top - Double(beam.depth.ticks), top: top)
        return builder.mesh(elementID: beam.id.rawValue, material: "beam")
    }

    /// A solid stair: one block per tread, each rising one riser higher.
    static func stair(_ stair: Stair, base: Double) -> Mesh? {
        let start = Vec(stair.runStart), end = Vec(stair.runEnd)
        let delta = end - start
        guard delta.length > 0, stair.riserCount >= 2 else { return nil }
        let u = delta * (1 / delta.length)
        let n = u.leftNormal * (Double(stair.width.ticks) / 2)
        let treads = stair.riserCount - 1
        let run = delta.length / Double(treads)
        var builder = MeshBuilder()
        for step in 0..<treads {
            let a = start + u * (run * Double(step)), b = start + u * (run * Double(step + 1))
            builder.prism([a - n, b - n, b + n, a + n], bottom: base,
                          top: base + Double(stair.riserHeight.ticks) * Double(step + 1))
        }
        return builder.mesh(elementID: stair.id.rawValue, material: "stair")
    }

    // MARK: - Roofs

    /// Roof surfaces, patch by patch (see `RoofPatch`): each pitched plane where it is the lowest, rising from
    /// its outer eave, with vertical gable ends where an edge has no pitch. Where rectangle patches overlap they
    /// form the valleys. A flat patch is a 250 mm cap at the eave.
    static func roof(_ roof: Roof, base: Double) -> [Mesh] {
        var builder = MeshBuilder()
        for patch in RoofPatch.patches(of: roof, base: base) {
            if patch.isFlat {
                builder.prism(patch.outer, bottom: patch.eave, top: patch.eave + RoofPatch.thickness)
            } else {
                envelope(patch, into: &builder)
            }
        }
        return [builder.mesh(elementID: roof.id.rawValue, material: "roof")].compactMap { $0 }
    }

    /// Each pitched plane where it is the lowest over the patch, and vertical gable ends under unpitched edges.
    static func envelope(_ patch: RoofPatch, into builder: inout MeshBuilder) {
        let outer = patch.outer, count = outer.count
        let pitched = patch.pitched
        for i in pitched {
            var region = outer
            for j in pitched where j != i {
                region = PolygonMath.clip(region, keepingBelow: 0) { patch.height(i, $0) - patch.height(j, $0) }
            }
            guard region.count >= 3, abs(PolygonMath.twiceSignedArea(region)) > 1 else { continue }
            let d = patch.lines[i].direction, k = patch.slopes[i]!
            let normal = (k * d.y, -k * d.x, 1.0)
            let points = region.map { ($0.x, $0.y, patch.height(i, $0)) }
            builder.face(points, normal: normal)
            builder.face(points.reversed(), normal: (-normal.0, -normal.1, -normal.2))
        }
        // Gable ends: vertical faces under the roof along edges without a pitch.
        for i in patch.slopes.indices where patch.slopes[i] == nil {
            let a = outer[i], b = outer[(i + 1) % count]
            let d = b - a
            let length = d.length
            guard length > 0 else { continue }
            let u = d * (1 / length)
            var stops = [0.0, length]
            // Where any two planes' ridge crosses this edge.
            for j in pitched {
                for k in pitched where k > j {
                    let fa = patch.height(j, a) - patch.height(k, a), fb = patch.height(j, b) - patch.height(k, b)
                    if (fa < 0) != (fb < 0), fa != fb { stops.append(length * fa / (fa - fb)) }
                }
            }
            let points = stops.sorted().map { t -> (Double, Double, Double) in
                let p = a + u * t
                return (p.x, p.y, patch.surface(p))
            }
            let outline = [(a.x, a.y, patch.eave)] + points + [(b.x, b.y, patch.eave)]
            let outward = (u.y, -u.x, 0.0)
            builder.face(outline, normal: outward)
            builder.face(outline.reversed(), normal: (-outward.0, -outward.1, 0))
        }
    }

    static func isConvex(_ polygon: [Vec]) -> Bool {
        let turns = polygon.indices.map { i -> Double in
            let a = polygon[i], b = polygon[(i + 1) % polygon.count], c = polygon[(i + 2) % polygon.count]
            return (b - a).cross(c - b)
        }
        return turns.allSatisfy { $0 >= -1e-6 } || turns.allSatisfy { $0 <= 1e-6 }
    }

    static func isRectilinear(_ polygon: [Vec]) -> Bool {
        zip(polygon, polygon.dropFirst() + polygon.prefix(1)).allSatisfy { a, b in a.x == b.x || a.y == b.y }
    }

    static func contains(_ polygon: [Vec], _ p: Vec) -> Bool {
        var inside = false
        for (a, b) in zip(polygon, polygon.dropFirst() + polygon.prefix(1)) where (a.y > p.y) != (b.y > p.y) {
            let x = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
            if p.x < x { inside.toggle() }
        }
        return inside
    }

    /// The largest axis-aligned rectangles inside a rectilinear polygon, as (minX, maxX, minY, maxY).
    static func maximalRectangles(_ polygon: [Vec]) -> [(Double, Double, Double, Double)] {
        let xs = Array(Set(polygon.map(\.x))).sorted(), ys = Array(Set(polygon.map(\.y))).sorted()
        func filled(_ i0: Int, _ i1: Int, _ j0: Int, _ j1: Int) -> Bool {
            for i in i0..<i1 { for j in j0..<j1 {
                if !contains(polygon, Vec((xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2)) { return false }
            } }
            return true
        }
        var result: [(Int, Int, Int, Int)] = []
        for i0 in 0..<xs.count - 1 { for i1 in (i0 + 1)..<xs.count {
            for j0 in 0..<ys.count - 1 { for j1 in (j0 + 1)..<ys.count where filled(i0, i1, j0, j1) {
                result.append((i0, i1, j0, j1))
            } }
        } }
        let maximal = result.filter { r in
            !result.contains { s in s != r && s.0 <= r.0 && s.1 >= r.1 && s.2 <= r.2 && s.3 >= r.3 }
        }
        return maximal.map { (xs[$0.0], xs[$0.1], ys[$0.2], ys[$0.3]) }
    }

    /// A rectangle edge's overhang: the overhang of the footprint edge it lies on, or none inside the footprint.
    static func overhang(on edge: (Vec, Vec), footprint: [Vec], planes: [RoofPlane]) -> Double {
        for (i, (a, b)) in zip(footprint, footprint.dropFirst() + footprint.prefix(1)).enumerated() {
            let d = b - a
            guard abs(d.cross(edge.0 - a)) < 1, abs(d.cross(edge.1 - a)) < 1 else { continue }
            return Double(planes[i].overhang.ticks)
        }
        return 0
    }
}
