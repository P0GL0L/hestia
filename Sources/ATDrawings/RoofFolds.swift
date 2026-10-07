import ATContracts
import Foundation

/// The fold lines of a roof seen in elevation: its ridges, hips, and valleys that show inside the silhouette.
///
/// Read from the roof mesh alone. The roof's top is the highest upward-facing triangle over each plan point,
/// so overlapping wings (as the engine builds an L) meet where one wing's plane rises above the other's: the
/// valley, though no mesh edge lies there. Triangles in one plane, such as two wings' coplanar slopes, count
/// as one plane, so they fold nowhere. A fold is kept where the roof in front of it, toward the viewer, is no
/// higher than it; where it projects onto the silhouette it is left to the outline.
enum RoofFolds {
    struct Vec2 {
        var x: Double
        var y: Double
    }

    /// An upward-facing roof plane, z = a·x + b·y + c, and the triangles of it in plan.
    struct Plane {
        var a: Double
        var b: Double
        var c: Double
        var triangles: [[Vec2]]

        func z(_ x: Double, _ y: Double) -> Double { a * x + b * y + c }
    }

    /// A fold in model space, as plan points with heights.
    struct Segment {
        var x0: Double, y0: Double, z0: Double
        var x1: Double, y1: Double, z1: Double

        func point(_ t: Double) -> (Double, Double, Double) {
            (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, z0 + (z1 - z0) * t)
        }
    }

    /// Height tolerance, in ticks, for "level with the top" and "no higher than".
    static let tolerance = 3.0

    /// Fold lines to draw on one elevation, in its (h, z) coordinates, away from the silhouette `outlines`.
    /// `toward` is the plan direction from the building to the viewer; `project` maps a plan point to h.
    static func lines(
        meshes: [Mesh], toward: Vec2, outlines: [[Point2]], project: (Double, Double) -> Double
    ) -> [(Point2, Point2)] {
        let planes = planes(of: meshes)
        var drawn: [(Point2, Point2)] = []
        for fold in folds(planes) {
            for seen in visible(fold, planes: planes, toward: toward) {
                let (x0, y0, z0) = seen.point(0), (x1, y1, z1) = seen.point(1)
                let a = (h: project(x0, y0), z: z0), b = (h: project(x1, y1), z: z1)
                drawn += offSilhouette(from: a, to: b, outlines: outlines)
            }
        }
        return merged(drawn)
    }

    // MARK: - Planes

    static func planes(of meshes: [Mesh]) -> [Plane] {
        var planes: [Plane] = []
        for mesh in meshes {
            var i = 0
            while i + 2 < mesh.indices.count {
                let p = (0..<3).map { mesh.positions[Int(mesh.indices[i + $0])] }
                i += 3
                let v = p.map { (Double($0.x.ticks), Double($0.y.ticks), Double($0.z.ticks)) }
                let (ux, uy, uz) = (v[1].0 - v[0].0, v[1].1 - v[0].1, v[1].2 - v[0].2)
                let (wx, wy, wz) = (v[2].0 - v[0].0, v[2].1 - v[0].1, v[2].2 - v[0].2)
                let nx: Double = uy * wz - uz * wy
                let ny: Double = uz * wx - ux * wz
                let nz: Double = ux * wy - uy * wx
                let size: Double = (nx * nx + ny * ny + nz * nz).squareRoot()
                // Upward-facing only: the underside copies and vertical gable faces are not the roof's top.
                guard size > 0, nz / size > 1e-6 else { continue }
                let a: Double = -nx / nz, b: Double = -ny / nz
                let c: Double = v[0].2 - a * v[0].0 - b * v[0].1
                let triangle = v.map { Vec2(x: $0.0, y: $0.1) }
                let cx: Double = (v[0].0 + v[1].0 + v[2].0) / 3, cy: Double = (v[0].1 + v[1].1 + v[2].1) / 3
                if let index = planes.firstIndex(where: {
                    abs($0.a - a) < 1e-4 && abs($0.b - b) < 1e-4 && abs($0.z(cx, cy) - (a * cx + b * cy + c)) < tolerance
                }) {
                    planes[index].triangles.append(triangle)
                } else {
                    planes.append(Plane(a: a, b: b, c: c, triangles: [triangle]))
                }
            }
        }
        return planes
    }

    /// The roof's top over a plan point: the highest triangle there, or nil off the roof.
    static func top(_ planes: [Plane], _ x: Double, _ y: Double) -> Double? {
        var best: Double?
        for plane in planes where plane.triangles.contains(where: { contains($0, x, y) }) {
            let z = plane.z(x, y)
            best = max(best ?? z, z)
        }
        return best
    }

    static func contains(_ triangle: [Vec2], _ x: Double, _ y: Double) -> Bool {
        func side(_ p: Vec2, _ q: Vec2) -> Double { (q.x - p.x) * (y - p.y) - (q.y - p.y) * (x - p.x) }
        let d0 = side(triangle[0], triangle[1]), d1 = side(triangle[1], triangle[2]), d2 = side(triangle[2], triangle[0])
        let slack = 1e-6 * max(abs(d0), abs(d1), abs(d2), 1)
        return (d0 >= -slack && d1 >= -slack && d2 >= -slack) || (d0 <= slack && d1 <= slack && d2 <= slack)
    }

    /// Whether a plane is the roof's top at a plan point.
    static func active(_ plane: Plane, _ planes: [Plane], _ x: Double, _ y: Double) -> Bool {
        guard plane.triangles.contains(where: { contains($0, x, y) }), let top = top(planes, x, y) else { return false }
        return plane.z(x, y) >= top - tolerance
    }

    // MARK: - Folds

    /// Whether the roof's top changes from one plane to the other across the line at (x, y): level along it is
    /// not enough, since a plane can touch the top along a line and stay buried on both sides of it.
    static func creases(_ p: Plane, _ q: Plane, _ planes: [Plane], _ x: Double, _ y: Double, across n: Vec2) -> Bool {
        guard active(p, planes, x, y), active(q, planes, x, y) else { return false }
        let step = Double(Length.millimeters(1).ticks)
        let (ax, ay) = (x + n.x * step, y + n.y * step), (bx, by) = (x - n.x * step, y - n.y * step)
        let pThenQ = active(p, planes, ax, ay) && !active(q, planes, ax, ay)
            && active(q, planes, bx, by) && !active(p, planes, bx, by)
        let qThenP = active(q, planes, ax, ay) && !active(p, planes, ax, ay)
            && active(p, planes, bx, by) && !active(q, planes, bx, by)
        return pThenQ || qThenP
    }

    /// Every stretch where two planes meet with both on top.
    static func folds(_ planes: [Plane]) -> [Segment] {
        var segments: [Segment] = []
        let edges: [(Vec2, Vec2)] = planes.flatMap { plane in
            plane.triangles.flatMap { t in [(t[0], t[1]), (t[1], t[2]), (t[2], t[0])] }
        }
        for i in planes.indices {
            for j in planes.indices where j > i {
                let p = planes[i], q = planes[j]
                // Plan line where the two heights agree: da·x + db·y + dc = 0.
                let da: Double = p.a - q.a, db: Double = p.b - q.b, dc: Double = p.c - q.c
                let norm: Double = (da * da + db * db).squareRoot()
                guard norm > 1e-9 else { continue }
                let origin = Vec2(x: -da * dc / (norm * norm), y: -db * dc / (norm * norm))
                let along = Vec2(x: -db / norm, y: da / norm)
                // Stations along the line where anything can change: triangle edges and other planes crossing.
                var stations: [Double] = []
                for (e0, e1) in edges {
                    let ex = e1.x - e0.x, ey = e1.y - e0.y
                    let denominator: Double = along.x * ey - along.y * ex
                    guard abs(denominator) > 1e-12 else { continue }
                    let rx = e0.x - origin.x, ry = e0.y - origin.y
                    let t: Double = (rx * ey - ry * ex) / denominator
                    let s: Double = (rx * along.y - ry * along.x) / denominator
                    if s >= -1e-9, s <= 1 + 1e-9 { stations.append(t) }
                }
                for (k, r) in planes.enumerated() where k != i && k != j {
                    let slope: Double = (p.a - r.a) * along.x + (p.b - r.b) * along.y
                    guard abs(slope) > 1e-12 else { continue }
                    let at: Double = (p.a - r.a) * origin.x + (p.b - r.b) * origin.y + (p.c - r.c)
                    stations.append(-at / slope)
                }
                stations.sort()
                var run: (Double, Double)?
                for (t0, t1) in zip(stations, stations.dropFirst()) where t1 - t0 > 1 {
                    let t = (t0 + t1) / 2
                    let x = origin.x + along.x * t, y = origin.y + along.y * t
                    if creases(p, q, planes, x, y, across: Vec2(x: -along.y, y: along.x)) {
                        if let current = run, abs(current.1 - t0) < 1e-6 { run = (current.0, t1) } else {
                            if let current = run { segments.append(segment(p, origin, along, current)) }
                            run = (t0, t1)
                        }
                    }
                }
                if let current = run { segments.append(segment(p, origin, along, current)) }
            }
        }
        return segments
    }

    static func segment(_ plane: Plane, _ origin: Vec2, _ along: Vec2, _ run: (Double, Double)) -> Segment {
        let x0 = origin.x + along.x * run.0, y0 = origin.y + along.y * run.0
        let x1 = origin.x + along.x * run.1, y1 = origin.y + along.y * run.1
        return Segment(x0: x0, y0: y0, z0: plane.z(x0, y0), x1: x1, y1: y1, z1: plane.z(x1, y1))
    }

    // MARK: - Visibility

    /// Whether the roof in front of a point, toward the viewer, stays no higher than it.
    static func seen(_ x: Double, _ y: Double, _ z: Double, planes: [Plane], toward d: Vec2) -> Bool {
        for plane in planes {
            for triangle in plane.triangles {
                // The stretch of the ray from (x, y) along d that crosses the triangle, past the point itself.
                var low = 1.0, high = Double.infinity
                var empty = false
                // Inside is to the left of every edge of a counterclockwise triangle, to the right otherwise.
                let (t0, t1, t2) = (triangle[0], triangle[1], triangle[2])
                let area: Double = (t1.x - t0.x) * (t2.y - t0.y) - (t1.y - t0.y) * (t2.x - t0.x)
                guard abs(area) > 1e-9 else { continue }
                let sign: Double = area > 0 ? 1 : -1
                for (p, q) in [(t0, t1), (t1, t2), (t2, t0)] {
                    let ex = q.x - p.x, ey = q.y - p.y
                    let at: Double = sign * (ex * (y - p.y) - ey * (x - p.x))
                    let rate: Double = sign * (ex * d.y - ey * d.x)
                    if abs(rate) < 1e-12 {
                        if at < 0 { empty = true }
                    } else if rate > 0 {
                        low = max(low, -at / rate)
                    } else {
                        high = min(high, -at / rate)
                    }
                }
                guard !empty, high > low else { continue }
                for s in [low, high] where s.isFinite {
                    if plane.z(x + d.x * s, y + d.y * s) > z + tolerance { return false }
                }
            }
        }
        return true
    }

    /// The parts of a fold the viewer sees, to a tick along its length.
    static func visible(_ fold: Segment, planes: [Plane], toward: Vec2) -> [Segment] {
        func test(_ t: Double) -> Bool {
            let (x, y, z) = fold.point(t)
            return seen(x, y, z, planes: planes, toward: toward)
        }
        let length: Double = hypot(fold.x1 - fold.x0, fold.y1 - fold.y0)
        guard length > 1 else { return [] }
        return runs(samples: 48, length: length, test: test).map { t0, t1 in
            let (x0, y0, z0) = fold.point(t0), (x1, y1, z1) = fold.point(t1)
            return Segment(x0: x0, y0: y0, z0: z0, x1: x1, y1: y1, z1: z1)
        }
    }

    /// Stretches of [0, 1] where `test` holds, found on a grid and refined to a tick of `length`.
    static func runs(samples: Int, length: Double, test: (Double) -> Bool) -> [(Double, Double)] {
        let grid = (0...samples).map { Double($0) / Double(samples) }
        let marks = grid.map(test)
        func edge(_ a: Double, _ b: Double, _ insideAtA: Bool) -> Double {
            var (lo, hi) = (a, b)
            while (hi - lo) * length > 0.5 {
                let mid = (lo + hi) / 2
                if test(mid) == insideAtA { lo = mid } else { hi = mid }
            }
            return insideAtA ? lo : hi
        }
        var result: [(Double, Double)] = []
        var start: Double? = marks[0] ? 0 : nil
        for k in 1..<grid.count {
            if marks[k] != marks[k - 1] {
                let cut = edge(grid[k - 1], grid[k], marks[k - 1])
                if marks[k] { start = cut } else if let s = start { result.append((s, cut)); start = nil }
            }
        }
        if let s = start { result.append((s, 1)) }
        return result
    }

    // MARK: - Against the silhouette

    /// The parts of a projected fold not lying along the silhouette.
    static func offSilhouette(from a: (h: Double, z: Double), to b: (h: Double, z: Double), outlines: [[Point2]])
        -> [(Point2, Point2)] {
        let length: Double = hypot(b.h - a.h, b.z - a.z)
        guard length > Double(Length.millimeters(1).ticks) else { return [] }
        let edges: [((Double, Double), (Double, Double))] = outlines.flatMap { outline in
            zip(outline, outline.dropFirst() + outline.prefix(1)).map {
                ((Double($0.x.ticks), Double($0.y.ticks)), (Double($1.x.ticks), Double($1.y.ticks)))
            }
        }
        func off(_ t: Double) -> Bool {
            let h = a.h + (b.h - a.h) * t, z = a.z + (b.z - a.z) * t
            return !edges.contains { distance(h, z, $0.0, $0.1) <= 2 }
        }
        let minimum = Double(Length.millimeters(10).ticks)
        func at(_ t: Double) -> Point2 {
            let h: Double = a.h + (b.h - a.h) * t
            let z: Double = a.z + (b.z - a.z) * t
            return paperPoint(Int64(h.rounded()), Int64(z.rounded()))
        }
        return runs(samples: 48, length: length, test: off).compactMap { t0, t1 in
            guard (t1 - t0) * length >= minimum else { return nil }
            return (at(t0), at(t1))
        }
    }

    static func distance(_ h: Double, _ z: Double, _ p: (Double, Double), _ q: (Double, Double)) -> Double {
        let dx = q.0 - p.0, dz = q.1 - p.1
        let lengthSquared: Double = dx * dx + dz * dz
        guard lengthSquared > 0 else { return hypot(h - p.0, z - p.1) }
        let t: Double = max(0, min(1, ((h - p.0) * dx + (z - p.1) * dz) / lengthSquared))
        return hypot(h - (p.0 + dx * t), z - (p.1 + dz * t))
    }

    /// Joins lines that lie on one another, so a fold seen twice is drawn once.
    static func merged(_ lines: [(Point2, Point2)]) -> [(Point2, Point2)] {
        var result: [(Point2, Point2)] = []
        for line in lines {
            let a = (Double(line.0.x.ticks), Double(line.0.y.ticks)), b = (Double(line.1.x.ticks), Double(line.1.y.ticks))
            let covered = result.contains { other in
                let p = (Double(other.0.x.ticks), Double(other.0.y.ticks))
                let q = (Double(other.1.x.ticks), Double(other.1.y.ticks))
                return distance(a.0, a.1, p, q) <= 2 && distance(b.0, b.1, p, q) <= 2
            }
            if covered { continue }
            // Drop any line this one covers.
            result.removeAll { other in
                let p = (Double(other.0.x.ticks), Double(other.0.y.ticks))
                let q = (Double(other.1.x.ticks), Double(other.1.y.ticks))
                return distance(p.0, p.1, a, b) <= 2 && distance(q.0, q.1, a, b) <= 2
            }
            result.append(line)
        }
        return result
    }
}
