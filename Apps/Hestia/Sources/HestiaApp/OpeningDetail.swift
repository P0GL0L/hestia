import ATContracts
import Foundation

/// Doors and windows built as a carpenter would show them, in place of the engine's flat panes: painted casing
/// around every opening, a solid door leaf with a handle, and windows with a frame, a meeting rail, glass with
/// thickness, and a sill. All sizes are in feet and come from the opening and its wall.
enum OpeningDetail {
    /// Casing face width and how far it stands proud of the wall face.
    static let casing = 0.29
    static let proud = 0.06
    static let leafThickness = 0.146
    static let frameDepth = 0.3

    static func add(_ document: ModelDocument, to solids: inout [Look: Solid]) {
        let walls = Dictionary(document.walls.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for opening in document.openings {
            guard let wall = walls[opening.wallID] else { continue }
            let floor = document.storeys.first { $0.id == wall.storeyID }.map { HouseScene.feet($0.elevation) } ?? 0
            let frame = Frame(wall: wall, opening: opening, floor: floor)
            guard frame.width > 0.2, frame.height > 0.2 else { continue }
            if opening.kind.isDoor {
                door(frame, kind: opening.kind, to: &solids)
            } else if opening.kind == .casedOpening {
                trim(frame, to: &solids)
            } else {
                window(frame, to: &solids)
            }
        }
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

    /// Casing on both faces: two legs and a head, standing proud of the wall.
    private static func trim(_ frame: Frame, to solids: inout [Look: Solid], withSill: Bool = false) {
        var solid = solids[.trim] ?? Solid(look: .trim)
        let depth = frame.wallThickness + 2 * proud
        let top = frame.sill + frame.height
        let bottom = withSill ? frame.sill - casing : frame.sill
        frame.box(&solid, along: frame.start - casing / 2, z0: bottom, length: casing, depth: depth,
                  tall: top + casing - bottom)
        frame.box(&solid, along: frame.start + frame.width + casing / 2, z0: bottom, length: casing, depth: depth,
                  tall: top + casing - bottom)
        frame.box(&solid, along: frame.start + frame.width / 2, z0: top, length: frame.width, depth: depth,
                  tall: casing)
        if withSill {
            frame.box(&solid, along: frame.start + frame.width / 2, z0: frame.sill - casing, length: frame.width,
                      depth: depth, tall: casing)
        }
        // The jamb liners across the wall's thickness, so the opening reads as finished, not cut.
        let liner = 0.06
        frame.box(&solid, along: frame.start + liner / 2, z0: frame.sill, length: liner, depth: frame.wallThickness,
                  tall: frame.height)
        frame.box(&solid, along: frame.start + frame.width - liner / 2, z0: frame.sill, length: liner,
                  depth: frame.wallThickness, tall: frame.height)
        frame.box(&solid, along: frame.start + frame.width / 2, z0: top - liner, length: frame.width,
                  depth: frame.wallThickness, tall: liner)
        solids[.trim] = solid
    }

    /// Casing, a leaf with a slight gap all round, and a handle on both faces. A garage door has no handle.
    private static func door(_ frame: Frame, kind: OpeningKind, to solids: inout [Look: Solid]) {
        trim(frame, to: &solids)
        var leaf = solids[.door] ?? Solid(look: .door)
        let gap = 0.03, liner = 0.06
        let width = frame.width - 2 * (liner + gap), height = frame.height - liner - gap
        let panels = kind == .doubleDoor || kind == .slidingDoor || kind == .foldingDoor ? 2 : 1
        let each = width / Double(panels)
        for panel in 0..<panels {
            let middle = frame.start + liner + gap + each * (Double(panel) + 0.5)
            frame.box(&leaf, along: middle, z0: frame.sill + 0.02, length: each - (panels > 1 ? gap : 0),
                      depth: leafThickness, tall: height - 0.02)
        }
        solids[.door] = leaf
        guard kind != .garageDoor else { return }
        var handle = solids[.metal] ?? Solid(look: .metal)
        let along = frame.start + frame.width - liner - gap - 0.25
        for side in [-1.0, 1.0] {
            let knob = frame.point(along, side * (leafThickness / 2 + 0.1))
            Shapes.ellipsoid(&handle, cx: knob.x, cy: knob.y, cz: frame.sill + 3, rx: 0.1, ry: 0.1, rz: 0.1,
                             rings: 6, segments: 10)
        }
        solids[.metal] = handle
    }

    /// Casing with a sill, a sash frame set back in the wall, a meeting rail, and two panes of glass.
    private static func window(_ frame: Frame, to solids: inout [Look: Solid]) {
        trim(frame, to: &solids, withSill: true)
        var sash = solids[.trim] ?? Solid(look: .trim)
        let bar = 0.16, top = frame.sill + frame.height
        // Sash frame: two stiles, a head, a bottom rail, and the meeting rail halfway up.
        frame.box(&sash, along: frame.start + bar / 2, z0: frame.sill, length: bar, depth: frameDepth,
                  tall: frame.height)
        frame.box(&sash, along: frame.start + frame.width - bar / 2, z0: frame.sill, length: bar, depth: frameDepth,
                  tall: frame.height)
        for z0 in [frame.sill, top - bar, frame.sill + frame.height / 2 - bar / 2] {
            frame.box(&sash, along: frame.start + frame.width / 2, z0: z0, length: frame.width, depth: frameDepth,
                      tall: bar)
        }
        // The outside sill, sloped in reality, here a shelf standing out from the wall face.
        frame.box(&sash, along: frame.start + frame.width / 2, across: -(frame.wallThickness / 2 + 0.1),
                  z0: frame.sill - 0.12, length: frame.width + 2 * casing + 0.2, depth: 0.25, tall: 0.12)
        solids[.trim] = sash
        var glass = solids[.glass] ?? Solid(look: .glass)
        frame.box(&glass, along: frame.start + frame.width / 2, z0: frame.sill + bar, length: frame.width - 2 * bar,
                  depth: 0.03, tall: frame.height - 2 * bar)
        solids[.glass] = glass
    }
}
