import ATContracts
import Foundation

/// A dimension whose figure is wider than its own span, as on a short step in a chain, would print its figure
/// over its ticks and the next dimension's. As a drafter does, the figure moves: out a line from the chain, or
/// past the end of the span, wherever it is clear; the dimension's lines stay where they are.
enum DimensionText {
    static func fit(_ items: [DisplayItem], scale: DrawingScale?) -> [DisplayItem] {
        let height = Length.millimeters(2)
        var crowded: [Int] = []
        do {
            let space = LabelSpace(items, scale: scale, padding: 0)
            for (index, item) in items.enumerated() {
                guard case let .dimension(from, to, offset, override) = item.primitive else { continue }
                let parts = DrawingAudit.dimensionParts(from: from, to: to, offset: offset, override: override,
                                                        scale: scale)
                let box = parts.label.box
                // Its figure against every stroke on the view, its own included.
                if space.strokes.contains(where: { DrawingAudit.crosses($0.a, $0.b, box) }) { crowded.append(index) }
            }
        }
        guard !crowded.isEmpty else { return items }
        var result = items
        var moved: [(index: Int, string: String, place: (position: Point2, rotation: Angle), item: DisplayItem)] = []
        for index in crowded {
            guard case let .dimension(from, to, offset, override) = items[index].primitive else { continue }
            let string = override ?? SheetPDF.measuredLabel(
                paperTicks: Int64(hypot(Double(to.x.ticks - from.x.ticks), Double(to.y.ticks - from.y.ticks))
                    .rounded()), scale: scale)
            result[index].primitive = .dimension(from: from, to: to, offset: offset, override: "")
            moved.append((index, string, SheetPDF.labelPlacement(from: from, to: to, offset: offset, height: height),
                          items[index]))
        }
        var space = LabelSpace(result, scale: scale)
        var added: [DisplayItem] = []
        for entry in moved {
            guard case let .dimension(from, to, _, _) = entry.item.primitive else { continue }
            let (x0, y0) = (Double(from.x.ticks), Double(from.y.ticks))
            let (x1, y1) = (Double(to.x.ticks), Double(to.y.ticks))
            let length = max(hypot(x1 - x0, y1 - y0), 1)
            let angle = Double(entry.place.rotation.microDegrees) / 1_000_000 * .pi / 180
            let (ux, uy) = (cos(angle), sin(angle)), (upX, upY) = (-sin(angle), cos(angle))
            let size = Double(height.ticks) / 0.718
            let width = HelveticaMetrics.width(of: entry.string) * size
            let gap = Double(mmTicks(1))
            let (px, py) = (Double(entry.place.position.x.ticks), Double(entry.place.position.y.ticks))
            // Which way is out from the chain: the side the figure already sits on.
            let (mx, my) = ((x0 + x1) / 2, (y0 + y1) / 2)
            let outward: Double = (px - mx) * upX + (py - my) * upY >= 0 ? 1 : -1
            let step = Double(height.ticks) + gap * 1.5
            let beyond = length / 2 + width / 2 + gap * 2
            let offsets: [(Double, Double)] = [
                (beyond, 0), (-beyond, 0), (0, step * outward), (beyond, step * outward), (-beyond, step * outward),
                (0, 2 * step * outward), (beyond * 1.6, 0), (-beyond * 1.6, 0),
            ]
            let candidates = offsets.map { along, across -> [DisplayItem] in
                let x = px + ux * along + upX * across, y = py + uy * along + upY * across
                return [DisplayItem(.text(position: paperPoint(Int64(x.rounded()), Int64(y.rounded())),
                                          string: entry.string, height: height, rotation: entry.place.rotation,
                                          alignment: .center),
                                    style: entry.item.style, elementID: entry.item.elementID)]
            }
            added += space.place(candidates, required: true)
        }
        return result + added
    }
}
