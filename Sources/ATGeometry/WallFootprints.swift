import ATContracts
import Foundation

/// Plan footprints for straight walls at any angle, joined where they meet.
///
/// Where wall ends share a point, each wall's faces are mitred against its angular neighbours, so L corners
/// meet cleanly and three or more ends fill the junction between them. Where a wall ends on another wall's
/// centerline (a T), the ending wall stops at the through wall's face and the through wall stays whole. Where
/// thinner walls end at a junction with thicker ones, the thicker walls join among themselves as if the thinner
/// ones were not there, and each thinner wall stops flush on their faces (square where the face is square to
/// it). Very sharp angles are bevelled at four wall thicknesses so a mitre never shoots off.
public struct WallFootprints: Sendable {
    public init() {}

    /// One closed counterclockwise polygon per wall.
    public func footprints(for walls: [Wall]) throws -> [WallID: [Point2]] {
        let geometry = try walls.map(WallLine.init)
        var ends: [JunctionPoint: [(index: Int, atStart: Bool)]] = [:]
        for (index, wall) in walls.enumerated() {
            ends[JunctionPoint(wall.start), default: []].append((index, true))
            ends[JunctionPoint(wall.end), default: []].append((index, false))
        }
        var result: [WallID: [Point2]] = [:]
        // Thickest first, so a thinner wall can stop on the finished outlines of the thicker ones it meets.
        var finished: [Int: [Vec]] = [:]
        let order = walls.indices.sorted { geometry[$0].half > geometry[$1].half }
        for index in order {
            let wall = walls[index]
            let start = cap(at: wall.start, wall: index, atStart: true, ends: ends, lines: geometry, finished: finished)
            let end = cap(at: wall.end, wall: index, atStart: false, ends: ends, lines: geometry, finished: finished)
            // Away from the start is +u, so its left face is +n; away from the end is -u, so its left is -n.
            var polygon = [start.right, end.left]
            if let node = end.node { polygon.append(node) }
            polygon += [end.right, start.left]
            if let node = start.node { polygon.append(node) }
            let rounded = polygon.map { $0.rounded() }
            result[wall.id] = rounded
            finished[index] = rounded.map(Vec.init)
        }
        return result
    }

    struct Cap {
        var left: Vec
        var right: Vec
        var node: Vec?
    }

    private struct Arm {
        var direction: Vec
        var half: Double
        var ending: Bool
        var wall: Int
    }

    private func cap(
        at point: Point2, wall: Int, atStart: Bool, ends: [JunctionPoint: [(index: Int, atStart: Bool)]],
        lines: [WallLine], finished: [Int: [Vec]]
    ) -> Cap {
        let node = Vec(point)
        var arms: [Arm] = []
        for end in ends[JunctionPoint(point)] ?? [] {
            let line = lines[end.index]
            arms.append(Arm(direction: end.atStart ? line.u : -line.u, half: line.half, ending: true, wall: end.index))
        }
        for (index, line) in lines.enumerated() where line.containsInterior(point) {
            arms.append(Arm(direction: line.u, half: line.half, ending: false, wall: index))
            arms.append(Arm(direction: -line.u, half: line.half, ending: false, wall: index))
        }
        let me = lines[wall]
        let away = atStart ? me.u : -me.u
        let leftNormal = away.leftNormal
        // Thicker walls ending here: stop flush on their outlines.
        let thicker = Set(arms.filter { $0.ending && $0.half > me.half + 1e-9 }.map(\.wall))
        let shapes = thicker.compactMap { finished[$0] }
        if !thicker.isEmpty, shapes.count == thicker.count {
            let limit = 4 * 2 * thicker.map { lines[$0].half }.max()!
            let leftStart = node + leftNormal * me.half, rightStart = node - leftNormal * me.half
            let left = leftStart + away * exit(from: leftStart, along: away, shapes: shapes, limit: limit)
            let right = rightStart + away * exit(from: rightStart, along: away, shapes: shapes, limit: limit)
            return Cap(left: left, right: right, node: nil)
        }
        // Thinner walls here join the thicker ones on their own; they do not shape this end.
        arms = arms.filter { $0.half >= me.half - 1e-9 }
        guard arms.count > 1 else {
            return Cap(left: node + leftNormal * me.half, right: node - leftNormal * me.half, node: nil)
        }
        arms.sort { $0.direction.angle < $1.direction.angle }
        guard let k = arms.firstIndex(where: { $0.wall == wall && $0.ending && ($0.direction - away).length < 1e-9 })
        else {
            return Cap(left: node + leftNormal * me.half, right: node - leftNormal * me.half, node: nil)
        }
        let next = arms[(k + 1) % arms.count]
        let previous = arms[(k - 1 + arms.count) % arms.count]
        let limit = 4 * max(me.half * 2, 1)
        // My left face meets the counterclockwise neighbour's right face.
        let left = corner(node: node, from: away, offset: me.half, side: 1,
                          to: next.direction, toOffset: next.half, toSide: -1, limit: limit)
        // My right face meets the clockwise neighbour's left face.
        let right = corner(node: node, from: away, offset: me.half, side: -1,
                           to: previous.direction, toOffset: previous.half, toSide: 1, limit: limit)
        let endingCount = arms.filter(\.ending).count
        let hasThrough = arms.contains { !$0.ending }
        return Cap(left: left, right: right, node: endingCount >= 3 && !hasThrough ? node : nil)
    }

    /// How far a ray runs from `start` before it leaves every one of `shapes`; zero when it starts outside.
    private func exit(from start: Vec, along direction: Vec, shapes: [[Vec]], limit: Double) -> Double {
        var stations: [Double] = [0, limit]
        for shape in shapes {
            for (a, b) in zip(shape, shape.dropFirst() + shape.prefix(1)) {
                let edge = b - a
                let denominator = direction.cross(edge)
                guard abs(denominator) > 1e-12 else { continue }
                let t: Double = (a - start).cross(edge) / denominator
                let s: Double = (a - start).cross(direction) / denominator
                if t > 0, t < limit, s >= -1e-9, s <= 1 + 1e-9 { stations.append(t) }
            }
        }
        stations.sort()
        for (t0, t1) in zip(stations, stations.dropFirst()) where t1 - t0 > 1e-6 {
            let middle = start + direction * ((t0 + t1) / 2)
            if !shapes.contains(where: { PolygonMath.contains($0, middle) }) { return t0 }
        }
        return limit
    }

    /// Where the face `side` of an arm along `from` meets face `toSide` of an arm along `to`.
    private func corner(
        node: Vec, from: Vec, offset: Double, side: Double, to: Vec, toOffset: Double, toSide: Double, limit: Double
    ) -> Vec {
        let p = node + from.leftNormal * (offset * side)
        let q = node + to.leftNormal * (toOffset * toSide)
        let denominator = from.cross(to)
        guard abs(denominator) > 1e-9 else { return p }
        let t = (q - p).cross(to) / denominator
        // Bevel very sharp mitres instead of letting them run out.
        return p + from * max(min(t, limit), -limit)
    }
}

/// A wall's centerline as unit direction, origin, length, and half thickness.
struct WallLine {
    var origin: Vec
    var u: Vec
    var length: Double
    var half: Double
    var startTicks: (Int64, Int64)
    var endTicks: (Int64, Int64)

    init(_ wall: Wall) throws {
        let start = Vec(wall.start), end = Vec(wall.end)
        let delta = end - start
        length = delta.length
        guard length > 0 else { throw GeometryError.zeroLengthWall(wall.id) }
        origin = start
        u = delta * (1 / length)
        half = Double(wall.thickness.ticks) / 2
        startTicks = (wall.start.x.ticks, wall.start.y.ticks)
        endTicks = (wall.end.x.ticks, wall.end.y.ticks)
    }

    var n: Vec { u.leftNormal }

    /// Exact test: the point lies on the centerline strictly between the ends.
    func containsInterior(_ point: Point2) -> Bool {
        let (sx, sy) = startTicks, (ex, ey) = endTicks
        let (px, py) = (point.x.ticks, point.y.ticks)
        let (dx, dy) = (ex - sx, ey - sy)
        let (rx, ry) = (px - sx, py - sy)
        guard dx.multipliedReportingOverflow(by: ry).partialValue == dy.multipliedReportingOverflow(by: rx).partialValue
        else { return false }
        let dot = rx * dx + ry * dy
        return dot > 0 && dot < dx * dx + dy * dy
    }

    /// Distance of a point along the centerline from the start.
    func along(_ p: Vec) -> Double { (p - origin).dot(u) }
}

/// A 2D vector in ticks, as doubles for intersection math. Results round back to ticks.
struct Vec: Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: Point2) {
        x = Double(point.x.ticks)
        y = Double(point.y.ticks)
    }

    static func + (a: Vec, b: Vec) -> Vec { Vec(a.x + b.x, a.y + b.y) }
    static func - (a: Vec, b: Vec) -> Vec { Vec(a.x - b.x, a.y - b.y) }
    static func * (a: Vec, s: Double) -> Vec { Vec(a.x * s, a.y * s) }
    static prefix func - (a: Vec) -> Vec { Vec(-a.x, -a.y) }

    func dot(_ b: Vec) -> Double { x * b.x + y * b.y }
    func cross(_ b: Vec) -> Double { x * b.y - y * b.x }
    var length: Double { (x * x + y * y).squareRoot() }
    var leftNormal: Vec { Vec(-y, x) }
    var angle: Double { atan2(y, x) }

    func rounded() -> Point2 {
        Point2(x: Length(ticks: Int64(x.rounded())), y: Length(ticks: Int64(y.rounded())))
    }
}

/// Polygon helpers shared by the engine.
enum PolygonMath {
    /// Twice the signed area; positive for counterclockwise.
    static func twiceSignedArea(_ points: [Vec]) -> Double {
        zip(points, points.dropFirst() + points.prefix(1)).reduce(0) { $0 + $1.0.cross($1.1) }
    }

    /// Whether a point lies inside a polygon, by ray casting.
    static func contains(_ polygon: [Vec], _ p: Vec) -> Bool {
        var inside = false
        for (a, b) in zip(polygon, polygon.dropFirst() + polygon.prefix(1)) where (a.y > p.y) != (b.y > p.y) {
            let x: Double = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
            if p.x < x { inside.toggle() }
        }
        return inside
    }

    /// Keeps the part of a polygon where `value(p) <= limit` (Sutherland–Hodgman against one line).
    static func clip(_ polygon: [Vec], keepingBelow limit: Double, of value: (Vec) -> Double) -> [Vec] {
        guard !polygon.isEmpty else { return [] }
        var output: [Vec] = []
        for (a, b) in zip(polygon, polygon.dropFirst() + polygon.prefix(1)) {
            let va = value(a) - limit, vb = value(b) - limit
            if va <= 0 { output.append(a) }
            if (va < 0 && vb > 0) || (va > 0 && vb < 0) {
                let t = va / (va - vb)
                output.append(a + (b - a) * t)
            }
        }
        return output
    }
}
