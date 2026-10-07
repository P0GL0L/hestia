import ATContracts
import Foundation

/// One convex piece of a roof: its outer eave outline and the pitched planes rising inward from each eave edge.
///
/// A convex footprint is one patch. A rectilinear footprint that is not convex is covered by one hip patch per
/// largest rectangle, and the roof surface is the highest patch over each point. Anything else is a single
/// flat patch. Meshes and sections both read the roof through these patches, so they always agree.
struct RoofPatch {
    /// Thickness of a flat cap, and of the roof drawn in section below the pitched surface.
    static let thickness = Double(Length.millimeters(250).ticks)

    /// Outer eave outline: each footprint edge pushed out by its overhang, counterclockwise.
    var outer: [Vec]
    /// Each outer eave edge as an origin and unit direction; the inside is on the left.
    var lines: [(origin: Vec, direction: Vec)]
    /// Rise per unit run for each edge, or nil for a gable or flat edge.
    var slopes: [Double?]
    var eave: Double

    /// Indices of the edges that carry a pitched plane.
    var pitched: [Int] { slopes.indices.filter { (slopes[$0] ?? 0) > 0 } }

    var isFlat: Bool { pitched.isEmpty }

    /// Height of edge `i`'s plane over a plan point.
    func height(_ i: Int, _ p: Vec) -> Double {
        let line = lines[i]
        let run: Double = line.direction.cross(p - line.origin)
        return eave + (slopes[i] ?? 0) * run
    }

    /// The roof's top over a plan point inside `outer`: the lowest pitched plane, or the flat cap's top.
    func surface(_ p: Vec) -> Double {
        let planes = pitched
        guard !planes.isEmpty else { return eave + Self.thickness }
        var lowest = Double.infinity
        for i in planes { lowest = min(lowest, height(i, p)) }
        return lowest
    }

    /// A patch over a convex counterclockwise footprint with one plane per edge.
    init?(footprint: [Vec], planes: [RoofPlane], eave: Double) {
        let count = footprint.count
        guard count >= 3, planes.count == count else { return nil }
        let twelve = Double(Length.inches(12).ticks)
        var lines: [(origin: Vec, direction: Vec)] = []
        for i in 0..<count {
            let a = footprint[i], b = footprint[(i + 1) % count]
            let d = (b - a) * (1 / max((b - a).length, 1))
            lines.append((a - d.leftNormal * Double(planes[i].overhang.ticks), d))
        }
        var outer: [Vec] = []
        for i in 0..<count {
            let p = lines[(i - 1 + count) % count], q = lines[i]
            let denominator = p.direction.cross(q.direction)
            if abs(denominator) < 1e-9 {
                outer.append(q.origin)
            } else {
                let t: Double = (q.origin - p.origin).cross(q.direction) / denominator
                outer.append(p.origin + p.direction * t)
            }
        }
        self.outer = outer
        self.lines = lines
        slopes = planes.map { plane in plane.pitchRisePer12.map { Double($0.ticks) / twelve } }
        self.eave = eave
    }

    /// The patches covering a roof whose storey sits at `base`.
    static func patches(of roof: Roof, base: Double) -> [RoofPatch] {
        let eave = base + Double(roof.eaveHeight.ticks)
        var footprint = roof.footprint.map(Vec.init)
        var planes = roof.planes
        guard footprint.count >= 3, planes.count == footprint.count else { return [] }
        if PolygonMath.twiceSignedArea(footprint) < 0 {
            footprint.reverse()
            let flipped: [RoofPlane] = planes.reversed()
            planes = Array(flipped.dropFirst()) + Array(flipped.prefix(1))
        }
        if ElementMeshes.isConvex(footprint) {
            return [RoofPatch(footprint: footprint, planes: planes, eave: eave)].compactMap { $0 }
        }
        if ElementMeshes.isRectilinear(footprint) {
            let pitch = planes.compactMap(\.pitchRisePer12).max()
            return ElementMeshes.maximalRectangles(footprint).compactMap { rect in
                let box = [Vec(rect.0, rect.2), Vec(rect.1, rect.2), Vec(rect.1, rect.3), Vec(rect.0, rect.3)]
                let boxPlanes = zip(box, box.dropFirst() + box.prefix(1)).map { a, b in
                    let overhang = ElementMeshes.overhang(on: (a, b), footprint: footprint, planes: planes)
                    return RoofPlane(pitchRisePer12: pitch, overhang: Length(ticks: Int64(overhang.rounded())))
                }
                return RoofPatch(footprint: box, planes: boxPlanes, eave: eave)
            }
        }
        // Not convex and not rectilinear: a flat cap over the footprint itself.
        let flat = Array(repeating: RoofPlane(pitchRisePer12: nil, overhang: .millimeters(0)), count: footprint.count)
        guard var patch = RoofPatch(footprint: footprint, planes: flat, eave: eave) else { return [] }
        patch.outer = footprint
        return [patch]
    }
}
