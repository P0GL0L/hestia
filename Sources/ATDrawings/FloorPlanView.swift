import ATContracts
import Foundation

/// Schematic floor plan: cut walls with hatching, door swings, window symbols, stairs, and room tags with area.
enum FloorPlanView {
    static let wallStyle = DisplayStyle(layer: "A-WALL", pen: .heavy)
    static let beyondStyle = DisplayStyle(layer: "A-WALL", pen: .thin)
    static let hatchStyle = DisplayStyle(layer: "A-WALL-PATT", pen: .extraFine)
    static let doorStyle = DisplayStyle(layer: "A-DOOR", pen: .thin)
    static let glazingStyle = DisplayStyle(layer: "A-GLAZ", pen: .thin)
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

    static func items(
        document: ModelDocument, storey: StoreyID, outlines: [ClassifiedOutline], areas: [RoomID: Area],
        view: ViewTransform, stairsBelow: [ClassifiedOutline] = []
    ) -> [DisplayItem] {
        var items: [DisplayItem] = []
        let hatchSpacing = Length.millimeters(1)
        for outline in outlines where outline.kind == .wall {
            let polygon = outline.polygon.map(view.paper)
            if outline.classification == .cut {
                items.append(DisplayItem(.hatch(boundary: polygon, pattern: .diagonal, spacing: hatchSpacing,
                                                angle: .degrees(45)), style: hatchStyle, elementID: outline.elementID))
            }
            items.append(DisplayItem(.polyline(points: polygon, closed: true),
                                     style: outline.classification == .cut ? wallStyle : beyondStyle,
                                     elementID: outline.elementID))
        }
        for outline in outlines where outline.kind == .stair {
            items += StairPlan.items(outline, document: document, view: view)
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
            if let mark = marks[opening.id] { items.append(tag(mark, for: opening, in: wall, view: view)) }
        }
        let imperial = DrawingUnits.style(document, scale: view.scale) == .feetInchesFractions
        for room in document.rooms where room.storeyID == storey {
            guard let polygon = roomPolygon(room.boundaryWallIDs.compactMap { walls[$0] }) else { continue }
            let center = view.paper(centroid(polygon))
            items.append(DisplayItem(.text(position: center, string: room.name.uppercased(), height: .millimeters(3),
                                           rotation: .degrees(0), alignment: .center),
                                     style: roomStyle, elementID: room.id.rawValue))
            if let area = areas[room.id] {
                items.append(DisplayItem(
                    .text(position: Point2(x: center.x, y: Length(ticks: center.y.ticks - mmTicks(5))),
                          string: areaLabel(area, imperial: imperial), height: .millimeters(2),
                          rotation: .degrees(0), alignment: .center),
                    style: roomStyle, elementID: room.id.rawValue))
            }
        }
        return items
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

    /// Jambs across the wall, then a swing and leaf for hinged doors, a slide line for other doors, and
    /// glazing lines for windows. A cased opening is its two jambs only.
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
        let style = opening.kind.isWindow ? glazingStyle : doorStyle
        var items = [
            DisplayItem(.line(start: at(a, -half), end: at(a, half)), style: style, elementID: id),
            DisplayItem(.line(start: at(b, -half), end: at(b, half)), style: style, elementID: id),
        ]
        if opening.kind == .casedOpening {
            return items
        }
        if !opening.kind.isDoor {
            for across in [-half / 3, half / 3] {
                items.append(DisplayItem(.line(start: at(a, across), end: at(b, across)), style: style, elementID: id))
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

    /// The schedule mark, set just outside the wall's right face at the opening's middle.
    static func tag(_ mark: String, for opening: Opening, in wall: Wall, view: ViewTransform) -> DisplayItem {
        let sx = Double(wall.start.x.ticks), sy = Double(wall.start.y.ticks)
        let dx = Double(wall.end.x.ticks) - sx, dy = Double(wall.end.y.ticks) - sy
        let length = max((dx * dx + dy * dy).squareRoot(), 1)
        let (ux, uy) = (dx / length, dy / length)
        let along = Double(opening.offsetAlongWall.ticks + opening.width.ticks / 2)
        let across = -(Double(wall.thickness.ticks) / 2
            + Double(mmTicks(4) * view.scale.modelUnitsPerPaperUnit))
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
