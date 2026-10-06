import ATContracts
import Foundation

/// Schematic building section along a sheet's section line, looking to the left of start → end.
///
/// Section coordinates are (distance along the line from its start, elevation). When the geometry engine
/// returns a cut, that is drawn. Otherwise the section is built from the model: walls the line crosses are cut
/// (with any opening at the cut), slabs are cut where the line passes over them, box-footprint roofs are cut
/// to their pitched profile rising from the outer eave, and the nearest parallel walls beyond are drawn light. Schematic only.
enum SectionView {
    static let cutStyle = DisplayStyle(layer: "A-SECT-MCUT", pen: .heavy)
    static let hatchStyle = DisplayStyle(layer: "A-SECT-PATT", pen: .extraFine)
    static let beyondStyle = DisplayStyle(layer: "A-SECT-BYND", pen: .thin)
    static let roofThickness = Length.millimeters(250).ticks

    struct Line {
        var sx: Double, sy: Double, ux: Double, uy: Double, length: Double

        init(_ line: SectionLine) {
            sx = Double(line.start.x.ticks)
            sy = Double(line.start.y.ticks)
            let dx = Double(line.end.x.ticks) - sx, dy = Double(line.end.y.ticks) - sy
            length = (dx * dx + dy * dy).squareRoot()
            ux = length > 0 ? dx / length : 1
            uy = length > 0 ? dy / length : 0
        }

        /// (distance along, distance to the left) of a plan point.
        func local(_ x: Double, _ y: Double) -> (along: Double, left: Double) {
            let (rx, ry) = (x - sx, y - sy)
            return (rx * ux + ry * uy, -rx * uy + ry * ux)
        }
    }

    // MARK: - Engine output

    static func extent(_ outlines: [ClassifiedOutline]) -> (min: Point2, max: Point2)? {
        let points = outlines.flatMap(\.polygon)
        guard let x0 = points.map(\.x.ticks).min(), let x1 = points.map(\.x.ticks).max(),
              let y0 = points.map(\.y.ticks).min(), let y1 = points.map(\.y.ticks).max() else { return nil }
        return (paperPoint(x0, y0), paperPoint(x1, y1))
    }

    static func items(_ outlines: [ClassifiedOutline], view: ViewTransform) -> [DisplayItem] {
        outlines.flatMap { outline -> [DisplayItem] in
            let polygon = outline.polygon.map { view.paper($0) }
            guard outline.classification == .cut else {
                return [DisplayItem(.polyline(points: polygon, closed: true), style: beyondStyle,
                                    elementID: outline.elementID)]
            }
            return [
                DisplayItem(.hatch(boundary: polygon, pattern: outline.kind == .slab ? .concrete : .diagonal,
                                   spacing: .millimeters(1), angle: .degrees(45)), style: hatchStyle,
                            elementID: outline.elementID),
                DisplayItem(.polyline(points: polygon, closed: true), style: cutStyle, elementID: outline.elementID),
            ]
        }
    }

    // MARK: - Model-based schematic cut

    /// Cut and beyond outlines from the model, in section coordinates.
    static func modelOutlines(_ document: ModelDocument, along section: SectionLine) -> [ClassifiedOutline] {
        let line = Line(section)
        guard line.length > 0 else { return [] }
        let elevations = Dictionary(uniqueKeysWithValues: document.storeys.map { ($0.id, $0.elevation.ticks) })
        var outlines: [ClassifiedOutline] = []
        var beyond: [(depth: Double, base: Int64, outline: ClassifiedOutline, range: (Int64, Int64))] = []
        for wall in document.walls {
            let base = elevations[wall.storeyID] ?? 0
            let a = line.local(Double(wall.start.x.ticks), Double(wall.start.y.ticks))
            let b = line.local(Double(wall.end.x.ticks), Double(wall.end.y.ticks))
            let half = Double(wall.thickness.ticks) / 2
            if (a.left > 0) != (b.left > 0), a.left != b.left {
                // The line crosses the wall's centerline: cut it.
                let t = a.left / (a.left - b.left)
                let along = a.along + (b.along - a.along) * t
                guard along >= 0, along <= line.length else { continue }
                let wallLength = hypot(b.along - a.along, b.left - a.left)
                let sine = max(abs(b.left - a.left) / max(wallLength, 1), 0.05)
                let width = half / sine
                let x0 = Int64((along - width).rounded()), x1 = Int64((along + width).rounded())
                let atWall = Int64((t * wallLength).rounded())
                let opening = document.openings.first {
                    $0.wallID == wall.id && $0.offsetAlongWall.ticks <= atWall
                        && atWall <= $0.offsetAlongWall.ticks + $0.width.ticks
                }
                var bands: [(Int64, Int64)] = [(base, base + wall.height.ticks)]
                if let opening {
                    let sill = base + opening.sillHeight.ticks
                    bands = [(base, sill), (sill + opening.height.ticks, base + wall.height.ticks)].filter { $0.0 < $0.1 }
                }
                for (z0, z1) in bands {
                    outlines.append(ClassifiedOutline(elementID: wall.id.rawValue, kind: .wall, classification: .cut,
                                                      polygon: box(x0, x1, z0, z1)))
                }
            } else if abs(a.left - b.left) < 1, a.left > half {
                // Parallel to the line and behind it: a candidate for the view beyond.
                let x0 = Int64(min(a.along, b.along).rounded()), x1 = Int64(max(a.along, b.along).rounded())
                let outline = ClassifiedOutline(elementID: wall.id.rawValue, kind: .wall, classification: .beyond,
                                                polygon: box(x0, x1, base, base + wall.height.ticks))
                beyond.append((a.left, base, outline, (x0, x1)))
            }
        }
        var covered: [Int64: [(Int64, Int64)]] = [:]
        for candidate in beyond.sorted(by: { $0.depth < $1.depth }) {
            let visible = ElevationView.subtract([candidate.range], covered[candidate.base] ?? [])
            guard !visible.isEmpty else { continue }
            covered[candidate.base, default: []].append(candidate.range)
            outlines.append(candidate.outline)
        }
        for slab in document.slabs {
            let base = elevations[slab.storeyID] ?? 0
            let top = base + slab.topOffset.ticks
            for (x0, x1) in crossings(of: slab.outline, line: line) {
                outlines.append(ClassifiedOutline(elementID: slab.id.rawValue, kind: .slab, classification: .cut,
                                                  polygon: box(x0, x1, top - slab.thickness.ticks, top)))
            }
        }
        for roof in document.roofs {
            if let profile = roofProfile(roof, base: elevations[roof.storeyID] ?? 0, line: line) {
                outlines.append(ClassifiedOutline(elementID: roof.id.rawValue, kind: .roof, classification: .cut,
                                                  polygon: profile))
            }
        }
        return outlines
    }

    static func box(_ x0: Int64, _ x1: Int64, _ z0: Int64, _ z1: Int64) -> [Point2] {
        [paperPoint(x0, z0), paperPoint(x1, z0), paperPoint(x1, z1), paperPoint(x0, z1)]
    }

    /// Intervals along the line that lie inside a polygon.
    static func crossings(of polygon: [Point2], line: Line) -> [(Int64, Int64)] {
        var hits: [Double] = []
        for (p, q) in zip(polygon, polygon.dropFirst() + polygon.prefix(1)) {
            let a = line.local(Double(p.x.ticks), Double(p.y.ticks))
            let b = line.local(Double(q.x.ticks), Double(q.y.ticks))
            if (a.left > 0) != (b.left > 0) {
                hits.append(a.along + (b.along - a.along) * a.left / (a.left - b.left))
            }
        }
        hits.sort()
        return stride(from: 0, to: hits.count - 1, by: 2).compactMap { i in
            let x0 = max(hits[i], 0), x1 = min(hits[i + 1], line.length)
            return x0 < x1 ? (Int64(x0.rounded()), Int64(x1.rounded())) : nil
        }
    }

    /// The cut through a box-footprint roof: top surface from the edge pitches, a uniform thickness below.
    static func roofProfile(_ roof: Roof, base: Int64, line: Line) -> [Point2]? {
        guard let (_, outer) = RoofPlanView.boxes(roof) else { return nil }
        let outerBox = [paperPoint(outer.0, outer.2), paperPoint(outer.1, outer.2), paperPoint(outer.1, outer.3),
                        paperPoint(outer.0, outer.3)]
        guard let (start, end) = crossings(of: outerBox, line: line).first else { return nil }
        let eave = Double(base + roof.eaveHeight.ticks)
        let twelve = Double(Length.inches(12).ticks)
        // Height over a point: the lowest of the pitched planes, each rising inward from its outer eave (the
        // footprint edge pushed out by its overhang), the same rule the elevation uses. The footprint is
        // counterclockwise, so the inside of each edge is on its left.
        let footprint = roof.footprint.map { (Double($0.x.ticks), Double($0.y.ticks)) }
        func height(at along: Double) -> Double {
            let x = line.sx + line.ux * along, y = line.sy + line.uy * along
            var lowest: Double?
            for (index, plane) in roof.planes.enumerated() where index < footprint.count {
                guard let pitch = plane.pitchRisePer12 else { continue }
                let (ax, ay) = footprint[index]
                let (bx, by) = footprint[(index + 1) % footprint.count]
                let length = max(hypot(bx - ax, by - ay), 1)
                let inside = ((bx - ax) * (y - ay) - (by - ay) * (x - ax)) / length + Double(plane.overhang.ticks)
                let z = eave + inside * Double(pitch.ticks) / twelve
                lowest = min(lowest ?? z, z)
            }
            return lowest ?? eave
        }
        let samples = 48
        let top = (0...samples).map { i -> Point2 in
            let along = Double(start) + Double(end - start) * Double(i) / Double(samples)
            return paperPoint(Int64(along.rounded()), Int64(height(at: along).rounded()))
        }
        let bottom = top.reversed().map { Point2(x: $0.x, y: Length(ticks: $0.y.ticks - roofThickness)) }
        return top + bottom
    }

    /// Ground line and level marks under and beside a section.
    static func annotations(_ document: ModelDocument, extent: (min: Point2, max: Point2), view: ViewTransform,
                            imperial: Bool) -> [DisplayItem] {
        let reach = Length.millimeters(1500).ticks
        let grade = document.storeys.map(\.elevation.ticks).min() ?? 0
        func at(_ x: Int64, _ z: Int64) -> Point2 { view.paper(paperPoint(x, z)) }
        var items = [DisplayItem(.line(start: at(extent.min.x.ticks - reach, grade),
                                       end: at(extent.max.x.ticks + reach, grade)), style: ElevationView.groundStyle)]
        for storey in document.storeys {
            let z = storey.elevation.ticks
            let mark = at(extent.max.x.ticks + reach / 3, z)
            items.append(DisplayItem(.line(start: mark, end: at(extent.max.x.ticks + reach, z)),
                                     style: ElevationView.levelStyle))
            items.append(DisplayItem(
                .text(position: Point2(x: mark.x, y: Length(ticks: mark.y.ticks + mmTicks(1))),
                      string: "\(storey.name.uppercased()) "
                        + LengthFormatting.format(storey.elevation, style: imperial ? .feetInchesFractions : .metric),
                      height: .millimeters(2), rotation: .degrees(0), alignment: .left),
                style: ElevationView.levelStyle))
        }
        return items
    }
}
