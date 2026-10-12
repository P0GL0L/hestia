import Foundation

/// A molding: a cross-section run along a straight length, as trim is milled. The cross-section's s runs across
/// the face of the trim and t out from the surface it is fixed to; both in feet. Extruding it to any length keeps
/// its profile exact, so the same casing fits every door and window.
struct Molding: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        var s: Double
        var t: Double
    }

    /// The cross-section, counterclockwise in (s, t), from the surface out and back.
    var section: [Point]

    var width: Double { (section.map(\.s).max() ?? 0) - (section.map(\.s).min() ?? 0) }
    var proud: Double { section.map(\.t).max() ?? 0 }

    /// Flat craftsman casing with eased edges and a shallow back band: symmetric, so legs and heads need no
    /// handedness. `width` across, `proud` out from the wall.
    static func casing(width: Double, proud: Double) -> Molding {
        let ease = min(proud * 0.4, width * 0.1)
        let band = width * 0.18
        let step = proud * 0.25
        return Molding(section: [
            Point(s: 0, t: 0), Point(s: width, t: 0),
            Point(s: width, t: proud - step - ease), Point(s: width - ease, t: proud - step),
            Point(s: width - band, t: proud - step), Point(s: width - band - ease, t: proud),
            Point(s: band + ease, t: proud), Point(s: band, t: proud - step),
            Point(s: ease, t: proud - step), Point(s: 0, t: proud - step - ease),
        ])
    }

    /// A baseboard: a tall flat board with a rounded cap at the top. s runs up from the floor.
    static func baseboard(height: Double, thickness: Double) -> Molding {
        let cap = height * 0.16
        let lip = thickness * 0.35
        return Molding(section: [
            Point(s: 0, t: 0), Point(s: height, t: 0),
            Point(s: height, t: thickness * 0.55), Point(s: height - cap * 0.35, t: thickness),
            Point(s: height - cap, t: thickness), Point(s: height - cap - lip * 0.6, t: thickness - lip),
            Point(s: 0, t: thickness - lip),
        ])
    }

    /// Adds the molding run from `start` along the unit vector `run` for `length`, with its section's s along
    /// the unit vector `across` and t along the unit vector `out`. All vectors are plan (x, y, height) in feet;
    /// `across` and `out` must be perpendicular to `run` and to each other.
    func extrude(_ solid: inout Solid, start: Vector, run: Vector, length: Double, across: Vector, out: Vector) {
        guard section.count >= 3, length > 0 else { return }
        func place(_ point: Point, _ along: Double) -> (Double, Double, Double) {
            let at = start + run * along + across * point.s + out * point.t
            return (at.x, at.y, at.z)
        }
        let ring = section
        for index in ring.indices {
            let a = ring[index], b = ring[(index + 1) % ring.count]
            let (ds, dt) = (b.s - a.s, b.t - a.t)
            let size = (ds * ds + dt * dt).squareRoot()
            guard size > 1e-9 else { continue }
            // Outward for a counterclockwise section: the edge turned clockwise.
            let normal = across * (dt / size) + out * (-ds / size)
            Self.face(&solid, [place(a, 0), place(b, 0), place(b, length), place(a, length)], normal: normal)
        }
        let flat = ring.map { (x: $0.s, y: $0.t) }
        let triangles = Triangulation.ears(Triangulation.counterclockwise(flat))
        let ordered = Triangulation.twiceArea(flat) < 0 ? Array(ring.reversed()) : ring
        for (end, sign) in [(0.0, -1.0), (length, 1.0)] {
            let points = ordered.map { place($0, end) }
            Self.triangles(&solid, points, triangles, normal: run * sign)
        }
    }

    /// A flat polygon wound counterclockwise as seen from `normal`, whichever way its points were given.
    private static func face(_ solid: inout Solid, _ points: [(Double, Double, Double)], normal: Vector) {
        let ordered = facing(points, normal) ? points : points.reversed()
        solid.addFan(ordered, normal: Solid.planNormal(normal.x, normal.y, normal.z))
    }

    private static func triangles(_ solid: inout Solid, _ points: [(Double, Double, Double)],
                                  _ triangles: [(Int, Int, Int)], normal: Vector) {
        guard let first = triangles.first else { return }
        let sample = [points[first.0], points[first.1], points[first.2]]
        let ordered = facing(sample, normal) ? triangles : triangles.map { ($0.0, $0.2, $0.1) }
        solid.addTriangles(points, ordered, normal: Solid.planNormal(normal.x, normal.y, normal.z))
    }

    /// Whether the first three points turn counterclockwise as seen from the side `normal` points to.
    private static func facing(_ points: [(Double, Double, Double)], _ normal: Vector) -> Bool {
        guard points.count >= 3 else { return true }
        let a = Vector(points[0]), b = Vector(points[1]), c = Vector(points[2])
        return (b - a).cross(c - a).dot(normal) >= 0
    }
}

/// A direction or point in plan space: x east, y north, z up, in feet.
struct Vector: Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        (self.x, self.y, self.z) = (x, y, z)
    }

    init(_ point: (Double, Double, Double)) {
        (x, y, z) = point
    }

    static func + (a: Vector, b: Vector) -> Vector { Vector(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vector, b: Vector) -> Vector { Vector(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: Vector, k: Double) -> Vector { Vector(a.x * k, a.y * k, a.z * k) }

    func dot(_ other: Vector) -> Double { x * other.x + y * other.y + z * other.z }

    func cross(_ other: Vector) -> Vector {
        Vector(y * other.z - z * other.y, z * other.x - x * other.z, x * other.y - y * other.x)
    }
}
