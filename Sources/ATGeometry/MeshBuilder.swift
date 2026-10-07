import ATContracts
import Foundation

/// Accumulates flat-shaded triangles for one element and one material.
struct MeshBuilder {
    var positions: [Point3] = []
    var normals: [Vector3f] = []
    var uvs: [TextureCoordinate] = []
    var indices: [UInt32] = []

    /// UVs repeat every meter.
    private static let uvScale = 1 / Double(Length.millimeters(1000).ticks)

    /// Adds a planar polygon, triangulated, facing `normal`. Points must be in counterclockwise order seen from
    /// the side the normal points to.
    mutating func face(_ points: [(Double, Double, Double)], normal: (Double, Double, Double)) {
        guard points.count >= 3 else { return }
        let length = max((normal.0 * normal.0 + normal.1 * normal.1 + normal.2 * normal.2).squareRoot(), 1e-12)
        let n = Vector3f(x: Float(normal.0 / length), y: Float(normal.1 / length), z: Float(normal.2 / length))
        // Project to the plane's dominant axes for triangulation and UVs.
        let ax = abs(n.x), ay = abs(n.y), az = abs(n.z)
        let flat: [Vec] = points.map { p in
            if az >= ax && az >= ay { return Vec(p.0, p.1) }
            if ax >= ay { return Vec(p.1, p.2) }
            return Vec(p.0, p.2)
        }
        let triangles = Triangulation.earClip(flat)
        let first = UInt32(positions.count)
        for (p, f) in zip(points, flat) {
            positions.append(Point3(x: Length(ticks: Int64(p.0.rounded())), y: Length(ticks: Int64(p.1.rounded())),
                                    z: Length(ticks: Int64(p.2.rounded()))))
            normals.append(n)
            uvs.append(TextureCoordinate(u: Float(f.x * Self.uvScale), v: Float(f.y * Self.uvScale)))
        }
        // Keep each triangle's winding counterclockwise as seen along the normal.
        for (a, b, c) in triangles {
            let pa = points[a], pb = points[b], pc = points[c]
            let u = (pb.0 - pa.0, pb.1 - pa.1, pb.2 - pa.2), v = (pc.0 - pa.0, pc.1 - pa.1, pc.2 - pa.2)
            let cross = (u.1 * v.2 - u.2 * v.1, u.2 * v.0 - u.0 * v.2, u.0 * v.1 - u.1 * v.0)
            let facing = cross.0 * normal.0 + cross.1 * normal.1 + cross.2 * normal.2
            indices += facing >= 0 ? [first + UInt32(a), first + UInt32(b), first + UInt32(c)]
                                   : [first + UInt32(a), first + UInt32(c), first + UInt32(b)]
        }
    }

    /// A vertical prism over a plan polygon from `bottom` to `top`.
    mutating func prism(_ polygon: [Vec], bottom: Double, top: Double) {
        guard polygon.count >= 3, top > bottom else { return }
        let ccw = PolygonMath.twiceSignedArea(polygon) >= 0 ? polygon : polygon.reversed()
        face(ccw.map { ($0.x, $0.y, top) }, normal: (0, 0, 1))
        face(ccw.reversed().map { ($0.x, $0.y, bottom) }, normal: (0, 0, -1))
        for (a, b) in zip(ccw, ccw.dropFirst() + ccw.prefix(1)) {
            let d = b - a
            guard d.length > 0 else { continue }
            face([(a.x, a.y, bottom), (b.x, b.y, bottom), (b.x, b.y, top), (a.x, a.y, top)], normal: (d.y, -d.x, 0))
        }
    }

    func mesh(elementID: UUID, material: String) -> Mesh? {
        guard !indices.isEmpty else { return nil }
        return Mesh(elementID: elementID, materialID: MaterialID(material), positions: positions, normals: normals,
                    uvs: uvs, indices: indices)
    }
}

enum Triangulation {
    /// Ear clipping for a simple polygon in either winding. Returns index triples into `points`.
    static func earClip(_ points: [Vec]) -> [(Int, Int, Int)] {
        var remaining = Array(points.indices)
        guard remaining.count >= 3 else { return [] }
        let ccw = PolygonMath.twiceSignedArea(points) >= 0
        func convex(_ a: Vec, _ b: Vec, _ c: Vec) -> Bool {
            let turn = (b - a).cross(c - b)
            return ccw ? turn > 1e-9 : turn < -1e-9
        }
        func inside(_ p: Vec, _ a: Vec, _ b: Vec, _ c: Vec) -> Bool {
            let d1 = (b - a).cross(p - a), d2 = (c - b).cross(p - b), d3 = (a - c).cross(p - c)
            return ccw ? (d1 > 1e-9 && d2 > 1e-9 && d3 > 1e-9) : (d1 < -1e-9 && d2 < -1e-9 && d3 < -1e-9)
        }
        var triangles: [(Int, Int, Int)] = []
        var guardCount = 0
        while remaining.count > 3 && guardCount < points.count * points.count {
            guardCount += 1
            var clipped = false
            for i in remaining.indices {
                let ia = remaining[(i - 1 + remaining.count) % remaining.count], ib = remaining[i]
                let ic = remaining[(i + 1) % remaining.count]
                let (a, b, c) = (points[ia], points[ib], points[ic])
                guard convex(a, b, c) else { continue }
                if remaining.contains(where: { $0 != ia && $0 != ib && $0 != ic && inside(points[$0], a, b, c) }) {
                    continue
                }
                triangles.append((ia, ib, ic))
                remaining.remove(at: i)
                clipped = true
                break
            }
            // Collinear leftovers: drop the middle vertex and carry on.
            if !clipped { remaining.remove(at: 1) }
        }
        if remaining.count == 3 { triangles.append((remaining[0], remaining[1], remaining[2])) }
        return triangles
    }
}
