import ATContracts
import SwiftUI

/// The floor plan as the drawing set draws it: walls with their hatch, door swings, glazing, stairs, floor
/// openings, and room tags, fitted to the view. Items are in sheet paper space. A click reports the paper point
/// under it; `pendingStart`, a paper point, is marked while a wall waits for its end.
struct PlanCanvas: View {
    var items: [DisplayItem]
    var pendingStart: Point2?
    var onClick: (Point2) -> Void

    var body: some View {
        GeometryReader { proxy in
            let fit = DisplayList(items: items).bounds.map { PlanFit(bounds: $0, size: proxy.size) }
            Canvas { context, _ in
                guard let fit else { return }
                for item in items {
                    draw(item, in: &context, fit: fit)
                }
                if let start = pendingStart {
                    let p = fit.point(start)
                    let mark = Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                    context.stroke(mark, with: .color(.orange), lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            // A press and release without moving: the package's macOS target has DragGesture, not located taps.
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).onEnded { value in
                guard let fit else { return }
                onClick(fit.paper(value.location))
            })
        }
    }

    private func draw(_ item: DisplayItem, in context: inout GraphicsContext, fit: PlanFit) {
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

    private func polyline(_ points: [Point2], closed: Bool, fit: PlanFit) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: fit.point(first))
        for point in points.dropFirst() { path.addLine(to: fit.point(point)) }
        if closed { path.closeSubpath() }
        return path
    }

    /// The pen's printed width, at the view's scale, never thinner than half a point.
    private func stroke(_ style: DisplayStyle, fit: PlanFit) -> StrokeStyle {
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
