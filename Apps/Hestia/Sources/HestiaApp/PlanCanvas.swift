import ATContracts
import SwiftUI

/// The floor plan as the drawing set draws it: walls with their hatch, door swings, glazing, stairs, floor
/// openings, and room tags, fitted to the view. Items are in model space, so they stay put when an edit moves
/// the plan on its sheet, and `bounds` is the model area the view fits, which the caller holds steady while
/// drawing; `zoom` and `pan` move the view over it. With no items, that area is outlined so there is somewhere
/// to click. Terrain from `overlay` draws under the plan and furniture over it; `preview` and `labels` show
/// what the current tool is about to add. `pendingStart`, a model point, is marked while a tool waits for its
/// second point, and walls whose IDs are in `selected` are outlined in orange. `penScale` is the plan's scale
/// ratio, so pens keep their printed widths. Pointer, scroll, and key input goes to `onInput` with the fit it
/// was made in.
struct PlanCanvas: View {
    var items: [DisplayItem]
    var bounds: (min: Point2, max: Point2)?
    var pendingStart: Point2?
    var selected: Set<UUID> = []
    var penScale: Double = 1
    var overlay = PlanOverlay()
    var preview: [PlanOverlay.Shape] = []
    var labels: [PlanOverlay.Label] = []
    var zoom: Double = 1
    var pan: CGSize = .zero
    var onInput: @MainActor (PlanInput, PlanFit) -> Void

    var body: some View {
        GeometryReader { proxy in
            let fit = bounds.map { PlanFit(bounds: $0, size: proxy.size, zoom: zoom, pan: pan) }
            Canvas { context, _ in
                guard let fit, let bounds else { return }
                if items.isEmpty {
                    // Paper y runs up and the view's down, so the paper maximum is the view's top.
                    let low: CGPoint = fit.point(bounds.min)
                    let high: CGPoint = fit.point(bounds.max)
                    let area = CGRect(x: low.x, y: high.y, width: high.x - low.x, height: low.y - high.y)
                    let outline = StrokeStyle(lineWidth: 1, dash: [4, 4])
                    context.stroke(Path(area), with: .color(Color(white: 0.8)), style: outline)
                }
                for shape in overlay.under {
                    paint(shape, in: &context, fit: fit)
                }
                for item in items {
                    draw(item, in: &context, fit: fit)
                }
                for shape in overlay.over {
                    paint(shape, in: &context, fit: fit)
                }
                for item in items where item.style.layer == "A-WALL" {
                    guard let id = item.elementID, selected.contains(id),
                          case let .polyline(points, closed) = item.primitive else { continue }
                    let outline = polyline(points, closed: closed, fit: fit)
                    context.stroke(outline, with: .color(.orange), lineWidth: 3)
                }
                for shape in preview {
                    paint(shape, in: &context, fit: fit)
                }
                for label in overlay.labels + labels {
                    write(label, in: &context, fit: fit)
                }
                if let start = pendingStart {
                    let p = fit.point(start)
                    let mark = Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                    context.stroke(mark, with: .color(.orange), lineWidth: 2)
                }
            }
            .overlay(PlanMouse { input in
                if let fit { onInput(input, fit) }
            })
        }
    }

    private func paint(_ shape: PlanOverlay.Shape, in context: inout GraphicsContext, fit: PlanFit) {
        let path = polyline(shape.points, closed: shape.closed, fit: fit)
        switch shape.paint {
        case let .fill(look, opacity):
            let rgb = look.rgb
            context.fill(path, with: .color(Color(red: rgb.red, green: rgb.green, blue: rgb.blue).opacity(opacity)))
        case let .stroke(red, green, blue, width, dashed):
            let style = dashed ? StrokeStyle(lineWidth: width, dash: [5, 4]) : StrokeStyle(lineWidth: width)
            context.stroke(path, with: .color(Color(red: red, green: green, blue: blue)), style: style)
        }
    }

    /// A label centered on its point; a highlighted one on a white tag, for the length being drawn.
    private func write(_ label: PlanOverlay.Label, in context: inout GraphicsContext, fit: PlanFit) {
        let color = label.highlighted ? Color(red: 0.75, green: 0.3, blue: 0) : Color(white: 0.25)
        let text = context.resolve(Text(label.text).font(.system(size: label.size, weight: label.highlighted ? .semibold
            : .regular)).foregroundColor(color))
        let point = fit.point(label.position)
        if label.highlighted {
            let size = text.measure(in: CGSize(width: 400, height: 60))
            let tag = CGRect(x: point.x - size.width / 2 - 4, y: point.y - size.height / 2 - 2,
                             width: size.width + 8, height: size.height + 4)
            context.fill(Path(roundedRect: tag, cornerRadius: 4), with: .color(Color.white.opacity(0.92)))
            context.stroke(Path(roundedRect: tag, cornerRadius: 4), with: .color(color), lineWidth: 1)
        }
        context.draw(text, at: point, anchor: .center)
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
        let width = max(fit.points(pen) * penScale, 0.5)
        switch style.pattern {
        case .solid: return StrokeStyle(lineWidth: width)
        case .dashed: return StrokeStyle(lineWidth: width, dash: [6, 3])
        case .hidden: return StrokeStyle(lineWidth: width, dash: [3, 2])
        case .center: return StrokeStyle(lineWidth: width, dash: [10, 3, 2, 3])
        }
    }
}
