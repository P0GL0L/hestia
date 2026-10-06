import ATContracts
import Foundation

struct AxisAlignedWall {
    enum Orientation {
        case horizontal
        case vertical
    }

    let wall: Wall
    let orientation: Orientation
    let increasing: Bool
    let halfThickness: Int64

    init(wall: Wall) throws {
        self.wall = wall
        let sx = wall.start.x.ticks
        let sy = wall.start.y.ticks
        let ex = wall.end.x.ticks
        let ey = wall.end.y.ticks
        let dx = ex - sx
        let dy = ey - sy
        if dx == 0, dy == 0 {
            throw GeometryError.zeroLengthWall(wall.id)
        }
        halfThickness = wall.thickness.ticks / 2
        if dy == 0 {
            orientation = .horizontal
            increasing = dx > 0
        } else if dx == 0 {
            orientation = .vertical
            increasing = dy > 0
        } else {
            throw GeometryError.wallNotAxisAligned(wall.id)
        }
    }

    var centerY: Int64? {
        guard orientation == .horizontal else { return nil }
        return wall.start.y.ticks
    }

    var centerX: Int64? {
        guard orientation == .vertical else { return nil }
        return wall.start.x.ticks
    }

    var minAlong: Int64 {
        switch orientation {
        case .horizontal:
            min(wall.start.x.ticks, wall.end.x.ticks)
        case .vertical:
            min(wall.start.y.ticks, wall.end.y.ticks)
        }
    }

    var maxAlong: Int64 {
        switch orientation {
        case .horizontal:
            max(wall.start.x.ticks, wall.end.x.ticks)
        case .vertical:
            max(wall.start.y.ticks, wall.end.y.ticks)
        }
    }

    func containsInteriorPoint(x: Int64, y: Int64) -> Bool {
        switch orientation {
        case .horizontal:
            guard let cy = centerY else { return false }
            guard y == cy else { return false }
            let minX = minAlong
            let maxX = maxAlong
            return x > minX && x < maxX
        case .vertical:
            guard let cx = centerX else { return false }
            guard x == cx else { return false }
            let minY = minAlong
            let maxY = maxAlong
            return y > minY && y < maxY
        }
    }

    func endpoint(at point: Point2) -> EndpointRole? {
        let px = point.x.ticks
        let py = point.y.ticks
        if wall.start.x.ticks == px, wall.start.y.ticks == py {
            return .start
        }
        if wall.end.x.ticks == px, wall.end.y.ticks == py {
            return .end
        }
        return nil
    }

    enum EndpointRole {
        case start
        case end
    }
}

struct JunctionPoint: Hashable {
    var x: Int64
    var y: Int64

    init(_ point: Point2) {
        x = point.x.ticks
        y = point.y.ticks
    }
}

enum JunctionKind {
    case lJoin
    case tJoin
    case xJoin
}
