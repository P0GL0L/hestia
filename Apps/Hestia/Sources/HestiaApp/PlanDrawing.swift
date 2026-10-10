import ATContracts
import Foundation

/// How a plan overlay shape is drawn.
enum PlanPaint: Equatable {
    case fill(Look, opacity: Double)
    /// A line `width` view points wide.
    case stroke(red: Double, green: Double, blue: Double, width: Double, dashed: Bool)
}

/// Extra things the plan view draws around the drawing set's plan: terrain patches under it, furniture over
/// it, and the preview of what the current tool is about to add. All in model ticks, like the plan.
struct PlanOverlay: Equatable {
    struct Shape: Equatable {
        var points: [Point2]
        var closed: Bool
        var paint: PlanPaint
    }

    struct Label: Equatable {
        var position: Point2
        var text: String
        /// In view points.
        var size: Double
        var highlighted: Bool = false
    }

    var under: [Shape] = []
    var over: [Shape] = []
    var labels: [Label] = []

    static let ink = (red: 0.25, green: 0.25, blue: 0.27)
    static let accent = (red: 0.95, green: 0.45, blue: 0.05)

    /// Terrain under the plan and furniture over it, for one storey. The selected placement is outlined in the
    /// accent color.
    init(document: ModelDocument, storey: StoreyID?, selected: PlacementID? = nil) {
        let patches = document.terrainPatches.sorted {
            SiteKind(patchName: $0.name).order < SiteKind(patchName: $1.name).order
        }
        for patch in patches {
            let kind = SiteKind(patchName: patch.name)
            if kind == .lot {
                under.append(Shape(points: patch.boundary, closed: true, paint: .fill(.lawn, opacity: 0.25)))
                under.append(Shape(points: patch.boundary, closed: true,
                                   paint: .stroke(red: 0.2, green: 0.45, blue: 0.2, width: 1.5, dashed: true)))
            } else {
                under.append(Shape(points: patch.boundary, closed: true, paint: .fill(kind.look, opacity: 0.55)))
            }
            if let middle = Self.middle(patch.boundary) {
                labels.append(Label(position: middle, text: patch.name, size: 10))
            }
        }
        for placement in document.placements where placement.storeyID == storey {
            let item = Furniture.item(placement.catalogItemID) ?? Furniture.placeholder(placement.catalogItemID)
            over += Self.furniture(item, at: placement.position, rotation: placement.rotation,
                                   highlighted: placement.id == selected)
        }
    }

    init() {}

    /// An item's plan symbol: its footprint, filled, with each part's outline inside. Planting is a circle.
    static func furniture(_ item: FurnitureItem, at position: Point2, rotation: Angle, highlighted: Bool = false,
                          ghost: Bool = false) -> [Shape] {
        let (cx, cy) = (HouseScene.feet(position.x), HouseScene.feet(position.y))
        let turn = Double(rotation.microDegrees) / 1_000_000 * .pi / 180
        let line = highlighted ? accent : ink
        let width = highlighted ? 2.0 : 0.8
        if item.isPlant {
            let radius = max(item.width, item.depth) / 2
            let circle = (0..<24).map { step -> Point2 in
                let angle = Double(step) / 24 * 2 * .pi
                return point(cx + radius * cos(angle), cy + radius * sin(angle))
            }
            return [Shape(points: circle, closed: true, paint: .fill(.foliage, opacity: ghost ? 0.25 : 0.45)),
                    Shape(points: circle, closed: true,
                          paint: .stroke(red: line.red, green: line.green, blue: line.blue, width: width,
                                         dashed: ghost))]
        }
        let outline = item.outline(cx: cx, cy: cy, turn: turn).map { point($0.x, $0.y) }
        let body = item.parts.max { $0.width * $0.depth < $1.width * $1.depth }?.look ?? .wood
        var shapes = [Shape(points: outline, closed: true, paint: .fill(body, opacity: ghost ? 0.25 : 0.5))]
        // Parts that show from above: skip legs and thin trim, which only clutter the symbol.
        for part in item.parts where part.width * part.depth >= 0.5 && part.z + part.height > 0.3 {
            let corners = part.footprint(cx: cx, cy: cy, turn: turn).map { point($0.x, $0.y) }
            shapes.append(Shape(points: corners, closed: true,
                                paint: .stroke(red: ink.red, green: ink.green, blue: ink.blue, width: 0.5,
                                               dashed: false)))
        }
        shapes.append(Shape(points: outline, closed: true,
                            paint: .stroke(red: line.red, green: line.green, blue: line.blue, width: width,
                                           dashed: ghost)))
        return shapes
    }

    /// A rubber-band line from `start` to `end` in the accent color.
    static func band(_ start: Point2, _ end: Point2) -> Shape {
        Shape(points: [start, end], closed: false,
              paint: .stroke(red: accent.red, green: accent.green, blue: accent.blue, width: 2, dashed: true))
    }

    /// A rubber-band rectangle with corners at `a` and `b`.
    static func box(_ a: Point2, _ b: Point2, fill: Look? = nil) -> [Shape] {
        let corners = PlanGeometry.rectangle(a, b)
        var shapes: [Shape] = []
        if let fill { shapes.append(Shape(points: corners, closed: true, paint: .fill(fill, opacity: 0.4))) }
        shapes.append(Shape(points: corners, closed: true,
                            paint: .stroke(red: accent.red, green: accent.green, blue: accent.blue, width: 2,
                                           dashed: true)))
        return shapes
    }

    static func point(_ xFeet: Double, _ yFeet: Double) -> Point2 {
        let perFoot = Double(Length.feet(1).ticks)
        return Point2(x: Length(ticks: Int64((xFeet * perFoot).rounded())),
                      y: Length(ticks: Int64((yFeet * perFoot).rounded())))
    }

    static func middle(_ points: [Point2]) -> Point2? {
        guard !points.isEmpty else { return nil }
        let x = points.map { Double($0.x.ticks) }.reduce(0, +) / Double(points.count)
        let y = points.map { Double($0.y.ticks) }.reduce(0, +) / Double(points.count)
        return Point2(x: Length(ticks: Int64(x.rounded())), y: Length(ticks: Int64(y.rounded())))
    }
}

/// Plan geometry for the drawing tools, in model ticks.
enum PlanGeometry {
    /// The rectangle with opposite corners `a` and `b`, counterclockwise from its lower left.
    static func rectangle(_ a: Point2, _ b: Point2) -> [Point2] {
        let (x0, x1) = (min(a.x.ticks, b.x.ticks), max(a.x.ticks, b.x.ticks))
        let (y0, y1) = (min(a.y.ticks, b.y.ticks), max(a.y.ticks, b.y.ticks))
        return [Point2(x: Length(ticks: x0), y: Length(ticks: y0)), Point2(x: Length(ticks: x1), y: Length(ticks: y0)),
                Point2(x: Length(ticks: x1), y: Length(ticks: y1)), Point2(x: Length(ticks: x0), y: Length(ticks: y1))]
    }

    static func distance(_ a: Point2, _ b: Point2) -> Length {
        let dx = Double(b.x.ticks - a.x.ticks), dy = Double(b.y.ticks - a.y.ticks)
        return Length(ticks: Int64((dx * dx + dy * dy).squareRoot().rounded()))
    }

    /// The point `length` from `start` toward `toward`; east when the two are the same point.
    static func reach(from start: Point2, toward: Point2, length: Length) -> Point2 {
        var dx = Double(toward.x.ticks - start.x.ticks), dy = Double(toward.y.ticks - start.y.ticks)
        let size = (dx * dx + dy * dy).squareRoot()
        if size < 1 { (dx, dy) = (1, 0) } else { (dx, dy) = (dx / size, dy / size) }
        let ticks = Double(length.ticks)
        return Point2(x: Length(ticks: start.x.ticks + Int64((dx * ticks).rounded())),
                      y: Length(ticks: start.y.ticks + Int64((dy * ticks).rounded())))
    }

    /// Opposite corner of a `width` by `depth` rectangle from `start`, on the side of `toward`.
    static func corner(from start: Point2, toward: Point2, width: Length, depth: Length) -> Point2 {
        let sx: Int64 = toward.x.ticks < start.x.ticks ? -1 : 1
        let sy: Int64 = toward.y.ticks < start.y.ticks ? -1 : 1
        return Point2(x: Length(ticks: start.x.ticks + sx * width.ticks),
                      y: Length(ticks: start.y.ticks + sy * depth.ticks))
    }

    /// Distance from a point to a segment, in ticks.
    static func distance(from p: Point2, toSegment a: Point2, _ b: Point2) -> Double {
        let (px, py) = (Double(p.x.ticks), Double(p.y.ticks))
        let (ax, ay, bx, by) = (Double(a.x.ticks), Double(a.y.ticks), Double(b.x.ticks), Double(b.y.ticks))
        let (dx, dy) = (bx - ax, by - ay)
        let squared = dx * dx + dy * dy
        let t = squared > 0 ? min(max(((px - ax) * dx + (py - ay) * dy) / squared, 0), 1) : 0
        return hypot(px - (ax + dx * t), py - (ay + dy * t))
    }

    /// Whether a point is inside a polygon (even-odd).
    static func contains(_ polygon: [Point2], _ p: Point2) -> Bool {
        var inside = false
        let (px, py) = (Double(p.x.ticks), Double(p.y.ticks))
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            let (ax, ay, bx, by) = (Double(a.x.ticks), Double(a.y.ticks), Double(b.x.ticks), Double(b.y.ticks))
            if (ay > py) != (by > py), px < (bx - ax) * (py - ay) / (by - ay) + ax { inside.toggle() }
        }
        return inside
    }
}

/// Lengths typed while drawing. Imperial projects read `12`, `12'`, `12'6`, `12' 6"`, `12'-6 1/2"`, `144"`,
/// and `12.5`; a bare number is feet. Metric projects read `3.6`, `3.6 m`, `3600 mm`, and `360 cm`; a bare
/// number is metres. Either reads the other's units when they are written out. Nil when the text is not a
/// length or is not positive.
enum LengthEntry {
    static func parse(_ text: String, metric: Bool) -> Length? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let result: Length?
        if let value = number(trimmed, dropping: "mm") {
            result = millimeters(value)
        } else if let value = number(trimmed, dropping: "cm") {
            result = millimeters(value * 10)
        } else if let value = number(trimmed, dropping: "m") {
            result = millimeters(value * 1000)
        } else if let value = Double(trimmed) {
            result = metric ? millimeters(value * 1000) : feet(value)
        } else {
            result = imperial(trimmed)
        }
        guard let result, result.ticks > 0 else { return nil }
        return result
    }

    /// "W x D", as two lengths.
    static func pair(_ text: String, metric: Bool) -> (Length, Length)? {
        let pieces = text.lowercased().split { $0 == "x" || $0 == "×" || $0 == "*" || $0 == "," }
        guard pieces.count == 2, let width = parse(String(pieces[0]), metric: metric),
              let depth = parse(String(pieces[1]), metric: metric) else { return nil }
        return (width, depth)
    }

    private static func number(_ text: String, dropping unit: String) -> Double? {
        guard text.hasSuffix(unit) else { return nil }
        return Double(text.dropLast(unit.count).trimmingCharacters(in: .whitespaces))
    }

    /// Millimetres to the model's tick, so a typed 3607.5 mm stays 3607.5 mm.
    private static func millimeters(_ value: Double) -> Length {
        Length(ticks: Int64((value * Double(Length.ticksPerMillimeter)).rounded()))
    }

    private static func feet(_ value: Double) -> Length {
        Length(ticks: Int64((value * Double(Length.feet(1).ticks)).rounded()))
    }

    /// Feet and inches with an optional fraction of an inch.
    private static func imperial(_ text: String) -> Length? {
        var feetPart = 0.0, inchText = text
        if let mark = text.firstIndex(of: "'") {
            guard let value = Double(text[..<mark].trimmingCharacters(in: .whitespaces)) else { return nil }
            feetPart = value
            inchText = String(text[text.index(after: mark)...])
        }
        inchText = inchText.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "-", with: " ")
        let words = inchText.split(separator: " ").map(String.init)
        var inches = 0.0
        for word in words {
            if let slash = word.firstIndex(of: "/") {
                guard let top = Double(word[..<slash]), let bottom = Double(word[word.index(after: slash)...]),
                      bottom > 0 else { return nil }
                inches += top / bottom
            } else if let value = Double(word) {
                inches += value
            } else {
                return nil
            }
        }
        if !text.contains("'") && !text.contains("\"") { return nil }
        let ticksPerInch = Double(Length.inches(1).ticks)
        return Length(ticks: Int64(((feetPart * 12 + inches) * ticksPerInch).rounded()))
    }
}
