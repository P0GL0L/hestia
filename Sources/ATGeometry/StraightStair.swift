import ATContracts
import Foundation

public enum StraightStairError: Error, Sendable, Equatable {
    case invalidRiserCount
    case runExceedsOpeningLength
}

/// Straight stair between two storeys: equal risers and treads along one axis.
public struct StraightStair: Hashable, Sendable {
    public var riserRise: Length
    public var treadRun: Length
    public var riserCount: Int

    public init(riserRise: Length, treadRun: Length, riserCount: Int) {
        self.riserRise = riserRise
        self.treadRun = treadRun
        self.riserCount = riserCount
    }

    /// Horizontal plan length covered by treads (one fewer tread than risers).
    public var totalPlanRun: Length {
        guard riserCount > 0 else { return Length(ticks: 0) }
        return Length(ticks: treadRun.ticks * Int64(riserCount - 1))
    }

    public var totalRise: Length {
        Length(ticks: riserRise.ticks * Int64(riserCount))
    }

    public func validate(openingLength: Length) throws {
        guard riserCount >= 2 else {
            throw StraightStairError.invalidRiserCount
        }
        if totalPlanRun.ticks > openingLength.ticks {
            throw StraightStairError.runExceedsOpeningLength
        }
    }
}

public struct StraightStairSlabCut: Sendable {
    public init() {}

    /// Rectangular opening cut in the slab above, aligned to the stair run.
    public func opening(
        for stair: StraightStair,
        origin: Point2,
        cutWidth: Length,
        runsAlongX: Bool,
        openingLengthLimit: Length
    ) throws -> AxisAlignedRectangle2 {
        try stair.validate(openingLength: openingLengthLimit)
        let run = stair.totalPlanRun.ticks
        let width = cutWidth.ticks
        let ox = origin.x.ticks
        let oy = origin.y.ticks
        if runsAlongX {
            return AxisAlignedRectangle2(
                minX: Length(ticks: ox),
                minY: Length(ticks: oy),
                maxX: Length(ticks: ox + run),
                maxY: Length(ticks: oy + width)
            )
        }
        return AxisAlignedRectangle2(
            minX: Length(ticks: ox),
            minY: Length(ticks: oy),
            maxX: Length(ticks: ox + width),
            maxY: Length(ticks: oy + run)
        )
    }
}
