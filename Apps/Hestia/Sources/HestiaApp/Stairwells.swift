import ATContracts
import Foundation

/// The openings stairs need in the floors above them. Each flight (`WalkHouse.Flight`) cuts the ceilings of the
/// storey it starts on and the floors and slabs of the storey it reaches, over its whole run and width, so a walk
/// up a stair rises through a stairwell instead of through a ceiling or a floor.
///
/// A floor is cut by keeping the parts of it outside each well: before the flight, beyond it, and to either side
/// of it along its run. Concave outlines are split into triangles first, so clipping never bridges disconnected
/// pieces of a floor.
enum Stairwells {
    private struct PointKey: Hashable {
        var x: Int64
        var y: Int64

        init(_ point: (x: Double, y: Double)) {
            x = Int64((point.x * 1e8).rounded())
            y = Int64((point.y * 1e8).rounded())
        }

        func precedes(_ other: PointKey) -> Bool { x == other.x ? y < other.y : x < other.x }
    }

    private struct SegmentKey: Hashable {
        var first: PointKey
        var second: PointKey

        init(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) {
            let ka = PointKey(a), kb = PointKey(b)
            (first, second) = ka.precedes(kb) ? (ka, kb) : (kb, ka)
        }
    }

    private struct Segment {
        var count: Int
        var a: (x: Double, y: Double)
        var b: (x: Double, y: Double)
    }

    /// The parts of a plan outline (feet) outside every given well.
    static func outside(_ outline: [(x: Double, y: Double)], wells: [WalkHouse.Flight])
        -> [[(x: Double, y: Double)]] {
        guard !wells.isEmpty else { return outline.count >= 3 ? [outline] : [] }
        let ring = Triangulation.counterclockwise(outline)
        let ears = Triangulation.ears(ring)
        var pieces = isConvex(ring) ? [ring] : ears.map { [ring[$0.0], ring[$0.1], ring[$0.2]] }
        for well in wells {
            pieces = pieces.flatMap { piece -> [[(x: Double, y: Double)]] in
                // A part the well does not reach stays whole.
                guard !clip(piece, regions(well)[4]).isEmpty else { return [piece] }
                return regions(well).prefix(4).map { clip(piece, $0) }
                    .filter { abs(Triangulation.twiceArea($0)) > 1e-6 }
            }
        }
        return pieces
    }

    private static func isConvex(_ ring: [(x: Double, y: Double)]) -> Bool {
        guard ring.count >= 3 else { return false }
        return ring.indices.allSatisfy { index in
            let a = ring[index], b = ring[(index + 1) % ring.count], c = ring[(index + 2) % ring.count]
            return (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) >= -1e-9
        }
    }

    /// A half-plane: the points where `a * x + b * y <= c`.
    typealias HalfPlane = (a: Double, b: Double, c: Double)

    /// Before the flight, beyond it, to its left, and to its right along its run; then the well itself.
    static func regions(_ well: WalkHouse.Flight) -> [[HalfPlane]] {
        // along = (x - sx) * ux + (y - sy) * uy, across = -(x - sx) * uy + (y - sy) * ux.
        let along0 = well.startX * well.ux + well.startY * well.uy
        let across0 = -well.startX * well.uy + well.startY * well.ux
        let alongAtMost = { (value: Double) -> HalfPlane in (well.ux, well.uy, along0 + value) }
        let alongAtLeast = { (value: Double) -> HalfPlane in (-well.ux, -well.uy, -(along0 + value)) }
        let acrossAtMost = { (value: Double) -> HalfPlane in (-well.uy, well.ux, across0 + value) }
        let acrossAtLeast = { (value: Double) -> HalfPlane in (well.uy, -well.ux, -(across0 + value)) }
        let (length, half) = (well.length, well.halfWidth)
        return [
            [alongAtMost(0)],
            [alongAtLeast(length)],
            [alongAtLeast(0), alongAtMost(length), acrossAtLeast(half)],
            [alongAtLeast(0), alongAtMost(length), acrossAtMost(-half)],
            [alongAtLeast(0), alongAtMost(length), acrossAtLeast(-half), acrossAtMost(half)],
        ]
    }

    /// The outline clipped to the convex region where every half-plane holds (Sutherland–Hodgman), without
    /// repeated points.
    static func clip(_ outline: [(x: Double, y: Double)], _ region: [HalfPlane]) -> [(x: Double, y: Double)] {
        var points = outline
        for plane in region {
            guard !points.isEmpty else { break }
            var kept: [(x: Double, y: Double)] = []
            for index in points.indices {
                let p = points[index], q = points[(index + 1) % points.count]
                let fp = plane.a * p.x + plane.b * p.y - plane.c
                let fq = plane.a * q.x + plane.b * q.y - plane.c
                if fp <= 1e-9 { kept.append(p) }
                if (fp < -1e-9 && fq > 1e-9) || (fp > 1e-9 && fq < -1e-9) {
                    let t = fp / (fp - fq)
                    kept.append((p.x + (q.x - p.x) * t, p.y + (q.y - p.y) * t))
                }
            }
            points = kept
        }
        var unique: [(x: Double, y: Double)] = []
        for point in points {
            if let last = unique.last, abs(last.x - point.x) < 1e-9, abs(last.y - point.y) < 1e-9 { continue }
            unique.append(point)
        }
        if let first = unique.first, let last = unique.last, unique.count > 1,
           abs(first.x - last.x) < 1e-9, abs(first.y - last.y) < 1e-9 {
            unique.removeLast()
        }
        return unique.count >= 3 ? unique : []
    }

    /// A slab as a solid with its stairwells cut through. Its side faces follow the exposed boundary of the actual
    /// cut union, including partial and overlapping wells, rather than blindly drawing four sides for every well.
    static func slab(_ outline: [(x: Double, y: Double)], bottom: Double, top: Double, wells: [WalkHouse.Flight],
                     into solid: inout Solid) {
        let pieces = outside(outline, wells: wells)
        for piece in pieces {
            Shapes.flat(&solid, piece, height: top)
            Shapes.flat(&solid, piece, height: bottom, facingUp: false)
        }
        for edge in boundary(of: pieces) {
            side(edge.a, edge.b, bottom: bottom, top: top, into: &solid)
        }
    }

    /// Directed edges exposed around the union of non-overlapping pieces. Splitting at every collinear vertex
    /// lets adjacent pieces cancel even when one side was divided by a later well.
    private static func boundary(of pieces: [[(x: Double, y: Double)]]) -> [Segment] {
        let vertices = pieces.flatMap { $0 }
        var segments: [SegmentKey: Segment] = [:]
        for piece in pieces {
            let ring = Triangulation.counterclockwise(piece)
            for index in ring.indices {
                let a = ring[index], b = ring[(index + 1) % ring.count]
                let (dx, dy) = (b.x - a.x, b.y - a.y)
                let squared = dx * dx + dy * dy
                guard squared > 1e-18 else { continue }
                var cuts = [(t: 0.0, point: a), (t: 1.0, point: b)]
                for point in vertices {
                    let cross = dx * (point.y - a.y) - dy * (point.x - a.x)
                    guard abs(cross) <= 1e-8 * max(squared.squareRoot(), 1) else { continue }
                    let t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / squared
                    if t > 1e-9, t < 1 - 1e-9 { cuts.append((t, point)) }
                }
                cuts.sort { $0.t < $1.t }
                var unique: [(t: Double, point: (x: Double, y: Double))] = []
                for cut in cuts where unique.last.map({ abs($0.t - cut.t) > 1e-9 }) ?? true {
                    unique.append(cut)
                }
                for part in 0..<(unique.count - 1) {
                    let start = unique[part].point, end = unique[part + 1].point
                    let key = SegmentKey(start, end)
                    if var segment = segments[key] {
                        segment.count += 1
                        segments[key] = segment
                    } else {
                        segments[key] = Segment(count: 1, a: start, b: end)
                    }
                }
            }
        }
        return segments.values.filter { $0.count == 1 }
    }

    /// One upright face from `a` to `b`, facing to the right of that direction.
    private static func side(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double), bottom: Double,
                             top: Double, into solid: inout Solid) {
        let (dx, dy) = (b.x - a.x, b.y - a.y)
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1e-9 else { return }
        solid.addFan([(a.x, a.y, bottom), (b.x, b.y, bottom), (b.x, b.y, top), (a.x, a.y, top)],
                     normal: Solid.planNormal(dy / length, -dx / length, 0))
    }
}
