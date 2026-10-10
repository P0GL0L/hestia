import ATContracts
import Foundation

/// How the plan view fits the sheet's paper space into the view: centered, y up, with a margin, then zoomed by
/// `zoom` and shifted by `pan` view points. It maps both ways, so a click on the view can be taken back to the
/// paper point under it.
struct PlanFit: Equatable {
    var minX: Double
    var minY: Double
    var scale: Double
    var originX: Double
    var originY: Double
    var height: Double
    var width: Double

    /// The view's size.
    var size: CGSize { CGSize(width: width, height: height) }

    init(bounds: (min: Point2, max: Point2), size: CGSize, zoom: Double = 1, pan: CGSize = .zero) {
        minX = Double(bounds.min.x.ticks)
        minY = Double(bounds.min.y.ticks)
        let width = max(Double(bounds.max.x.ticks) - minX, 1)
        let depth = max(Double(bounds.max.y.ticks) - minY, 1)
        scale = min(Double(size.width) / width, Double(size.height) / depth) * 0.9 * zoom
        originX = (Double(size.width) - width * scale) / 2 + Double(pan.width)
        originY = (Double(size.height) - depth * scale) / 2 - Double(pan.height)
        height = Double(size.height)
        self.width = Double(size.width)
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

    /// The pan that keeps `paper` under the view point `location` once the view is zoomed to `zoom`.
    static func pan(keeping paper: Point2, at location: CGPoint, bounds: (min: Point2, max: Point2), size: CGSize,
                    zoom: Double) -> CGSize {
        let unpanned = PlanFit(bounds: bounds, size: size, zoom: zoom).point(paper)
        return CGSize(width: location.x - unpanned.x, height: location.y - unpanned.y)
    }

    /// A paper length in view points.
    func points(_ length: Length) -> Double { Double(length.ticks) * scale }
}
