import ATContracts
import SwiftUI

/// The floor plan as the drawing set draws it: walls with their hatch, door swings, glazing, stairs, floor
/// openings, and room tags, fitted to the view. Items are in sheet paper space.
struct PlanCanvas: View {
    var items: [DisplayItem]

    var body: some View {
        Canvas { context, size in
            guard let bounds = DisplayList(items: items).bounds else { return }
            let fit = Fit(bounds: bounds, size: size)
            for item in items {
                draw(item, in: &context, fit: fit)
            }
        }
    }

    /// Paper space to view points: centered, y up, with a margin.
    struct Fit {
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

        func point(_ p: Point2) -> CGPoint {
            point(Double(p.x.ticks), Double(p.y.ticks))
        }

        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: originX + (x - minX) * scale, y: height - (originY + (y - minY) * scale))
        }

        func points(_ length: Length) -> Double { Double(length.ticks) * scale }
    }

    private func draw(_ item: DisplayItem, in context: inout GraphicsContext, fit: Fit) {
        let style = stroke(item.style, fit: fit)
        switch item.primitive {
        case let .line(start, end):
            var path = Path()
            path.move(to: fit.point(start))
            path.addLine(to: fit.point(end))
            context.stroke(path, with: .color(.black), style: style)
        case let .polyline(points, closed):
            context.stroke(polyline(points, closed: closed, fit: fit), with: .color(.black), style: style)
        case let .arc(center, radius, start, sweep):
            var path = Path()
            let steps = 32
            for step in 0...steps {
                let degrees = Double(start.microDegrees + sweep.microDegrees * Int64(step) / Int64(steps)) / 1_000_000
                let radians = degrees * .pi / 180
                let x = Double(center.x.ticks) + Double(radius.ticks) * cos(radians)
                let y = Double(center.y.ticks) + Double(radius.ticks) * sin(radians)
                if step == 0 { path.move(to: fit.point(x, y)) } else { path.addLine(to: fit.point(x, y)) }
            }
            context.stroke(path, with: .color(.black), style: style)
        case let .hatch(boundary, _, _, _):
            // A light fill reads better on screen than the hatch lines themselves.
            context.fill(polyline(boundary, closed: true, fit: fit), with: .color(Color(white: 0.82)))
        case let .text(position, string, height, rotation, alignment):
            // Height is cap height; Helvetica's cap height is 0.718 of its size.
            let size = max(fit.points(height) / 0.718, 6)
            let anchor: UnitPoint
            switch alignment {
            case .left: anchor = .bottomLeading
            case .center: anchor = .bottom
            case .right: anchor = .bottomTrailing
            }
            var copy = context
            copy.translateBy(x: fit.point(position).x, y: fit.point(position).y)
            copy.rotate(by: .degrees(-Double(rotation.microDegrees) / 1_000_000))
            copy.draw(Text(string).font(.system(size: size)), at: .zero, anchor: anchor)
        case .dimension, .symbol:
            break
        }
    }

    private func polyline(_ points: [Point2], closed: Bool, fit: Fit) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: fit.point(first))
        for point in points.dropFirst() { path.addLine(to: fit.point(point)) }
        if closed { path.closeSubpath() }
        return path
    }

    /// The pen's printed width, at the view's scale, never thinner than half a point.
    private func stroke(_ style: DisplayStyle, fit: Fit) -> StrokeStyle {
        let pen = Length(ticks: Int64(style.pen.rawValue) * Length.ticksPerMillimeter / 100)
        let width = max(fit.points(pen), 0.5)
        switch style.pattern {
        case .solid: return StrokeStyle(lineWidth: width)
        case .dashed: return StrokeStyle(lineWidth: width, dash: [6, 3])
        case .hidden: return StrokeStyle(lineWidth: width, dash: [3, 2])
        case .center: return StrokeStyle(lineWidth: width, dash: [10, 3, 2, 3])
        }
    }
}
