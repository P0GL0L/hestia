import Foundation

/// Angle in micro-degrees (1° = 1_000_000 micro-degrees).
public struct Angle: Hashable, Codable, Sendable, Comparable {
    public var microDegrees: Int64

    public init(microDegrees: Int64) {
        self.microDegrees = microDegrees
    }

    public static let microDegreesPerDegree: Int64 = 1_000_000

    public static func degrees(_ degrees: Int64) -> Angle {
        Angle(microDegrees: degrees * microDegreesPerDegree)
    }

    public static func < (lhs: Angle, rhs: Angle) -> Bool {
        lhs.microDegrees < rhs.microDegrees
    }
}
