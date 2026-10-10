import ATContracts
import ATDrawings
import Foundation

/// Someone walking through the house at eye height. Plan feet: x east, y north. `heading` is a compass
/// bearing in radians, 0 facing north and growing clockwise; `pitch` tilts the view up (positive) or down.
struct Walker: Equatable, Sendable {
    var x: Double
    var y: Double
    /// The floor walked on, in feet.
    var floor: Double
    var heading: Double = 0
    var pitch: Double = 0

    static let eyeHeight = 5.4
    /// How close the walker's middle comes to a wall face.
    static let radius = 0.8
    static let walkSpeed = 5.0
    static let runSpeed = 12.0
    static let turnSpeed = 1.8
    static let pitchLimit = 1.2

    /// The eye, in view space.
    var eye: ScenePoint { .plan(x, y, floor + Self.eyeHeight) }

    /// The way the walker faces, flat on the plan.
    var forward: (x: Double, y: Double) { (sin(heading), cos(heading)) }

    /// To the walker's right, flat on the plan.
    var right: (x: Double, y: Double) { (cos(heading), -sin(heading)) }

    /// Moves for `seconds` as the keys held ask, stopping at walls and sliding along them.
    mutating func step(_ input: WalkInput, seconds: Double, barriers: WalkBarriers) {
        heading += input.turn * Self.turnSpeed * seconds
        var dx = forward.x * input.forward + right.x * input.strafe
        var dy = forward.y * input.forward + right.y * input.strafe
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1e-9 else { return }
        let distance = (input.fast ? Self.runSpeed : Self.walkSpeed) * seconds
        dx = dx / length * distance
        dy = dy / length * distance
        // Short steps, so a fast stride never jumps through a wall.
        let steps = max(Int((distance / 0.25).rounded(.up)), 1)
        for _ in 0..<steps {
            (x, y) = barriers.resolve(x: x + dx / Double(steps), y: y + dy / Double(steps), radius: Self.radius)
        }
    }

    /// Turns the view by a mouse drag in view points.
    mutating func look(dx: Double, dy: Double) {
        heading += dx * 0.004
        pitch = min(max(pitch - dy * 0.004, -Self.pitchLimit), Self.pitchLimit)
    }

    /// Where a walk starts on a storey: in the middle of its largest room, facing north. With no rooms, in the
    /// middle of its walls; with no walls, 20 feet south of the origin.
    static func start(in document: ModelDocument, storey: StoreyID?) -> Walker {
        let level = document.storeys.first { $0.id == storey }
        let floor = level.map { HouseScene.feet($0.elevation) } ?? 0
        var best: (area: Double, x: Double, y: Double)?
        for room in document.rooms where room.storeyID == storey {
            guard let outline = RoomOutline.centerline(of: room, in: document) else { continue }
            let plan = outline.map { (x: HouseScene.feet($0.x), y: HouseScene.feet($0.y)) }
            guard let middle = centroid(plan), best == nil || middle.area > best!.area else { continue }
            best = middle
        }
        if let best { return Walker(x: best.x, y: best.y, floor: floor) }
        let walls = document.walls.filter { $0.storeyID == storey }
        if !walls.isEmpty {
            let xs = walls.flatMap { [HouseScene.feet($0.start.x), HouseScene.feet($0.end.x)] }
            let ys = walls.flatMap { [HouseScene.feet($0.start.y), HouseScene.feet($0.end.y)] }
            return Walker(x: ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, y: ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2,
                          floor: floor)
        }
        return Walker(x: 0, y: -20, floor: floor)
    }

    /// A polygon's area and the middle of that area.
    static func centroid(_ points: [(x: Double, y: Double)]) -> (area: Double, x: Double, y: Double)? {
        guard points.count >= 3 else { return nil }
        var twice = 0.0, cx = 0.0, cy = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            let cross = a.x * b.y - b.x * a.y
            twice += cross
            cx += (a.x + b.x) * cross
            cy += (a.y + b.y) * cross
        }
        guard abs(twice) > 1e-9 else { return nil }
        return (abs(twice) / 2, cx / (3 * twice), cy / (3 * twice))
    }
}

/// The keys held while walking, each -1...1.
struct WalkInput: Equatable, Sendable {
    /// Ahead is positive.
    var forward = 0.0
    /// Right is positive.
    var strafe = 0.0
    /// Clockwise is positive.
    var turn = 0.0
    var fast = false
}

/// The walls a walker cannot pass, as plan segments in feet, cut open where doors and cased openings are.
struct WalkBarriers: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        var ax: Double
        var ay: Double
        var bx: Double
        var by: Double
        /// Half the wall's thickness.
        var half: Double
    }

    var segments: [Segment]

    init(segments: [Segment]) {
        self.segments = segments
    }

    /// The storey's walls, each split around its doors and cased openings. Windows stay solid.
    init(document: ModelDocument, storey: StoreyID?) {
        var segments: [Segment] = []
        for wall in document.walls where wall.storeyID == storey {
            let (ax, ay) = (HouseScene.feet(wall.start.x), HouseScene.feet(wall.start.y))
            let (bx, by) = (HouseScene.feet(wall.end.x), HouseScene.feet(wall.end.y))
            let length = ((bx - ax) * (bx - ax) + (by - ay) * (by - ay)).squareRoot()
            guard length > 1e-9 else { continue }
            let gaps = document.openings
                .filter { $0.wallID == wall.id && ($0.kind.isDoor || $0.kind == .casedOpening) }
                .map { opening -> (Double, Double) in
                    let from = HouseScene.feet(opening.offsetAlongWall)
                    return (from, from + HouseScene.feet(opening.width))
                }
                .sorted { $0.0 < $1.0 }
            var from = 0.0
            let half = HouseScene.feet(wall.thickness) / 2
            func piece(_ s: Double, _ e: Double) {
                guard e - s > 1e-6 else { return }
                let (ux, uy) = ((bx - ax) / length, (by - ay) / length)
                segments.append(Segment(ax: ax + ux * s, ay: ay + uy * s, bx: ax + ux * e, by: ay + uy * e, half: half))
            }
            for gap in gaps {
                piece(from, min(gap.0, length))
                from = max(from, gap.1)
            }
            piece(from, length)
        }
        self.segments = segments
    }

    /// The nearest place to (x, y) where a walker of `radius` overlaps no wall: pushed straight out of each wall
    /// it overlaps, a few rounds over, so it slides along walls and stops in corners.
    func resolve(x: Double, y: Double, radius: Double) -> (Double, Double) {
        var (px, py) = (x, y)
        for _ in 0..<4 {
            var moved = false
            for segment in segments {
                let (dx, dy) = (segment.bx - segment.ax, segment.by - segment.ay)
                let lengthSquared = dx * dx + dy * dy
                let along = ((px - segment.ax) * dx + (py - segment.ay) * dy) / max(lengthSquared, 1e-12)
                let t = min(max(along, 0), 1)
                let (cx, cy) = (segment.ax + dx * t, segment.ay + dy * t)
                let (ox, oy) = (px - cx, py - cy)
                let distance = (ox * ox + oy * oy).squareRoot()
                let reach = segment.half + radius
                guard distance < reach else { continue }
                if distance > 1e-9 {
                    px = cx + ox / distance * reach
                    py = cy + oy / distance * reach
                } else {
                    // Exactly on the centerline: step out to the wall's left.
                    let length = max(lengthSquared.squareRoot(), 1e-9)
                    px = cx - dy / length * reach
                    py = cy + dx / length * reach
                }
                moved = true
            }
            if !moved { break }
        }
        return (px, py)
    }
}
