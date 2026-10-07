import ATContracts
import Foundation

/// The outline of a mesh seen from the side: its triangles projected to (h, z) and merged.
///
/// Between two consecutive vertex positions along h, every triangle that spans the stretch is bounded by two
/// straight edges, so the silhouette there is the upper envelope of the top edges and the lower envelope of
/// the bottom edges, both exact. Triangles seen edge on add no area and are skipped. Stretches no triangle
/// covers split the result into separate outlines. A shape that a vertical line meets in two separate pieces
/// is outlined as one, from its lowest to its highest point, which suits roofs.
enum MeshSilhouette {
    typealias Point = (h: Double, z: Double)

    /// The projected outline of `mesh`, each point mapped by `project` from a model point to (h, z).
    static func outlines(of meshes: [Mesh], project: (Point3) -> Point) -> [[Point2]] {
        var triangles: [[Point]] = []
        for mesh in meshes {
            var i = 0
            while i + 2 < mesh.indices.count {
                let corners = (0..<3).map { project(mesh.positions[Int(mesh.indices[i + $0])]) }
                i += 3
                let twiceArea: Double = (corners[1].h - corners[0].h) * (corners[2].z - corners[0].z)
                    - (corners[2].h - corners[0].h) * (corners[1].z - corners[0].z)
                if abs(twiceArea) > 0.5 { triangles.append(corners) }
            }
        }
        return outlines(triangles)
    }

    static func outlines(_ triangles: [[Point]]) -> [[Point2]] {
        let stations = Array(Set(triangles.flatMap { $0.map(\.h) })).sorted()
        var result: [[Point2]] = []
        var top: [Point] = []
        var bottom: [Point] = []
        func close() {
            if !top.isEmpty { result.append(simplified(top + bottom.reversed())) }
            top = []
            bottom = []
        }
        for (a, b) in zip(stations, stations.dropFirst()) where b > a {
            var upper: [Line] = []
            var lower: [Line] = []
            for triangle in triangles {
                guard let (high, low) = bounds(triangle, from: a, to: b) else { continue }
                upper.append(high)
                lower.append(low)
            }
            guard !upper.isEmpty else {
                close()
                continue
            }
            let tops = envelope(upper, from: a, to: b, highest: true)
            let bottoms = envelope(lower, from: a, to: b, highest: false)
            top += tops
            bottom += bottoms
        }
        close()
        return result
    }

    /// z along h, as a straight edge.
    struct Line {
        var h0: Double
        var z0: Double
        var slope: Double

        func z(_ h: Double) -> Double { z0 + (h - h0) * slope }
    }

    /// The top and bottom edges of a triangle over [a, b], or nil when it does not span the stretch.
    static func bounds(_ triangle: [Point], from a: Double, to b: Double) -> (Line, Line)? {
        var edges: [Line] = []
        for (p, q) in [(triangle[0], triangle[1]), (triangle[1], triangle[2]), (triangle[2], triangle[0])] {
            guard p.h != q.h, min(p.h, q.h) <= a, max(p.h, q.h) >= b else { continue }
            edges.append(Line(h0: p.h, z0: p.z, slope: (q.z - p.z) / (q.h - p.h)))
        }
        guard edges.count == 2 else { return nil }
        let middle = (a + b) / 2
        return edges[0].z(middle) >= edges[1].z(middle) ? (edges[0], edges[1]) : (edges[1], edges[0])
    }

    /// The highest (or lowest) of the lines over [a, b], at every station where it can bend.
    static func envelope(_ lines: [Line], from a: Double, to b: Double, highest: Bool) -> [Point] {
        var stations = [a, b]
        for i in lines.indices {
            for j in lines.indices where j > i {
                let dSlope: Double = lines[i].slope - lines[j].slope
                guard abs(dSlope) > 1e-12 else { continue }
                // Where the two lines meet.
                let gap: Double = lines[j].z(a) - lines[i].z(a)
                let h: Double = a + gap / dSlope
                if h > a, h < b { stations.append(h) }
            }
        }
        return stations.sorted().map { h in
            let zs = lines.map { $0.z(h) }
            return (h, highest ? zs.max()! : zs.min()!)
        }
    }

    /// Rounds to ticks and drops repeated points and points within a tick of a straight run.
    static func simplified(_ points: [Point]) -> [Point2] {
        var result: [Point2] = []
        for point in points {
            let p = paperPoint(Int64(point.h.rounded()), Int64(point.z.rounded()))
            if result.last != p { result.append(p) }
        }
        if result.count > 1, result.first == result.last { result.removeLast() }
        var changed = true
        while changed, result.count > 3 {
            changed = false
            for i in result.indices {
                let a = result[(i - 1 + result.count) % result.count], b = result[i]
                let c = result[(i + 1) % result.count]
                // Within a tick of the straight line from a to c, and between them: b adds nothing.
                let abx = Double(b.x.ticks - a.x.ticks), aby = Double(b.y.ticks - a.y.ticks)
                let acx = Double(c.x.ticks - a.x.ticks), acy = Double(c.y.ticks - a.y.ticks)
                let chord: Double = max(hypot(acx, acy), 1)
                let offLine: Double = abs(abx * acy - aby * acx) / chord
                let along: Double = (abx * acx + aby * acy) / (chord * chord)
                if offLine <= 1, along > 0, along < 1 {
                    result.remove(at: i)
                    changed = true
                    break
                }
            }
        }
        return result
    }
}
