import ATContracts
import Foundation

/// Doors and windows built as a carpenter would show them, in place of the engine's flat panes: painted casing
/// around every opening, a solid door leaf with a handle, standing open, and windows with a frame, a meeting
/// rail, glass with thickness, and a sill. All sizes are in feet and come from the opening and its wall.
///
/// Every part is first worked out as a `Piece` in the opening's own frame, and a part is only made when it fits:
/// a very small opening keeps its casing and drops the detail that has no room, so no part ever has a negative
/// or zero size and no two parts overlap. The model itself is never changed.
enum OpeningDetail {
    /// Casing face width and how far it stands proud of the wall face.
    static let casing = 0.29
    static let proud = 0.06
    /// The jamb and head liners across the wall's thickness.
    static let liner = 0.06
    /// The gap around a door leaf.
    static let gap = 0.03
    static let leafThickness = 0.146
    /// Window sash bars: width on the face and depth into the wall.
    static let bar = 0.16
    static let frameDepth = 0.3
    /// The smallest pane, leaf, or opening left between parts that is worth drawing.
    static let least = 0.04
    /// A door leaf narrower than this gets no handle.
    static let handleRoom = 0.6

    enum Part: Hashable, Sendable {
        case casing, liner, sill, leaf, handle, sash, glass
    }

    /// Which way a molded piece runs: up a jamb, or along the wall across a head or sill.
    enum Run: Equatable, Sendable {
        case up
        case along
    }

    /// One part of an opening as a box in the opening's frame: `along` the wall from its start and `across` from
    /// its centerline (left positive) give the box's middle; it stands on `z0`. A handle is drawn as the ball
    /// that fits the box. Casing is a molding cut to fill its box (`run`), its back on the wall and its face
    /// toward `outward` (+1 the wall's left side, -1 its right).
    struct Piece: Equatable, Sendable {
        var part: Part
        var look: Look
        var along: Double
        var across: Double = 0
        var z0: Double
        var length: Double
        var depth: Double
        var tall: Double
        var run: Run?
        var outward: Double = 1
    }

    static func add(_ document: ModelDocument, to solids: inout [Look: Solid]) {
        for (frame, pieces) in details(document) {
            for piece in pieces {
                var solid = solids[piece.look] ?? Solid(look: piece.look)
                if piece.part == .handle {
                    let middle = frame.point(piece.along, piece.across)
                    Shapes.ellipsoid(&solid, cx: middle.x, cy: middle.y, cz: piece.z0 + piece.tall / 2,
                                     rx: piece.length / 2, ry: piece.depth / 2, rz: piece.tall / 2,
                                     rings: 6, segments: 10)
                } else if let run = piece.run {
                    mold(piece, run: run, in: frame, to: &solid)
                } else {
                    frame.box(&solid, along: piece.along, across: piece.across, z0: piece.z0,
                              length: piece.length, depth: piece.depth, tall: piece.tall)
                }
                solids[piece.look] = solid
            }
        }
    }

    /// A casing piece as a molding filling its box: its back on the wall, its face out, its length along `run`.
    private static func mold(_ piece: Piece, run: Run, in frame: Frame, to solid: inout Solid) {
        let along = Vector(frame.ux, frame.uy, 0)
        let left = Vector(-frame.uy, frame.ux, 0)
        let up = Vector(0, 0, 1)
        let back = piece.across - piece.outward * piece.depth / 2
        let corner = frame.point(piece.along - piece.length / 2, back)
        let start = Vector(corner.x, corner.y, piece.z0)
        let out = left * piece.outward
        switch run {
        case .up:
            Molding.casing(width: piece.length, proud: piece.depth)
                .extrude(&solid, start: start, run: up, length: piece.tall, across: along, out: out)
        case .along:
            Molding.casing(width: piece.tall, proud: piece.depth)
                .extrude(&solid, start: start, run: along, length: piece.length, across: up, out: out)
        }
    }

    /// Every opening in the document whose wall is there, with its parts; only the storey's when one is given.
    static func details(_ document: ModelDocument, storey: StoreyID? = nil) -> [(frame: Frame, pieces: [Piece])] {
        let walls = Dictionary(document.walls.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return document.openings.compactMap { opening in
            guard let wall = walls[opening.wallID], storey == nil || wall.storeyID == storey else { return nil }
            let floor = document.storeys.first { $0.id == wall.storeyID }.map { HouseScene.feet($0.elevation) } ?? 0
            let frame = Frame(wall: wall, opening: opening, floor: floor)
            let swing = opening.swing ?? defaultSwing(document, wall: wall, opening: opening)
            return (frame, pieces(frame, kind: opening.kind, swing: swing))
        }
    }

    /// The way a door with no recorded swing opens: into the building, the side whose floor reaches a foot past
    /// the wall's face (the box of the storey's walls when it has no slab), hinged at the wall's start; left
    /// when that does not tell the sides apart.
    static func defaultSwing(_ document: ModelDocument, wall: Wall, opening: Opening) -> DoorSwing {
        let sx = Double(wall.start.x.ticks), sy = Double(wall.start.y.ticks)
        let dx = Double(wall.end.x.ticks) - sx, dy = Double(wall.end.y.ticks) - sy
        let length = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        let (ux, uy) = (dx / length, dy / length)
        let along = Double(opening.offsetAlongWall.ticks) + Double(opening.width.ticks) / 2
        let reach = Double(wall.thickness.ticks) / 2 + Double(Length.feet(1).ticks)
        func point(_ side: Double) -> Point2 {
            Point2(x: Length(ticks: Int64((sx + ux * along - uy * side * reach).rounded())),
                   y: Length(ticks: Int64((sy + uy * along + ux * side * reach).rounded())))
        }
        let slabs = document.slabs.filter { $0.storeyID == wall.storeyID }
        let inside: (Point2) -> Bool
        if slabs.isEmpty {
            let ends: [Point2] = document.walls.filter { $0.storeyID == wall.storeyID }.flatMap { [$0.start, $0.end] }
            let xs: [Int64] = ends.map(\.x.ticks), ys: [Int64] = ends.map(\.y.ticks)
            let (x0, x1, y0, y1) = (xs.min() ?? 0, xs.max() ?? 0, ys.min() ?? 0, ys.max() ?? 0)
            inside = { $0.x.ticks > x0 && $0.x.ticks < x1 && $0.y.ticks > y0 && $0.y.ticks < y1 }
        } else {
            inside = { point in slabs.contains { HestiaModel.contains($0.outline, point) } }
        }
        let right = inside(point(-1)) && !inside(point(1))
        return DoorSwing(hinge: .nearStart, opensToward: right ? .right : .left)
    }

    /// The standing door leaves of the storey's doors as walls a walker cannot pass through, each where it
    /// stands open, so a walk goes round a leaf and never through it.
    static func leafBarriers(_ document: ModelDocument, storey: StoreyID) -> [WalkBarriers.Segment] {
        var segments: [WalkBarriers.Segment] = []
        for (frame, pieces) in details(document, storey: storey) {
            for piece in pieces where piece.part == .leaf && piece.tall > max(piece.length, piece.depth) {
                // Through the leaf's middle along its longer side in plan, as thick as its shorter side.
                let lengthwise = piece.length >= piece.depth
                let reach = max(piece.length, piece.depth) / 2
                let a = lengthwise ? frame.point(piece.along - reach, piece.across)
                    : frame.point(piece.along, piece.across - reach)
                let b = lengthwise ? frame.point(piece.along + reach, piece.across)
                    : frame.point(piece.along, piece.across + reach)
                segments.append(WalkBarriers.Segment(ax: a.x, ay: a.y, bx: b.x, by: b.y,
                                                     half: min(piece.length, piece.depth) / 2))
            }
        }
        return segments
    }

    /// The parts of one opening of the given kind, a door standing open the way `swing` says.
    static func pieces(_ frame: Frame, kind: OpeningKind,
                       swing: DoorSwing = DoorSwing(hinge: .nearStart, opensToward: .left)) -> [Piece] {
        guard frame.width > 0, frame.height > 0 else { return [] }
        if kind.isDoor {
            return trim(frame) + door(frame, kind: kind, swing: swing)
        } else if kind == .casedOpening {
            return trim(frame)
        }
        return trim(frame, withSill: true) + window(frame)
    }

    /// Where an opening sits: its middle on the wall's centerline, the wall's direction, and its size.
    struct Frame {
        var ax: Double
        var ay: Double
        var ux: Double
        var uy: Double
        var start: Double
        var width: Double
        var sill: Double
        var height: Double
        var wallThickness: Double

        init(wall: Wall, opening: Opening, floor: Double) {
            ax = HouseScene.feet(wall.start.x)
            ay = HouseScene.feet(wall.start.y)
            let dx = HouseScene.feet(wall.end.x) - ax, dy = HouseScene.feet(wall.end.y) - ay
            let length = max((dx * dx + dy * dy).squareRoot(), 1e-9)
            (ux, uy) = (dx / length, dy / length)
            start = HouseScene.feet(opening.offsetAlongWall)
            width = HouseScene.feet(opening.width)
            sill = floor + HouseScene.feet(opening.sillHeight)
            height = HouseScene.feet(opening.height)
            wallThickness = HouseScene.feet(wall.thickness)
        }

        var turn: Double { atan2(uy, ux) }
        var top: Double { sill + height }
        var middle: Double { start + width / 2 }

        /// Whether the jamb and head liners fit, leaving an opening between them.
        var hasLiners: Bool {
            wallThickness > 0 && width >= 2 * OpeningDetail.liner + OpeningDetail.least
                && height >= OpeningDetail.liner + OpeningDetail.least
        }

        /// How far the leaf or sash stands in from the jambs and below the head.
        var inset: Double { hasLiners ? OpeningDetail.liner : 0 }

        /// A plan point `along` the wall from its start and `across` from the centerline (left positive).
        func point(_ along: Double, _ across: Double = 0) -> (x: Double, y: Double) {
            (ax + ux * along - uy * across, ay + uy * along + ux * across)
        }

        /// A box `length` along the wall, `depth` across it, and `tall` high, its middle at `along` and
        /// `across`, standing on `z0`.
        func box(_ solid: inout Solid, along: Double, across: Double = 0, z0: Double, length: Double,
                 depth: Double, tall: Double) {
            let middle = point(along, across)
            Shapes.box(&solid, cx: middle.x, cy: middle.y, z0: z0, width: length, depth: depth, height: tall,
                       turn: turn)
        }
    }

    /// Molded casing on both faces of the wall, two legs and a head, and for a window a bottom piece too; then
    /// the liners across the wall's thickness, so the opening reads as finished, not cut. Casing always fits;
    /// liners only when the opening is big enough to show between them.
    private static func trim(_ frame: Frame, withSill: Bool = false) -> [Piece] {
        let bottom = withSill ? frame.sill - casing : frame.sill
        let legTall = frame.top + casing - bottom
        var pieces: [Piece] = []
        for side in [1.0, -1.0] {
            let across = side * (frame.wallThickness / 2 + proud / 2)
            pieces += [
                Piece(part: .casing, look: .trim, along: frame.start - casing / 2, across: across, z0: bottom,
                      length: casing, depth: proud, tall: legTall, run: .up, outward: side),
                Piece(part: .casing, look: .trim, along: frame.start + frame.width + casing / 2, across: across,
                      z0: bottom, length: casing, depth: proud, tall: legTall, run: .up, outward: side),
                Piece(part: .casing, look: .trim, along: frame.middle, across: across, z0: frame.top,
                      length: frame.width, depth: proud, tall: casing, run: .along, outward: side),
            ]
            if withSill {
                pieces.append(Piece(part: .casing, look: .trim, along: frame.middle, across: across,
                                    z0: frame.sill - casing, length: frame.width, depth: proud, tall: casing,
                                    run: .along, outward: side))
            }
        }
        guard frame.hasLiners else { return pieces }
        let jambTall = frame.height - liner
        pieces += [
            Piece(part: .liner, look: .trim, along: frame.start + liner / 2, z0: frame.sill, length: liner,
                  depth: frame.wallThickness, tall: jambTall),
            Piece(part: .liner, look: .trim, along: frame.start + frame.width - liner / 2, z0: frame.sill,
                  length: liner, depth: frame.wallThickness, tall: jambTall),
            Piece(part: .liner, look: .trim, along: frame.middle, z0: frame.top - liner, length: frame.width,
                  depth: frame.wallThickness, tall: liner),
        ]
        return pieces
    }

    /// The door as it stands open, so a walk through it never meets the leaf: a hinged leaf turned square to the
    /// wall on its swing side against its hinge jamb (a double door's two leaves, one at each jamb); a folding
    /// door's halves folded up at the jambs; a sliding door's moving panel slid over its fixed one; a pocket door
    /// away in its pocket inside the wall; a garage door raised flat under the head on its swing side. Every leaf
    /// keeps a slight gap from the liners; a door too narrow to split has a single leaf, and one too narrow
    /// for even that turned open keeps its leaf shut.
    private static func door(_ frame: Frame, kind: OpeningKind, swing: DoorSwing) -> [Piece] {
        let clear = frame.inset + gap
        let width = frame.width - 2 * clear
        let tall = frame.height - frame.inset - gap - 0.02
        guard width >= least, tall >= least else { return [] }
        let open = Opened(z0: frame.sill + 0.02, tall: tall, side: swing.opensToward == .left ? 1 : -1,
                          face: frame.wallThickness / 2)
        let near = frame.start + clear, far = frame.start + frame.width - clear
        let each = (width - gap) / 2
        let thick = kind == .foldingDoor ? 2 * leafThickness : leafThickness
        // A doorway too narrow for its leaves turned open keeps them shut in the wall: no walk fits through it.
        if kind != .pocketDoor, kind == .slidingDoor ? each < least : thick > width {
            return [Piece(part: .leaf, look: .door, along: frame.middle, z0: open.z0, length: width,
                          depth: leafThickness, tall: tall)]
        }
        let pair = each >= least && 2 * thick + gap <= width
        switch kind {
        case .pocketDoor:
            return []
        case .garageDoor:
            return [Piece(part: .leaf, look: .door, along: frame.middle, across: open.side * (open.face + tall / 2),
                          z0: open.z0 + tall - leafThickness, length: width, depth: tall, tall: leafThickness)]
        case .slidingDoor:
            // Both panels over the start half, in tracks either side of the centerline.
            let track = (leafThickness + gap) / 2
            var pieces = [-track, track].map {
                Piece(part: .leaf, look: .door, along: near + each / 2, across: $0, z0: open.z0, length: each,
                      depth: leafThickness, tall: tall)
            }
            let knob = 0.2
            if each >= handleRoom, tall >= 2 * knob {
                let along = near + each - 0.25
                let height = min(3, tall / 2) - knob / 2
                let outside = track + (leafThickness + knob) / 2
                for face in [-1.0, 1.0] {
                    pieces.append(Piece(part: .handle, look: .metal, along: along, across: face * outside,
                                        z0: open.z0 + height, length: knob, depth: knob, tall: knob))
                }
            }
            return pieces
        case .doubleDoor where pair, .foldingDoor where pair:
            let folded = kind == .foldingDoor
            return leaf(hinge: near, toward: 1, width: each, folded: folded, open)
                + leaf(hinge: far, toward: -1, width: each, folded: folded, open)
        default:
            let atStart = swing.hinge == .nearStart
            return leaf(hinge: atStart ? near : far, toward: atStart ? 1 : -1, width: width,
                        folded: kind == .foldingDoor, open)
        }
    }

    /// How a door's leaves stand open: from `z0`, `tall` high, out from the wall's `face` (half its thickness)
    /// on `side` (1 left of the wall's direction, -1 right).
    private struct Opened {
        var z0: Double
        var tall: Double
        var side: Double
        var face: Double
    }

    /// One leaf `width` wide turned open square to the wall: standing `toward` the opening from its `hinge`
    /// and reaching out from the wall's face; folded in half, twice as thick and half as far out, for a folding
    /// door. A leaf wide and tall enough has a handle on both faces near its free edge.
    private static func leaf(hinge: Double, toward: Double, width: Double, folded: Bool, _ open: Opened) -> [Piece] {
        let thick = folded ? 2 * leafThickness : leafThickness
        let out = folded ? width / 2 : width
        let along = hinge + toward * thick / 2
        var pieces = [Piece(part: .leaf, look: .door, along: along, across: open.side * (open.face + out / 2),
                            z0: open.z0, length: thick, depth: out, tall: open.tall)]
        let knob = 0.2
        guard width >= handleRoom, open.tall >= 2 * knob else { return pieces }
        let height = min(3, open.tall / 2) - knob / 2
        let across = open.side * (open.face + out - 0.25)
        for faceSide in [-1.0, 1.0] {
            pieces.append(Piece(part: .handle, look: .metal, along: along + faceSide * (thick + knob) / 2,
                                across: across, z0: open.z0 + height, length: knob, depth: knob, tall: knob))
        }
        return pieces
    }

    /// The outside sill, then the sash set inside the liners: two stiles, a head and bottom rail between them,
    /// a meeting rail halfway up when there is room for two panes, and glass in each pane. When the sash bars do
    /// not fit, the window is a single pane of glass; when that does not fit either, it is casing alone.
    private static func window(_ frame: Frame) -> [Piece] {
        // The sill is a shelf on the outside face, just past the casing.
        var pieces = [Piece(part: .sill, look: .trim, along: frame.middle,
                            across: -(frame.wallThickness / 2 + proud + 0.125), z0: frame.sill - 0.12,
                            length: frame.width + 2 * casing + 0.2, depth: 0.25, tall: 0.12)]
        let left = frame.start + frame.inset
        let width = frame.width - 2 * frame.inset
        let height = frame.height - frame.inset
        guard width >= 2 * bar + least, height >= 2 * bar + least else {
            if width >= least, height >= least {
                pieces.append(Piece(part: .glass, look: .glass, along: frame.middle, z0: frame.sill, length: width,
                                    depth: 0.03, tall: height))
            }
            return pieces
        }
        let top = frame.sill + height, inner = width - 2 * bar
        pieces += [
            Piece(part: .sash, look: .trim, along: left + bar / 2, z0: frame.sill, length: bar, depth: frameDepth,
                  tall: height),
            Piece(part: .sash, look: .trim, along: left + width - bar / 2, z0: frame.sill, length: bar,
                  depth: frameDepth, tall: height),
            Piece(part: .sash, look: .trim, along: frame.middle, z0: frame.sill, length: inner, depth: frameDepth,
                  tall: bar),
            Piece(part: .sash, look: .trim, along: frame.middle, z0: top - bar, length: inner, depth: frameDepth,
                  tall: bar),
        ]
        var panes = [(frame.sill + bar, top - bar)]
        if height >= 3 * bar + 2 * least {
            let rail = frame.sill + height / 2 - bar / 2
            pieces.append(Piece(part: .sash, look: .trim, along: frame.middle, z0: rail, length: inner,
                                depth: frameDepth, tall: bar))
            panes = [(frame.sill + bar, rail), (rail + bar, top - bar)]
        }
        for (low, high) in panes {
            pieces.append(Piece(part: .glass, look: .glass, along: frame.middle, z0: low, length: inner,
                                depth: 0.03, tall: high - low))
        }
        return pieces
    }
}
