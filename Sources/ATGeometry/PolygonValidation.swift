import ATContracts
import Foundation

public enum PolygonValidation {
    public static func hasSelfIntersection(_ polygon: ClosedPolygon2) -> Bool {
        let vertices = polygon.vertices
        let count = vertices.count
        guard count >= 3 else { return false }

        func ticks(_ point: Point2) -> (Int64, Int64) {
            (point.x.ticks, point.y.ticks)
        }

        for i in 0 ..< count {
            let iNext = (i + 1) % count
            let (a1x, a1y) = ticks(vertices[i])
            let (a2x, a2y) = ticks(vertices[iNext])
            for j in i + 1 ..< count {
                let jNext = (j + 1) % count
                if i == j || iNext == j || i == jNext { continue }
                let (b1x, b1y) = ticks(vertices[j])
                let (b2x, b2y) = ticks(vertices[jNext])
                if IntegerMath.segmentsIntersect(
                    a1x: a1x, a1y: a1y, a2x: a2x, a2y: a2y,
                    b1x: b1x, b1y: b1y, b2x: b2x, b2y: b2y
                ) {
                    return true
                }
            }
        }
        return false
    }
}
