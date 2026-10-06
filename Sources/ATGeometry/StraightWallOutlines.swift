import ATContracts
import Foundation

public struct StraightWallOutlines: Sendable {
    public init() {}

    public func outlines(for walls: [Wall]) throws -> [WallID: ClosedPolygon2] {
        let axisWalls = try walls.map { try AxisAlignedWall(wall: $0) }
        let junctions = JunctionIndex(axisWalls: axisWalls)
        var result: [WallID: ClosedPolygon2] = [:]
        for axisWall in axisWalls {
            result[axisWall.wall.id] = try Self.polygon(for: axisWall, junctions: junctions)
        }
        return result
    }

    private static func polygon(for wall: AxisAlignedWall, junctions: JunctionIndex) throws -> ClosedPolygon2 {
        switch wall.orientation {
        case .horizontal:
            return polygonForHorizontal(wall: wall, junctions: junctions)
        case .vertical:
            return polygonForVertical(wall: wall, junctions: junctions)
        }
    }

    private static func polygonForHorizontal(wall: AxisAlignedWall, junctions: JunctionIndex) -> ClosedPolygon2 {
        let y = wall.centerY!
        let h = wall.halfThickness
        var south = y - h
        var north = y + h
        var west = wall.minAlong
        var east = wall.maxAlong

        trimHorizontalEnd(
            wall: wall,
            at: JunctionPoint(wall.wall.start),
            junctions: junctions,
            isStart: true,
            south: &south,
            north: &north,
            west: &west,
            east: &east
        )
        trimHorizontalEnd(
            wall: wall,
            at: JunctionPoint(wall.wall.end),
            junctions: junctions,
            isStart: false,
            south: &south,
            north: &north,
            west: &west,
            east: &east
        )

        let interiorCuts = junctions.interiorCuts(on: wall)
        if interiorCuts.isEmpty {
            let vertices = [
                point(west, south),
                point(east, south),
                point(east, north),
                point(west, north),
            ]
            return ClosedPolygon2(vertices: vertices)
        }

        var vertices: [Point2] = [
            point(west, south),
            point(east, south),
            point(east, north),
        ]
        for cut in interiorCuts.sorted(by: { $0.position > $1.position }) {
            let half = cut.crossHalfThickness
            vertices.append(point(cut.position + half, north))
            vertices.append(point(cut.position + half, south))
            vertices.append(point(cut.position - half, south))
            vertices.append(point(cut.position - half, north))
        }
        vertices.append(point(west, north))
        return ClosedPolygon2(vertices: vertices)
    }

    private static func polygonForVertical(wall: AxisAlignedWall, junctions: JunctionIndex) -> ClosedPolygon2 {
        let x = wall.centerX!
        let h = wall.halfThickness
        var west = x - h
        var east = x + h
        var south = wall.minAlong
        var north = wall.maxAlong

        trimVerticalEnd(
            wall: wall,
            at: JunctionPoint(wall.wall.start),
            junctions: junctions,
            isStart: true,
            west: &west,
            east: &east,
            south: &south,
            north: &north
        )
        trimVerticalEnd(
            wall: wall,
            at: JunctionPoint(wall.wall.end),
            junctions: junctions,
            isStart: false,
            west: &west,
            east: &east,
            south: &south,
            north: &north
        )

        let interiorCuts = junctions.interiorCuts(on: wall)
        if interiorCuts.isEmpty {
            let vertices = [
                point(west, south),
                point(west, north),
                point(east, north),
                point(east, south),
            ]
            return ClosedPolygon2(vertices: vertices)
        }

        var vertices: [Point2] = [
            point(west, south),
            point(west, north),
            point(east, north),
        ]
        for cut in interiorCuts.sorted(by: { $0.position > $1.position }) {
            let half = cut.crossHalfThickness
            vertices.append(point(east, cut.position + half))
            vertices.append(point(west, cut.position + half))
            vertices.append(point(west, cut.position - half))
            vertices.append(point(east, cut.position - half))
        }
        vertices.append(point(east, south))
        return ClosedPolygon2(vertices: vertices)
    }

    private static func trimHorizontalEnd(
        wall: AxisAlignedWall,
        at point: JunctionPoint,
        junctions: JunctionIndex,
        isStart: Bool,
        south: inout Int64,
        north: inout Int64,
        west: inout Int64,
        east: inout Int64
    ) {
        guard let context = junctions.context(at: point, for: wall) else { return }
        let h = wall.halfThickness
        switch context.kind {
        case .lJoin:
            guard let partner = context.partner(for: wall) else { return }
            let partnerHalf = partner.halfThickness
            let outerSouth = point.y - h
            let outerNorth = point.y + h
            let outerWest = point.x - partnerHalf
            let outerEast = point.x + partnerHalf
            if isStart {
                west = outerWest
                south = outerSouth
                north = outerNorth
                if partner.orientation == .vertical, partner.increasing {
                    west = outerWest
                    north = point.y + partnerHalf
                    south = point.y - h
                }
            } else {
                east = outerEast
                south = outerSouth
                north = outerNorth
            }
            applyLMiterHorizontal(
                wall: wall,
                partner: partner,
                at: point,
                isStart: isStart,
                south: &south,
                north: &north,
                west: &west,
                east: &east
            )
        case .tJoin:
            if context.isStem(wall) {
                if isStart {
                    south = point.y + context.throughHalfThickness(on: wall)
                } else {
                    north = point.y - context.throughHalfThickness(on: wall)
                }
            }
        case .xJoin:
            if context.isStem(wall) {
                if isStart {
                    south = point.y + context.throughHalfThickness(on: wall)
                } else {
                    north = point.y - context.throughHalfThickness(on: wall)
                }
            }
        }
    }

    private static func trimVerticalEnd(
        wall: AxisAlignedWall,
        at point: JunctionPoint,
        junctions: JunctionIndex,
        isStart: Bool,
        west: inout Int64,
        east: inout Int64,
        south: inout Int64,
        north: inout Int64
    ) {
        guard let context = junctions.context(at: point, for: wall) else { return }
        let h = wall.halfThickness
        switch context.kind {
        case .lJoin:
            guard let partner = context.partner(for: wall) else { return }
            applyLMiterVertical(
                wall: wall,
                partner: partner,
                at: point,
                isStart: isStart,
                west: &west,
                east: &east,
                south: &south,
                north: &north
            )
        case .tJoin, .xJoin:
            if context.isStem(wall) {
                if isStart {
                    south = point.y + context.throughHalfThickness(on: wall)
                } else {
                    north = point.y - context.throughHalfThickness(on: wall)
                }
            }
        }
    }

    private static func applyLMiterHorizontal(
        wall: AxisAlignedWall,
        partner: AxisAlignedWall,
        at point: JunctionPoint,
        isStart: Bool,
        south: inout Int64,
        north: inout Int64,
        west: inout Int64,
        east: inout Int64
    ) {
        let h = wall.halfThickness
        let partnerHalf = partner.halfThickness
        let outer = miterCorner(
            horizontal: wall,
            vertical: partner,
            at: point,
            preferOuter: true
        )
        let inner = miterCorner(
            horizontal: wall,
            vertical: partner,
            at: point,
            preferOuter: false
        )
        if isStart {
            west = outer.x
            south = outer.y
            north = inner.y
            west = min(west, inner.x)
        } else {
            east = outer.x
            south = outer.y
            north = inner.y
            east = max(east, inner.x)
        }
        if isStart {
            west = min(outer.x, inner.x)
            south = min(outer.y, inner.y)
            north = max(outer.y, inner.y)
        } else {
            east = max(outer.x, inner.x)
            south = min(outer.y, inner.y)
            north = max(outer.y, inner.y)
        }
        _ = h
        _ = partnerHalf
    }

    private static func applyLMiterVertical(
        wall: AxisAlignedWall,
        partner: AxisAlignedWall,
        at point: JunctionPoint,
        isStart: Bool,
        west: inout Int64,
        east: inout Int64,
        south: inout Int64,
        north: inout Int64
    ) {
        let outer = miterCorner(
            horizontal: partner,
            vertical: wall,
            at: point,
            preferOuter: true
        )
        let inner = miterCorner(
            horizontal: partner,
            vertical: wall,
            at: point,
            preferOuter: false
        )
        if isStart {
            south = min(outer.y, inner.y)
            west = min(outer.x, inner.x)
            east = max(outer.x, inner.x)
        } else {
            north = max(outer.y, inner.y)
            west = min(outer.x, inner.x)
            east = max(outer.x, inner.x)
        }
    }

    private static func miterCorner(
        horizontal: AxisAlignedWall,
        vertical: AxisAlignedWall,
        at point: JunctionPoint,
        preferOuter: Bool
    ) -> (x: Int64, y: Int64) {
        let y = horizontal.centerY!
        let x = vertical.centerX!
        let hH = horizontal.halfThickness
        let hV = vertical.halfThickness
        let southY = y - hH
        let northY = y + hH
        let westX = x - hV
        let eastX = x + hV
        if preferOuter {
            return (westX, southY)
        }
        return (eastX, northY)
    }

    private static func point(_ x: Int64, _ y: Int64) -> Point2 {
        Point2(x: Length(ticks: x), y: Length(ticks: y))
    }
}

private struct InteriorCut {
    var position: Int64
    var crossHalfThickness: Int64
}

private struct JunctionContext {
    var kind: JunctionKind
    var point: JunctionPoint
    var walls: [AxisAlignedWall]

    func partner(for wall: AxisAlignedWall) -> AxisAlignedWall? {
        walls.first { $0.wall.id != wall.wall.id }
    }

    func isStem(_ wall: AxisAlignedWall) -> Bool {
        let atPoint = Point2(x: Length(ticks: point.x), y: Length(ticks: point.y))
        guard wall.endpoint(at: atPoint) != nil else { return false }
        return walls.contains { other in
            other.wall.id != wall.wall.id && other.containsInteriorPoint(x: point.x, y: point.y)
        }
    }

    func throughHalfThickness(on stem: AxisAlignedWall) -> Int64 {
        guard let through = walls.first(where: {
            $0.wall.id != stem.wall.id && $0.containsInteriorPoint(x: point.x, y: point.y)
        }) else {
            return walls.map(\.halfThickness).max() ?? stem.halfThickness
        }
        return through.halfThickness
    }
}

private struct JunctionIndex {
    private var byPoint: [JunctionPoint: JunctionContext] = [:]
    private var interiorOnWall: [WallID: [InteriorCut]] = [:]

    init(axisWalls: [AxisAlignedWall]) {
        var builtByPoint: [JunctionPoint: JunctionContext] = [:]
        var builtInterior: [WallID: [InteriorCut]] = [:]
        var endpointWalls: [JunctionPoint: [AxisAlignedWall]] = [:]
        for wall in axisWalls {
            endpointWalls[JunctionPoint(wall.wall.start), default: []].append(wall)
            endpointWalls[JunctionPoint(wall.wall.end), default: []].append(wall)
        }

        for wall in axisWalls {
            for other in axisWalls where other.wall.id != wall.wall.id {
                for endpoint in [wall.wall.start, wall.wall.end] {
                    let key = JunctionPoint(endpoint)
                    if other.containsInteriorPoint(x: key.x, y: key.y) {
                        endpointWalls[key, default: []].append(wall)
                        endpointWalls[key, default: []].append(other)
                    }
                }
            }
        }

        for (point, walls) in endpointWalls {
            let unique = Self.uniqueWalls(walls)
            let kind = Self.classify(at: point, walls: unique)
            builtByPoint[point] = JunctionContext(kind: kind, point: point, walls: unique)
        }

        for wall in axisWalls {
            for other in axisWalls where other.wall.id != wall.wall.id {
                if let crossing = Self.crossingPoint(wall, other) {
                    let key = JunctionPoint(crossing)
                    var wallsAt = builtByPoint[key]?.walls ?? []
                    wallsAt.append(wall)
                    wallsAt.append(other)
                    let unique = Self.uniqueWalls(wallsAt)
                    builtByPoint[key] = JunctionContext(kind: .xJoin, point: key, walls: unique)
                    Self.recordInteriorCut(stem: wall, through: other, at: key, into: &builtInterior)
                    Self.recordInteriorCut(stem: other, through: wall, at: key, into: &builtInterior)
                }
            }
        }

        byPoint = builtByPoint
        interiorOnWall = builtInterior
    }

    func context(at point: JunctionPoint, for wall: AxisAlignedWall) -> JunctionContext? {
        guard let context = byPoint[point] else { return nil }
        guard context.walls.contains(where: { $0.wall.id == wall.wall.id }) else { return nil }
        return context
    }

    func interiorCuts(on wall: AxisAlignedWall) -> [InteriorCut] {
        interiorOnWall[wall.wall.id] ?? []
    }

    private static func recordInteriorCut(
        stem: AxisAlignedWall,
        through: AxisAlignedWall,
        at point: JunctionPoint,
        into interiorOnWall: inout [WallID: [InteriorCut]]
    ) {
        guard stem.endpoint(at: Point2(x: Length(ticks: point.x), y: Length(ticks: point.y))) != nil else {
            return
        }
        guard through.containsInteriorPoint(x: point.x, y: point.y) else { return }
        let cut: InteriorCut
        switch through.orientation {
        case .horizontal:
            cut = InteriorCut(position: point.x, crossHalfThickness: stem.halfThickness)
        case .vertical:
            cut = InteriorCut(position: point.y, crossHalfThickness: stem.halfThickness)
        }
        var cuts = interiorOnWall[through.wall.id] ?? []
        if !cuts.contains(where: { $0.position == cut.position }) {
            cuts.append(cut)
            interiorOnWall[through.wall.id] = cuts
        }
    }

    private static func crossingPoint(_ a: AxisAlignedWall, _ b: AxisAlignedWall) -> Point2? {
        guard a.orientation != b.orientation else { return nil }
        let horizontal = a.orientation == .horizontal ? a : b
        let vertical = a.orientation == .vertical ? a : b
        guard let y = horizontal.centerY, let x = vertical.centerX else { return nil }
        if horizontal.containsInteriorPoint(x: x, y: y), vertical.containsInteriorPoint(x: x, y: y) {
            return Point2(x: Length(ticks: x), y: Length(ticks: y))
        }
        return nil
    }

    private static func uniqueWalls(_ walls: [AxisAlignedWall]) -> [AxisAlignedWall] {
        var seen: Set<WallID> = []
        var result: [AxisAlignedWall] = []
        for wall in walls {
            if seen.insert(wall.wall.id).inserted {
                result.append(wall)
            }
        }
        return result
    }

    private static func classify(at point: JunctionPoint, walls: [AxisAlignedWall]) -> JunctionKind {
        if walls.count >= 4 {
            return .xJoin
        }
        let endpointHits = walls.filter {
            $0.endpoint(at: Point2(x: Length(ticks: point.x), y: Length(ticks: point.y))) != nil
        }
        if walls.count == 3 || (walls.count == 2 && endpointHits.count == 1) {
            return .tJoin
        }
        return .lJoin
    }
}
