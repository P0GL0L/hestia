import ATContracts
import Foundation

/// A building section along a line, looking to its left, in section coordinates: x is the distance along the
/// line from its start and y is the elevation.
///
/// Every element the line passes through is cut exactly where the line crosses its plan footprint: walls use
/// their joined footprints, split at every opening into full-height pieces and the sill and head over each
/// opening; slabs, columns and beams use their outlines; a stair is cut to its stepped profile; and a roof is
/// cut through the same patches its mesh is built from, as a band 250 mm deep under its surface. Walls wholly
/// to the left of the line are drawn beyond, nearest first, only where nothing nearer on their storey hides
/// them, with their openings. Cuts are clipped to the line's length.
struct SectionCut {
    let document: ModelDocument
    let frame: Frame

    /// The section line as an origin and unit direction.
    struct Frame {
        var origin: Vec
        var u: Vec
        var length: Double

        init?(_ line: SectionLine) {
            origin = Vec(line.start)
            let delta = Vec(line.end) - origin
            length = delta.length
            guard length > 0 else { return nil }
            u = delta * (1 / length)
        }

        /// Distance along the line from its start.
        func along(_ p: Vec) -> Double { (p - origin).dot(u) }

        /// Distance to the left of the line; the view looks this way.
        func left(_ p: Vec) -> Double { u.cross(p - origin) }

        /// The plan point at a distance along the line.
        func point(_ s: Double) -> Vec { origin + u * s }

        /// Stretches of the line, within its length, that lie inside a polygon.
        func intervals(inside polygon: [Vec]) -> [(Double, Double)] {
            var hits: [Double] = []
            for (p, q) in zip(polygon, polygon.dropFirst() + polygon.prefix(1)) {
                let a = left(p), b = left(q)
                guard (a > 0) != (b > 0) else { continue }
                let t: Double = a / (a - b)
                let sp = along(p), sq = along(q)
                hits.append(sp + (sq - sp) * t)
            }
            hits.sort()
            var result: [(Double, Double)] = []
            var i = 0
            while i + 1 < hits.count {
                let s0 = max(hits[i], 0), s1 = min(hits[i + 1], length)
                if s1 - s0 > 0.5 { result.append((s0, s1)) }
                i += 2
            }
            return result
        }
    }

    init?(document: ModelDocument, line: SectionLine) {
        guard let frame = Frame(line) else { return nil }
        self.document = document
        self.frame = frame
    }

    func outlines() throws -> [ClassifiedOutline] {
        var outlines: [ClassifiedOutline] = []
        for storey in document.storeys {
            outlines += try walls(on: storey)
            let base = Double(storey.elevation.ticks)
            for slab in document.slabs where slab.storeyID == storey.id {
                let top = base + Double(slab.topOffset.ticks)
                let bottom = top - Double(slab.thickness.ticks)
                outlines += boxes(slab.outline.map(Vec.init), bottom, top, id: slab.id.rawValue, kind: .slab)
            }
            for column in document.columns where column.storeyID == storey.id {
                let outline = HestiaGeometryEngine.columnOutline(column).map(Vec.init)
                let top = base + Double(column.height.ticks)
                outlines += boxes(outline, base, top, id: column.id.rawValue, kind: .column)
            }
            for beam in document.beams where beam.storeyID == storey.id {
                guard let outline = Self.beamOutline(beam) else { continue }
                let top = base + Double(beam.topOffset.ticks)
                let bottom = top - Double(beam.depth.ticks)
                outlines += boxes(outline, bottom, top, id: beam.id.rawValue, kind: .beam)
            }
            for stair in document.stairs where stair.storeyID == storey.id {
                outlines += self.stair(stair, base: base)
            }
            for roof in document.roofs where roof.storeyID == storey.id {
                outlines += self.roof(roof, base: base)
            }
        }
        return outlines
    }

    // MARK: - Walls

    private func walls(on storey: Storey) throws -> [ClassifiedOutline] {
        let base = Double(storey.elevation.ticks)
        let walls = document.walls.filter { $0.storeyID == storey.id }
        let footprints = try WallFootprints().footprints(for: walls)
        var outlines: [ClassifiedOutline] = []
        // Stretches of the line where a wall is cut, which hide whatever is beyond them.
        var covered: [(Double, Double)] = []
        var behind: [(depth: Double, wall: Wall, footprint: [Vec])] = []
        for wall in walls {
            guard let footprint = footprints[wall.id] else { continue }
            let polygon = footprint.map(Vec.init)
            let id = wall.id.rawValue
            let top = base + Double(wall.height.ticks)
            let openings = document.openings.filter { $0.wallID == wall.id }
            let pieces = try HestiaGeometryEngine.pieces(of: footprint, wall: wall, cutAt: openings)
            var cut = false
            for piece in pieces {
                let intervals = frame.intervals(inside: piece.map(Vec.init))
                covered += intervals
                cut = cut || !intervals.isEmpty
                outlines += intervals.map { Self.outline(id, .wall, .cut, $0, base, top) }
            }
            let line = try WallLine(wall)
            for opening in openings {
                let a = Double(opening.offsetAlongWall.ticks), b = a + Double(opening.width.ticks)
                let below = PolygonMath.clip(polygon, keepingBelow: b) { line.along($0) }
                let span = PolygonMath.clip(below, keepingBelow: -a) { -line.along($0) }
                let sill = base + Double(opening.sillHeight.ticks)
                let head = sill + Double(opening.height.ticks)
                for interval in frame.intervals(inside: span) {
                    cut = true
                    // The wall runs on behind its own opening, so the span still hides what lies beyond.
                    covered.append(interval)
                    if sill > base { outlines.append(Self.outline(id, .wall, .cut, interval, base, sill)) }
                    if top > head { outlines.append(Self.outline(id, .wall, .cut, interval, head, top)) }
                }
            }
            let depths = polygon.map(frame.left)
            if !cut, let nearest = depths.min(), nearest > 0 {
                behind.append((nearest, wall, polygon))
            }
        }
        for candidate in behind.sorted(by: { $0.depth < $1.depth }) {
            let wall = candidate.wall
            let stations = candidate.footprint.map(frame.along)
            let s0 = max(stations.min()!, 0), s1 = min(stations.max()!, frame.length)
            guard s1 - s0 > 0.5 else { continue }
            let visible = Self.subtract([(s0, s1)], covered)
            covered.append((s0, s1))
            let top = base + Double(wall.height.ticks)
            outlines += visible.map { Self.outline(wall.id.rawValue, .wall, .beyond, $0, base, top) }
            outlines += try openingsBeyond(wall, visible: visible, base: base)
        }
        return outlines
    }

    /// Openings in a wall seen beyond, clipped to the parts of the wall that show.
    private func openingsBeyond(_ wall: Wall, visible: [(Double, Double)], base: Double) throws -> [ClassifiedOutline] {
        let line = try WallLine(wall)
        var outlines: [ClassifiedOutline] = []
        for opening in document.openings where opening.wallID == wall.id {
            let a = Double(opening.offsetAlongWall.ticks), b = a + Double(opening.width.ticks)
            let sa = frame.along(line.origin + line.u * a), sb = frame.along(line.origin + line.u * b)
            let sill = base + Double(opening.sillHeight.ticks)
            let head = sill + Double(opening.height.ticks)
            for (v0, v1) in visible {
                let s0 = max(min(sa, sb), v0), s1 = min(max(sa, sb), v1)
                guard s1 - s0 > 0.5 else { continue }
                outlines.append(Self.outline(opening.id.rawValue, .opening, .beyond, (s0, s1), sill, head))
            }
        }
        return outlines
    }

    // MARK: - Stairs and roofs

    /// The stair's stepped profile: each tread block where the line passes through it, joined into one
    /// outline wherever the blocks touch.
    private func stair(_ stair: Stair, base: Double) -> [ClassifiedOutline] {
        let start = Vec(stair.runStart), end = Vec(stair.runEnd)
        let delta = end - start
        guard delta.length > 0, stair.riserCount >= 2 else { return [] }
        let u = delta * (1 / delta.length)
        let n = u.leftNormal * (Double(stair.width.ticks) / 2)
        let treads = stair.riserCount - 1
        let run = delta.length / Double(treads)
        var steps: [(s0: Double, s1: Double, top: Double)] = []
        for step in 0..<treads {
            let a = start + u * (run * Double(step)), b = start + u * (run * Double(step + 1))
            let top = base + Double(stair.riserHeight.ticks) * Double(step + 1)
            for (s0, s1) in frame.intervals(inside: [a - n, b - n, b + n, a + n]) {
                steps.append((s0, s1, top))
            }
        }
        steps.sort { $0.s0 < $1.s0 }
        var outlines: [ClassifiedOutline] = []
        var group: [(s0: Double, s1: Double, top: Double)] = []
        func flush() {
            guard let first = group.first, let last = group.last else { return }
            var points = [Vec(first.s0, base)]
            for step in group {
                points.append(Vec(step.s0, step.top))
                points.append(Vec(step.s1, step.top))
            }
            points.append(Vec(last.s1, base))
            outlines.append(ClassifiedOutline(elementID: stair.id.rawValue, kind: .stair, classification: .cut,
                                              polygon: Self.simplified(points)))
            group = []
        }
        for step in steps {
            if let last = group.last, step.s0 - last.s1 > 0.5 { flush() }
            group.append(step)
        }
        flush()
        return outlines
    }

    /// The roof cut: its surface along the line over every stretch a patch covers, with the band below it.
    private func roof(_ roof: Roof, base: Double) -> [ClassifiedOutline] {
        let patches = RoofPatch.patches(of: roof, base: base)
        var covered: [(patch: Int, s0: Double, s1: Double)] = []
        for (index, patch) in patches.enumerated() {
            covered += frame.intervals(inside: patch.outer).map { (index, $0.0, $0.1) }
        }
        let spans = Self.union(covered.map { ($0.s0, $0.s1) })
        var outlines: [ClassifiedOutline] = []
        for (s0, s1) in spans {
            // The surface is piecewise linear along the line, bending only where two planes cross or a patch
            // starts or ends, so it is exact at those stations.
            var stations = [s0, s1]
            for entry in covered where entry.s1 > s0 && entry.s0 < s1 {
                stations += [entry.s0, entry.s1]
            }
            stations += crossings(patches, from: s0, to: s1)
            stations = Array(Set(stations.map { min(max($0, s0), s1) })).sorted()
            var top: [Vec] = []
            for s in stations {
                let z = surface(patches, covered, at: s)
                top.append(Vec(s, z))
            }
            let bottom = top.reversed().map { Vec($0.x, $0.y - RoofPatch.thickness) }
            outlines.append(ClassifiedOutline(elementID: roof.id.rawValue, kind: .roof, classification: .cut,
                                              polygon: Self.simplified(top + bottom)))
        }
        return outlines
    }

    /// Stations along the line where any two pitched planes reach the same height.
    private func crossings(_ patches: [RoofPatch], from s0: Double, to s1: Double) -> [Double] {
        var linear: [(at0: Double, slope: Double)] = []
        for patch in patches {
            for i in patch.pitched {
                let h0 = patch.height(i, frame.point(0))
                let h1 = patch.height(i, frame.point(1))
                linear.append((h0, h1 - h0))
            }
        }
        var stations: [Double] = []
        for i in linear.indices {
            for j in linear.indices where j > i {
                let dSlope: Double = linear[i].slope - linear[j].slope
                guard abs(dSlope) > 1e-12 else { continue }
                let s: Double = (linear[j].at0 - linear[i].at0) / dSlope
                if s > s0, s < s1 { stations.append(s) }
            }
        }
        return stations
    }

    /// The highest patch surface over a station.
    private func surface(_ patches: [RoofPatch], _ covered: [(patch: Int, s0: Double, s1: Double)],
                         at s: Double) -> Double {
        let p = frame.point(s)
        var highest = -Double.infinity
        for entry in covered where entry.s0 - 0.5 <= s && s <= entry.s1 + 0.5 {
            highest = max(highest, patches[entry.patch].surface(p))
        }
        return highest
    }

    // MARK: - Helpers

    private func boxes(_ outline: [Vec], _ bottom: Double, _ top: Double, id: UUID, kind: ElementKind)
        -> [ClassifiedOutline] {
        frame.intervals(inside: outline).map { Self.outline(id, kind, .cut, $0, bottom, top) }
    }

    static func outline(_ id: UUID, _ kind: ElementKind, _ classification: OutlineClassification,
                        _ interval: (Double, Double), _ bottom: Double, _ top: Double) -> ClassifiedOutline {
        let (s0, s1) = interval
        let points = [Vec(s0, bottom), Vec(s1, bottom), Vec(s1, top), Vec(s0, top)]
        return ClassifiedOutline(elementID: id, kind: kind, classification: classification,
                                 polygon: points.map { $0.rounded() })
    }

    static func beamOutline(_ beam: Beam) -> [Vec]? {
        let start = Vec(beam.start), end = Vec(beam.end)
        let delta = end - start
        guard delta.length > 0 else { return nil }
        let n = (delta * (1 / delta.length)).leftNormal * (Double(beam.width.ticks) / 2)
        return [start - n, end - n, end + n, start + n]
    }

    /// Rounds to ticks and drops repeated and collinear points.
    static func simplified(_ points: [Vec]) -> [Point2] {
        var result: [Point2] = []
        for point in points.map({ $0.rounded() }) where result.last != point {
            result.append(point)
        }
        if result.count > 1, result.first == result.last { result.removeLast() }
        var changed = true
        while changed, result.count > 3 {
            changed = false
            for i in result.indices {
                let a = Vec(result[(i - 1 + result.count) % result.count]), b = Vec(result[i])
                let c = Vec(result[(i + 1) % result.count])
                if abs((b - a).cross(c - b)) < 1e-6 * max((b - a).length * (c - b).length, 1) {
                    result.remove(at: i)
                    changed = true
                    break
                }
            }
        }
        return result
    }

    /// Merged, sorted intervals.
    static func union(_ intervals: [(Double, Double)]) -> [(Double, Double)] {
        var result: [(Double, Double)] = []
        for (s0, s1) in intervals.sorted(by: { $0.0 < $1.0 }) {
            if let last = result.last, s0 <= last.1 + 0.5 {
                result[result.count - 1].1 = max(last.1, s1)
            } else {
                result.append((s0, s1))
            }
        }
        return result
    }

    /// The parts of `intervals` not covered by any of `cover`.
    static func subtract(_ intervals: [(Double, Double)], _ cover: [(Double, Double)]) -> [(Double, Double)] {
        var remaining = intervals
        for (c0, c1) in union(cover) {
            remaining = remaining.flatMap { (s0, s1) -> [(Double, Double)] in
                guard c1 > s0, c0 < s1 else { return [(s0, s1)] }
                return [(s0, c0), (c1, s1)].filter { $0.1 - $0.0 > 0.5 }
            }
        }
        return remaining
    }
}
