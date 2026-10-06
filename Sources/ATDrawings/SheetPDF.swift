import ATContracts
import Foundation

/// Renders sheets to a true-scale vector PDF using only the standard 14 fonts.
///
/// Every sheet becomes one page the size of its paper. Coordinates on a sheet are paper space, so a
/// 100 mm line in the display list prints 100 mm long. Pure Swift and Foundation; no Apple frameworks.
public enum SheetPDF {
    /// PDF points per tick: 72 points per inch, 25.4 mm per inch, 320 ticks per mm.
    static let pointsPerTick = 72.0 / 25.4 / Double(Length.ticksPerMillimeter)

    public static func render(_ sheets: [SheetDrawing]) -> Data {
        var writer = PDF14Writer()
        let fontObject = 3
        let firstPage = 4
        let kids = sheets.indices.map { "\(firstPage + $0 * 2) 0 R" }.joined(separator: " ")
        writer.addObject(number: 1, body: "<< /Type /Catalog /Pages 2 0 R >>")
        writer.addObject(number: 2, body: "<< /Type /Pages /Kids [\(kids)] /Count \(sheets.count) >>")
        writer.addObject(number: fontObject,
                         body: "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        for (index, sheet) in sheets.enumerated() {
            let page = firstPage + index * 2
            let content = Data(contentStream(for: sheet).utf8)
            writer.addObject(number: page, body: """
                << /Type /Page /Parent 2 0 R /MediaBox [0 0 \(pt(sheet.paper.width)) \(pt(sheet.paper.height))] \
                /Contents \(page + 1) 0 R /Resources << /Font << /F1 \(fontObject) 0 R >> >> >>
                """)
            writer.addObject(number: page + 1,
                             body: "<< /Length \(content.count) >>\nstream\n\(String(decoding: content, as: UTF8.self))endstream")
        }
        writer.finish(rootObjectNumber: 1, objectCount: firstPage + sheets.count * 2 - 1)
        return writer.data
    }

    /// The page content stream for one sheet.
    static func contentStream(for sheet: SheetDrawing) -> String {
        var out = "1 J 1 j 0 G 0 g\n"
        for item in sheet.content.items {
            out += "q\n"
            out += "\(num(Double(item.style.pen.micrometers) / 1000 * 72 / 25.4)) w\n"
            out += dash(item.style.pattern)
            out += draw(item.primitive, scale: sheet.scale)
            out += "Q\n"
        }
        return out
    }

    // MARK: - Primitives

    private static func draw(_ primitive: DisplayPrimitive, scale: DrawingScale?) -> String {
        switch primitive {
        case let .line(start, end):
            return "\(xy(start)) m \(xy(end)) l S\n"
        case let .polyline(points, closed):
            return path(points, closed: closed) + "S\n"
        case let .arc(center, radius, start, sweep):
            return arcPath(center: center, radius: radius, start: start, sweep: sweep, moveFirst: true) + "S\n"
        case let .text(position, string, height, rotation, alignment):
            return text(string, at: position, height: height, rotation: rotation, alignment: alignment)
        case let .hatch(boundary, pattern, spacing, angle):
            return hatch(boundary, pattern: pattern, spacing: spacing, angle: angle)
        case let .dimension(from, to, offset, override):
            return dimension(from: from, to: to, offset: offset, override: override, scale: scale)
        case let .symbol(name, position, rotation, size):
            return symbol(name, at: position, rotation: rotation, size: size)
        }
    }

    private static func path(_ points: [Point2], closed: Bool) -> String {
        guard let first = points.first else { return "" }
        var out = "\(xy(first)) m"
        for point in points.dropFirst() { out += " \(xy(point)) l" }
        return out + (closed ? " h\n" : "\n")
    }

    /// Cubic Bézier approximation, at most 90° per segment.
    private static func arcPath(center: Point2, radius: Length, start: Angle, sweep: Angle, moveFirst: Bool) -> String {
        let r = Double(radius.ticks) * pointsPerTick
        let cx = Double(center.x.ticks) * pointsPerTick
        let cy = Double(center.y.ticks) * pointsPerTick
        let a0 = radians(start)
        let total = radians(sweep)
        let segments = max(1, Int((abs(total) / (Double.pi / 2)).rounded(.up)))
        let step = total / Double(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var out = moveFirst ? "\(num(cx + r * cos(a0))) \(num(cy + r * sin(a0))) m" : ""
        for i in 0..<segments {
            let t0 = a0 + Double(i) * step
            let t1 = t0 + step
            let p1 = (cx + r * (cos(t0) - k * sin(t0)), cy + r * (sin(t0) + k * cos(t0)))
            let p2 = (cx + r * (cos(t1) + k * sin(t1)), cy + r * (sin(t1) - k * cos(t1)))
            out += " \(num(p1.0)) \(num(p1.1)) \(num(p2.0)) \(num(p2.1)) \(num(cx + r * cos(t1))) \(num(cy + r * sin(t1))) c"
        }
        return out + "\n"
    }

    static func text(
        _ string: String, at position: Point2, height: Length, rotation: Angle, alignment: TextAlignment
    ) -> String {
        // Cap height of Helvetica is 718/1000 of the font size; `height` is cap height on paper.
        let size = Double(height.ticks) * pointsPerTick / 0.718
        let width = HelveticaMetrics.width(of: string) * size
        let shift = alignment == .left ? 0 : (alignment == .center ? width / 2 : width)
        let a = radians(rotation)
        let x = Double(position.x.ticks) * pointsPerTick - shift * cos(a)
        let y = Double(position.y.ticks) * pointsPerTick - shift * sin(a)
        return "BT /F1 \(num(size)) Tf \(num(cos(a))) \(num(sin(a))) \(num(-sin(a))) \(num(cos(a))) \(num(x)) \(num(y)) Tm (\(literal(string))) Tj ET\n"
    }

    private static func hatch(_ boundary: [Point2], pattern: HatchPattern, spacing: Length, angle: Angle) -> String {
        guard boundary.count >= 3 else { return "" }
        if pattern == .solid { return path(boundary, closed: true) + "f\n" }
        var out = path(boundary, closed: true) + "W n\n"
        let xs = boundary.map { Double($0.x.ticks) * pointsPerTick }
        let ys = boundary.map { Double($0.y.ticks) * pointsPerTick }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return "" }
        let gap = max(Double(spacing.ticks) * pointsPerTick, 0.5)
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let reach = hypot(maxX - minX, maxY - minY) / 2 + gap
        var angles = [radians(angle)]
        if pattern == .crosshatch || pattern == .earth { angles.append(radians(angle) + .pi / 2) }
        let stride = pattern == .concrete ? gap * 2 : gap
        for a in angles {
            let (dx, dy) = (cos(a), sin(a))
            var offset = -reach
            while offset <= reach {
                let px = cx - dy * offset
                let py = cy + dx * offset
                out += "\(num(px - dx * reach)) \(num(py - dy * reach)) m \(num(px + dx * reach)) \(num(py + dy * reach)) l S\n"
                offset += stride
            }
        }
        return out
    }

    /// Extension lines, a dimension line with architectural ticks, and the measured value above it.
    private static func dimension(
        from: Point2, to: Point2, offset: Length, override: String?, scale: DrawingScale?
    ) -> String {
        let (x0, y0) = (Double(from.x.ticks), Double(from.y.ticks))
        let (x1, y1) = (Double(to.x.ticks), Double(to.y.ticks))
        let length = hypot(x1 - x0, y1 - y0)
        guard length > 0 else { return "" }
        let (ux, uy) = ((x1 - x0) / length, (y1 - y0) / length)
        let (nx, ny) = (-uy, ux)
        let off = Double(offset.ticks)
        let gap = 1.5 * Double(Length.ticksPerMillimeter)
        let tick = 1.5 * Double(Length.ticksPerMillimeter)
        func p(_ x: Double, _ y: Double) -> String { "\(num(x * pointsPerTick)) \(num(y * pointsPerTick))" }
        let sign: Double = off >= 0 ? 1 : -1
        var out = ""
        for (bx, by) in [(x0, y0), (x1, y1)] {
            out += "\(p(bx + nx * gap * sign, by + ny * gap * sign)) m \(p(bx + nx * (off + tick * sign), by + ny * (off + tick * sign))) l S\n"
            let (dx, dy) = (bx + nx * off, by + ny * off)
            out += "\(p(dx - (ux + nx) * tick / 2, dy - (uy + ny) * tick / 2)) m \(p(dx + (ux + nx) * tick / 2, dy + (uy + ny) * tick / 2)) l S\n"
        }
        out += "\(p(x0 + nx * off, y0 + ny * off)) m \(p(x1 + nx * off, y1 + ny * off)) l S\n"
        let label = override ?? measuredLabel(paperTicks: Int64(length.rounded()), scale: scale)
        let mid = Point2(x: Length(ticks: Int64(((x0 + x1) / 2 + nx * (off + gap * sign)).rounded())),
                         y: Length(ticks: Int64(((y0 + y1) / 2 + ny * (off + gap * sign)).rounded())))
        var angle = atan2(uy, ux)
        if angle > .pi / 2 + 1e-9 || angle <= -.pi / 2 { angle += .pi }
        let rotation = Angle(microDegrees: Int64((angle * 180 / .pi * 1_000_000).rounded()))
        out += "0 g\n" + text(label, at: mid, height: .millimeters(2), rotation: rotation, alignment: .center)
        return out
    }

    /// Model length for a paper length, rounded to 1/16" or 1 mm, in the scale's unit system.
    static func measuredLabel(paperTicks: Int64, scale: DrawingScale?) -> String {
        let model = paperTicks * (scale?.modelUnitsPerPaperUnit ?? 1)
        let imperial = scale?.label.contains("\"") ?? false
        let unit = imperial ? Length.ticksPerSixtyFourthInch * 4 : Length.ticksPerMillimeter
        let rounded = Length(ticks: ((model + unit / 2) / unit) * unit)
        return LengthFormatting.format(rounded, style: imperial ? .feetInchesFractions : .metric)
    }

    /// Simple outline symbols; unknown names draw a labeled circle so nothing silently disappears.
    private static func symbol(_ name: String, at position: Point2, rotation: Angle, size: Length) -> String {
        let r = Length(ticks: size.ticks / 2)
        var out = arcPath(center: position, radius: r, start: .degrees(0), sweep: .degrees(360), moveFirst: true) + "S\n"
        switch name {
        case "north-arrow":
            let a = radians(rotation) + .pi / 2
            let tip = Point2(x: Length(ticks: position.x.ticks + Int64(Double(r.ticks) * cos(a))),
                             y: Length(ticks: position.y.ticks + Int64(Double(r.ticks) * sin(a))))
            out += "\(xy(position)) m \(xy(tip)) l S\n"
            out += text("N", at: tip, height: Length(ticks: size.ticks / 4), rotation: .degrees(0), alignment: .center)
        default:
            let label = String(name.split(separator: "-").compactMap(\.first).prefix(2)).uppercased()
            out += text(label, at: Point2(x: position.x, y: Length(ticks: position.y.ticks - size.ticks / 6)),
                        height: Length(ticks: size.ticks / 3), rotation: rotation, alignment: .center)
        }
        return out
    }

    // MARK: - Formatting

    private static func dash(_ pattern: LinePattern) -> String {
        let mm = 72 / 25.4
        switch pattern {
        case .solid: return "[] 0 d\n"
        case .dashed: return "[\(num(3 * mm)) \(num(1.5 * mm))] 0 d\n"
        case .hidden: return "[\(num(1.5 * mm)) \(num(0.75 * mm))] 0 d\n"
        case .center: return "[\(num(6 * mm)) \(num(1 * mm)) \(num(1 * mm)) \(num(1 * mm))] 0 d\n"
        }
    }

    static func pt(_ length: Length) -> String { num(Double(length.ticks) * pointsPerTick) }

    private static func xy(_ point: Point2) -> String { "\(pt(point.x)) \(pt(point.y))" }

    private static func radians(_ angle: Angle) -> Double {
        Double(angle.microDegrees) / 1_000_000 * .pi / 180
    }

    static func num(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        return rounded == 0 ? "0" : String(format: "%.3f", rounded)
    }

    /// WinAnsi literal; characters outside it become `?`.
    static func literal(_ string: String) -> String {
        var out = ""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "(": out += "\\("
            case ")": out += "\\)"
            case " "..."~": out.unicodeScalars.append(scalar)
            default: out += "?"
            }
        }
        return out
    }
}

/// Helvetica advance widths (per 1000 em) for printable ASCII, from the standard AFM.
enum HelveticaMetrics {
    private static let widths: [Int] = [
        278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, // space to /
        556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, // 0 to ?
        1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, // @ to O
        667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, // P to _
        333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, // ` to o
        556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584, // p to ~
    ]

    /// Width in ems; characters outside printable ASCII count as `?`.
    static func width(of string: String) -> Double {
        string.unicodeScalars.reduce(0) { total, scalar in
            let code = Int(scalar.value)
            let index = (32...126).contains(code) ? code - 32 : Int(("?" as Unicode.Scalar).value) - 32
            return total + Double(widths[index]) / 1000
        }
    }
}
