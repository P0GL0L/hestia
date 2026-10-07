import ATContracts
import Foundation

/// A room's boundary walls in an order that walks around the room, so where each wall's line meets the next
/// one's is a corner. A room keeps its walls in the order they were picked, which need not go around.
enum RoomWalk {
    /// The walls in walking order: the stored order when each wall already touches the next and the last
    /// touches the first, else the first such order found starting from the first wall, preferring the stored
    /// order at each step. Nil when the walls do not close into one loop, or are too few or too many to try.
    static func ordered(_ walls: [Wall]) -> [Wall]? {
        let count = walls.count
        guard count >= 3, count <= 16 else { return nil }
        var touching: [[Bool]] = Array(repeating: Array(repeating: false, count: count), count: count)
        for i in 0..<count {
            for j in (i + 1)..<count where touches(walls[i], walls[j]) {
                touching[i][j] = true
                touching[j][i] = true
            }
        }
        if (0..<count).allSatisfy({ touching[$0][($0 + 1) % count] }) { return walls }
        var path: [Int] = [0]
        var used: Set<Int> = [0]
        func extend() -> Bool {
            let last = path[path.count - 1]
            if path.count == count { return touching[last][0] }
            for next in 0..<count where !used.contains(next) && touching[last][next] {
                path.append(next)
                used.insert(next)
                if extend() { return true }
                path.removeLast()
                used.remove(next)
            }
            return false
        }
        return extend() ? path.map { walls[$0] } : nil
    }

    /// Whether two walls meet: their centerlines cross, or come within the thicker one's half thickness of
    /// each other (a wall stopping at another's face), plus a millimetre.
    static func touches(_ a: Wall, _ b: Wall) -> Bool {
        let reach: Double = Double(max(a.thickness.ticks, b.thickness.ticks)) / 2 + Double(Length.ticksPerMillimeter)
        return distance(a, b) <= reach
    }

    /// The shortest distance between two walls' centerline segments, in ticks.
    static func distance(_ a: Wall, _ b: Wall) -> Double {
        let p = point(a.start), q = point(a.end), r = point(b.start), s = point(b.end)
        if crosses(p, q, r, s) { return 0 }
        let ends: [Double] = [toSegment(p, r, s), toSegment(q, r, s), toSegment(r, p, q), toSegment(s, p, q)]
        return ends.min() ?? .infinity
    }

    private static func point(_ p: Point2) -> (Double, Double) {
        (Double(p.x.ticks), Double(p.y.ticks))
    }

    private static func cross(_ o: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> Double {
        (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
    }

    /// Whether segments pq and rs cross properly (each one's ends on opposite sides of the other).
    private static func crosses(
        _ p: (Double, Double), _ q: (Double, Double), _ r: (Double, Double), _ s: (Double, Double)
    ) -> Bool {
        let d1 = cross(r, s, p), d2 = cross(r, s, q), d3 = cross(p, q, r), d4 = cross(p, q, s)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    /// The distance from a point to the segment ab.
    private static func toSegment(_ p: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let dx = b.0 - a.0, dy = b.1 - a.1
        let lengthSquared: Double = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.0 - a.0, p.1 - a.1) }
        let t: Double = max(0, min(1, ((p.0 - a.0) * dx + (p.1 - a.1) * dy) / lengthSquared))
        return hypot(p.0 - (a.0 + dx * t), p.1 - (a.1 + dy * t))
    }

    /// The document with each room's boundary in walking order, for computing what follows from the order,
    /// such as areas. The document itself is not changed; rooms whose walls do not close keep their order.
    static func walked(_ document: ModelDocument) -> ModelDocument {
        var copy = document
        var walls: [WallID: Wall] = [:]
        for wall in document.walls { walls[wall.id] = wall }
        for index in copy.rooms.indices {
            let ids = copy.rooms[index].boundaryWallIDs
            let boundary = ids.compactMap { walls[$0] }
            guard boundary.count == ids.count, let walk = ordered(boundary) else { continue }
            copy.rooms[index].boundaryWallIDs = walk.map(\.id)
        }
        return copy
    }
}
