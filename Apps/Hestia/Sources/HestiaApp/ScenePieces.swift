import Foundation

/// A point or direction in the 3D view: feet, y up, x east, and z south, so plan north runs toward -z.
struct ScenePoint: Equatable, Sendable {
    var x: Float
    var y: Float
    var z: Float

    init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// A plan point in feet (x east, y north) at a height in feet, in view space.
    static func plan(_ x: Double, _ y: Double, _ height: Double) -> ScenePoint {
        ScenePoint(Float(x), Float(height), Float(-y))
    }
}

/// How a surface looks in the 3D view. The colors are schematic, picked to read clearly in daylight.
enum Look: String, CaseIterable, Sendable {
    case wall, glass, door, roof, slab, stair, structure
    case woodFloor, tileFloor, carpet, ceiling
    case grass, lawn, concrete, paving, gravel, water, mulch, deck
    case fabric, fabricDark, leather, wood, woodDark, white, metal, porcelain, stone, linen, black
    case trunk, foliage, foliageDark, blossom

    /// sRGB red, green, blue, each 0...1.
    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .wall: return (0.93, 0.91, 0.87)
        case .glass: return (0.62, 0.80, 0.92)
        case .door: return (0.55, 0.38, 0.24)
        case .roof: return (0.36, 0.24, 0.20)
        case .slab, .concrete: return (0.72, 0.71, 0.68)
        case .stair: return (0.70, 0.52, 0.31)
        case .structure: return (0.60, 0.60, 0.62)
        case .woodFloor: return (0.66, 0.47, 0.30)
        case .tileFloor: return (0.84, 0.84, 0.82)
        case .carpet: return (0.63, 0.60, 0.55)
        case .ceiling: return (0.97, 0.97, 0.96)
        case .grass: return (0.38, 0.56, 0.27)
        case .lawn: return (0.44, 0.66, 0.30)
        case .paving: return (0.66, 0.60, 0.54)
        case .gravel: return (0.74, 0.71, 0.64)
        case .water: return (0.27, 0.52, 0.70)
        case .mulch: return (0.38, 0.26, 0.18)
        case .deck: return (0.58, 0.42, 0.28)
        case .fabric: return (0.47, 0.55, 0.62)
        case .fabricDark: return (0.30, 0.33, 0.38)
        case .leather: return (0.45, 0.28, 0.18)
        case .wood: return (0.72, 0.55, 0.37)
        case .woodDark: return (0.40, 0.27, 0.17)
        case .white: return (0.95, 0.95, 0.94)
        case .metal: return (0.70, 0.72, 0.75)
        case .porcelain: return (0.98, 0.98, 0.97)
        case .stone: return (0.55, 0.54, 0.52)
        case .linen: return (0.92, 0.89, 0.83)
        case .black: return (0.12, 0.12, 0.13)
        case .trunk: return (0.40, 0.29, 0.20)
        case .foliage: return (0.27, 0.50, 0.22)
        case .foliageDark: return (0.16, 0.36, 0.20)
        case .blossom: return (0.86, 0.45, 0.55)
        }
    }

    /// 1 is opaque.
    var opacity: Double {
        switch self {
        case .glass: return 0.35
        case .water: return 0.85
        default: return 1
        }
    }
}

/// What a solid belongs to, so the view can show or hide a group of them at once.
enum SolidGroup: Equatable, Sendable {
    /// Walls, floors, stairs, and furniture.
    case house
    /// Roofs, which can be hidden to look into the rooms from above.
    case roof
    /// Ceilings, shown only while walking, so orbiting looks down into the rooms.
    case ceiling
    /// Ground, lot, paving, and planting.
    case site
}

/// One colored triangle mesh in view space. Front faces wind counterclockwise.
struct Solid: Equatable, Sendable {
    var look: Look
    var group: SolidGroup = .house
    var positions: [ScenePoint] = []
    var normals: [ScenePoint] = []
    var indices: [UInt32] = []

    init(look: Look, group: SolidGroup = .house) {
        self.look = look
        self.group = group
    }

    /// Adds a flat polygon in plan coordinates, one normal for all of it. `points` are plan (x, y, height)
    /// triples in feet, counterclockwise as seen from the side the normal points to.
    mutating func addFan(_ points: [(Double, Double, Double)], normal: ScenePoint) {
        guard points.count >= 3 else { return }
        let base = UInt32(positions.count)
        for point in points {
            positions.append(.plan(point.0, point.1, point.2))
            normals.append(normal)
        }
        for index in 1..<(points.count - 1) {
            indices += [base, base + UInt32(index), base + UInt32(index + 1)]
        }
    }

    /// Adds triangles in plan coordinates, one normal for all of them, keeping the order given.
    mutating func addTriangles(_ points: [(Double, Double, Double)], _ triangles: [(Int, Int, Int)],
                               normal: ScenePoint) {
        let base = UInt32(positions.count)
        for point in points {
            positions.append(.plan(point.0, point.1, point.2))
            normals.append(normal)
        }
        for triangle in triangles {
            indices += [base + UInt32(triangle.0), base + UInt32(triangle.1), base + UInt32(triangle.2)]
        }
    }

    /// The direction (dx, dy, dz) in plan axes, as a view-space normal.
    static func planNormal(_ dx: Double, _ dy: Double, _ dz: Double) -> ScenePoint {
        ScenePoint(Float(dx), Float(dz), Float(-dy))
    }
}

/// Simple shapes in plan coordinates: feet, x east, y north, z up. Each adds its faces to a solid.
enum Shapes {
    /// A box standing on `z0`, centered on (cx, cy), `width` along its own x and `depth` along its own y, turned
    /// `turn` radians counterclockwise.
    static func box(_ solid: inout Solid, cx: Double, cy: Double, z0: Double,
                    width: Double, depth: Double, height: Double, turn: Double = 0) {
        let (c, s) = (cos(turn), sin(turn))
        func corner(_ ix: Double, _ iy: Double, _ iz: Double) -> (Double, Double, Double) {
            let lx = (ix - 0.5) * width, ly = (iy - 0.5) * depth
            return (cx + lx * c - ly * s, cy + lx * s + ly * c, z0 + iz * height)
        }
        // Each face's corners counterclockwise as seen from outside, with its outward normal in local axes.
        let faces: [([(Double, Double, Double)], (Double, Double, Double))] = [
            ([(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], (0, 0, 1)),
            ([(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)], (0, 0, -1)),
            ([(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)], (1, 0, 0)),
            ([(0, 1, 0), (0, 0, 0), (0, 0, 1), (0, 1, 1)], (-1, 0, 0)),
            ([(1, 1, 0), (0, 1, 0), (0, 1, 1), (1, 1, 1)], (0, 1, 0)),
            ([(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)], (0, -1, 0)),
        ]
        for (corners, local) in faces {
            let normal = Solid.planNormal(local.0 * c - local.1 * s, local.0 * s + local.1 * c, local.2)
            solid.addFan(corners.map { corner($0.0, $0.1, $0.2) }, normal: normal)
        }
    }

    /// An upright cylinder standing on `z0`, with a top cap.
    static func cylinder(_ solid: inout Solid, cx: Double, cy: Double, z0: Double,
                         radius: Double, height: Double, segments: Int = 16) {
        let steps = max(segments, 3)
        for step in 0..<steps {
            let a0 = Double(step) / Double(steps) * 2 * .pi, a1 = Double(step + 1) / Double(steps) * 2 * .pi
            let mid = (a0 + a1) / 2
            let quad = [(cx + radius * cos(a0), cy + radius * sin(a0), z0),
                        (cx + radius * cos(a1), cy + radius * sin(a1), z0),
                        (cx + radius * cos(a1), cy + radius * sin(a1), z0 + height),
                        (cx + radius * cos(a0), cy + radius * sin(a0), z0 + height)]
            solid.addFan(quad, normal: Solid.planNormal(cos(mid), sin(mid), 0))
        }
        let top = (0..<steps).map { step -> (Double, Double, Double) in
            let angle = Double(step) / Double(steps) * 2 * .pi
            return (cx + radius * cos(angle), cy + radius * sin(angle), z0 + height)
        }
        solid.addFan(top, normal: Solid.planNormal(0, 0, 1))
    }

    /// An upright cone on a ring at `z0`, its tip `height` above.
    static func cone(_ solid: inout Solid, cx: Double, cy: Double, z0: Double,
                     radius: Double, height: Double, segments: Int = 16) {
        let steps = max(segments, 3)
        let slope = atan2(radius, height)
        for step in 0..<steps {
            let a0 = Double(step) / Double(steps) * 2 * .pi, a1 = Double(step + 1) / Double(steps) * 2 * .pi
            let mid = (a0 + a1) / 2
            let normal = Solid.planNormal(cos(mid) * cos(slope), sin(mid) * cos(slope), sin(slope))
            solid.addFan([(cx + radius * cos(a0), cy + radius * sin(a0), z0),
                          (cx + radius * cos(a1), cy + radius * sin(a1), z0),
                          (cx, cy, z0 + height)], normal: normal)
        }
    }

    /// An ellipsoid centered on (cx, cy, cz) with the given half sizes, smooth shaded.
    static func ellipsoid(_ solid: inout Solid, cx: Double, cy: Double, cz: Double,
                          rx: Double, ry: Double, rz: Double, rings: Int = 8, segments: Int = 14) {
        let base = UInt32(solid.positions.count)
        let latitudes = max(rings, 2), longitudes = max(segments, 3)
        for ring in 0...latitudes {
            let phi = Double(ring) / Double(latitudes) * .pi - .pi / 2
            for step in 0...longitudes {
                let theta = Double(step) / Double(longitudes) * 2 * .pi
                let (nx, ny, nz) = (cos(phi) * cos(theta), cos(phi) * sin(theta), sin(phi))
                solid.positions.append(.plan(cx + rx * nx, cy + ry * ny, cz + rz * nz))
                let length = max((nx * nx / (rx * rx) + ny * ny / (ry * ry) + nz * nz / (rz * rz)).squareRoot(), 1e-9)
                solid.normals.append(Solid.planNormal(nx / rx / length, ny / ry / length, nz / rz / length))
            }
        }
        let row = UInt32(longitudes + 1)
        for ring in 0..<UInt32(latitudes) {
            for step in 0..<UInt32(longitudes) {
                let a = base + ring * row + step, b = a + row
                solid.indices += [a, a + 1, b + 1, a, b + 1, b]
            }
        }
    }

    /// A flat horizontal polygon at `height`, facing up (or down), triangulated so concave outlines work.
    static func flat(_ solid: inout Solid, _ outline: [(x: Double, y: Double)], height: Double, facingUp: Bool = true) {
        let ring = Triangulation.counterclockwise(outline)
        let triangles = Triangulation.ears(ring)
        guard !triangles.isEmpty else { return }
        let points = ring.map { ($0.x, $0.y, height) }
        let ordered = facingUp ? triangles : triangles.map { ($0.0, $0.2, $0.1) }
        solid.addTriangles(points, ordered, normal: Solid.planNormal(0, 0, facingUp ? 1 : -1))
    }
}

/// Splits a simple polygon into triangles by ear clipping.
enum Triangulation {
    /// Twice the signed area: positive when the points run counterclockwise.
    static func twiceArea(_ points: [(x: Double, y: Double)]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum
    }

    /// The points counterclockwise, without a repeated closing point.
    static func counterclockwise(_ points: [(x: Double, y: Double)]) -> [(x: Double, y: Double)] {
        var ring = points
        if let first = ring.first, let last = ring.last, ring.count > 1, first == last { ring.removeLast() }
        return twiceArea(ring) < 0 ? ring.reversed() : ring
    }

    /// Triangles of a counterclockwise simple polygon, as index triples counterclockwise. Empty when the polygon
    /// has fewer than three corners or cannot be split.
    static func ears(_ ring: [(x: Double, y: Double)]) -> [(Int, Int, Int)] {
        guard ring.count >= 3 else { return [] }
        var remaining = Array(ring.indices)
        var triangles: [(Int, Int, Int)] = []
        var guardCount = 0
        while remaining.count > 3 && guardCount < ring.count * ring.count {
            guardCount += 1
            var clipped = false
            for position in remaining.indices {
                let previous = remaining[(position + remaining.count - 1) % remaining.count]
                let current = remaining[position], next = remaining[(position + 1) % remaining.count]
                guard isEar(previous, current, next, ring: ring, remaining: remaining) else { continue }
                triangles.append((previous, current, next))
                remaining.remove(at: position)
                clipped = true
                break
            }
            if !clipped { break }
        }
        if remaining.count == 3 { triangles.append((remaining[0], remaining[1], remaining[2])) }
        return triangles
    }

    private static func isEar(_ a: Int, _ b: Int, _ c: Int, ring: [(x: Double, y: Double)], remaining: [Int]) -> Bool {
        let (pa, pb, pc) = (ring[a], ring[b], ring[c])
        let cross = (pb.x - pa.x) * (pc.y - pa.y) - (pb.y - pa.y) * (pc.x - pa.x)
        guard cross > 1e-12 else { return false }
        for other in remaining where other != a && other != b && other != c {
            if inside(ring[other], pa, pb, pc) { return false }
        }
        return true
    }

    private static func inside(_ p: (x: Double, y: Double), _ a: (x: Double, y: Double), _ b: (x: Double, y: Double),
                               _ c: (x: Double, y: Double)) -> Bool {
        func side(_ u: (x: Double, y: Double), _ v: (x: Double, y: Double)) -> Double {
            (v.x - u.x) * (p.y - u.y) - (v.y - u.y) * (p.x - u.x)
        }
        return side(a, b) >= 0 && side(b, c) >= 0 && side(c, a) >= 0
    }
}
