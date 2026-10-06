import ATContracts
import Foundation

/// Drawing units for schematic DXF export ($INSUNITS).
public enum DXFDrawingUnits: Sendable, Hashable {
    /// AutoCAD $INSUNITS = 1
    case inches
    /// AutoCAD $INSUNITS = 4
    case millimeters

    public var insunitsCode: Int {
        switch self {
        case .inches: return 1
        case .millimeters: return 4
        }
    }

    /// Convert Hestia length ticks to drawing-unit coordinates (true scale).
    public func coordinate(from length: Length) -> Double {
        switch self {
        case .inches:
            let ticksPerInch = Length.ticksPerSixtyFourthInch * 64
            return Double(length.ticks) / Double(ticksPerInch)
        case .millimeters:
            return Double(length.ticks) / Double(Length.ticksPerMillimeter)
        }
    }

    /// Convert drawing-unit coordinates back to Hestia length ticks.
    public func length(from coordinate: Double) -> Length {
        switch self {
        case .inches:
            let ticksPerInch = Length.ticksPerSixtyFourthInch * 64
            let ticks = (coordinate * Double(ticksPerInch)).rounded()
            return Length(ticks: Int64(ticks))
        case .millimeters:
            let ticks = (coordinate * Double(Length.ticksPerMillimeter)).rounded()
            return Length(ticks: Int64(ticks))
        }
    }
}
