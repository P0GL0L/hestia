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
    /// With `room`, the view's area on the sheet, pitch figures stay inside it, clear of the views around it.
    static func meshItems(_ document: ModelDocument, _ direction: ElevationDirection, view: ViewTransform,
                          meshes: [Mesh], roofMeshes: [Mesh], room: PaperRect? = nil) -> [DisplayItem] {
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
        return items + pitchMarks(document, segments: segments, view: view, drawn: items, within: room?.corners())
    }

    static let pitchStyle = DisplayStyle(layer: "A-ELEV-ANNO", pen: .fine)

    /// A pitch triangle on each pitched roof's drawn slope, as elevations mark them: a small right triangle just
    /// above a sloped roof line this view actually shows, its long side parallel to it, "12" over its level leg
    /// and the rise beside its upright one. The line must be one of the roof's visible edges and run at one of
    /// its planes' pitches; the triangle goes a third, a quarter, or half the way along it where it clears the
    /// drawing (`LabelSpace`) and its figures stay `within` the given paper polygon, and each roof is marked
    /// once per pitch.
    static func pitchMarks(_ document: ModelDocument, segments: [HiddenLines.Segment], view: ViewTransform,
                           drawn: [DisplayItem], within: [Point2]? = nil) -> [DisplayItem] {
        var space = LabelSpace(drawn, scale: view.scale)
        var items: [DisplayItem] = []
        let twelve = Double(Length.inches(12).ticks)
        for roof in document.roofs {
            let rises = Set(roof.planes.compactMap(\.pitchRisePer12).filter { $0.ticks > 0 })
                .sorted(by: { $0.ticks < $1.ticks })
            /// Hidden-line clipping can leave fractional endpoints on the same source edge. Convert that edge's
            /// slope back to rise per 12 and allow only one drawing tick of numerical/mesh rounding, then assign
            /// it to the nearest stored pitch so nearby distinct pitches can never claim the same visible edge.
            func matchedRise(_ segment: HiddenLines.Segment) -> Length? {
                let run = abs(segment.end.h - segment.start.h)
                guard run > 0 else { return nil }
                let actual = abs(segment.end.v - segment.start.v) / run * twelve
                guard let nearest = rises.min(by: {
                    abs(Double($0.ticks) - actual) < abs(Double($1.ticks) - actual)
                }), abs(Double(nearest.ticks) - actual) <= 1 else { return nil }
                return nearest
            }
            for rise in rises {
                let slope = Double(rise.ticks) / twelve
                var candidates: [[DisplayItem]] = []
                for segment in segments where segment.elementID == roof.id.rawValue && matchedRise(segment) == rise {
                    let (a, b) = segment.start.h <= segment.end.h ? (segment.start, segment.end)
                        : (segment.end, segment.start)
                    let run = b.h - a.h
                    guard run > 0 else { continue }
                    let low = b.v >= a.v ? a : b, high = b.v >= a.v ? b : a
                    let paperLength = Double(view.paper(Length(ticks: Int64(hypot(run, b.v - a.v)))).ticks)
                    guard paperLength >= Double(mmTicks(15)) else { continue }
                    let uphill: Double = high.h > low.h ? 1 : -1
                    for share in [1.0 / 3, 0.25, 0.5] {
                        let h = low.h + (high.h - low.h) * share, v = low.v + (high.v - low.v) * share
                        candidates.append(pitchTriangle(at: view.paper(paperPoint(Int64(h.rounded()),
                                                                                     Int64(v.rounded()))),
                                                        uphill: uphill, slope: slope, rise: rise,
                                                        elementID: roof.id.rawValue))
                    }
                }
                items += space.place(candidates, within: within, strictStrokes: true)
            }
        }
        return items
    }

    /// The triangle and its two figures, standing 2 mm above the roof line at `point`: its long side runs
    /// uphill (`uphill` 1 to the right, -1 to the left) at the roof's `slope`, its level leg across the top
    /// with "12" over it, and its upright leg at the downhill end with the rise beside it.
    static func pitchTriangle(at point: Point2, uphill: Double, slope: Double, rise: Length, elementID: UUID)
        -> [DisplayItem] {
        let leg = Double(mmTicks(7))
        let low = (x: Double(point.x.ticks), y: Double(point.y.ticks) + Double(mmTicks(2)))
        let high = (x: low.x + uphill * leg, y: low.y + leg * slope)
        let corner = (x: low.x, y: high.y)
        func p(_ x: Double, _ y: Double) -> Point2 { paperPoint(Int64(x.rounded()), Int64(y.rounded())) }
        let inches = Double(rise.ticks) / Double(Length.inches(1).ticks)
        let figure = inches == inches.rounded() ? String(Int(inches)) : String(format: "%.1f", inches)
        let gap = Double(mmTicks(1))
        return [
            DisplayItem(.polyline(points: [p(low.x, low.y), p(high.x, high.y), p(corner.x, corner.y)], closed: true),
                        style: pitchStyle, elementID: elementID),
            DisplayItem(.text(position: p((low.x + high.x) / 2, high.y + gap), string: "12",
                              height: .millimeters(2), rotation: .degrees(0), alignment: .center),
                        style: pitchStyle, elementID: elementID),
            DisplayItem(.text(position: p(low.x - uphill * gap, (low.y + high.y) / 2 - gap), string: figure,
                              height: .millimeters(2), rotation: .degrees(0), alignment: uphill > 0 ? .right : .left),
                        style: pitchStyle, elementID: elementID),
        ]
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
