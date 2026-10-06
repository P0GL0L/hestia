import Foundation

/// Pen width on paper, in hundredths of a millimeter, on the ISO 128 pen series.
public enum PenWeight: Int, Codable, Hashable, Sendable, CaseIterable {
    case extraFine = 13
    case fine = 18
    case thin = 25
    case medium = 35
    case wide = 50
    case heavy = 70
    case extraHeavy = 100

    /// Printed width in micrometers.
    public var micrometers: Int { rawValue * 10 }
}

/// How a stroke is drawn.
public enum LinePattern: String, Codable, Hashable, Sendable, CaseIterable {
    case solid
    case dashed
    /// Short dashes for edges hidden from view or above the cut plane.
    case hidden
    /// Long-short dashes for centerlines.
    case center
}

/// Fill pattern for a hatch region.
public enum HatchPattern: String, Codable, Hashable, Sendable, CaseIterable {
    case solid
    case diagonal
    case crosshatch
    case insulation
    case concrete
    case earth
}

/// Horizontal anchor of a text item at its position.
public enum TextAlignment: String, Codable, Hashable, Sendable, CaseIterable {
    case left
    case center
    case right
}

/// Layer, pen, and pattern for one display item. Layer names follow the US National CAD Standard, such as `A-WALL`.
public struct DisplayStyle: Codable, Hashable, Sendable {
    public var layer: String
    public var pen: PenWeight
    public var pattern: LinePattern

    public init(layer: String, pen: PenWeight = .thin, pattern: LinePattern = .solid) {
        self.layer = layer
        self.pen = pen
        self.pattern = pattern
    }
}

/// One drawable primitive.
///
/// Positions, radii, and dimension offsets are model space. Text heights, hatch spacing, and symbol sizes are
/// paper space, so annotation stays the same printed size at every scale.
public enum DisplayPrimitive: Codable, Hashable, Sendable {
    case line(start: Point2, end: Point2)
    case polyline(points: [Point2], closed: Bool)
    /// Counterclockwise from `start` through `sweep`; a negative sweep runs clockwise.
    case arc(center: Point2, radius: Length, start: Angle, sweep: Angle)
    case text(position: Point2, string: String, height: Length, rotation: Angle, alignment: TextAlignment)
    case hatch(boundary: [Point2], pattern: HatchPattern, spacing: Length, angle: Angle)
    /// A linear dimension between two points, drawn `offset` to the left of `from → to`.
    /// `override` replaces the measured value text when set.
    case dimension(from: Point2, to: Point2, offset: Length, override: String?)
    /// A named library symbol, such as an outlet or a north arrow, with its own paper-space size.
    case symbol(name: String, position: Point2, rotation: Angle, size: Length)
}

/// A primitive with its style, and the model element it came from so selection can map back.
public struct DisplayItem: Codable, Hashable, Sendable {
    public var primitive: DisplayPrimitive
    public var style: DisplayStyle
    public var elementID: UUID?

    public init(_ primitive: DisplayPrimitive, style: DisplayStyle, elementID: UUID? = nil) {
        self.primitive = primitive
        self.style = style
        self.elementID = elementID
    }
}

/// Platform-free vector drawing shared by drawings, exchange, and the app. Renderers draw items in order.
public struct DisplayList: Codable, Hashable, Sendable {
    public var items: [DisplayItem]

    public init(items: [DisplayItem] = []) {
        self.items = items
    }

    /// Distinct layer names in first-use order.
    public var layers: [String] {
        var seen = Set<String>()
        return items.map(\.style.layer).filter { seen.insert($0).inserted }
    }

    /// Model-space box around every defining point; arcs count as full circles. Nil when empty.
    public var bounds: (min: Point2, max: Point2)? {
        var xs: [Int64] = []
        var ys: [Int64] = []
        func add(_ point: Point2, pad: Int64 = 0) {
            xs += [point.x.ticks - pad, point.x.ticks + pad]
            ys += [point.y.ticks - pad, point.y.ticks + pad]
        }
        for item in items {
            switch item.primitive {
            case let .line(start, end): add(start); add(end)
            case let .polyline(points, _): points.forEach { add($0) }
            case let .arc(center, radius, _, _): add(center, pad: radius.ticks)
            case let .text(position, _, _, _, _): add(position)
            case let .hatch(boundary, _, _, _): boundary.forEach { add($0) }
            case let .dimension(from, to, _, _): add(from); add(to)
            case let .symbol(_, position, _, _): add(position)
            }
        }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }
        return (Point2(x: Length(ticks: minX), y: Length(ticks: minY)),
                Point2(x: Length(ticks: maxX), y: Length(ticks: maxY)))
    }
}
