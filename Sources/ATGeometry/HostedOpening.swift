import ATContracts
import Foundation

public enum HostedOpeningValidationError: Error, Sendable, Equatable {
    case extendsPastWallStart
    case extendsPastWallEnd
    case zeroLengthWall
}

public struct HostedOpeningValidator: Sendable {
    public init() {}

    public func validate(opening: Opening, on wall: Wall) throws {
        let sx = wall.start.x.ticks
        let sy = wall.start.y.ticks
        let ex = wall.end.x.ticks
        let ey = wall.end.y.ticks
        let dx = ex - sx
        let dy = ey - sy
        let lengthTicks = IntegerMath.hypotTicks(dx: dx, dy: dy)
        if lengthTicks == 0 {
            throw HostedOpeningValidationError.zeroLengthWall
        }

        let offset = opening.offsetAlongWall.ticks
        let width = opening.width.ticks
        if offset < 0 {
            throw HostedOpeningValidationError.extendsPastWallStart
        }
        if offset + width > lengthTicks {
            throw HostedOpeningValidationError.extendsPastWallEnd
        }
    }
}

public func wallCenterlineLength(_ wall: Wall) -> Length {
    let dx = wall.end.x.ticks - wall.start.x.ticks
    let dy = wall.end.y.ticks - wall.start.y.ticks
    return Length(ticks: IntegerMath.hypotTicks(dx: dx, dy: dy))
}
