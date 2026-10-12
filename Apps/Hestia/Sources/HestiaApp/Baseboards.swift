import ATContracts
import ATDrawings
import Foundation

/// Baseboards around every room: a molded board along the foot of each wall's inside face, stopping at the casing
/// of each door and cased opening, and at floor-length windows.
enum Baseboards {
    static let height = 0.375
    static let thickness = 0.05
    static let floorLift = 0.02

    /// One run of baseboard: from `start`, `length` feet along the unit plan direction `run`, its face toward the
    /// unit plan direction `into` the room, standing on `floor`.
    struct Run: Sendable {
        var start: (x: Double, y: Double)
        var run: (x: Double, y: Double)
        var into: (x: Double, y: Double)
        var length: Double
        var floor: Double
    }

    static func add(_ document: ModelDocument, to solids: inout [Look: Solid]) {
        let board = Molding.baseboard(height: height, thickness: thickness)
        var solid = solids[.trim] ?? Solid(look: .trim)
        for piece in runs(document) {
            board.extrude(&solid, start: Vector(piece.start.x, piece.start.y, piece.floor),
                          run: Vector(piece.run.x, piece.run.y, 0), length: piece.length, across: Vector(0, 0, 1),
                          out: Vector(piece.into.x, piece.into.y, 0))
        }
        if !solid.indices.isEmpty { solids[.trim] = solid }
    }

    /// Every baseboard run in the document's rooms.
    static func runs(_ document: ModelDocument) -> [Run] {
        let walls = Dictionary(document.walls.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var runs: [Run] = []
        for room in document.rooms {
            guard let outline = RoomOutline.centerline(of: room, in: document) else { continue }
            let plan = outline.map { (x: HouseScene.feet($0.x), y: HouseScene.feet($0.y)) }
            let ring = Triangulation.counterclockwise(plan)
            guard ring.count >= 3 else { continue }
            let boundary = room.boundaryWallIDs.compactMap { walls[$0] }
            let storey = document.storeys.first { $0.id == room.storeyID }
            let floor = (storey.map { HouseScene.feet($0.elevation) } ?? 0) + floorLift
            let sides = ring.indices.map { index in
                side(from: ring[index], to: ring[(index + 1) % ring.count], walls: boundary)
            }
            for index in sides.indices {
                let side = sides[index]
                let before = sides[(index + sides.count - 1) % sides.count]
                let after = sides[(index + 1) % sides.count]
                guard let start = corner(before, side), let end = corner(side, after) else { continue }
                let length = (end.x - start.x) * side.direction.x + (end.y - start.y) * side.direction.y
                guard length > 0.05 else { continue }
                let gaps = side.walls.flatMap { openings(on: $0, document: document, side: side, from: start) }
                for (from, to) in pieces(length: length, minus: gaps) {
                    runs.append(Run(start: (start.x + side.direction.x * from, start.y + side.direction.y * from),
                                    run: side.direction, into: side.inward, length: to - from, floor: floor))
                }
            }
        }
        return runs
    }

    /// A side of a room's centerline outline, with every collinear wall segment on it and its inside face line.
    private struct Side {
        var from: (x: Double, y: Double)
        var direction: (x: Double, y: Double)
        var inward: (x: Double, y: Double)
        var offset: Double
        var walls: [Wall]

        /// A point on the wall's inside face line.
        var face: (x: Double, y: Double) { (from.x + inward.x * offset, from.y + inward.y * offset) }
    }

    private static func side(from a: (x: Double, y: Double), to b: (x: Double, y: Double), walls: [Wall]) -> Side {
        let (dx, dy) = (b.x - a.x, b.y - a.y)
        let size = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        let direction = (x: dx / size, y: dy / size)
        let inward = (x: -direction.y, y: direction.x)
        let middle = (x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        // RoomOutline removes collinear junctions, so one side may comprise several wall segments. Keep every
        // segment on this supporting line whose projection overlaps the side, in either drawing direction.
        let matching = walls.filter { wall in
            let first = (x: HouseScene.feet(wall.start.x), y: HouseScene.feet(wall.start.y))
            let second = (x: HouseScene.feet(wall.end.x), y: HouseScene.feet(wall.end.y))
            let (wx, wy) = (second.x - first.x, second.y - first.y)
            let wallSize = (wx * wx + wy * wy).squareRoot()
            guard wallSize > 1e-9 else { return false }
            let parallel = abs(wx * direction.y - wy * direction.x) / wallSize < 1e-6
            let fromLine = abs((first.x - a.x) * inward.x + (first.y - a.y) * inward.y)
            let p0 = (first.x - a.x) * direction.x + (first.y - a.y) * direction.y
            let p1 = (second.x - a.x) * direction.x + (second.y - a.y) * direction.y
            return parallel && fromLine < 0.05 && max(p0, p1) > -0.05 && min(p0, p1) < size + 0.05
        }
        let wall = matching.min { distance(middle, to: $0) < distance(middle, to: $1) }
            .flatMap { distance(middle, to: $0) < 0.05 ? $0 : nil }
        let offset = wall.map { HouseScene.feet($0.thickness) / 2 } ?? 0.25
        return Side(from: a, direction: direction, inward: inward, offset: offset, walls: matching)
    }

    private static func distance(_ point: (x: Double, y: Double), to wall: Wall) -> Double {
        let a = (x: HouseScene.feet(wall.start.x), y: HouseScene.feet(wall.start.y))
        let b = (x: HouseScene.feet(wall.end.x), y: HouseScene.feet(wall.end.y))
        let (dx, dy) = (b.x - a.x, b.y - a.y)
        let size = dx * dx + dy * dy
        let t = size > 0 ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / size, 0), 1) : 0
        let (px, py) = (a.x + dx * t - point.x, a.y + dy * t - point.y)
        return (px * px + py * py).squareRoot()
    }

    /// Where two consecutive sides' inside faces meet; for sides in line, where the second begins.
    private static func corner(_ first: Side, _ second: Side) -> (x: Double, y: Double)? {
        let cross = first.direction.x * second.direction.y - first.direction.y * second.direction.x
        let (p, q) = (first.face, second.face)
        guard abs(cross) > 1e-6 else { return q }
        let t = ((q.x - p.x) * second.direction.y - (q.y - p.y) * second.direction.x) / cross
        return (p.x + first.direction.x * t, p.y + first.direction.y * t)
    }

    /// Stretches of a side, measured from its start, covered by a door, cased opening, or a window whose casing
    /// reaches the board, widened by the casing the baseboard stops against.
    private static func openings(on wall: Wall, document: ModelDocument, side: Side,
                                 from start: (x: Double, y: Double)) -> [(Double, Double)] {
        let a = (x: HouseScene.feet(wall.start.x), y: HouseScene.feet(wall.start.y))
        let b = (x: HouseScene.feet(wall.end.x), y: HouseScene.feet(wall.end.y))
        let size = max(((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot(), 1e-9)
        let along = (x: (b.x - a.x) / size, y: (b.y - a.y) / size)
        func measure(_ offset: Double) -> Double {
            let point = (x: a.x + along.x * offset, y: a.y + along.y * offset)
            return (point.x - start.x) * side.direction.x + (point.y - start.y) * side.direction.y
        }
        return document.openings.filter { opening in
            let reachesFloor = opening.kind.isDoor || opening.kind == .casedOpening
                || HouseScene.feet(opening.sillHeight) - OpeningDetail.casing < floorLift + height
            return opening.wallID == wall.id && reachesFloor
        }.map { opening in
            let offset = HouseScene.feet(opening.offsetAlongWall)
            let (first, second) = (measure(offset), measure(offset + HouseScene.feet(opening.width)))
            return (min(first, second) - OpeningDetail.casing, max(first, second) + OpeningDetail.casing)
        }
    }

    /// The stretches of 0...length left after taking out the gaps, each longer than a sliver.
    static func pieces(length: Double, minus gaps: [(Double, Double)]) -> [(Double, Double)] {
        var pieces = [(0.0, length)]
        for gap in gaps {
            pieces = pieces.flatMap { piece -> [(Double, Double)] in
                guard gap.1 > piece.0, gap.0 < piece.1 else { return [piece] }
                return [(piece.0, gap.0), (gap.1, piece.1)].filter { $0.1 - $0.0 > 0.05 }
            }
        }
        return pieces.filter { $0.1 - $0.0 > 0.05 }
    }
}
