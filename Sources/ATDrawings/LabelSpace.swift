import ATContracts
import Foundation

/// What is already drawn on a view, for finding room for labels: each label is tried at its places in order of
/// preference and set at the first where its text crosses no line, hatch, or other text, and its own lines
/// cross no text already set, with `padding` to spare. The geometry is `DrawingAudit`'s, so a label placed here
/// is one the audit passes.
struct LabelSpace {
    private(set) var labels: [DrawingAudit.Box] = []
    private(set) var strokes: [DrawingAudit.Stroke] = []
    private(set) var areas: [DrawingAudit.Area] = []
    let scale: DrawingScale?
    /// Clear paper kept around each label placed here, so nothing set by it merely touches.
    let padding: Double

    init(_ items: [DisplayItem], scale: DrawingScale?, padding: Double = Double(Length.ticksPerMillimeter) * 0.8) {
        self.scale = scale
        self.padding = padding
        add(items)
    }

    mutating func add(_ items: [DisplayItem]) {
        let parts = DrawingAudit.parts(items, scale: scale)
        labels += parts.labels.map(\.box)
        strokes += parts.strokes
        areas += parts.areas
    }

    /// How many things a candidate runs into: its text against everything drawn and against its own lines and
    /// other text, and its lines against the text already set. Zero when it is clear. With `within`, a paper
    /// polygon, text outside it counts too.
    ///
    /// With `crossing`, the candidate's own lines longer than 4 mm (less a millimetre at each end, where they
    /// meet what they measure) also may not cross lines already drawn on those layers: a room's dimension line
    /// is kept off door swings, stairs, and walls.
    func collisions(_ candidate: [DisplayItem], within: [Point2]? = nil, crossing: Set<String> = []) -> Int {
        let own = DrawingAudit.parts(candidate, scale: scale)
        let boxes = own.labels.map { DrawingAudit.inset($0.box, by: -padding) }
        var count = 0
        for (index, box) in boxes.enumerated() {
            let (x0, x1, y0, y1) = (box.minX, box.maxX, box.minY, box.maxY)
            for stroke in strokes + own.strokes {
                // A quick look at the stroke's extent first.
                if max(stroke.a.x, stroke.b.x) < x0 || min(stroke.a.x, stroke.b.x) > x1
                    || max(stroke.a.y, stroke.b.y) < y0 || min(stroke.a.y, stroke.b.y) > y1 { continue }
                if DrawingAudit.crosses(stroke.a, stroke.b, box) { count += 1 }
            }
            count += areas.filter { DrawingAudit.over(box, $0) }.count
            count += labels.filter { $0.maxX > x0 && $0.minX < x1 && $0.maxY > y0 && $0.minY < y1 }
                .filter { DrawingAudit.overlaps(box, $0) }.count
            count += boxes[(index + 1)...].filter { DrawingAudit.overlaps(box, $0) }.count
            if let within {
                let xs = within.map { Double($0.x.ticks) }, ys = within.map { Double($0.y.ticks) }
                count += box.corners.filter { !RasterOutline.inside($0.x, $0.y, xs, ys) }.count
            }
        }
        for stroke in own.strokes {
            for box in labels where DrawingAudit.crosses(stroke.a, stroke.b, box) { count += 1 }
        }
        if !crossing.isEmpty {
            let trim = Double(Length.ticksPerMillimeter)
            for stroke in own.strokes {
                // Ticks and extension lines at the ends sit on what they measure; only the long lines count.
                let length = hypot(stroke.b.x - stroke.a.x, stroke.b.y - stroke.a.y)
                guard length > trim * 4 else { continue }
                let (ux, uy) = ((stroke.b.x - stroke.a.x) / length, (stroke.b.y - stroke.a.y) / length)
                let a = (x: stroke.a.x + ux * trim, y: stroke.a.y + uy * trim)
                let b = (x: stroke.b.x - ux * trim, y: stroke.b.y - uy * trim)
                for other in strokes where crossing.contains(other.layer) && Self.intersect(a, b, other.a, other.b) {
                    count += 1
                }
            }
        }
        return count
    }

    /// Whether two segments cross or touch.
    static func intersect(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double), _ c: (x: Double, y: Double),
                          _ d: (x: Double, y: Double)) -> Bool {
        if max(a.x, b.x) < min(c.x, d.x) || max(c.x, d.x) < min(a.x, b.x) || max(a.y, b.y) < min(c.y, d.y)
            || max(c.y, d.y) < min(a.y, b.y) { return false }
        func side(_ p: (x: Double, y: Double), _ q: (x: Double, y: Double), _ r: (x: Double, y: Double)) -> Double {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let (d1, d2) = (side(c, d, a), side(c, d, b)), (d3, d4) = (side(a, b, c), side(a, b, d))
        return ((d1 > 0) != (d2 > 0) || d1 == 0 || d2 == 0) && ((d3 > 0) != (d4 > 0) || d3 == 0 || d4 == 0)
    }

    /// The first clear candidate, added to the space; nothing when none is clear. A label that cannot clear the
    /// drawing is left out rather than set over it.
    mutating func place(_ candidates: [[DisplayItem]], within: [Point2]? = nil,
                        crossing: Set<String> = []) -> [DisplayItem] {
        for candidate in candidates where collisions(candidate, within: within, crossing: crossing) == 0 {
            add(candidate)
            return candidate
        }
        return []
    }
}
