import ATContracts
import Foundation

public struct RoomAreaCalculator: Sendable {
    public init() {}

    /// Net interior area for a closed loop of axis-aligned straight walls.
    public func netArea(for walls: [Wall]) throws -> Area2 {
        let axisWalls = try walls.map { try AxisAlignedWall(wall: $0) }
        let loop = try orderedLoop(from: axisWalls)
        let innerVertices = innerBoundary(from: loop)
        return Area2(tickSquares: shoelaceTickSquares(innerVertices))
    }

    private struct LoopEdge {
        var wall: AxisAlignedWall
        var from: JunctionPoint
        var to: JunctionPoint
    }

    private func orderedLoop(from walls: [AxisAlignedWall]) throws -> [LoopEdge] {
        guard walls.count >= 3 else { throw GeometryError.openWallLoop }
        var remaining = walls
        var edges: [LoopEdge] = []
        let first = remaining.removeFirst()
        let start = JunctionPoint(first.wall.start)
        let firstEnd = JunctionPoint(first.wall.end)
        edges.append(LoopEdge(wall: first, from: start, to: firstEnd))
        var cursor = firstEnd

        while cursor != start {
            guard let nextIndex = remaining.firstIndex(where: { wall in
                JunctionPoint(wall.wall.start) == cursor || JunctionPoint(wall.wall.end) == cursor
            }) else {
                throw GeometryError.disjointWallLoop
            }
            let next = remaining.remove(at: nextIndex)
            let nextStart = JunctionPoint(next.wall.start)
            let nextEnd = JunctionPoint(next.wall.end)
            if nextStart == cursor {
                edges.append(LoopEdge(wall: next, from: nextStart, to: nextEnd))
                cursor = nextEnd
            } else if nextEnd == cursor {
                edges.append(LoopEdge(wall: next, from: nextEnd, to: nextStart))
                cursor = nextStart
            } else {
                throw GeometryError.disjointWallLoop
            }
        }
        if !remaining.isEmpty {
            throw GeometryError.openWallLoop
        }
        return edges
    }

    private func innerBoundary(from loop: [LoopEdge]) -> [Point2] {
        var corners: [Point2] = []
        for index in loop.indices {
            let edge = loop[index]
            let next = loop[(index + 1) % loop.count]
            corners.append(innerCorner(current: edge, next: next))
        }
        return corners
    }

    private func innerCorner(current: LoopEdge, next: LoopEdge) -> Point2 {
        let joint = current.to
        let h0 = current.wall.halfThickness
        let h1 = next.wall.halfThickness

        let currentHorizontal = current.wall.orientation == .horizontal
        let nextHorizontal = next.wall.orientation == .horizontal

        var x = joint.x
        var y = joint.y

        if currentHorizontal {
            let yCenter = current.wall.centerY!
            let increasing = current.to.x > current.from.x
            y = yCenter + (increasing ? h0 : -h0)
        } else {
            let xCenter = current.wall.centerX!
            let increasing = current.to.y > current.from.y
            x = xCenter + (increasing ? -h0 : h0)
        }

        if nextHorizontal {
            let yCenter = next.wall.centerY!
            let increasing = next.to.x > next.from.x
            y = yCenter + (increasing ? h1 : -h1)
        } else {
            let xCenter = next.wall.centerX!
            let increasing = next.to.y > next.from.y
            x = xCenter + (increasing ? -h1 : h1)
        }

        return Point2(x: Length(ticks: x), y: Length(ticks: y))
    }

    private func shoelaceTickSquares(_ vertices: [Point2]) -> Int64 {
        guard vertices.count >= 3 else { return 0 }
        var sum: Int64 = 0
        for index in vertices.indices {
            let current = vertices[index]
            let next = vertices[(index + 1) % vertices.count]
            sum += current.x.ticks * next.y.ticks
            sum -= next.x.ticks * current.y.ticks
        }
        return abs(sum) / 2
    }
}
