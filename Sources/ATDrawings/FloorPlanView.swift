import ATContracts
import Foundation

/// Schematic floor plan: cut walls with hatching, door swings, window symbols, stairs, and room tags with area.
enum FloorPlanView {
    /// Cut walls: the house's outside walls heaviest, as blueprints draw them, and inside walls a weight down.
    static let wallStyle = DisplayStyle(layer: "A-WALL", pen: .heavy)
    static let interiorWallStyle = DisplayStyle(layer: "A-WALL", pen: .medium)
    static let beyondStyle = DisplayStyle(layer: "A-WALL", pen: .thin)
    static let hatchStyle = DisplayStyle(layer: "A-WALL-PATT", pen: .extraFine)
    static let doorStyle = DisplayStyle(layer: "A-DOOR", pen: .thin)
    static let glazingStyle = DisplayStyle(layer: "A-GLAZ", pen: .thin)
    /// A window wholly above the plan cut is seen beyond it, so it is drawn dashed.
    static let glazingAboveStyle = DisplayStyle(layer: "A-GLAZ", pen: .thin, pattern: .dashed)
    /// The height the plan is cut at: 4'-0" above the floor, the geometry engine's plan cut.
    static let planCut: Length = .inches(48)
    static let roomStyle = DisplayStyle(layer: "A-AREA-IDEN", pen: .fine)
    static let stairStyle = DisplayStyle(layer: "A-FLOR-STRS", pen: .thin)
    static let floorOpeningStyle = DisplayStyle(layer: "A-FLOR-OPNG", pen: .thin, pattern: .dashed)

    /// Model-space extent of a storey's walls, or nil when it has none.
    static func extent(of document: ModelDocument, storey: StoreyID) -> (min: Point2, max: Point2)? {
        let walls = document.walls.filter { $0.storeyID == storey }
        guard !walls.isEmpty else { return nil }
        let half = walls.map(\.thickness.ticks).max()! / 2
        let xs = walls.flatMap { [$0.start.x.ticks, $0.end.x.ticks] }
        let ys = walls.flatMap { [$0.start.y.ticks, $0.end.y.ticks] }
        return (paperPoint(xs.min()! - half, ys.min()! - half), paperPoint(xs.max()! + half, ys.max()! + half))
    }

    /// The plan's drawing. With `labels` false, the room tags and opening marks are left out, for `PlanLabels`
    /// to place where they have room.
    static func items(
        document: ModelDocument, storey: StoreyID, outlines: [ClassifiedOutline], areas: [RoomID: Area],
        view: ViewTransform, stairsBelow: [ClassifiedOutline] = [], labels: Bool = true
    ) -> [DisplayItem] {
        var items: [DisplayItem] = []
        let hatchSpacing = Length.millimeters(1)
        let outside = exteriorWalls(document, storey: storey)
        for outline in outlines where outline.kind == .wall {
            let polygon = outline.polygon.map(view.paper)
            if outline.classification == .cut {
                items.append(DisplayItem(.hatch(boundary: polygon, pattern: .diagonal, spacing: hatchSpacing,
                                                angle: .degrees(45)), style: hatchStyle, elementID: outline.elementID))
            }
            let cutStyle = outside.contains(WallID(outline.elementID)) ? wallStyle : interiorWallStyle
            items.append(DisplayItem(.polyline(points: polygon, closed: true),
                                     style: outline.classification == .cut ? cutStyle : beyondStyle,
                                     elementID: outline.elementID))
        }
        for outline in outlines where outline.kind == .stair {
            items += StairPlan.items(outline, document: document, view: view, drawn: items)
        }
        // A stair from the storey below arrives through an opening in this floor.
        for outline in stairsBelow where outline.kind == .stair {
            items.append(DisplayItem(.polyline(points: outline.polygon.map(view.paper), closed: true),
                                     style: floorOpeningStyle, elementID: outline.elementID))
        }
        let walls = Dictionary(uniqueKeysWithValues: document.walls.map { ($0.id, $0) })
        let marks = ScheduleView.marks(document)
        for opening in document.openings {
            guard let wall = walls[opening.wallID], wall.storeyID == storey else { continue }
            items += symbol(for: opening, in: wall, view: view)
            if labels, let mark = marks[opening.id] { items.append(tag(mark, for: opening, in: wall, view: view)) }
        }
        guard labels else { return items }
        for room in document.rooms where room.storeyID == storey {
            if let tag = roomTag(room, document: document, areas: areas, view: view) {
                items += tag.lines(.full, at: (0, 0))
            }
        }
        return items
    }

    /// How much of a room's tag is set, and how.
    enum RoomTagForm: CaseIterable {
        /// Name, size, and area.
        case full
        /// Name and area.
        case nameAndArea
        /// The name alone.
        case name
        /// The name alone, in smaller letters.
        case smallName
        /// The name turned to read up the room, for a narrow room.
        case turnedName
        /// The name's words one under another, in smaller letters.
        case stackedName
        /// The name turned, in smaller letters.
        case smallTurnedName
    }

    /// The storey's walls with a face on the outside of the house: walls one of whose sides, just past its
    /// face, lies outside the storey's outline (its walls and rooms together, holes filled).
    static func exteriorWalls(_ document: ModelDocument, storey: StoreyID) -> Set<WallID> {
        let walls = document.walls.filter { $0.storeyID == storey }
        var shapes = walls.map(SitePlanView.wallOutline)
        for room in document.rooms where room.storeyID == storey {
            if let outline = RoomOutline.centerline(of: room, in: document) { shapes.append(outline) }
        }
        let outer = RasterOutline.union(shapes, cell: Length.inches(3).ticks)
            .filter { SitePlanView.signedTwiceArea($0) > 0 }
            .map { loop in (loop.map { Double($0.x.ticks) }, loop.map { Double($0.y.ticks) }) }
        func inside(_ x: Double, _ y: Double) -> Bool { outer.contains { RasterOutline.inside(x, y, $0.0, $0.1) } }
        var result = Set<WallID>()
        for wall in walls {
            let (ax, ay) = (Double(wall.start.x.ticks), Double(wall.start.y.ticks))
            let (bx, by) = (Double(wall.end.x.ticks), Double(wall.end.y.ticks))
            let length = ((bx - ax) * (bx - ax) + (by - ay) * (by - ay)).squareRoot()
            guard length > 0 else { continue }
            let reach = Double(wall.thickness.ticks) / 2 + Double(Length.inches(6).ticks)
            let (nx, ny) = (-(by - ay) / length * reach, (bx - ax) / length * reach)
            // Test at a quarter, the middle, and three quarters, so a wall partly outside counts.
            for share in [0.25, 0.5, 0.75] {
                let (mx, my) = (ax + (bx - ax) * share, ay + (by - ay) * share)
                if !inside(mx + nx, my + ny) || !inside(mx - nx, my - ny) {
                    result.insert(wall.id)
                    break
                }
            }
        }
        return result
    }

    /// A room's tag: its name, its clear size when it is a box, and its area, centred on the room, ready to be
    /// set in full or shortened and moved by `lines`.
    struct RoomTag {
        var id: UUID
        var center: Point2
        var name: String
        var size: String?
        var area: String?
        /// The room's centerline outline on paper.
        var outline: [Point2]

        /// The tag's lines in `form`, moved by `shift` (paper ticks). The clear size takes the line under the
        /// name; the area then moves down a line.
        func lines(_ form: RoomTagForm, at shift: (x: Int64, y: Int64)) -> [DisplayItem] {
            let x = center.x.ticks + shift.x, y = center.y.ticks + shift.y
            func text(_ string: String, drop: Int64, height: Int64) -> DisplayItem {
                DisplayItem(.text(position: paperPoint(x, y - mmTicks(drop)), string: string,
                                  height: .millimeters(height), rotation: .degrees(0), alignment: .center),
                            style: roomStyle, elementID: id)
            }
            switch form {
            case .full:
                var items = [text(name, drop: 0, height: 3)]
                if let size { items.append(text(size, drop: 5, height: 2)) }
                if let area { items.append(text(area, drop: size == nil ? 5 : 9, height: 2)) }
                return items
            case .nameAndArea:
                return [text(name, drop: 0, height: 3)] + (area.map { [text($0, drop: 5, height: 2)] } ?? [])
            case .name:
                return [text(name, drop: 0, height: 3)]
            case .smallName:
                return [text(name, drop: 0, height: 2)]
            case .turnedName, .smallTurnedName:
                let height: Int64 = form == .turnedName ? 3 : 2
                return [DisplayItem(.text(position: paperPoint(x + mmTicks(height) / 2, y), string: name,
                                          height: .millimeters(height), rotation: .degrees(90), alignment: .center),
                                    style: roomStyle, elementID: id)]
            case .stackedName:
                let words = name.split(separator: " ").map(String.init)
                let first: Int64 = -Int64(words.count - 1) * 3 / 2
                var items: [DisplayItem] = []
                for (index, word) in words.enumerated() {
                    let drop: Int64 = first + Int64(index) * 3
                    items.append(text(word, drop: drop, height: 2))
                }
                return items
            }
        }
    }

    /// The tag for a room whose walls make an outline; nil otherwise.
    static func roomTag(_ room: Room, document: ModelDocument, areas: [RoomID: Area], view: ViewTransform)
        -> RoomTag? {
        let walls = Dictionary(uniqueKeysWithValues: document.walls.map { ($0.id, $0) })
        let boundary = room.boundaryWallIDs.compactMap { walls[$0] }
        guard let polygon = roomPolygon(boundary) else { return nil }
        let units = DrawingUnits.style(document, scale: view.scale)
        let size = clearSize(polygon, boundary: boundary).map {
            DrawingUnits.label($0.width, style: units) + " x " + DrawingUnits.label($0.depth, style: units)
        }
        let area = areas[room.id].map { areaLabel($0, imperial: units == .feetInchesFractions) }
        return RoomTag(id: room.id.rawValue, center: view.paper(centroid(polygon)), name: room.name.uppercased(),
                       size: size, area: area, outline: polygon.map { view.paper($0) })
    }

    /// The room's centerline polygon: where each boundary wall's line meets the next one's, walking around
    /// the room (`RoomWalk`), or in boundary order when the walls do not close. Nil when fewer than three
    /// corners can be found.
    static func roomPolygon(_ boundary: [Wall]) -> [Point2]? {
        guard boundary.count >= 3 else { return nil }
        let walls: [Wall] = RoomWalk.ordered(boundary) ?? boundary
        var corners: [Point2] = []
        for (a, b) in zip(walls, walls.dropFirst() + walls.prefix(1)) {
            let (ax, ay) = (Double(a.start.x.ticks), Double(a.start.y.ticks))
            let (adx, ady) = (Double(a.end.x.ticks) - ax, Double(a.end.y.ticks) - ay)
            let (bx, by) = (Double(b.start.x.ticks), Double(b.start.y.ticks))
            let (bdx, bdy) = (Double(b.end.x.ticks) - bx, Double(b.end.y.ticks) - by)
            let denominator = adx * bdy - ady * bdx
            guard abs(denominator) > 1e-9 else { continue }
            let t = ((bx - ax) * bdy - (by - ay) * bdx) / denominator
            corners.append(paperPoint(Int64((ax + adx * t).rounded()), Int64((ay + ady * t).rounded())))
        }
        return corners.count >= 3 ? corners : nil
    }

    /// A room's clear width (along x) and depth (along y), face to face, when its centerline polygon is a
    /// rectangle square to the axes: each side's centerline less half the thickness of the walls on it. Nil for
    /// any other shape, or when a side has no wall on it or walls of more than one thickness.
    static func clearSize(_ polygon: [Point2], boundary: [Wall]) -> (width: Length, depth: Length)? {
        guard polygon.count == 4 else { return nil }
        let xs = Set(polygon.map(\.x.ticks)), ys = Set(polygon.map(\.y.ticks))
        guard xs.count == 2, ys.count == 2, let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(),
              let y1 = ys.max() else { return nil }
        // Every corner of the box must be in the polygon, so it is the box and not a bow tie of its corners.
        let corners: Set<[Int64]> = Set(polygon.map { [$0.x.ticks, $0.y.ticks] })
        guard corners == [[x0, y0], [x1, y0], [x1, y1], [x0, y1]] else { return nil }
        /// Half the thickness of the walls lying on one side's line, when they agree.
        func half(_ onSide: (Wall) -> Bool) -> Int64? {
            let thicknesses = Set(boundary.filter(onSide).map(\.thickness.ticks))
            guard thicknesses.count == 1, let thickness = thicknesses.first else { return nil }
            return thickness / 2
        }
        guard let west = half({ $0.start.x.ticks == x0 && $0.end.x.ticks == x0 }),
              let east = half({ $0.start.x.ticks == x1 && $0.end.x.ticks == x1 }),
              let south = half({ $0.start.y.ticks == y0 && $0.end.y.ticks == y0 }),
              let north = half({ $0.start.y.ticks == y1 && $0.end.y.ticks == y1 }) else { return nil }
        let width = x1 - x0 - west - east, depth = y1 - y0 - south - north
        guard width > 0, depth > 0 else { return nil }
        return (Length(ticks: width), Length(ticks: depth))
    }

    /// Vertex average; good enough to place a tag inside a convex room.
    static func centroid(_ points: [Point2]) -> Point2 {
        let n = Int64(points.count)
        return paperPoint(points.reduce(0) { $0 + $1.x.ticks } / n, points.reduce(0) { $0 + $1.y.ticks } / n)
    }

    /// Whole square feet or tenths of a square meter.
    static func areaLabel(_ area: Area, imperial: Bool) -> String {
        let squareMillimeters = Double(area.tickSquares) / Double(Area.tickSquaresPerSquareMillimeter)
        if imperial {
            return "\(Int((squareMillimeters / (304.8 * 304.8)).rounded())) SF"
        }
        return String(format: "%.1f SQ M", squareMillimeters / 1_000_000)
    }

    /// Whether an opening is wholly above the plan cut: its sill at or above the cut and its head above it.
    static func isAboveCut(_ opening: Opening) -> Bool {
        opening.sillHeight.ticks >= planCut.ticks && opening.sillHeight.ticks + opening.height.ticks > planCut.ticks
    }

    /// Where a pocket door's leaf sits, along the wall from its start: beside the opening toward the wall start,
    /// as long as the opening is wide; toward the wall end when that run would pass the wall start; nil when
    /// neither side of the wall has room, so the leaf is never drawn past a wall end.
    static func pocketRun(opening: (a: Double, b: Double), wallLength: Double) -> (from: Double, to: Double)? {
        let width = opening.b - opening.a
        if opening.a - width >= 0 { return (opening.a - width, opening.a) }
        if opening.b + width <= wallLength { return (opening.b, opening.b + width) }
        return nil
    }

    /// Jambs across the wall, then a swing and leaf for hinged doors, the leaf in its pocket for a pocket door
    /// (a rectangle inside the wall, a quarter of its thickness in from each face), a slide line for other doors,
    /// and for windows the sills at both faces and a pair of glass lines between, dashed for a window wholly above
    /// the plan cut. A cased opening is its two
    /// jambs only.
    static func symbol(for opening: Opening, in wall: Wall, view: ViewTransform) -> [DisplayItem] {
        let sx = Double(wall.start.x.ticks), sy = Double(wall.start.y.ticks)
        let dx = Double(wall.end.x.ticks) - sx, dy = Double(wall.end.y.ticks) - sy
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return [] }
        let (ux, uy) = (dx / length, dy / length)
        let (nx, ny) = (-uy, ux)
        let half = Double(wall.thickness.ticks) / 2
        let a = Double(opening.offsetAlongWall.ticks)
        let b = a + Double(opening.width.ticks)
        func at(_ along: Double, _ across: Double) -> Point2 {
            view.paper(paperPoint(Int64((sx + ux * along + nx * across).rounded()),
                                  Int64((sy + uy * along + ny * across).rounded())))
        }
        let id = opening.id.rawValue
        let style = opening.kind.isWindow ? (isAboveCut(opening) ? glazingAboveStyle : glazingStyle) : doorStyle
        var items = [
            DisplayItem(.line(start: at(a, -half), end: at(a, half)), style: style, elementID: id),
            DisplayItem(.line(start: at(b, -half), end: at(b, half)), style: style, elementID: id),
        ]
        if opening.kind == .casedOpening {
            return items
        }
        if !opening.kind.isDoor {
            // As blueprints draw a window: the wall's two faces carried across as the sills, and the glass, a
            // pair of close lines, in the middle.
            for across in [-half, -half / 6, half / 6, half] {
                items.append(DisplayItem(.line(start: at(a, across), end: at(b, across)), style: style, elementID: id))
            }
            return items
        }
        if opening.kind == .pocketDoor {
            if let pocket = pocketRun(opening: (a, b), wallLength: length) {
                let inset = half / 2
                let leaf = [at(pocket.from, -inset), at(pocket.to, -inset), at(pocket.to, inset), at(pocket.from, inset)]
                items.append(DisplayItem(.polyline(points: leaf, closed: true), style: style, elementID: id))
            }
            return items
        }
        guard let swing = opening.swing else {
            items.append(DisplayItem(.line(start: at(a, 0), end: at(b, 0)), style: style, elementID: id))
            return items
        }
        let side: Double = swing.opensToward == .left ? 1 : -1
        let width = b - a
        let (hingeAlong, closedDirection): (Double, Double) = swing.hinge == .nearStart ? (a, 1) : (b, -1)
        let hinge = at(hingeAlong, side * half)
        let leafEnd = at(hingeAlong, side * (half + width))
        items.append(DisplayItem(.line(start: hinge, end: leafEnd), style: style, elementID: id))
        let leafAngle = atan2(ny * side, nx * side)
        let closedAngle = atan2(uy * closedDirection, ux * closedDirection)
        var sweep = closedAngle - leafAngle
        if sweep > .pi { sweep -= 2 * .pi }
        if sweep <= -.pi { sweep += 2 * .pi }
        items.append(DisplayItem(
            .arc(center: hinge, radius: view.paper(Length(ticks: Int64(width.rounded()))),
                 start: angle(leafAngle), sweep: angle(sweep)),
            style: DisplayStyle(layer: "A-DOOR", pen: .extraFine), elementID: id))
        return items
    }

    /// The schedule mark, set just outside the wall's right face at the opening's middle; or, for `PlanLabels`
    /// looking for room, `beyond` millimetres off the face on the given `side` (1 right, -1 left), moved `along`
    /// the wall by that share of the opening's width.
    static func tag(_ mark: String, for opening: Opening, in wall: Wall, view: ViewTransform, side: Double = 1,
                    beyond: Int64 = 4, along shift: Double = 0) -> DisplayItem {
        let sx = Double(wall.start.x.ticks), sy = Double(wall.start.y.ticks)
        let dx = Double(wall.end.x.ticks) - sx, dy = Double(wall.end.y.ticks) - sy
        let length = max((dx * dx + dy * dy).squareRoot(), 1)
        let (ux, uy) = (dx / length, dy / length)
        let along = Double(opening.offsetAlongWall.ticks) + Double(opening.width.ticks) * (0.5 + shift)
        let across = -side * (Double(wall.thickness.ticks) / 2
            + Double(mmTicks(beyond) * view.scale.modelUnitsPerPaperUnit))
        let anchor = view.paper(paperPoint(Int64((sx + ux * along + uy * -across).rounded()),
                                           Int64((sy + uy * along - ux * -across).rounded())))
        return DisplayItem(.text(position: Point2(x: anchor.x, y: Length(ticks: anchor.y.ticks - mmTicks(1))),
                                 string: mark, height: .millimeters(2), rotation: .degrees(0), alignment: .center),
                           style: DisplayStyle(layer: "A-ANNO-TEXT", pen: .fine), elementID: opening.id.rawValue)
    }

    static func angle(_ radians: Double) -> Angle {
        Angle(microDegrees: Int64((radians * 180 / .pi * 1_000_000).rounded()))
    }
}
