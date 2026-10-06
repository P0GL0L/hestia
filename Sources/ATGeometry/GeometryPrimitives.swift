import ATContracts
import Foundation

/// Planar area stored as square 1/320 mm ticks (Length × Length).
public struct Area2: Hashable, Sendable {
    public var tickSquares: Int64

    public init(tickSquares: Int64) {
        self.tickSquares = tickSquares
    }

    public static func fromDimensions(width: Length, height: Length) -> Area2 {
        Area2(tickSquares: width.ticks * height.ticks)
    }

    /// Whole square millimeters (truncates toward zero).
    public var squareMillimeters: Int64 {
        let scale = Length.ticksPerMillimeter * Length.ticksPerMillimeter
        return tickSquares / scale
    }
}

/// Closed 2D polygon. First vertex is not repeated at the end.
public struct ClosedPolygon2: Hashable, Sendable {
    public var vertices: [Point2]

    public init(vertices: [Point2]) {
        self.vertices = vertices
    }

    public var isClosed: Bool {
        vertices.count >= 3
    }
}

public enum GeometryError: Error, Sendable, Equatable {
    case zeroLengthWall(WallID)
    case wallNotAxisAligned(WallID)
    case openWallLoop
    case disjointWallLoop
}
