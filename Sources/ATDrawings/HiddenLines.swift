import ATContracts
import Foundation

/// Hidden-line drawing of the model's meshes from one side, as a draftsman draws an elevation or a roof plan:
/// only the edges that show, at their true position, nothing seen through anything nearer.
///
/// Every triangle is projected onto the picture (h, v) with its depth, so the nearest depth at any point can be
/// found. The edges worth drawing are found on the meshes themselves: an outline where a face toward the viewer
/// meets one turned away or none (a silhouette); a fold between faces toward the viewer at an angle (a ridge,
/// hip, valley, or corner); and where faces of two different elements cut through each other (a roof meeting a
/// wall or another roof), found by intersecting their triangles. Each edge is then walked along the picture and
/// kept only where nothing is nearer than it. An outline whose two sides are both flush, coplanar faces, such as
/// the joint between two walls in line, is left out.
enum HiddenLines {
    /// A projection: where a model point (x, y, z in ticks, z up) falls in the picture and how far it is from
    /// the viewer (smaller is nearer), all in ticks; and the direction toward the viewer, for telling which faces
    /// face it.
    struct View: Sendable {
        var project: @Sendable (Double, Double, Double) -> (h: Double, v: Double, depth: Double)
        var toward: (x: Double, y: Double, z: Double)
    }

    enum Kind: Equatable, Sendable {
        /// The outline of the drawing against the empty background.
        case profile
        /// An outline in front of something farther.
        case outline
        /// A fold between two faces that both face the viewer.
        case fold
        /// Where two elements cut through each other.
        case intersection
    }

    /// A visible stretch of an edge, in picture coordinates (ticks).
    struct Segment: Equatable, Sendable {
        var start: (h: Double, v: Double)
        var end: (h: Double, v: Double)
        var kind: Kind
        var elementID: UUID?

        static func == (a: Segment, b: Segment) -> Bool {
            a.start == b.start && a.end == b.end && a.kind == b.kind && a.elementID == b.elementID
        }
    }

    struct Triangle {
        var points: [(x: Double, y: Double, z: Double)]
        var picture: [(h: Double, v: Double, depth: Double)]
        var normal: (x: Double, y: Double, z: Double)
        var mesh: Int
        var elementID: UUID?
    }

    /// The visible edges of `meshes` seen through `view`. `cell` is the step, in ticks, at which edges are walked, and
    /// `tolerance` how much nearer something must be, in ticks, to hide an edge. With `near`, everything nearer
    /// than that depth is cut away first, as a section removes what lies in front of its cut; the cut itself
    /// draws no lines here, since the section draws it.
    static func segments(_ meshes: [Mesh], view: View, cell: Double, tolerance: Double, near: Double? = nil)
        -> [Segment] {
        let triangles = triangles(meshes, view: view, near: near)
        guard !triangles.isEmpty, cell > 0 else { return [] }
        let buffer = DepthBuffer(triangles, cell: cell)
        var found: [Segment] = []
        var candidates = edges(triangles, view: view) + intersections(triangles, view: view)
        if let near {
            candidates.removeAll { edge in
                abs(view.project(edge.a.x, edge.a.y, edge.a.z).depth - near) < 1
                    && abs(view.project(edge.b.x, edge.b.y, edge.b.z).depth - near) < 1
            }
        }
        for edge in candidates {
            found += visible(edge, view: view, buffer: buffer, tolerance: tolerance)
        }
        return found
    }

    // MARK: - Triangles

    static func triangles(_ meshes: [Mesh], view: View, near: Double? = nil) -> [Triangle] {
        var result: [Triangle] = []
        for (index, mesh) in meshes.enumerated() {
            let points = mesh.positions.map { (x: Double($0.x.ticks), y: Double($0.y.ticks), z: Double($0.z.ticks)) }
            let pictured = points.map { view.project($0.x, $0.y, $0.z) }
            var corner = 0
            while corner + 2 < mesh.indices.count {
                let a = Int(mesh.indices[corner]), b = Int(mesh.indices[corner + 1])
                let c = Int(mesh.indices[corner + 2])
                corner += 3
                guard a < points.count, b < points.count, c < points.count else { continue }
                let (p, q, r) = (points[a], points[b], points[c])
                let u = (q.x - p.x, q.y - p.y, q.z - p.z), w = (r.x - p.x, r.y - p.y, r.z - p.z)
                let n = (u.1 * w.2 - u.2 * w.1, u.2 * w.0 - u.0 * w.2, u.0 * w.1 - u.1 * w.0)
                let size = (n.0 * n.0 + n.1 * n.1 + n.2 * n.2).squareRoot()
                guard size > 1e-9 else { continue }
                let normal = (n.0 / size, n.1 / size, n.2 / size)
                let corners = [p, q, r], seen = [pictured[a], pictured[b], pictured[c]]
                guard let near, seen.contains(where: { $0.depth < near }) else {
                    result.append(Triangle(points: corners, picture: seen, normal: normal, mesh: index,
                                           elementID: mesh.elementID))
                    continue
                }
                // Keep the part at or beyond `near`, fanned back into triangles.
                let kept = clip(corners, seen.map(\.depth), near: near)
                guard kept.count >= 3 else { continue }
                for k in 1..<(kept.count - 1) {
                    let points = [kept[0], kept[k], kept[k + 1]]
                    result.append(Triangle(points: points, picture: points.map { view.project($0.x, $0.y, $0.z) },
                                           normal: normal, mesh: index, elementID: mesh.elementID))
                }
            }
        }
        return result
    }

    /// A polygon's part whose depth is at least `near`, with points on the cut where it crosses.
    static func clip(_ points: [(x: Double, y: Double, z: Double)], _ depths: [Double], near: Double)
        -> [(x: Double, y: Double, z: Double)] {
        var kept: [(x: Double, y: Double, z: Double)] = []
        for i in points.indices {
            let j = (i + 1) % points.count
            let (p, q, dp, dq) = (points[i], points[j], depths[i], depths[j])
            if dp >= near { kept.append(p) }
            if (dp >= near) != (dq >= near) {
                let k = (near - dp) / (dq - dp)
                kept.append((p.x + (q.x - p.x) * k, p.y + (q.y - p.y) * k, p.z + (q.z - p.z) * k))
            }
        }
        return kept
    }

    // MARK: - Depth

    /// The nearest depth anywhere on the picture, found exactly from the triangles there: they are filed in bins
    /// on a coarse grid, and a query interpolates the depth of each one holding the point. Exact depths matter at
    /// a silhouette, where a face seen almost edge-on changes depth quickly across any grid cell. `cell` is the
    /// step at which edges are walked.
    struct DepthBuffer {
        var cell: Double
        private var triangles: [[(h: Double, v: Double, depth: Double)]]
        private var h0: Double
        private var v0: Double
        private var bin: Double
        private var columns: Int
        private var rows: Int
        private var bins: [[Int32]]

        init(_ triangles: [Triangle], cell: Double) {
            self.cell = cell
            self.triangles = triangles.map(\.picture)
            let hs = triangles.flatMap { $0.picture.map(\.h) }, vs = triangles.flatMap { $0.picture.map(\.v) }
            h0 = (hs.min() ?? 0) - cell
            v0 = (vs.min() ?? 0) - cell
            let width = (hs.max() ?? 0) + cell - h0, height = (vs.max() ?? 0) + cell - v0
            bin = max(max(width, height) / 256, cell)
            columns = max(Int(width / bin) + 1, 1)
            rows = max(Int(height / bin) + 1, 1)
            bins = [[Int32]](repeating: [], count: columns * rows)
            for (index, p) in self.triangles.enumerated() {
                let area = (p[1].h - p[0].h) * (p[2].v - p[0].v) - (p[2].h - p[0].h) * (p[1].v - p[0].v)
                guard abs(area) > 1e-9 else { continue }
                let c0 = max(Int((min(p[0].h, p[1].h, p[2].h) - h0) / bin), 0)
                let c1 = min(Int((max(p[0].h, p[1].h, p[2].h) - h0) / bin), columns - 1)
                let r0 = max(Int((min(p[0].v, p[1].v, p[2].v) - v0) / bin), 0)
                let r1 = min(Int((max(p[0].v, p[1].v, p[2].v) - v0) / bin), rows - 1)
                guard c0 <= c1, r0 <= r1 else { continue }
                for row in r0...r1 {
                    for column in c0...c1 { bins[row * columns + column].append(Int32(index)) }
                }
            }
        }

        /// The nearest depth at (h, v); infinity where nothing is drawn. A point on a triangle's edge counts as
        /// on it, to within a hundredth of a tick.
        func at(_ h: Double, _ v: Double) -> Double {
            let column = Int(((h - h0) / bin).rounded(.down)), row = Int(((v - v0) / bin).rounded(.down))
            guard column >= 0, row >= 0, column < columns, row < rows else { return .infinity }
            var nearest = Double.infinity
            for index in bins[row * columns + column] {
                let p = triangles[Int(index)]
                let area = (p[1].h - p[0].h) * (p[2].v - p[0].v) - (p[2].h - p[0].h) * (p[1].v - p[0].v)
                let w0 = ((p[1].h - h) * (p[2].v - v) - (p[2].h - h) * (p[1].v - v)) / area
                let w1 = ((p[2].h - h) * (p[0].v - v) - (p[0].h - h) * (p[2].v - v)) / area
                let w2 = 1 - w0 - w1
                // The slack, as a share of the triangle, that is no more than a tick across any of its sides.
                let span = max(abs(p[1].h - p[0].h) + abs(p[1].v - p[0].v), abs(p[2].h - p[0].h) + abs(p[2].v - p[0].v),
                               abs(p[2].h - p[1].h) + abs(p[2].v - p[1].v))
                let slack = -span / abs(area)
                guard w0 >= slack, w1 >= slack, w2 >= slack else { continue }
                nearest = min(nearest, w0 * p[0].depth + w1 * p[1].depth + w2 * p[2].depth)
            }
            return nearest
        }
    }

    // MARK: - Edges

    /// An edge to test: its ends in the model and its kind.
    struct Edge {
        var a: (x: Double, y: Double, z: Double)
        var b: (x: Double, y: Double, z: Double)
        var kind: Kind
        var elementID: UUID?
    }

    /// Outlines and folds: every edge whose faces turned toward the viewer are one (an outline) or meet at an
    /// angle (a fold). Faces are matched across meshes by their exact corner positions.
    static func edges(_ triangles: [Triangle], view: View) -> [Edge] {
        struct Key: Hashable {
            var a: [Int64]
            var b: [Int64]
        }
        func key(_ p: (x: Double, y: Double, z: Double)) -> [Int64] {
            [Int64(p.x.rounded()), Int64(p.y.rounded()), Int64(p.z.rounded())]
        }
        var sides: [Key: [Int]] = [:]
        for (index, triangle) in triangles.enumerated() {
            for corner in 0..<3 {
                let (p, q) = (key(triangle.points[corner]), key(triangle.points[(corner + 1) % 3]))
                let edge = p.lexicographicallyPrecedes(q) ? Key(a: p, b: q) : Key(a: q, b: p)
                sides[edge, default: []].append(index)
            }
        }
        let toward = view.toward
        func facing(_ triangle: Triangle) -> Bool {
            triangle.normal.x * toward.x + triangle.normal.y * toward.y + triangle.normal.z * toward.z > 1e-6
        }
        var result: [Edge] = []
        for (edge, faces) in sides {
            let front = faces.filter { facing(triangles[$0]) }
            guard let first = front.first else { continue }
            let a = (x: Double(edge.a[0]), y: Double(edge.a[1]), z: Double(edge.a[2]))
            let b = (x: Double(edge.b[0]), y: Double(edge.b[1]), z: Double(edge.b[2]))
            let n = triangles[first].normal
            let folded = front.contains { other in
                let m = triangles[other].normal
                return n.x * m.x + n.y * m.y + n.z * m.z < 0.9998
            }
            if folded {
                result.append(Edge(a: a, b: b, kind: .fold, elementID: triangles[first].elementID))
            } else if front.count == 1 {
                result.append(Edge(a: a, b: b, kind: .outline, elementID: triangles[first].elementID))
            }
        }
        return result
    }

    /// Where triangles of two different elements cut through each other, as segments in the model. Triangles
    /// only touching, or lying in one plane, give none.
    static func intersections(_ triangles: [Triangle], view: View) -> [Edge] {
        // Bucket triangles by a coarse grid over their model boxes, so only neighbours are compared.
        let all = triangles.flatMap { $0.points }
        guard let x0 = all.map(\.x).min(), let x1 = all.map(\.x).max(), let y0 = all.map(\.y).min(),
              let y1 = all.map(\.y).max() else { return [] }
        let size = max(max(x1 - x0, y1 - y0) / 64, 1)
        var buckets: [Int: [Int]] = [:]
        func boxes(_ triangle: Triangle) -> [Int] {
            let xs = triangle.points.map(\.x), ys = triangle.points.map(\.y)
            let c0 = Int(((xs.min() ?? 0) - x0) / size), c1 = Int(((xs.max() ?? 0) - x0) / size)
            let r0 = Int(((ys.min() ?? 0) - y0) / size), r1 = Int(((ys.max() ?? 0) - y0) / size)
            return (r0...r1).flatMap { row in (c0...c1).map { row * 100_000 + $0 } }
        }
        for (index, triangle) in triangles.enumerated() {
            for box in boxes(triangle) { buckets[box, default: []].append(index) }
        }
        // Each triangle's box in the model, to pass over pairs that cannot meet.
        let lows = triangles.map { t in
            (x: min(t.points[0].x, t.points[1].x, t.points[2].x), y: min(t.points[0].y, t.points[1].y, t.points[2].y),
             z: min(t.points[0].z, t.points[1].z, t.points[2].z))
        }
        let highs = triangles.map { t in
            (x: max(t.points[0].x, t.points[1].x, t.points[2].x), y: max(t.points[0].y, t.points[1].y, t.points[2].y),
             z: max(t.points[0].z, t.points[1].z, t.points[2].z))
        }
        func apart(_ a: Int, _ b: Int) -> Bool {
            lows[a].x > highs[b].x || lows[b].x > highs[a].x || lows[a].y > highs[b].y || lows[b].y > highs[a].y
                || lows[a].z > highs[b].z || lows[b].z > highs[a].z
        }
        var seen = Set<Int>()
        var result: [Edge] = []
        for members in buckets.values where members.count > 1 {
            for i in members.indices {
                for j in members.indices where j > i {
                    let (a, b) = (members[i], members[j])
                    guard !apart(a, b) else { continue }
                    let (first, second) = (triangles[a], triangles[b])
                    guard first.mesh != second.mesh, first.elementID != second.elementID || first.elementID == nil
                    else { continue }
                    let pair = min(a, b) * triangles.count + max(a, b)
                    guard seen.insert(pair).inserted else { continue }
                    if let cut = cut(first, second) {
                        result.append(Edge(a: cut.0, b: cut.1, kind: .intersection, elementID: first.elementID))
                    }
                }
            }
        }
        return result
    }

    /// The segment where two triangles cross, if they do.
    static func cut(_ s: Triangle, _ t: Triangle) -> ((x: Double, y: Double, z: Double),
                                                       (x: Double, y: Double, z: Double))? {
        func dot(_ p: (x: Double, y: Double, z: Double), _ n: (x: Double, y: Double, z: Double)) -> Double {
            p.x * n.x + p.y * n.y + p.z * n.z
        }
        // Coplanar or parallel faces do not cut.
        let cross = (s.normal.y * t.normal.z - s.normal.z * t.normal.y,
                     s.normal.z * t.normal.x - s.normal.x * t.normal.z,
                     s.normal.x * t.normal.y - s.normal.y * t.normal.x)
        let length = (cross.0 * cross.0 + cross.1 * cross.1 + cross.2 * cross.2).squareRoot()
        guard length > 1e-4 else { return nil }
        let direction = (x: cross.0 / length, y: cross.1 / length, z: cross.2 / length)
        /// The stretch of the line, as parameters along `direction`, where triangle `a` meets plane `b`.
        func span(_ a: Triangle, on b: Triangle) -> (Double, Double)? {
            let offset = dot(b.points[0], b.normal)
            let distances = a.points.map { dot($0, b.normal) - offset }
            let epsilon = 0.5
            guard !(distances.allSatisfy { $0 > epsilon } || distances.allSatisfy { $0 < -epsilon }) else { return nil }
            var params: [Double] = []
            for i in 0..<3 {
                let (p, q) = (a.points[i], a.points[(i + 1) % 3])
                let (dp, dq) = (distances[i], distances[(i + 1) % 3])
                if abs(dp) <= epsilon { params.append(dot(p, direction)) }
                if (dp > epsilon && dq < -epsilon) || (dp < -epsilon && dq > epsilon) {
                    let k = dp / (dp - dq)
                    let x = (x: p.x + (q.x - p.x) * k, y: p.y + (q.y - p.y) * k, z: p.z + (q.z - p.z) * k)
                    params.append(dot(x, direction))
                }
            }
            guard let low = params.min(), let high = params.max() else { return nil }
            return (low, high)
        }
        // Faces that only touch, end to end or edge to face, do not cut through each other; their meeting is a
        // mesh edge already. One of them must pass through the other's plane.
        func crosses(_ a: Triangle, _ b: Triangle) -> Bool {
            let offset = dot(b.points[0], b.normal)
            let distances = a.points.map { dot($0, b.normal) - offset }
            return distances.contains { $0 > 0.5 } && distances.contains { $0 < -0.5 }
        }
        guard crosses(s, t) || crosses(t, s) else { return nil }
        guard let first = span(s, on: t), let second = span(t, on: s) else { return nil }
        let (low, high) = (max(first.0, second.0), min(first.1, second.1))
        guard high - low > 1 else { return nil }
        // A point on both planes, to place the line.
        let d1 = dot(s.points[0], s.normal), d2 = dot(t.points[0], t.normal)
        let n1 = s.normal, n2 = t.normal
        let n1n2 = dot(n1, n2)
        let det = 1 - n1n2 * n1n2
        guard abs(det) > 1e-9 else { return nil }
        let c1 = (d1 - d2 * n1n2) / det, c2 = (d2 - d1 * n1n2) / det
        let origin = (x: c1 * n1.x + c2 * n2.x, y: c1 * n1.y + c2 * n2.y, z: c1 * n1.z + c2 * n2.z)
        let along = dot(origin, direction)
        func point(_ parameter: Double) -> (x: Double, y: Double, z: Double) {
            let k = parameter - along
            return (origin.x + direction.x * k, origin.y + direction.y * k, origin.z + direction.z * k)
        }
        return (point(low), point(high))
    }

    // MARK: - Visibility

    /// The stretches of an edge nothing hides. The edge is walked every two cells, and wherever what is seen
    /// changes between two steps the change is found to an eighth of a cell, so a hidden stretch narrower than
    /// two cells can be missed, and a visible one shorter than a cell is left out. An outline is dropped where
    /// both of its sides are flush with it (a joint within one surface), and becomes a profile where either side
    /// is empty.
    static func visible(_ edge: Edge, view: View, buffer: DepthBuffer, tolerance: Double) -> [Segment] {
        let (pa, pb) = (view.project(edge.a.x, edge.a.y, edge.a.z), view.project(edge.b.x, edge.b.y, edge.b.z))
        let (dh, dv) = (pb.h - pa.h, pb.v - pa.v)
        let length = (dh * dh + dv * dv).squareRoot()
        guard length > 1e-6 else { return [] }
        let steps = max(Int((length / (buffer.cell * 2)).rounded(.up)), 1)
        // Across the edge in the picture, a quarter of a cell each way.
        let (nh, nv) = (-dv / length * buffer.cell / 4, dh / length * buffer.cell / 4)
        /// What shows at a share `t` along the edge: nil where it is hidden, else its kind there.
        func seen(_ t: Double) -> Kind? {
            let (h, v, d) = (pa.h + dh * t, pa.v + dv * t, pa.depth + (pb.depth - pa.depth) * t)
            // Shown where nothing is nearer at that point by more than the tolerance.
            guard d <= buffer.at(h, v) + tolerance else { return nil }
            guard edge.kind == .outline else { return edge.kind }
            let (left, right) = (buffer.at(h + nh, v + nv), buffer.at(h - nh, v - nv))
            if abs(left - d) <= tolerance && abs(right - d) <= tolerance { return nil }
            return left == .infinity || right == .infinity ? .profile : .outline
        }
        let precision = buffer.cell / 8 / length
        var result: [Segment] = []
        var run: (start: Double, kind: Kind)?
        var previous = (t: 0.0, kind: seen(0))
        if let kind = previous.kind { run = (0, kind) }
        // A run shorter than a cell is a sliver where the edge meets what hides it, not a line worth drawing.
        let shortest = buffer.cell / length
        func close(at t: Double) {
            guard let open = run, t - open.start >= shortest else { run = nil; return }
            result.append(Segment(start: (pa.h + dh * open.start, pa.v + dv * open.start),
                                  end: (pa.h + dh * t, pa.v + dv * t), kind: open.kind, elementID: edge.elementID))
            run = nil
        }
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let kind = seen(t)
            if kind != previous.kind {
                // Narrow the change down between the last step and this one.
                var (low, high) = (previous.t, t)
                while high - low > precision {
                    let middle = (low + high) / 2
                    if seen(middle) == previous.kind { low = middle } else { high = middle }
                }
                let change = (low + high) / 2
                close(at: change)
                if let kind { run = (change, kind) }
            }
            previous = (t, kind)
        }
        close(at: 1)
        return result
    }
}
