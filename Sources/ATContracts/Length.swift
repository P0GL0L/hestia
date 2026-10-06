import Foundation

/// Length in 1/320 mm ticks. 1 mm = 320 ticks; 1/64 inch = 127 ticks.
public struct Length: Hashable, Codable, Sendable, Comparable {
    public var ticks: Int64

    public init(ticks: Int64) {
        self.ticks = ticks
    }

    public static let ticksPerMillimeter: Int64 = 320
    public static let ticksPerSixtyFourthInch: Int64 = 127

    public static func millimeters(_ mm: Int64) -> Length {
        Length(ticks: mm * ticksPerMillimeter)
    }

    public static func sixtyFourthInches(_ count: Int64) -> Length {
        Length(ticks: count * ticksPerSixtyFourthInch)
    }

    public static func inches(_ whole: Int64) -> Length {
        sixtyFourthInches(whole * 64)
    }

    public static func feet(_ footCount: Int64, inchCount: Int64 = 0) -> Length {
        Length.inches(footCount * 12 + inchCount)
    }

    public static func < (lhs: Length, rhs: Length) -> Bool {
        lhs.ticks < rhs.ticks
    }
}
