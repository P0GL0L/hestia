import ATContracts
import Foundation

/// SVG writer for a model-space display list.
///
/// Line, polyline, arc, and dimension geometry passes through `scale`. Text height, hatch spacing,
/// and symbol size are already paper space and are not scaled. One user unit is one paper millimeter,
/// and pen width is `PenWeight.micrometers`. Each layer is one group whose id is the layer name.
/// Stamp text is written only when a text item already contains it.
public struct SVGWriter: Sendable {
    public var scale: DrawingScale

    public init(scale: DrawingScale) {
        self.scale = scale
    }

    public func document(_ list: DisplayList) -> String {
        var builder = SVGBuilder(scale: scale)
        builder.draw(list)
        return builder.finish()
    }
}

private struct SVGBuilder {
    var scale: DrawingScale
    private var order: [String] = []
    private var markup: [String: String] = [:]
    private var defs = ""
    private var clipCount = 0
    private var minX = 0.0
    private var minY = 0.0
    private var maxX = 0.0
    private var maxY = 0.0
    private var hasPoint = false

    mutating func draw(_ list: DisplayList) {
        for item in list.items {
            let element = draw(item.primitive, style: item.style)
            append(element, to: item.style.layer)
        }
    }

    func finish() -> String {
        var body = ""
        if !defs.isEmpty {
            body += "<defs>\n\(defs)</defs>\n"
        }
        for name in order {
            body += "<g id=\"\(escape(name))\">\n\(markup[name] ?? "")</g>\n"
        }
        let frame = viewFrame()
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <svg xmlns="http://www.w3.org/2000/svg" width="\(num(frame.width))mm" height="\(num(frame.height))mm" viewBox="\(num(frame.minX)) \(num(frame.minY)) \(num(frame.width)) \(num(frame.height))">
            \(body)</svg>
            """
    }

    private mutating func draw(_ primitive: DisplayPrimitive, style: DisplayStyle) -> String {
        switch primitive {
        case let .line(start, end):
            return line(from: model(start), to: model(end), style: style)
        case let .polyline(points, closed):
            return polyline(points.map(model), closed: closed, style: style)
        case let .arc(center, radius, start, sweep):
            return arc(center: center, radius: radius, start: start, sweep: sweep, style: style)
        case let .text(position, string, height, rotation, alignment):
            return text(string, at: model(position), height: height, rotation: rotation, alignment: alignment)
        case let .hatch(boundary, pattern, spacing, angle):
            return hatch(boundary, pattern: pattern, spacing: spacing, angle: angle, style: style)
        case let .dimension(from, to, offset, override):
            return dimension(from: from, to: to, offset: offset, override: override, style: style)
        case let .symbol(name, position, rotation, size):
            return symbol(name, at: position, rotation: rotation, size: size, style: style)
        }
    }

    private mutating func append(_ element: String, to layer: String) {
        guard !element.isEmpty else { return }
        if var existing = markup[layer] {
            existing += element
            markup[layer] = existing
        } else {
            order.append(layer)
            markup[layer] = element
        }
    }

    // MARK: Geometry

    /// Model point, in paper millimeters, still Y-up.
    private func model(_ point: Point2) -> (Double, Double) {
        (scaledMM(point.x), scaledMM(point.y))
    }

    /// Paper Y-up millimeters stored in SVG's Y-down user space.
    private func svg(_ paperX: Double, _ paperY: Double) -> (Double, Double) {
        (paperX, -paperY)
    }

    private mutating func line(
        from start: (Double, Double), to end: (Double, Double), style: DisplayStyle, clip: String? = nil
    ) -> String {
        let a = svg(start.0, start.1)
        let b = svg(end.0, end.1)
        let margin = strokeMM(style.pen) / 2
        note(a.0, a.1, margin: margin)
        note(b.0, b.1, margin: margin)
        let clipAttr = clip.map { " clip-path=\"url(#\($0))\"" } ?? ""
        return "<line x1=\"\(num(a.0))\" y1=\"\(num(a.1))\" x2=\"\(num(b.0))\" y2=\"\(num(b.1))\" \(stroke(style))\(clipAttr)/>\n"
    }

    private mutating func polyline(_ points: [(Double, Double)], closed: Bool, style: DisplayStyle) -> String {
        guard points.count >= 2 else { return "" }
        let stored = points.map { svg($0.0, $0.1) }
        let margin = strokeMM(style.pen) / 2
        for point in stored { note(point.0, point.1, margin: margin) }
        let name = closed && points.count >= 3 ? "polygon" : "polyline"
        return "<\(name) points=\"\(pointList(stored))\" \(stroke(style))/>\n"
    }

    private mutating func arc(
        center: Point2, radius: Length, start: Angle, sweep: Angle, style: DisplayStyle
    ) -> String {
        let paperRadius = scale.paper(radius)
        guard paperRadius.ticks != 0, sweep.microDegrees != 0 else { return "" }
        let c = model(center)
        let r = abs(paperMM(paperRadius))
        let a0 = radians(start)
        let delta = radians(sweep)
        let startPaper = (c.0 + r * cos(a0), c.1 + r * sin(a0))
        let endPaper = (c.0 + r * cos(a0 + delta), c.1 + r * sin(a0 + delta))
        let margin = strokeMM(style.pen) / 2
        note(svg(c.0, c.1).0, svg(c.0, c.1).1, margin: r + margin)
        if abs(sweep.microDegrees) >= 360_000_000 {
            let stored = svg(c.0, c.1)
            return "<circle cx=\"\(num(stored.0))\" cy=\"\(num(stored.1))\" r=\"\(num(r))\" \(stroke(style))/>\n"
        }
        let from = svg(startPaper.0, startPaper.1)
        let to = svg(endPaper.0, endPaper.1)
        note(from.0, from.1, margin: margin)
        note(to.0, to.1, margin: margin)
        // Positive sweep is counterclockwise in Y-up paper. Stored Y is flipped, so that arc uses sweep-flag 0.
        let large = abs(sweep.microDegrees) > 180_000_000 ? 1 : 0
        let sweepFlag = sweep.microDegrees >= 0 ? 0 : 1
        return "<path d=\"M \(num(from.0)) \(num(from.1)) A \(num(r)) \(num(r)) 0 \(large) \(sweepFlag) \(num(to.0)) \(num(to.1))\" \(stroke(style))/>\n"
    }

    private mutating func text(
        _ string: String, at paper: (Double, Double), height: Length, rotation: Angle, alignment: TextAlignment
    ) -> String {
        let stored = svg(paper.0, paper.1)
        let size = paperMM(height)
        note(stored.0, stored.1, margin: abs(size))
        let anchor: String
        switch alignment {
        case .left: anchor = "start"
        case .center: anchor = "middle"
        case .right: anchor = "end"
        }
        let degrees = -Double(rotation.microDegrees) / 1_000_000
        let transform = num(degrees) == "0"
            ? ""
            : " transform=\"rotate(\(num(degrees)) \(num(stored.0)) \(num(stored.1)))\""
        return "<text x=\"\(num(stored.0))\" y=\"\(num(stored.1))\" font-size=\"\(num(size))\" text-anchor=\"\(anchor)\" fill=\"#000000\"\(transform)>\(escape(string))</text>\n"
    }

    private mutating func hatch(
        _ boundary: [Point2], pattern: HatchPattern, spacing: Length, angle: Angle, style: DisplayStyle
    ) -> String {
        guard boundary.count >= 3 else { return "" }
        let paper = boundary.map(model)
        let stored = paper.map { svg($0.0, $0.1) }
        for point in stored { note(point.0, point.1) }
        if pattern == .solid {
            return "<polygon points=\"\(pointList(stored))\" fill=\"#000000\" stroke=\"none\"/>\n"
        }
        guard spacing.ticks > 0 else {
            return "<polygon points=\"\(pointList(stored))\" \(stroke(style))/>\n"
        }
        clipCount += 1
        let clipID = "clip-\(clipCount)"
        defs += "<clipPath id=\"\(clipID)\"><polygon points=\"\(pointList(stored))\"/></clipPath>\n"
        let xs = paper.map(\.0)
        let ys = paper.map(\.1)
        guard let loX = xs.min(), let hiX = xs.max(), let loY = ys.min(), let hiY = ys.max() else { return "" }
        let gap = paperMM(spacing)
        var step = pattern == .concrete ? gap * 2 : gap
        guard step > 0 else { return "" }
        let cx = (loX + hiX) / 2
        let cy = (loY + hiY) / 2
        var reach = ((hiX - loX) * (hiX - loX) + (hiY - loY) * (hiY - loY)).squareRoot() / 2 + step
        if reach * 2 / step > 4_000 {
            step = reach * 2 / 4_000
            reach = ((hiX - loX) * (hiX - loX) + (hiY - loY) * (hiY - loY)).squareRoot() / 2 + step
        }
        var angles = [radians(angle)]
        if pattern == .crosshatch || pattern == .earth {
            angles.append(radians(angle) + .pi / 2)
        }
        var lines = ""
        for theta in angles {
            let dx = cos(theta)
            let dy = sin(theta)
            var offset = -reach
            var count = 0
            while offset <= reach && count < 4_000 {
                let px = cx - dy * offset
                let py = cy + dx * offset
                lines += line(
                    from: (px - dx * reach, py - dy * reach),
                    to: (px + dx * reach, py + dy * reach),
                    style: style,
                    clip: clipID
                )
                offset += step
                count += 1
            }
        }
        return lines
    }

    private mutating func dimension(
        from: Point2, to: Point2, offset: Length, override: String?, style: DisplayStyle
    ) -> String {
        let start = model(from)
        let end = model(to)
        let dx = end.0 - start.0
        let dy = end.1 - start.1
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return "" }
        let ux = dx / length
        let uy = dy / length
        let nx = -uy
        let ny = ux
        let off = scaledMM(offset)
        let gap = 1.5
        let tick = 1.5
        let sign: Double = off >= 0 ? 1 : -1
        var out = ""
        for base in [start, end] {
            out += line(
                from: (base.0 + nx * gap * sign, base.1 + ny * gap * sign),
                to: (base.0 + nx * (off + tick * sign), base.1 + ny * (off + tick * sign)),
                style: style
            )
            let dimX = base.0 + nx * off
            let dimY = base.1 + ny * off
            out += line(
                from: (dimX - (ux + nx) * tick / 2, dimY - (uy + ny) * tick / 2),
                to: (dimX + (ux + nx) * tick / 2, dimY + (uy + ny) * tick / 2),
                style: style
            )
        }
        out += line(
            from: (start.0 + nx * off, start.1 + ny * off),
            to: (end.0 + nx * off, end.1 + ny * off),
            style: style
        )
        let label = override ?? measuredLabel(from: from, to: to)
        let mid = (
            (start.0 + end.0) / 2 + nx * (off + gap * sign),
            (start.1 + end.1) / 2 + ny * (off + gap * sign)
        )
        var angle = atan2(uy, ux)
        if angle > .pi / 2 + 1e-9 || angle <= -.pi / 2 { angle += .pi }
        let rotation = Angle(microDegrees: Int64((angle * 180 / .pi * 1_000_000).rounded()))
        out += text(label, at: mid, height: .millimeters(2), rotation: rotation, alignment: .center)
        return out
    }

    private func measuredLabel(from: Point2, to: Point2) -> String {
        let dx = Double(to.x.ticks - from.x.ticks)
        let dy = Double(to.y.ticks - from.y.ticks)
        let modelTicks = Int64((dx * dx + dy * dy).squareRoot().rounded())
        let imperial = scale.label.contains("\"")
        let unit = imperial ? Length.ticksPerSixtyFourthInch * 4 : Length.ticksPerMillimeter
        let rounded = ((modelTicks + unit / 2) / unit) * unit
        return LengthFormatting.format(
            Length(ticks: rounded),
            style: imperial ? .feetInchesFractions : .metric
        )
    }

    private mutating func symbol(
        _ name: String, at position: Point2, rotation: Angle, size: Length, style: DisplayStyle
    ) -> String {
        guard size.ticks > 0 else { return "" }
        let center = model(position)
        let r = paperMM(size) / 2
        let stored = svg(center.0, center.1)
        note(stored.0, stored.1, margin: r + strokeMM(style.pen) / 2)
        var out = "<circle cx=\"\(num(stored.0))\" cy=\"\(num(stored.1))\" r=\"\(num(r))\" \(stroke(style))/>\n"
        if name == "north-arrow" {
            let theta = radians(rotation) + .pi / 2
            let tip = (center.0 + r * cos(theta), center.1 + r * sin(theta))
            out += line(from: center, to: tip, style: style)
            out += text("N", at: tip, height: Length(ticks: size.ticks / 4), rotation: .degrees(0), alignment: .center)
        } else {
            let label = String(name.split(separator: "-").compactMap(\.first).prefix(2)).uppercased()
            let below = (center.0, center.1 - paperMM(size) / 6)
            out += text(
                label, at: below, height: Length(ticks: size.ticks / 3), rotation: rotation, alignment: .center
            )
        }
        return out
    }

    // MARK: Formatting

    private func stroke(_ style: DisplayStyle) -> String {
        var attributes = "fill=\"none\" stroke=\"#000000\" stroke-width=\"\(num(strokeMM(style.pen)))\""
        if let dashes = dashArray(style.pattern) {
            attributes += " stroke-dasharray=\"\(dashes)\""
        }
        return attributes
    }

    private func strokeMM(_ pen: PenWeight) -> Double {
        Double(pen.micrometers) / 1_000
    }

    /// Paper millimeters. Matches the ISO-style dashes used by the sheet PDF: 3/1.5, 1.5/0.75, and long-short.
    private func dashArray(_ pattern: LinePattern) -> String? {
        switch pattern {
        case .solid: return nil
        case .dashed: return "3 1.5"
        case .hidden: return "1.5 0.75"
        case .center: return "6 1 1 1"
        }
    }

    private func scaledMM(_ length: Length) -> Double {
        Double(scale.paper(length).ticks) / Double(Length.ticksPerMillimeter)
    }

    private func paperMM(_ length: Length) -> Double {
        Double(length.ticks) / Double(Length.ticksPerMillimeter)
    }

    private func radians(_ angle: Angle) -> Double {
        Double(angle.microDegrees) / 1_000_000 * .pi / 180
    }

    private mutating func note(_ x: Double, _ y: Double, margin: Double = 0) {
        let pad = max(0, margin)
        if hasPoint {
            minX = min(minX, x - pad)
            minY = min(minY, y - pad)
            maxX = max(maxX, x + pad)
            maxY = max(maxY, y + pad)
        } else {
            hasPoint = true
            minX = x - pad
            minY = y - pad
            maxX = x + pad
            maxY = y + pad
        }
    }

    private func viewFrame() -> (minX: Double, minY: Double, width: Double, height: Double) {
        guard hasPoint else { return (0, 0, 0, 0) }
        return (minX, minY, max(0, maxX - minX), max(0, maxY - minY))
    }

    private func pointList(_ points: [(Double, Double)]) -> String {
        points.map { "\(num($0.0)),\(num($0.1))" }.joined(separator: " ")
    }

    private func num(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 1_000_000).rounded() / 1_000_000
        if rounded == 0 { return "0" }
        var text = String(format: "%.6f", rounded)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
            text.removeLast()
        }
        return text
    }

    private func escape(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            case "\n": out += "&#10;"
            case "\r": out += "&#13;"
            default:
                if scalar.value < 0x20 {
                    out += "&#x\(String(scalar.value, radix: 16));"
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}
