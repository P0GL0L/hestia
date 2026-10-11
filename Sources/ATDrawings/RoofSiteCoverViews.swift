import ATContracts
import Foundation

/// Roof plan: walls below dashed, the eave line, ridge and hip lines, and the pitch of each sloped plane.
///
/// A box footprint is drawn from its own rule. Any other roof is drawn from the engine's roof mesh: the outer
/// eave as the mesh seen from above, every hip, ridge, and valley where the roof's top folds, and each plane's
/// pitch. Without a mesh it draws the footprint and says the planes are not resolved.
enum RoofPlanView {
    static let roofStyle = DisplayStyle(layer: "A-ROOF", pen: .medium)
    static let lineStyle = DisplayStyle(layer: "A-ROOF", pen: .thin)
    static let belowStyle = DisplayStyle(layer: "A-ROOF-OTLN", pen: .fine, pattern: .hidden)
    static let textStyle = DisplayStyle(layer: "A-ANNO-TEXT", pen: .fine)

    /// The roof's footprint box and overhang box, or nil when the footprint is not a box.
    static func boxes(_ roof: Roof) -> (inner: (Int64, Int64, Int64, Int64), outer: (Int64, Int64, Int64, Int64))? {
        let xs = roof.footprint.map(\.x.ticks), ys = roof.footprint.map(\.y.ticks)
        let (x0, x1, y0, y1) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        let isBox = roof.footprint.count == 4 && roof.footprint.allSatisfy {
            ($0.x.ticks == x0 || $0.x.ticks == x1) && ($0.y.ticks == y0 || $0.y.ticks == y1)
        }
        guard isBox else { return nil }
        let o = roof.planes.map(\.overhang.ticks).max() ?? 0
        return ((x0, x1, y0, y1), (x0 - o, x1 + o, y0 - o, y1 + o))
    }

    static func extent(_ document: ModelDocument) -> (min: Point2, max: Point2)? {
        var xs: [Int64] = [], ys: [Int64] = []
        for roof in document.roofs {
            let o = roof.planes.map(\.overhang.ticks).max() ?? 0
            xs += roof.footprint.map { $0.x.ticks - o } + roof.footprint.map { $0.x.ticks + o }
            ys += roof.footprint.map { $0.y.ticks - o } + roof.footprint.map { $0.y.ticks + o }
        }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
        return (paperPoint(x0, y0), paperPoint(x1, y1))
    }

    static func items(_ document: ModelDocument, view: ViewTransform, roofMeshes: [Mesh] = []) -> [DisplayItem] {
        // Several roofs overlap and meet; drawn one by one, each would show its whole outline through the others.
        // Drawn together from above, only what shows is drawn.
        let meshed = Set(roofMeshes.compactMap(\.elementID))
        if document.roofs.count > 1, document.roofs.allSatisfy({ meshed.contains($0.id.rawValue) }) {
            return together(document, view: view, roofMeshes: roofMeshes)
        }
        func at(_ x: Int64, _ y: Int64) -> Point2 { view.paper(paperPoint(x, y)) }
        var items: [DisplayItem] = []
        let roofStoreys = Set(document.roofs.map(\.storeyID))
        for wall in document.walls where roofStoreys.contains(wall.storeyID) {
            items.append(DisplayItem(.line(start: view.paper(wall.start), end: view.paper(wall.end)), style: belowStyle,
                                     elementID: wall.id.rawValue))
        }
        for roof in document.roofs {
            let id = roof.id.rawValue
            guard let (inner, outer) = boxes(roof) else {
                let meshes = roofMeshes.filter { $0.elementID == id }
                if let plan = meshPlan(meshes) {
                    items += plan.eaves.map { outline in
                        DisplayItem(.polyline(points: outline.map { view.paper($0) }, closed: true), style: roofStyle,
                                    elementID: id)
                    }
                    items += plan.folds.map { fold in
                        DisplayItem(.line(start: view.paper(fold.0), end: view.paper(fold.1)), style: lineStyle,
                                    elementID: id)
                    }
                    items += plan.pitches.map { label($0.1, at: view.paper($0.0)) }
                    continue
                }
                // No mesh: draw the footprint and say the planes are not resolved here.
                items.append(DisplayItem(.polyline(points: roof.footprint.map { view.paper($0) }, closed: true),
                                         style: roofStyle, elementID: id))
                let xs = roof.footprint.map(\.x.ticks), ys = roof.footprint.map(\.y.ticks)
                let middle = at((xs.min()! + xs.max()!) / 2, (ys.min()! + ys.max()!) / 2)
                items.append(label(unresolved, at: middle))
                continue
            }
            let (x0, x1, y0, y1) = outer
            items.append(DisplayItem(.polyline(points: [at(x0, y0), at(x1, y0), at(x1, y1), at(x0, y1)], closed: true),
                                     style: roofStyle, elementID: id))
            items.append(DisplayItem(.polyline(points: [at(inner.0, inner.2), at(inner.1, inner.2), at(inner.1, inner.3),
                                                        at(inner.0, inner.3)], closed: true),
                                     style: belowStyle, elementID: id))
            let pitched = roof.planes.compactMap(\.pitchRisePer12).filter { $0.ticks > 0 }
            guard let pitch = pitched.max() else {
                items.append(label("FLAT ROOF", at: at((x0 + x1) / 2, (y0 + y1) / 2)))
                continue
            }
            let gable = roof.planes.contains { $0.pitchRisePer12 == nil }
            let half = min(x1 - x0, y1 - y0) / 2
            let alongX = x1 - x0 >= y1 - y0
            let cy = (y0 + y1) / 2, cx = (x0 + x1) / 2
            let ridge = alongX ? (gable ? (at(x0, cy), at(x1, cy)) : (at(x0 + half, cy), at(x1 - half, cy)))
                               : (gable ? (at(cx, y0), at(cx, y1)) : (at(cx, y0 + half), at(cx, y1 - half)))
            items.append(DisplayItem(.line(start: ridge.0, end: ridge.1), style: lineStyle, elementID: id))
            if !gable {
                let near = ridge.0, far = ridge.1
                for (corner, end) in [(at(x0, y0), near), (at(x0, y1), near), (at(x1, y0), far), (at(x1, y1), far)] {
                    let target = alongX ? end : (corner.y.ticks < at(cx, cy).y.ticks ? near : far)
                    items.append(DisplayItem(.line(start: corner, end: target), style: lineStyle, elementID: id))
                }
            }
            let rise = LengthFormatting.format(pitch, style: .feetInchesFractions)
                .replacingOccurrences(of: "0'-", with: "").replacingOccurrences(of: "\"", with: "")
            let ratio = rise + ":12"
            let quarter = alongX ? (y1 - y0) / 4 : (x1 - x0) / 4
            let slopes = alongX ? [at(cx, y0 + quarter), at(cx, y1 - quarter)] : [at(x0 + quarter, cy), at(x1 - quarter, cy)]
            items += slopes.map { label(ratio, at: $0) }
        }
        return items
    }

    static let unresolved = "ROOF PLANES NOT RESOLVED"
    static let eaveStyle = DisplayStyle(layer: "A-ROOF", pen: .wide)
    static let arrowStyle = DisplayStyle(layer: "A-ANNO-SYMB", pen: .fine)

    /// Seen straight down: h is x, v is y, and nearer is higher.
    static let fromAbove = HiddenLines.View(project: { x, y, z in (x, y, -z) }, toward: (0, 0, 1))

    /// Every roof drawn together from above, as a roof plan is drawn: the eaves wherever a roof's edge shows
    /// against the ground, every ridge, hip, and valley that shows, the lines where one roof runs into another,
    /// nothing hidden under a higher roof; the building's outer walls dashed beneath; and on each sloped plane
    /// that shows, its pitch with an arrow pointing down the slope.
    static func together(_ document: ModelDocument, view: ViewTransform, roofMeshes: [Mesh]) -> [DisplayItem] {
        var items: [DisplayItem] = []
        for outline in SitePlanView.footprint(document) {
            items.append(DisplayItem(.polyline(points: outline.map { view.paper($0) }, closed: true),
                                     style: belowStyle))
        }
        let cell = Double(Length.inches(1).ticks)
        let segments = HiddenLines.segments(roofMeshes, view: fromAbove, cell: cell, tolerance: cell * 2)
        for segment in segments {
            let style = segment.kind == .profile ? eaveStyle : (segment.kind == .outline ? roofStyle : lineStyle)
            let start = view.paper(paperPoint(Int64(segment.start.h.rounded()), Int64(segment.start.v.rounded())))
            let end = view.paper(paperPoint(Int64(segment.end.h.rounded()), Int64(segment.end.v.rounded())))
            items.append(DisplayItem(.line(start: start, end: end), style: style, elementID: segment.elementID))
        }
        // A pitch where its plane is the top of the whole roof, not under another.
        let triangles = HiddenLines.triangles(roofMeshes, view: fromAbove)
        let buffer = HiddenLines.DepthBuffer(triangles, cell: cell * 6)
        for roof in document.roofs {
            let meshes = roofMeshes.filter { $0.elementID == roof.id.rawValue }
            let planes = RoofFolds.planes(of: meshes)
            for plane in planes {
                let slope = (plane.a * plane.a + plane.b * plane.b).squareRoot()
                guard slope > 1e-6, let spot = labelSpot(plane, planes) else { continue }
                let (x, y) = (Double(spot.x.ticks), Double(spot.y.ticks))
                let height = plane.a * x + plane.b * y + plane.c
                guard buffer.at(x, y) >= -height - cell * 6 else { continue }
                let rise = Length(ticks: Int64((slope * Double(Length.inches(12).ticks)).rounded()))
                let at = view.paper(spot)
                items.append(label(ratio(rise), at: at))
                items += slopeArrow(at: at, down: (-plane.a / slope, -plane.b / slope))
            }
        }
        return items
    }

    /// A short arrow beside a pitch, pointing down the slope (`down` a unit plan direction).
    static func slopeArrow(at point: Point2, down: (Double, Double)) -> [DisplayItem] {
        let reach = Double(mmTicks(6)), head = Double(mmTicks(3)) / 2
        let (x, y) = (Double(point.x.ticks), Double(point.y.ticks) - Double(mmTicks(4)))
        let tail = (x - down.0 * reach / 2, y - down.1 * reach / 2)
        let tip = (x + down.0 * reach / 2, y + down.1 * reach / 2)
        func pt(_ p: (Double, Double)) -> Point2 { paperPoint(Int64(p.0.rounded()), Int64(p.1.rounded())) }
        let back = (-down.0, -down.1), side = (-down.1, down.0)
        let left = (tip.0 + (back.0 + side.0 * 0.6) * head, tip.1 + (back.1 + side.1 * 0.6) * head)
        let right = (tip.0 + (back.0 - side.0 * 0.6) * head, tip.1 + (back.1 - side.1 * 0.6) * head)
        return [DisplayItem(.line(start: pt(tail), end: pt(tip)), style: arrowStyle),
                DisplayItem(.line(start: pt(left), end: pt(tip)), style: arrowStyle),
                DisplayItem(.line(start: pt(right), end: pt(tip)), style: arrowStyle)]
    }

    /// A roof drawn from its mesh, in model plan coordinates: the outer eave outlines, the folds (hips, ridges,
    /// and valleys), and a pitch label inside each sloped plane. Nil when there is no upward-facing roof.
    static func meshPlan(_ meshes: [Mesh]) -> (eaves: [[Point2]], folds: [(Point2, Point2)], pitches: [(Point2, String)])? {
        let planes = RoofFolds.planes(of: meshes)
        guard !planes.isEmpty else { return nil }
        // Seen from above, with y standing in for height: the union of the roof's triangles in plan.
        let eaves = MeshSilhouette.outlines(of: meshes) { point in (Double(point.x.ticks), Double(point.y.ticks)) }
        let folds = RoofFolds.folds(planes).map { fold in
            (paperPoint(Int64(fold.x0.rounded()), Int64(fold.y0.rounded())),
             paperPoint(Int64(fold.x1.rounded()), Int64(fold.y1.rounded())))
        }
        var pitches: [(Point2, String)] = []
        for plane in planes {
            let slope: Double = (plane.a * plane.a + plane.b * plane.b).squareRoot()
            guard slope > 1e-6, let spot = labelSpot(plane, planes) else { continue }
            let rise = Length(ticks: Int64((slope * Double(Length.inches(12).ticks)).rounded()))
            pitches.append((spot, ratio(rise)))
        }
        return (eaves, folds, pitches)
    }

    /// Where a plane's pitch goes: the middle of its largest triangle that is on top of the roof.
    static func labelSpot(_ plane: RoofFolds.Plane, _ planes: [RoofFolds.Plane]) -> Point2? {
        var best: (area: Double, x: Double, y: Double)?
        for t in plane.triangles {
            let x: Double = (t[0].x + t[1].x + t[2].x) / 3, y: Double = (t[0].y + t[1].y + t[2].y) / 3
            guard RoofFolds.active(plane, planes, x, y) else { continue }
            let area: Double = abs((t[1].x - t[0].x) * (t[2].y - t[0].y) - (t[2].x - t[0].x) * (t[1].y - t[0].y)) / 2
            if area > (best?.area ?? 0) { best = (area, x, y) }
        }
        return best.map { paperPoint(Int64($0.x.rounded()), Int64($0.y.rounded())) }
    }

    /// A pitch as rise over 12, such as 6:12.
    static func ratio(_ rise: Length) -> String {
        let text = LengthFormatting.format(rise, style: .feetInchesFractions)
            .replacingOccurrences(of: "0'-", with: "").replacingOccurrences(of: "\"", with: "")
        return text + ":12"
    }

    static func label(_ text: String, at point: Point2) -> DisplayItem {
        DisplayItem(.text(position: point, string: text, height: Length(ticks: mmTicks(5) / 2), rotation: .degrees(0),
                          alignment: .center), style: textStyle)
    }
}

/// Site plan: the lot as a property line with the length of each side, the other site areas, the building's
/// footprint hatched (its real outline, traced from its ground-floor walls and rooms), the roofs' outline dashed
/// beyond it, each area's name inside it where it does not collide with another, and a north arrow.
enum SitePlanView {
    static let lineStyle = DisplayStyle(layer: "C-PROP", pen: .medium, pattern: .center)
    static let areaStyle = DisplayStyle(layer: "C-SITE", pen: .thin)
    static let buildingStyle = DisplayStyle(layer: "A-AREA", pen: .heavy)
    static let roofStyle = DisplayStyle(layer: "A-ROOF-OTLN", pen: .thin, pattern: .dashed)

    /// The footprint of every building where it meets the ground: the outline of the walls and rooms of each
    /// building's storey at grade, together, at 3" resolution. Loops wound clockwise are holes, such as a
    /// courtyard.
    static func footprint(_ document: ModelDocument) -> [[Point2]] {
        let atGrade = Set(gradeStoreys(document))
        guard !atGrade.isEmpty else { return [] }
        var shapes: [[Point2]] = document.walls.filter { atGrade.contains($0.storeyID) }.map(wallOutline)
        for room in document.rooms where atGrade.contains(room.storeyID) {
            if let outline = RoomOutline.centerline(of: room, in: document) { shapes.append(outline) }
        }
        return RasterOutline.union(shapes, cell: Length.inches(3).ticks)
    }

    /// Each building's storey at grade: its lowest storey at or above zero, so a basement is passed over, or,
    /// for a building wholly below zero, its highest.
    static func gradeStoreys(_ document: ModelDocument) -> [StoreyID] {
        let buildings: [BuildingID: [Storey]] = Dictionary(grouping: document.storeys, by: \.buildingID)
        var result: [StoreyID] = []
        for storeys in buildings.values {
            let above: [Storey] = storeys.filter { $0.elevation.ticks >= 0 }
            let lowest: Storey? = above.min { $0.elevation.ticks < $1.elevation.ticks }
            if let storey = lowest ?? storeys.max(by: { $0.elevation.ticks < $1.elevation.ticks }) {
                result.append(storey.id)
            }
        }
        return result
    }

    /// A wall's plan rectangle, its centerline offset half its thickness each way.
    static func wallOutline(_ wall: Wall) -> [Point2] {
        let (ax, ay) = (Double(wall.start.x.ticks), Double(wall.start.y.ticks))
        let (bx, by) = (Double(wall.end.x.ticks), Double(wall.end.y.ticks))
        let length = max(((bx - ax) * (bx - ax) + (by - ay) * (by - ay)).squareRoot(), 1)
        let half = Double(wall.thickness.ticks) / 2
        let (nx, ny) = (-(by - ay) / length * half, (bx - ax) / length * half)
        func point(_ x: Double, _ y: Double) -> Point2 { paperPoint(Int64(x.rounded()), Int64(y.rounded())) }
        return [point(ax - nx, ay - ny), point(bx - nx, by - ny), point(bx + nx, by + ny), point(ax + nx, ay + ny)]
    }

    /// The site's extent: the lot and other areas, the building, and the roofs' drip line, with room around.
    static func extent(_ document: ModelDocument, roofMeshes: [Mesh] = []) -> (min: Point2, max: Point2)? {
        var points: [Point2] = footprint(document).flatMap { $0 }
        points += document.terrainPatches.flatMap(\.boundary)
        points += dripLine(document, roofMeshes: roofMeshes).flatMap { $0 }
        guard let x0 = points.map(\.x.ticks).min(), let x1 = points.map(\.x.ticks).max(),
              let y0 = points.map(\.y.ticks).min(), let y1 = points.map(\.y.ticks).max() else { return nil }
        let pad = Length.millimeters(3000).ticks
        return (paperPoint(x0 - pad, y0 - pad), paperPoint(x1 + pad, y1 + pad))
    }

    static let patternStyle = DisplayStyle(layer: "A-AREA-PATT", pen: .extraFine)

    static func items(_ document: ModelDocument, view: ViewTransform, area: PaperRect,
                      units: LengthFormatStyle = .feetInchesFractions, roofMeshes: [Mesh] = []) -> [DisplayItem] {
        var items: [DisplayItem] = []
        var labels: [PaperRect] = []
        let footprints = footprint(document)
        for patch in document.terrainPatches {
            let lot = SiteKindName.isLot(patch.name)
            items.append(DisplayItem(.polyline(points: patch.boundary.map { view.paper($0) }, closed: true),
                                     style: lot ? lineStyle : areaStyle, elementID: patch.id.rawValue))
            if lot {
                items += sideLengths(patch.boundary, view: view, units: units, taken: &labels)
            }
        }
        // The building outlined, every loop, and the drip line dashed. A hole the roof covers is a space inside
        // with no room drawn, and is filled; one open to the sky, a courtyard, is left open.
        let drip = dripLine(document, roofMeshes: roofMeshes)
        let shown = footprints.filter { loop in signedTwiceArea(loop) >= 0 || !covered(loop, by: drip) }
        let paperLoops = shown.map { $0.map { view.paper($0) } }
        for paper in paperLoops {
            items.append(DisplayItem(.polyline(points: paper, closed: true), style: buildingStyle))
        }
        for outline in drip {
            items.append(DisplayItem(.polyline(points: outline.map { view.paper($0) }, closed: true), style: roofStyle))
        }
        // The north arrow first, so no name is set under it. Then names where they have room (LabelSpace),
        // each left out when it has none: the building's first, inside it and out of any courtyard; the hatch
        // then stops short of it, as a drafter masks a name. Then each area's name inside it, clear of
        // everything drawn and of the smaller areas and building within it, the smallest areas first.
        items.append(DisplayItem(.symbol(name: "north-arrow", position: paperPoint(area.maxX - mmTicks(20),
                                                                                    area.maxY - mmTicks(20)),
                                         rotation: .degrees(0), size: .millimeters(16)),
                                 style: DisplayStyle(layer: "A-ANNO-SYMB", pen: .thin)))
        var space = LabelSpace(items, scale: view.scale)
        let courtyards = shown.filter { signedTwiceArea($0) < 0 }
        var name: [DisplayItem] = []
        if let biggest = shown.max(by: { Self.area($0) < Self.area($1) }) {
            name = space.place(labelCandidates(document.project.name.uppercased(), inside: biggest,
                                               avoiding: courtyards, view: view),
                               within: biggest.map { view.paper($0) })
        }
        let masks = DrawingAudit.parts(name, scale: view.scale).labels.map {
            DrawingAudit.inset($0.box, by: -Double(mmTicks(1)))
        }
        var hatch: [DisplayItem] = []
        for (start, end) in hatchLines(paperLoops, spacing: mmTicks(2)) {
            for piece in outside(start, end, masks) {
                hatch.append(DisplayItem(.line(start: piece.0, end: piece.1), style: patternStyle))
            }
        }
        space.add(hatch)
        items += hatch + name
        let patches = document.terrainPatches.sorted { Self.area($0.boundary) < Self.area($1.boundary) }
        for (index, patch) in patches.enumerated() {
            let smaller = patches[..<index].map(\.boundary)
            items += space.place(labelCandidates(patch.name.uppercased(), inside: patch.boundary,
                                                 avoiding: footprints + smaller, view: view),
                                 within: patch.boundary.map { view.paper($0) })
        }
        return items
    }

    /// The roofs' drip line seen from above: the union of the roof meshes' triangles when the engine gives
    /// them, else of each footprint grown by its edges' own overhangs, at 3" resolution.
    static func dripLine(_ document: ModelDocument, roofMeshes: [Mesh]) -> [[Point2]] {
        var shapes: [[Point2]] = []
        for mesh in roofMeshes {
            var corner = 0
            while corner + 2 < mesh.indices.count {
                let indices = mesh.indices[corner..<(corner + 3)].map(Int.init)
                corner += 3
                guard indices.allSatisfy({ $0 < mesh.positions.count }) else { continue }
                shapes.append(indices.map { Point2(x: mesh.positions[$0].x, y: mesh.positions[$0].y) })
            }
        }
        let meshed = Set(roofMeshes.compactMap(\.elementID))
        shapes += document.roofs.filter { !meshed.contains($0.id.rawValue) }.map(roofOutline)
        return RasterOutline.union(shapes, cell: Length.inches(3).ticks)
    }

    /// Whether all of `hole` lies under the `roofs` (loops, even-odd), tested on a 16 by 16 grid of points
    /// inside it: a hole only partly roofed is still open to the sky.
    static func covered(_ hole: [Point2], by roofs: [[Point2]]) -> Bool {
        let hx = hole.map { Double($0.x.ticks) }, hy = hole.map { Double($0.y.ticks) }
        guard let x0 = hx.min(), let x1 = hx.max(), let y0 = hy.min(), let y1 = hy.max() else { return false }
        let loops = roofs.map { roof in (roof.map { Double($0.x.ticks) }, roof.map { Double($0.y.ticks) }) }
        var tested = 0
        for row in 0..<16 {
            for column in 0..<16 {
                let x = x0 + (x1 - x0) * (Double(column) + 0.5) / 16, y = y0 + (y1 - y0) * (Double(row) + 0.5) / 16
                guard RasterOutline.inside(x, y, hx, hy) else { continue }
                tested += 1
                let under = loops.filter { RasterOutline.inside(x, y, $0.0, $0.1) }.count
                if under % 2 == 0 { return false }
            }
        }
        return tested > 0
    }

    /// A roof's footprint with each edge moved out by its own plane's overhang, the corners mitred: the drip
    /// line, for engines that give no roof mesh. Footprints wound either way grow outward.
    static func roofOutline(_ roof: Roof) -> [Point2] {
        let points = roof.footprint.map { (x: Double($0.x.ticks), y: Double($0.y.ticks)) }
        let count = points.count
        guard count >= 3 else { return roof.footprint }
        let turn: Double = signedTwiceArea(roof.footprint) < 0 ? -1 : 1
        // Each edge's line moved outward: a point on it and its direction.
        let lines = (0..<count).map { index -> (x: Double, y: Double, dx: Double, dy: Double) in
            let (a, b) = (points[index], points[(index + 1) % count])
            let length = max(((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot(), 1e-9)
            let (dx, dy) = ((b.x - a.x) / length, (b.y - a.y) / length)
            let grow = Double(index < roof.planes.count ? roof.planes[index].overhang.ticks : 0)
            return (a.x + dy * grow * turn, a.y - dx * grow * turn, dx, dy)
        }
        return (0..<count).map { index in
            let (p, q) = (lines[(index + count - 1) % count], lines[index])
            let cross = p.dx * q.dy - p.dy * q.dx
            // Edges in line: the moved corner is simply on the moved line.
            guard abs(cross) > 1e-9 else { return paperPoint(Int64(q.x.rounded()), Int64(q.y.rounded())) }
            let t = ((q.x - p.x) * q.dy - (q.y - p.y) * q.dx) / cross
            return paperPoint(Int64((p.x + p.dx * t).rounded()), Int64((p.y + p.dy * t).rounded()))
        }
    }

    static func signedTwiceArea(_ points: [Point2]) -> Double {
        var twice = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            twice += Double(a.x.ticks) * Double(b.y.ticks) - Double(b.x.ticks) * Double(a.y.ticks)
        }
        return twice
    }

    /// 45° hatch lines `spacing` apart over the area the loops enclose, even-odd, so holes stay open.
    static func hatchLines(_ loops: [[Point2]], spacing: Int64) -> [(Point2, Point2)] {
        // In a frame turned 45°, the lines run along u at fixed v.
        let root = 0.5.squareRoot()
        func turned(_ p: Point2) -> (u: Double, v: Double) {
            let (x, y) = (Double(p.x.ticks), Double(p.y.ticks))
            return ((x + y) * root, (y - x) * root)
        }
        func back(_ u: Double, _ v: Double) -> Point2 {
            paperPoint(Int64(((u - v) * root).rounded()), Int64(((u + v) * root).rounded()))
        }
        let edges = loops.flatMap { loop in
            loop.indices.map { (turned(loop[$0]), turned(loop[($0 + 1) % loop.count])) }
        }
        let vs = edges.flatMap { [$0.0.v, $0.1.v] }
        guard spacing > 0, let v0 = vs.min(), let v1 = vs.max() else { return [] }
        var lines: [(Point2, Point2)] = []
        var v = (v0 / Double(spacing)).rounded(.up) * Double(spacing)
        while v < v1 {
            let crossings = edges.compactMap { a, b -> Double? in
                guard (a.v > v) != (b.v > v) else { return nil }
                return a.u + (b.u - a.u) * (v - a.v) / (b.v - a.v)
            }.sorted()
            for pair in stride(from: 0, to: crossings.count - 1, by: 2) {
                lines.append((back(crossings[pair], v), back(crossings[pair + 1], v)))
            }
            v += Double(spacing)
        }
        return lines
    }

    static func area(_ points: [Point2]) -> Double {
        var twice = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            twice += Double(a.x.ticks) * Double(b.y.ticks) - Double(b.x.ticks) * Double(a.y.ticks)
        }
        return abs(twice) / 2
    }

    /// The length of each side of the lot, written along it just outside, each label's box added to `taken`.
    static func sideLengths(_ boundary: [Point2], view: ViewTransform, units: LengthFormatStyle,
                            taken: inout [PaperRect]) -> [DisplayItem] {
        let style = DisplayStyle(layer: "C-PROP-IDEN", pen: .fine)
        let height = Double(mmTicks(5) / 2)
        // Outward is to the right of each side for a counterclockwise lot, to the left for a clockwise one.
        let outward: Double = signedTwiceArea(boundary.map { view.paper($0) }) >= 0 ? 1 : -1
        var items: [DisplayItem] = []
        for index in boundary.indices {
            let a = boundary[index], b = boundary[(index + 1) % boundary.count]
            let (dx, dy) = (Double(b.x.ticks - a.x.ticks), Double(b.y.ticks - a.y.ticks))
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { continue }
            let (pa, pb) = (view.paper(a), view.paper(b))
            let (px, py) = (Double(pb.x.ticks - pa.x.ticks), Double(pb.y.ticks - pa.y.ticks))
            let paperLength = max((px * px + py * py).squareRoot(), 1)
            var angle = atan2(py, px) * 180 / .pi
            if angle > 90 || angle <= -90 { angle += 180 }
            // The text's middle a text height and a half off the line, outside the lot.
            let (nx, ny) = (py / paperLength * outward, -px / paperLength * outward)
            let off = height * 1.5
            let mx = Double(pa.x.ticks + pb.x.ticks) / 2 + nx * off
            let my = Double(pa.y.ticks + pb.y.ticks) / 2 + ny * off
            let text = LengthFormatting.format(Length(ticks: Int64(length.rounded())), style: units)
            // Its baseline sits below its middle by half its height, across the text's own direction.
            let radians = angle * .pi / 180
            let (ux, uy) = (cos(radians), sin(radians))
            let base = (x: mx + uy * height / 2, y: my - ux * height / 2)
            let width = height * 0.85 * Double(text.count)
            let reach = (x: abs(ux) * width / 2 + abs(uy) * height / 2, y: abs(uy) * width / 2 + abs(ux) * height / 2)
            // At the side's middle, else further along it either way, else further out; a label with nowhere
            // clear of the others is left out rather than printed over one.
            let (sx, sy) = (px / paperLength, py / paperLength)
            let room = max(paperLength / 2 - reach.x - reach.y, 0)
            let moves: [(along: Double, out: Double)] = [(0, 0), (-room / 2, 0), (room / 2, 0), (-room, 0),
                                                         (room, 0), (0, height * 1.5), (-room / 2, height * 1.5),
                                                         (room / 2, height * 1.5)]
            for move in moves {
                let cx = mx + sx * move.along + nx * move.out, cy = my + sy * move.along + ny * move.out
                let rect = PaperRect(minX: Int64(cx - reach.x), minY: Int64(cy - reach.y), width: Int64(reach.x * 2),
                                     height: Int64(reach.y * 2))
                guard !taken.contains(where: { $0.intersects(rect) }) else { continue }
                taken.append(rect)
                let shift = (x: sx * move.along + nx * move.out, y: sy * move.along + ny * move.out)
                let at = paperPoint(Int64((base.x + shift.x).rounded()), Int64((base.y + shift.y).rounded()))
                items.append(DisplayItem(.text(position: at, string: text, height: Length(ticks: mmTicks(5) / 2),
                                               rotation: Angle(microDegrees: Int64((angle * 1_000_000).rounded())),
                                               alignment: .center), style: style))
                break
            }
        }
        return items
    }

    /// A name at points across an area, nearest its middle first, at the site plan's text size and then
    /// smaller, leaving out points inside any of the `avoiding` areas.
    static func labelCandidates(_ name: String, inside boundary: [Point2], avoiding: [[Point2]],
                                view: ViewTransform) -> [[DisplayItem]] {
        let paper = boundary.map { view.paper($0) }
        let xs = paper.map { Double($0.x.ticks) }, ys = paper.map { Double($0.y.ticks) }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return [] }
        let obstacles = avoiding.map { area in
            (area.map { Double(view.paper($0).x.ticks) }, area.map { Double(view.paper($0).y.ticks) })
        }
        var points: [(x: Double, y: Double)] = []
        for row in 1..<24 {
            for column in 1..<24 {
                let x = x0 + (x1 - x0) * Double(column) / 24, y = y0 + (y1 - y0) * Double(row) / 24
                guard RasterOutline.inside(x, y, xs, ys),
                      !obstacles.contains(where: { RasterOutline.inside(x, y, $0.0, $0.1) }) else { continue }
                points.append((x, y))
            }
        }
        let (mx, my) = ((x0 + x1) / 2, (y0 + y1) / 2)
        points.sort { abs($0.x - mx) + abs($0.y - my) < abs($1.x - mx) + abs($1.y - my) }
        let large = points.map { point in
            [RoofPlanView.label(name, at: paperPoint(Int64(point.x), Int64(point.y - Double(mmTicks(1)))))]
        }
        let small = points.map { point in
            [DisplayItem(.text(position: paperPoint(Int64(point.x), Int64(point.y - Double(mmTicks(1)))),
                               string: name, height: .millimeters(2), rotation: .degrees(0), alignment: .center),
                         style: RoofPlanView.textStyle)]
        }
        return large + small
    }

    /// The parts of a line from `a` to `b` outside every box.
    static func outside(_ a: Point2, _ b: Point2, _ boxes: [DrawingAudit.Box]) -> [(Point2, Point2)] {
        var pieces: [(Double, Double)] = [(0, 1)]
        let (ax, ay) = (Double(a.x.ticks), Double(a.y.ticks)), (bx, by) = (Double(b.x.ticks), Double(b.y.ticks))
        for box in boxes {
            // The stretch of the line, as shares from a to b, inside this box.
            guard let inside = DrawingAudit.clip((ax, ay), (bx, by), box) else { continue }
            pieces = pieces.flatMap { piece -> [(Double, Double)] in
                [(piece.0, min(piece.1, inside.0)), (max(piece.0, inside.1), piece.1)].filter { $0.1 - $0.0 > 1e-6 }
            }
        }
        func at(_ t: Double) -> Point2 {
            paperPoint(Int64((ax + (bx - ax) * t).rounded()), Int64((ay + (by - ay) * t).rounded()))
        }
        return pieces.map { (at($0.0), at($0.1)) }
    }
}

extension PaperRect {
    func intersects(_ other: PaperRect) -> Bool {
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
    }
}

/// Which site areas are the lot: named "Lot" or "Lot" and a number, as the app names them.
enum SiteKindName {
    static func isLot(_ name: String) -> Bool {
        let words = name.split(separator: " ")
        guard words.first?.lowercased() == "lot" else { return false }
        return words.count == 1 || (words.count == 2 && Int(words[1]) != nil)
    }
}

/// Cover sheet: project name, the sheet index, and the schematic-only notes.
enum CoverSheet {
    static let notes = [
        "SCHEMATIC DESIGN DRAWINGS ONLY. NOT FOR CONSTRUCTION. NOT A PERMIT SET.",
        "These drawings are not engineered and are not sealed by a licensed professional.",
        "Verify all dimensions and conditions on site before any work.",
        "Structure, framing, and services shown are indicative only.",
    ]

    static func items(project: String, index: [Sheet], in area: PaperRect) -> [DisplayItem] {
        let left = area.minX + mmTicks(10)
        var y = area.maxY - mmTicks(20)
        let title = DisplayStyle(layer: "A-ANNO-TEXT", pen: .wide)
        let body = DisplayStyle(layer: "A-ANNO-TEXT", pen: .fine)
        var items = [DisplayItem(.text(position: paperPoint(left, y), string: project.uppercased(),
                                       height: .millimeters(10), rotation: .degrees(0), alignment: .left), style: title)]
        y -= mmTicks(25)
        items.append(DisplayItem(.text(position: paperPoint(left, y), string: "SHEET INDEX", height: .millimeters(4),
                                       rotation: .degrees(0), alignment: .left), style: title))
        for sheet in index {
            y -= mmTicks(8)
            items.append(DisplayItem(.text(position: paperPoint(left, y), string: sheet.number, height: .millimeters(3),
                                           rotation: .degrees(0), alignment: .left), style: body))
            items.append(DisplayItem(.text(position: paperPoint(left + mmTicks(30), y), string: sheet.title,
                                           height: .millimeters(3), rotation: .degrees(0), alignment: .left), style: body))
        }
        y -= mmTicks(20)
        items.append(DisplayItem(.text(position: paperPoint(left, y), string: "GENERAL NOTES", height: .millimeters(4),
                                       rotation: .degrees(0), alignment: .left), style: title))
        for (number, note) in notes.enumerated() {
            y -= mmTicks(8)
            items.append(DisplayItem(.text(position: paperPoint(left, y), string: "\(number + 1). \(note)",
                                           height: .millimeters(3), rotation: .degrees(0), alignment: .left), style: body))
        }
        return items + legend(at: paperPoint(area.minX + area.width / 2, area.maxY - mmTicks(45)))
    }

    /// What the abbreviations on the drawings stand for, in the order a reader looks them up.
    static let abbreviations: [(String, String)] = [
        ("AFF", "Above finished floor"), ("CLG", "Ceiling"), ("DN", "Down"), ("EQ", "Equal"),
        ("FF", "Finished floor"), ("MECH", "Mechanical"), ("NTS", "Not to scale"), ("SF", "Square feet"),
        ("TYP", "Typical"), ("UP", "Up"), ("WC", "Water closet"), ("WIC", "Walk-in closet"),
    ]

    /// The symbols the plans and elevations use, each drawn small beside what it means, then the
    /// abbreviations; its top left at `origin`.
    static func legend(at origin: Point2) -> [DisplayItem] {
        let title = DisplayStyle(layer: "A-ANNO-TEXT", pen: .wide)
        let body = DisplayStyle(layer: "A-ANNO-TEXT", pen: .fine)
        let wall = DisplayStyle(layer: "A-ANNO-SYMB", pen: .wide)
        let thin = DisplayStyle(layer: "A-ANNO-SYMB", pen: .thin)
        let (x, top) = (origin.x.ticks, origin.y.ticks)
        func text(_ string: String, _ dx: Int64, _ dy: Int64, height: Double = 3, style: DisplayStyle) -> DisplayItem {
            DisplayItem(.text(position: paperPoint(x + dx, top - dy), string: string,
                              height: .millimeters(Int64(height)), rotation: .degrees(0), alignment: .left),
                        style: style)
        }
        func line(_ x0: Int64, _ y0: Int64, _ x1: Int64, _ y1: Int64, _ style: DisplayStyle) -> DisplayItem {
            DisplayItem(.line(start: paperPoint(x + x0, top - y0), end: paperPoint(x + x1, top - y1)), style: style)
        }
        let column = mmTicks(30)
        var items = [text("SYMBOLS", 0, 0, height: 4, style: title)]
        // An exterior wall: two lines with the wall hatch between.
        var row = mmTicks(12)
        items.append(DisplayItem(.hatch(boundary: [paperPoint(x, top - row), paperPoint(x + mmTicks(20), top - row),
                                                   paperPoint(x + mmTicks(20), top - row - mmTicks(3)),
                                                   paperPoint(x, top - row - mmTicks(3))],
                                        pattern: .diagonal, spacing: .millimeters(1), angle: .degrees(45)),
                                 style: thin))
        items += [line(0, row, mmTicks(20), row, wall), line(0, row + mmTicks(3), mmTicks(20), row + mmTicks(3), wall),
                  text("Wall, cut in plan", column, row + mmTicks(2), style: body)]
        // A door: its leaf drawn open and the arc it swings through, with its mark.
        row += mmTicks(14)
        items += [line(0, row, mmTicks(4), row, wall), line(mmTicks(14), row, mmTicks(20), row, wall),
                  line(mmTicks(4), row, mmTicks(4), row - mmTicks(10), thin)]
        items.append(DisplayItem(.arc(center: paperPoint(x + mmTicks(4), top - row), radius: .millimeters(10),
                                      start: .degrees(0), sweep: .degrees(90)), style: thin))
        items.append(text("Door and its swing; D1 is its mark in the door schedule", column, row, style: body))
        // A window: glass lines in the wall, with its mark.
        row += mmTicks(12)
        items += [line(0, row, mmTicks(20), row, wall), line(0, row + mmTicks(3), mmTicks(20), row + mmTicks(3), wall),
                  line(mmTicks(4), row + mmTicks(3) / 2, mmTicks(16), row + mmTicks(3) / 2, thin),
                  text("Window; W1 is its mark in the window schedule", column, row + mmTicks(2), style: body)]
        // A stair, rising in the direction of its arrow.
        row += mmTicks(12)
        items += [line(0, row, mmTicks(16), row, thin), line(mmTicks(16), row, mmTicks(13), row - mmTicks(2), thin),
                  line(mmTicks(16), row, mmTicks(13), row + mmTicks(2), thin), text("UP", mmTicks(17), row + mmTicks(1),
                                                                                   style: body),
                  text("Stair, rising the way the arrow points", column, row + mmTicks(1), style: body)]
        // North, as on the site plan.
        row += mmTicks(14)
        items.append(DisplayItem(.symbol(name: "north-arrow", position: paperPoint(x + mmTicks(8), top - row),
                                         rotation: .degrees(0), size: .millimeters(10)), style: thin))
        items.append(text("North", column, row, style: body))
        row += mmTicks(20)
        items.append(text("ABBREVIATIONS", 0, row, height: 4, style: title))
        for (short, long) in abbreviations {
            row += mmTicks(7)
            items += [text(short, 0, row, style: body), text(long, mmTicks(20), row, style: body)]
        }
        return items
    }
}

extension SheetFrame {
    static func center(of points: [Point2]) -> Point2 {
        let xs = points.map(\.x.ticks), ys = points.map(\.y.ticks)
        return paperPoint((xs.min()! + xs.max()!) / 2, (ys.min()! + ys.max()!) / 2)
    }
}
