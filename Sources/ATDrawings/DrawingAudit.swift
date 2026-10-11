import ATContracts
import Foundation

/// Checks a drawn sheet the way a checker reads a blueprint: every piece of text must stand clear of the drawing
/// and of other text. Each label's box is measured exactly as the PDF sets it (Helvetica's widths, the cap height
/// the drawing asks for, its alignment and turn), and any line, arc, or dimension that crosses it, any hatched
/// area or symbol it lies over (a symbol fills its disk), or another label's box that overlaps it, is a finding.
///
/// Placement uses the same geometry (see `LabelSpace`), so labels can look for room before they are drawn.
enum DrawingAudit {
    /// A label's box on paper, in ticks: its four corners, counterclockwise.
    struct Box {
        var corners: [(x: Double, y: Double)]

        var minX: Double { corners.map(\.x).min() ?? 0 }
        var maxX: Double { corners.map(\.x).max() ?? 0 }
        var minY: Double { corners.map(\.y).min() ?? 0 }
        var maxY: Double { corners.map(\.y).max() ?? 0 }
    }

    /// One straight piece of linework, in paper ticks.
    struct Stroke {
        var a: (x: Double, y: Double)
        var b: (x: Double, y: Double)
        var layer: String
        var elementID: UUID?
    }

    struct Label {
        var string: String
        var box: Box
        var layer: String
        var elementID: UUID?
    }

    /// A hatched area, or the disk a symbol fills, as its boundary on paper.
    struct Area {
        var boundary: [(x: Double, y: Double)]
        var layer: String
        var isSymbol = false
    }

    struct Finding: CustomStringConvertible, Equatable {
        var label: String
        var layer: String
        /// What it runs into: another label's text, or a layer's linework or hatch.
        var other: String

        var description: String { "\"\(label)\" (\(layer)) runs into \(other)" }
    }

    /// How far inside its true outline a box is tested: none, so text touching a line is a finding.
    static let slack = 0.0

    // MARK: - Geometry of what is drawn

    /// The box `string` fills when set at `position` with `height` cap height, turned by `rotation`, aligned as
    /// given, exactly as SheetPDF sets it.
    static func box(_ string: String, at position: Point2, height: Length, rotation: Angle,
                    alignment: TextAlignment) -> Box {
        let size = Double(height.ticks) / 0.718
        let width = HelveticaMetrics.width(of: string) * size
        let shift = alignment == .left ? 0 : (alignment == .center ? width / 2 : width)
        let descends = string.contains { "gjpqy,;()[]{}".contains($0) }
        let bottom = descends ? -0.21 * size : -0.02 * size
        let top = Double(height.ticks) * 1.02
        let angle = Double(rotation.microDegrees) / 1_000_000 * .pi / 180
        let (c, s) = (cos(angle), sin(angle))
        let (x, y) = (Double(position.x.ticks), Double(position.y.ticks))
        let local = [(-shift, bottom), (width - shift, bottom), (width - shift, top), (-shift, top)]
        return Box(corners: local.map { (x + $0.0 * c - $0.1 * s, y + $0.0 * s + $0.1 * c) })
    }

    /// The labels, linework, and hatched areas of a display list, dimensions and symbols taken apart as the PDF
    /// draws them.
    static func parts(_ items: [DisplayItem], scale: DrawingScale?)
        -> (labels: [Label], strokes: [Stroke], areas: [Area]) {
        var labels: [Label] = [], strokes: [Stroke] = [], areas: [Area] = []
        func xy(_ p: Point2) -> (x: Double, y: Double) { (Double(p.x.ticks), Double(p.y.ticks)) }
        for item in items {
            let layer = item.style.layer, id = item.elementID
            func stroke(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) {
                strokes.append(Stroke(a: a, b: b, layer: layer, elementID: id))
            }
            switch item.primitive {
            case let .line(start, end):
                stroke(xy(start), xy(end))
            case let .polyline(points, closed):
                for (a, b) in zip(points, points.dropFirst()) { stroke(xy(a), xy(b)) }
                if closed, let first = points.first, let last = points.last { stroke(xy(last), xy(first)) }
            case let .arc(center, radius, start, sweep):
                let (cx, cy) = xy(center), r = Double(radius.ticks)
                let a0 = Double(start.microDegrees) / 1_000_000 * .pi / 180
                let total = Double(sweep.microDegrees) / 1_000_000 * .pi / 180
                let steps = max(Int(abs(total) / (.pi / 16)), 1)
                var previous = (cx + r * cos(a0), cy + r * sin(a0))
                for step in 1...steps {
                    let t = a0 + total * Double(step) / Double(steps)
                    let next = (cx + r * cos(t), cy + r * sin(t))
                    stroke(previous, next)
                    previous = next
                }
            case let .text(position, string, height, rotation, alignment):
                labels.append(Label(string: string, box: box(string, at: position, height: height,
                                                              rotation: rotation, alignment: alignment),
                                    layer: layer, elementID: id))
            case let .hatch(boundary, _, _, _):
                areas.append(Area(boundary: boundary.map(xy), layer: layer))
            case let .dimension(from, to, offset, override):
                let parts = dimensionParts(from: from, to: to, offset: offset, override: override, scale: scale)
                for (a, b) in parts.strokes { stroke(a, b) }
                labels.append(Label(string: parts.label.string, box: parts.label.box, layer: layer, elementID: id))
            case let .symbol(_, position, _, size):
                // The symbol's disk stands for all of it: text crossing its ring or sitting inside it is over it.
                let (cx, cy) = xy(position), r = Double(size.ticks) / 2
                var ring: [(x: Double, y: Double)] = []
                for step in 0..<16 {
                    let t = Double(step) / 16 * 2 * .pi
                    ring.append((cx + r * cos(t), cy + r * sin(t)))
                }
                for (index, point) in ring.enumerated() { stroke(point, ring[(index + 1) % ring.count]) }
                areas.append(Area(boundary: ring, layer: layer, isSymbol: true))
            }
        }
        return (labels, strokes, areas)
    }

    /// A dimension's strokes and label, placed exactly as SheetPDF draws them.
    static func dimensionParts(from: Point2, to: Point2, offset: Length, override: String?, scale: DrawingScale?)
        -> (strokes: [((x: Double, y: Double), (x: Double, y: Double))], label: (string: String, box: Box)) {
        let (x0, y0) = (Double(from.x.ticks), Double(from.y.ticks))
        let (x1, y1) = (Double(to.x.ticks), Double(to.y.ticks))
        let length = max(hypot(x1 - x0, y1 - y0), 1)
        let (ux, uy) = ((x1 - x0) / length, (y1 - y0) / length)
        let (nx, ny) = (-uy, ux)
        let off = Double(offset.ticks)
        let gap = 1.5 * Double(Length.ticksPerMillimeter), tick = gap
        let sign: Double = off >= 0 ? 1 : -1
        var strokes: [((x: Double, y: Double), (x: Double, y: Double))] = []
        for (bx, by) in [(x0, y0), (x1, y1)] {
            strokes.append(((bx + nx * gap * sign, by + ny * gap * sign),
                            (bx + nx * (off + tick * sign), by + ny * (off + tick * sign))))
            let (dx, dy) = (bx + nx * off, by + ny * off)
            strokes.append(((dx - (ux + nx) * tick / 2, dy - (uy + ny) * tick / 2),
                            (dx + (ux + nx) * tick / 2, dy + (uy + ny) * tick / 2)))
        }
        strokes.append(((x0 + nx * off, y0 + ny * off), (x1 + nx * off, y1 + ny * off)))
        let string = override ?? SheetPDF.measuredLabel(paperTicks: Int64(length.rounded()), scale: scale)
        let height = Length.millimeters(2)
        let place = SheetPDF.labelPlacement(from: from, to: to, offset: offset, height: height)
        return (strokes, (string, box(string, at: place.position, height: height, rotation: place.rotation,
                                       alignment: .center)))
    }

    // MARK: - Tests

    /// The box pulled in by `by` on every side.
    static func inset(_ box: Box, by: Double) -> Box {
        let cx = box.corners.map(\.x).reduce(0, +) / 4, cy = box.corners.map(\.y).reduce(0, +) / 4
        // The box's own axes, from its first two corners and its last.
        let (a, b, d) = (box.corners[0], box.corners[1], box.corners[3])
        let lu = max(hypot(b.x - a.x, b.y - a.y), 1e-9), lv = max(hypot(d.x - a.x, d.y - a.y), 1e-9)
        let u = ((b.x - a.x) / lu, (b.y - a.y) / lu), v = ((d.x - a.x) / lv, (d.y - a.y) / lv)
        let hu = max(lu / 2 - by, 0), hv = max(lv / 2 - by, 0)
        let signs: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        var corners: [(x: Double, y: Double)] = []
        for (su, sv) in signs {
            let x: Double = cx + u.0 * hu * su + v.0 * hv * sv
            let y: Double = cy + u.1 * hu * su + v.1 * hv * sv
            corners.append((x, y))
        }
        return Box(corners: corners)
    }

    /// Whether a segment crosses or lies inside a box.
    static func crosses(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double), _ box: Box) -> Bool {
        clip(a, b, box) != nil
    }

    /// The stretch of a segment inside a box, as shares from `a` to `b`; nil when it misses.
    static func clip(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double), _ box: Box) -> (Double, Double)? {
        // In the box's own frame the box is [0, lu] × [0, lv]; clip the segment to it (Liang–Barsky).
        let o = box.corners[0], p = box.corners[1], q = box.corners[3]
        let lu = hypot(p.x - o.x, p.y - o.y), lv = hypot(q.x - o.x, q.y - o.y)
        guard lu > 0, lv > 0 else { return nil }
        let u = ((p.x - o.x) / lu, (p.y - o.y) / lu), v = ((q.x - o.x) / lv, (q.y - o.y) / lv)
        func local(_ point: (x: Double, y: Double)) -> (Double, Double) {
            let (dx, dy) = (point.x - o.x, point.y - o.y)
            return (dx * u.0 + dy * u.1, dx * v.0 + dy * v.1)
        }
        let (s, e) = (local(a), local(b))
        var (t0, t1) = (0.0, 1.0)
        let delta = (e.0 - s.0, e.1 - s.1)
        for (pp, qq) in [(-delta.0, s.0), (delta.0, lu - s.0), (-delta.1, s.1), (delta.1, lv - s.1)] {
            if pp == 0 {
                if qq < 0 { return nil }
            } else {
                let r = qq / pp
                if pp < 0 { t0 = max(t0, r) } else { t1 = min(t1, r) }
                if t0 > t1 { return nil }
            }
        }
        return (t0, t1)
    }

    /// Whether two boxes overlap (separating axes).
    static func overlaps(_ first: Box, _ second: Box) -> Bool {
        for box in [first, second] {
            for index in 0..<2 {
                let a = box.corners[index], b = box.corners[index + 1]
                let axis = (-(b.y - a.y), b.x - a.x)
                let p1 = first.corners.map { $0.x * axis.0 + $0.y * axis.1 }
                let p2 = second.corners.map { $0.x * axis.0 + $0.y * axis.1 }
                if p1.max()! <= p2.min()! || p2.max()! <= p1.min()! { return false }
            }
        }
        return true
    }

    /// Whether a box lies over a hatched area: any corner or its middle inside it, or its edges crossing it.
    static func over(_ box: Box, _ area: Area) -> Bool {
        let xs = area.boundary.map(\.x), ys = area.boundary.map(\.y)
        guard xs.count >= 3 else { return false }
        let cx = box.corners.map(\.x).reduce(0, +) / 4, cy = box.corners.map(\.y).reduce(0, +) / 4
        let probes = box.corners + [(cx, cy)]
        if probes.contains(where: { RasterOutline.inside($0.x, $0.y, xs, ys) }) { return true }
        for index in area.boundary.indices {
            let a = area.boundary[index], b = area.boundary[(index + 1) % area.boundary.count]
            if crosses(a, b, box) { return true }
        }
        return false
    }

    // MARK: - Findings

    /// Every label on the sheet that runs into the drawing or another label.
    static func findings(_ sheet: SheetDrawing) -> [Finding] {
        findings(sheet.content.items, scale: sheet.scale)
    }

    static func findings(_ items: [DisplayItem], scale: DrawingScale?) -> [Finding] {
        let (labels, strokes, areas) = parts(items, scale: scale)
        var result: [Finding] = []
        for (index, label) in labels.enumerated() {
            let box = inset(label.box, by: slack)
            if let hit = strokes.first(where: { crosses($0.a, $0.b, box) }) {
                result.append(Finding(label: label.string, layer: label.layer, other: "\(hit.layer) linework"))
            }
            if let hit = areas.first(where: { over(box, $0) }) {
                result.append(Finding(label: label.string, layer: label.layer,
                                      other: "\(hit.layer) " + (hit.isSymbol ? "symbol" : "hatch")))
            }
            for other in labels[(index + 1)...] where overlaps(box, inset(other.box, by: slack)) {
                result.append(Finding(label: label.string, layer: label.layer, other: "\"\(other.string)\""))
            }
        }
        return result
    }
}
