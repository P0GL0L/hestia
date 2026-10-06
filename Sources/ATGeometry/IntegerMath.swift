import Foundation

enum IntegerMath {
    static func squared(_ value: Int64) -> Int64 {
        value * value
    }

    static func hypotTicks(dx: Int64, dy: Int64) -> Int64 {
        integerSqrt(squared(dx) + squared(dy))
    }

    static func integerSqrt(_ value: Int64) -> Int64 {
        guard value > 0 else { return 0 }
        var x = value
        var y = (x + 1) / 2
        while y < x {
            x = y
            y = (x + value / x) / 2
        }
        return x
    }

    static func lineIntersection(
        horizontalY: Int64,
        verticalX: Int64
    ) -> (x: Int64, y: Int64) {
        (verticalX, horizontalY)
    }

    /// Returns true if segments (a1,a2) and (b1,b2) properly intersect in 2D (integer ticks).
    static func segmentsIntersect(
        a1x: Int64, a1y: Int64, a2x: Int64, a2y: Int64,
        b1x: Int64, b1y: Int64, b2x: Int64, b2y: Int64
    ) -> Bool {
        func orient(_ ax: Int64, _ ay: Int64, _ bx: Int64, _ by: Int64, _ cx: Int64, _ cy: Int64) -> Int64 {
            (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
        }
        let o1 = orient(a1x, a1y, a2x, a2y, b1x, b1y)
        let o2 = orient(a1x, a1y, a2x, a2y, b2x, b2y)
        let o3 = orient(b1x, b1y, b2x, b2y, a1x, a1y)
        let o4 = orient(b1x, b1y, b2x, b2y, a2x, a2y)
        if o1 == 0, o2 == 0, o3 == 0, o4 == 0 {
            return false
        }
        return (o1 > 0) != (o2 > 0) && (o3 > 0) != (o4 > 0)
    }
}
