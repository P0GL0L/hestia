import ATContracts
import Foundation

/// Elevations and sections drawn from the engine's meshes with hidden lines removed: what a viewer standing on
/// that side would see, a roof behind another hidden by it, nothing seen through a wall. The building's profile
/// against the sky is heavy, edges in front of something farther are medium, and folds, the joints where roofs
/// and walls meet, and doors and windows are light, as blueprints weigh them.
extension ElevationView {
    static let profileStyle = DisplayStyle(layer: "A-ELEV-OTLN", pen: .heavy)

    /// The projection for a side: h left to right as the viewer sees it, v up, depth away from the viewer.
    static func lines(_ direction: ElevationDirection) -> HiddenLines.View {
        let toward: (x: Double, y: Double, z: Double)
        switch direction {
        case .south: toward = (0, -1, 0)
        case .north: toward = (0, 1, 0)
        case .east: toward = (1, 0, 0)
        case .west: toward = (-1, 0, 0)
        }
        return HiddenLines.View(project: { x, y, z in
            switch direction {
            case .south: return (x, z, y)
            case .north: return (-x, z, -y)
            case .east: return (y, z, -x)
            case .west: return (-y, z, x)
            }
        }, toward: toward)
    }

    /// The projection for a section along `line`, looking to its left: h along the line from its start, v up,
    /// depth to the left of the line, so the cut is at depth zero.
    static func lines(_ line: SectionLine) -> HiddenLines.View? {
        let (ox, oy) = (Double(line.start.x.ticks), Double(line.start.y.ticks))
        let (dx, dy) = (Double(line.end.x.ticks) - ox, Double(line.end.y.ticks) - oy)
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return nil }
        let (ux, uy) = (dx / length, dy / length)
        return HiddenLines.View(project: { x, y, z in
            let (px, py) = (x - ox, y - oy)
            return (px * ux + py * uy, z, ux * py - uy * px)
        }, toward: (uy, -ux, 0))
    }

    /// The visible edges of `meshes`, in the view's (h, v) model space, leaving out anything below `grade`.
    /// `near` cuts away what is in front of a section.
    static func visibleSegments(_ meshes: [Mesh], view: HiddenLines.View, grade: Int64, near: Double? = nil)
        -> [HiddenLines.Segment] {
        let cell = Double(Length.inches(1).ticks)
        return HiddenLines.segments(meshes, view: view, cell: cell, tolerance: cell, near: near).compactMap {
            guard let (a, b) = above(grade: Double(grade), $0.start, $0.end) else { return nil }
            return HiddenLines.Segment(start: a, end: b, kind: $0.kind, elementID: $0.elementID)
        }
    }

    /// Segments as drawing items, weighted by kind, doors and windows light; or all in `beyond` when given.
    static func lineItems(_ segments: [HiddenLines.Segment], transform: ViewTransform, openings: Set<UUID>,
                          beyond: DisplayStyle? = nil) -> [DisplayItem] {
        var items: [DisplayItem] = []
        for segment in segments {
            let style: DisplayStyle
            if let beyond {
                style = beyond
            } else if let id = segment.elementID, openings.contains(id) {
                style = openingStyle
            } else {
                switch segment.kind {
                case .profile: style = profileStyle
                case .outline: style = wallStyle
                case .fold, .intersection: style = foldStyle
                }
            }
            let (a, b) = (segment.start, segment.end)
            let start = transform.paper(paperPoint(Int64(a.h.rounded()), Int64(a.v.rounded())))
            let end = transform.paper(paperPoint(Int64(b.h.rounded()), Int64(b.v.rounded())))
            guard start != end else { continue }
            items.append(DisplayItem(.line(start: start, end: end), style: style, elementID: segment.elementID))
        }
        return items
    }

    /// The part of a segment at or above grade, if any.
    static func above(grade: Double, _ a: (h: Double, v: Double), _ b: (h: Double, v: Double))
        -> ((h: Double, v: Double), (h: Double, v: Double))? {
        let tolerance = 0.5
        switch (a.v >= grade - tolerance, b.v >= grade - tolerance) {
        case (true, true):
            // A line along the grade is the ground line's to draw.
            return abs(a.v - grade) <= tolerance && abs(b.v - grade) <= tolerance ? nil : (a, b)
        case (false, false): return nil
        default:
            let k = (grade - a.v) / (b.v - a.v)
            let cut = (h: a.h + (b.h - a.h) * k, v: grade)
            return a.v >= grade ? (a, cut) : (cut, b)
        }
    }

    /// The height of the ground: the lowest floor at grade (each building's lowest storey at or above zero, so a
    /// basement is passed over), or the lowest floor when every storey is below zero.
    static func grade(_ document: ModelDocument) -> Int64 {
        let atGrade = Set(SitePlanView.gradeStoreys(document))
        return document.storeys.filter { atGrade.contains($0.id) }.map(\.elevation.ticks).min()
            ?? document.storeys.map(\.elevation.ticks).min() ?? 0
    }

    /// The (h, z) extent of everything the meshes show above grade from this side; nil when nothing does.
    static func meshExtent(_ document: ModelDocument, _ direction: ElevationDirection, meshes: [Mesh])
        -> (min: Point2, max: Point2)? {
        let grade = grade(document)
        let view = lines(direction)
        var hs: [Double] = [], zs: [Double] = []
        for mesh in meshes {
            for point in mesh.positions where point.z.ticks > grade {
                let seen = view.project(Double(point.x.ticks), Double(point.y.ticks), Double(point.z.ticks))
                hs.append(seen.h)
                zs.append(seen.v)
            }
        }
        guard let h0 = hs.min(), let h1 = hs.max(), let z1 = zs.max(), h1 > h0 else { return nil }
        return (paperPoint(Int64(h0.rounded(.down)), grade), paperPoint(Int64(h1.rounded(.up)), Int64(z1.rounded(.up))))
    }

    /// An elevation drawn from the meshes: hidden-line edges, the ground line at grade, and level marks that
    /// do not crowd one another. It needs no wall square to the view, so a house set at an angle has one too.
    static func meshItems(_ document: ModelDocument, _ direction: ElevationDirection, view: ViewTransform,
                          meshes: [Mesh], roofMeshes: [Mesh]) -> [DisplayItem] {
        guard let extent = meshExtent(document, direction, meshes: meshes) else { return [] }
        let grade = grade(document)
        let openings = Set(document.openings.map(\.id.rawValue))
        let segments = visibleSegments(meshes, view: lines(direction), grade: grade)
        var items = lineItems(segments, transform: view, openings: openings)
        let minH = extent.min.x.ticks, maxH = extent.max.x.ticks
        let reach = Length.millimeters(1500).ticks
        func at(_ h: Int64, _ z: Int64) -> Point2 { view.paper(paperPoint(h, z)) }
        items.append(DisplayItem(.line(start: at(minH - reach, grade), end: at(maxH + reach, grade)),
                                 style: groundStyle))
        let units = DrawingUnits.style(document, scale: view.scale)
        let marked = levels(document, direction, roofMeshes: roofMeshes).filter { $0.z >= grade }
        for level in spaced(marked, view: view) {
            items.append(DisplayItem(.line(start: at(maxH + reach / 3, level.z), end: at(maxH + reach, level.z)),
                                     style: levelStyle))
            let label = level.name + " " + LengthFormatting.format(markHeight(level, units: units), style: units)
            let mark = at(maxH + reach / 3, level.z)
            items.append(DisplayItem(.text(position: Point2(x: mark.x, y: Length(ticks: mark.y.ticks + mmTicks(1))),
                                           string: label, height: .millimeters(2), rotation: .degrees(0),
                                           alignment: .left), style: levelStyle))
        }
        return items
    }

    /// The height a mark prints: floors exactly, roof heights (found from the roof's slopes) to the nearest
    /// half inch or millimetre, as an elevation reads them.
    static func markHeight(_ level: (name: String, z: Int64), units: LengthFormatStyle) -> Length {
        guard level.name == "RIDGE" || level.name == "EAVE" else { return Length(ticks: level.z) }
        let unit = units == .feetInchesFractions ? Length.ticksPerSixtyFourthInch * 32 : Length.ticksPerMillimeter
        return Length(ticks: ((level.z + unit / 2) / unit) * unit)
    }

    /// Level marks that each have room for their label: floors first, then the highest ridge, then the other
    /// ridges and eaves from the top down, each kept only where its label clears every kept one on paper.
    static func spaced(_ levels: [(name: String, z: Int64)], view: ViewTransform) -> [(name: String, z: Int64)] {
        let gap = mmTicks(4)
        func rank(_ level: (name: String, z: Int64)) -> Int {
            level.name == "RIDGE" ? 1 : (level.name == "EAVE" ? 2 : 0)
        }
        let ordered = levels.sorted { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : a.z > b.z
        }
        var kept: [(name: String, z: Int64)] = []
        for level in ordered {
            let y = view.paper(paperPoint(0, level.z)).y.ticks
            guard !kept.contains(where: { abs(view.paper(paperPoint(0, $0.z)).y.ticks - y) < gap }) else { continue }
            kept.append(level)
        }
        return kept.sorted { $0.z < $1.z }
    }
}
