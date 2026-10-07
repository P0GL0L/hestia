import ATContracts
import Foundation

/// How the plan view fits the sheet's paper space into the view: centered, y up, with a margin. It maps both
/// ways, so a click on the view can be taken back to the paper point under it.
struct PlanFit: Equatable {
    var minX: Double
    var minY: Double
    var scale: Double
    var originX: Double
    var originY: Double
    var height: Double

    init(bounds: (min: Point2, max: Point2), size: CGSize) {
        minX = Double(bounds.min.x.ticks)
        minY = Double(bounds.min.y.ticks)
        let width = max(Double(bounds.max.x.ticks) - minX, 1)
        let depth = max(Double(bounds.max.y.ticks) - minY, 1)
        scale = min(Double(size.width) / width, Double(size.height) / depth) * 0.9
        originX = (Double(size.width) - width * scale) / 2
        originY = (Double(size.height) - depth * scale) / 2
        height = Double(size.height)
    }

    /// The view point for a paper point.
    func point(_ p: Point2) -> CGPoint {
        point(Double(p.x.ticks), Double(p.y.ticks))
    }

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: originX + (x - minX) * scale, y: height - (originY + (y - minY) * scale))
    }

    /// The paper point under a view point: the inverse of `point`, to the nearest paper tick.
    func paper(_ location: CGPoint) -> Point2 {
        let x: Double = minX + (Double(location.x) - originX) / scale
        let y: Double = minY + (height - Double(location.y) - originY) / scale
        return Point2(x: Length(ticks: Int64(x.rounded())), y: Length(ticks: Int64(y.rounded())))
    }

    /// A paper length in view points.
    func points(_ length: Length) -> Double { Double(length.ticks) * scale }
}
