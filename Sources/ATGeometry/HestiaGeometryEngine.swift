import ATContracts
import Foundation

/// The geometry engine the app and drawings use with a live model.
///
/// Plan view: walls on the storey are joined (L, T, X, any angle) and cut at doors and windows that the plan
/// cut plane passes through; an opening wholly above the cut splits the wall too, its span seen beyond. Walls
/// lower than the cut plane, and columns and stairs, are classified to match.
/// Room areas come from each room's boundary walls, measured face to face. Meshes cover walls, openings,
/// slabs, columns, beams, stairs, and roofs.
public struct HestiaGeometryEngine: GeometryEngine {
    /// Height of the plan cut plane above the storey floor: 4'-0".
    public var planCutHeight: Length

    public init(planCutHeight: Length = .inches(48)) {
        self.planCutHeight = planCutHeight
    }

    public func planView(of document: ModelDocument, storey: StoreyID) throws -> [ClassifiedOutline] {
        guard document.storeys.contains(where: { $0.id == storey }) else {
            throw CommandValidationError.storeyNotFound(storey)
        }
        let walls = document.walls.filter { $0.storeyID == storey }
        let footprints = try WallFootprints().footprints(for: walls)
        let cut = planCutHeight.ticks
        var outlines: [ClassifiedOutline] = []
        for wall in walls {
            guard let footprint = footprints[wall.id] else { continue }
            let classification: OutlineClassification = wall.height.ticks > cut ? .cut : .beyond
            let hosted = document.openings.filter { $0.wallID == wall.id && $0.sillHeight.ticks + $0.height.ticks > cut }
            // An opening the cut passes through leaves a gap; one wholly above the cut leaves a span seen beyond.
            let crossing = hosted.filter { $0.sillHeight.ticks < cut }
            let above = hosted.filter { $0.sillHeight.ticks >= cut }
            for piece in try Self.planPieces(of: footprint, wall: wall, gaps: crossing, beyond: above) {
                outlines.append(ClassifiedOutline(elementID: wall.id.rawValue, kind: .wall,
                                                  classification: piece.beyond ? .beyond : classification,
                                                  polygon: piece.polygon))
            }
        }
        for column in document.columns where column.storeyID == storey {
            outlines.append(ClassifiedOutline(elementID: column.id.rawValue, kind: .column,
                                              classification: column.height.ticks > cut ? .cut : .beyond,
                                              polygon: Self.columnOutline(column)))
        }
        for stair in document.stairs where stair.storeyID == storey {
            outlines.append(ClassifiedOutline(elementID: stair.id.rawValue, kind: .stair, classification: .beyond,
                                              polygon: Self.stairOutline(stair)))
        }
        return outlines
    }

    public func roomAreas(of document: ModelDocument, storey: StoreyID) throws -> [RoomID: Area] {
        guard document.storeys.contains(where: { $0.id == storey }) else {
            throw CommandValidationError.storeyNotFound(storey)
        }
        let walls = Dictionary(uniqueKeysWithValues: document.walls.map { ($0.id, $0) })
        var areas: [RoomID: Area] = [:]
        for room in document.rooms where room.storeyID == storey {
            let boundary = room.boundaryWallIDs.compactMap { walls[$0] }
            if let inner = Self.innerPolygon(boundary) {
                areas[room.id] = Area(tickSquares: Int64((abs(PolygonMath.twiceSignedArea(inner)) / 2).rounded()))
            }
        }
        return areas
    }

    /// Walls (pieces between openings, sills, heads, glass, and door leaves), slabs, columns, beams, stairs, and
    /// roofs, each tagged with its element ID, at absolute elevations. Catalog placements come from the catalog.
    public func meshes(of document: ModelDocument) throws -> [Mesh] {
        var meshes: [Mesh] = []
        for storey in document.storeys {
            let base = Double(storey.elevation.ticks)
            let walls = document.walls.filter { $0.storeyID == storey.id }
            let footprints = try WallFootprints().footprints(for: walls)
            for wall in walls {
                guard let footprint = footprints[wall.id] else { continue }
                let openings = document.openings.filter { $0.wallID == wall.id }
                meshes += try ElementMeshes.wall(wall, footprint: footprint, openings: openings, base: base)
            }
            meshes += document.slabs.filter { $0.storeyID == storey.id }.compactMap { ElementMeshes.slab($0, base: base) }
            meshes += document.columns.filter { $0.storeyID == storey.id }.compactMap { ElementMeshes.column($0, base: base) }
            meshes += document.beams.filter { $0.storeyID == storey.id }.compactMap { ElementMeshes.beam($0, base: base) }
            meshes += document.stairs.filter { $0.storeyID == storey.id }.compactMap { ElementMeshes.stair($0, base: base) }
            meshes += document.roofs.filter { $0.storeyID == storey.id }.flatMap { ElementMeshes.roof($0, base: base) }
        }
        return meshes
    }

    /// A section looking to the left of the line; see `SectionCut`. A zero-length line has no section.
    public func section(of document: ModelDocument, along line: SectionLine) throws -> [ClassifiedOutline] {
        try SectionCut(document: document, line: line)?.outlines() ?? []
    }

    // MARK: - Plan pieces

    /// The footprint split at each opening's span along the wall, in counterclockwise pieces.
    static func pieces(of footprint: [Point2], wall: Wall, cutAt openings: [Opening]) throws -> [[Point2]] {
        let polygon = footprint.map(Vec.init)
        guard !openings.isEmpty else { return [footprint] }
        let line = try WallLine(wall)
        var spans: [(Double, Double)] = []
        for opening in openings {
            let start: Int64 = opening.offsetAlongWall.ticks
            let end: Int64 = start + opening.width.ticks
            spans.append((Double(start), Double(end)))
        }
        spans.sort { $0.0 < $1.0 }
        var pieces: [[Vec]] = []
        var lower = -Double.infinity
        for (a, b) in spans {
            var piece = PolygonMath.clip(polygon, keepingBelow: a) { line.along($0) }
            if lower.isFinite { piece = PolygonMath.clip(piece, keepingBelow: -lower) { -line.along($0) } }
            pieces.append(piece)
            lower = b
        }
        pieces.append(PolygonMath.clip(polygon, keepingBelow: -lower) { -line.along($0) })
        return pieces.filter { abs(PolygonMath.twiceSignedArea($0)) > 1 }.map { $0.map { $0.rounded() } }
    }

    /// The footprint split for the plan at every opening in `gaps` and `beyond`, in counterclockwise pieces along
    /// the wall. A gap's span is left out; a beyond opening's span is its own piece, flagged so it is drawn as
    /// seen beyond the cut. The pieces between openings are the wall itself.
    static func planPieces(of footprint: [Point2], wall: Wall, gaps: [Opening], beyond: [Opening]) throws
        -> [(polygon: [Point2], beyond: Bool)] {
        guard !(gaps.isEmpty && beyond.isEmpty) else { return [(footprint, false)] }
        let polygon = footprint.map(Vec.init)
        let line = try WallLine(wall)
        var spans: [(a: Double, b: Double, beyond: Bool)] = []
        for opening in gaps + beyond {
            let start = Double(opening.offsetAlongWall.ticks)
            spans.append((start, start + Double(opening.width.ticks), beyond.contains(opening)))
        }
        spans.sort { $0.a < $1.a }
        /// The footprint between two distances along the wall.
        func between(_ low: Double, _ high: Double) -> [Vec] {
            var piece = polygon
            if high.isFinite { piece = PolygonMath.clip(piece, keepingBelow: high) { line.along($0) } }
            if low.isFinite { piece = PolygonMath.clip(piece, keepingBelow: -low) { -line.along($0) } }
            return piece
        }
        var pieces: [(polygon: [Vec], beyond: Bool)] = []
        var lower = -Double.infinity
        for span in spans {
            pieces.append((between(lower, span.a), false))
            if span.beyond { pieces.append((between(span.a, span.b), true)) }
            lower = span.b
        }
        pieces.append((between(lower, .infinity), false))
        return pieces.filter { abs(PolygonMath.twiceSignedArea($0.polygon)) > 1 }
            .map { ($0.polygon.map { $0.rounded() }, $0.beyond) }
    }

    static func columnOutline(_ column: Column) -> [Point2] {
        let center = Vec(column.center)
        let angle = Double(column.rotation.microDegrees) / 1_000_000 * .pi / 180
        let (c, s) = (cos(angle), sin(angle))
        let w = Double(column.width.ticks) / 2, d = Double(column.depth.ticks) / 2
        let local: [Vec]
        switch column.shape {
        case .rectangular:
            local = [Vec(-w, -d), Vec(w, -d), Vec(w, d), Vec(-w, d)]
        case .round:
            local = (0..<24).map { i in
                let t = Double(i) / 24 * 2 * .pi
                return Vec(w * cos(t), w * sin(t))
            }
        }
        return local.map { (center + Vec($0.x * c - $0.y * s, $0.x * s + $0.y * c)).rounded() }
    }

    static func stairOutline(_ stair: Stair) -> [Point2] {
        let start = Vec(stair.runStart), end = Vec(stair.runEnd)
        let delta = end - start
        let length = max(delta.length, 1)
        let n = (delta * (1 / length)).leftNormal * (Double(stair.width.ticks) / 2)
        return [start - n, end - n, end + n, start + n].map { $0.rounded() }
    }

    // MARK: - Rooms

    /// The room's inner polygon: each boundary wall's centerline moved in by half its thickness, joined in
    /// boundary order. Consecutive walls on one line, such as a side split around an opening, are one side.
    /// Nil when the boundary does not close into a polygon, or when walls on one line differ in thickness.
    static func innerPolygon(_ walls: [Wall]) -> [Vec]? {
        guard walls.count >= 3, let pieces = try? walls.map(WallLine.init),
              let lines = sides(pieces), lines.count >= 3 else { return nil }
        func meet(_ a: (Vec, Vec), _ b: (Vec, Vec)) -> Vec? {
            let denominator = a.1.cross(b.1)
            guard abs(denominator) > 1e-9 else { return nil }
            return a.0 + a.1 * ((b.0 - a.0).cross(b.1) / denominator)
        }
        let centerlines = lines.map { ($0.origin, $0.u) }
        var corners: [Vec] = []
        for i in lines.indices {
            guard let corner = meet(centerlines[i], centerlines[(i + 1) % lines.count]) else { return nil }
            corners.append(corner)
        }
        // Edge i runs from corner i-1 to corner i along wall i; inside is to the left of a counterclockwise loop.
        let sign: Double = PolygonMath.twiceSignedArea(corners) >= 0 ? 1 : -1
        var offsets: [(Vec, Vec)] = []
        for i in lines.indices {
            let from = corners[(i - 1 + lines.count) % lines.count], to = corners[i]
            let direction = to - from
            let length = direction.length
            guard length > 0 else { return nil }
            let unit = direction * (1 / length)
            offsets.append((from + unit.leftNormal * (lines[i].half * sign), unit))
        }
        var inner: [Vec] = []
        for i in offsets.indices {
            guard let corner = meet(offsets[i], offsets[(i + 1) % offsets.count]) else { return nil }
            inner.append(corner)
        }
        return inner
    }

    /// Boundary pieces with consecutive collinear ones, wrapping around from the last to the first, folded
    /// into one side each. Nil when two collinear neighbours differ in thickness: their inner faces are not
    /// one line, so the room has no single side there.
    static func sides(_ pieces: [WallLine]) -> [WallLine]? {
        // Within a hundredth of a millimetre of the other's line, and parallel to a millionth.
        let tolerance = Double(Length.ticksPerMillimeter) / 100
        func collinear(_ a: WallLine, _ b: WallLine) -> Bool {
            abs(a.u.cross(b.u)) < 1e-6 && abs((b.origin - a.origin).cross(a.u)) < tolerance
        }
        // Start where a new side begins, so a side that wraps from the last piece to the first stays whole.
        let count = pieces.count
        let begins: (Int) -> Bool = { index in !collinear(pieces[(index - 1 + count) % count], pieces[index]) }
        guard let start = pieces.indices.first(where: begins) else { return nil }
        var sides: [WallLine] = []
        for step in 0..<count {
            let piece = pieces[(start + step) % count]
            if let last = sides.last, collinear(last, piece) {
                guard abs(last.half - piece.half) < 1e-9 else { return nil }
                continue
            }
            sides.append(piece)
        }
        return sides
    }
}
