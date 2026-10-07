import ATContracts
import Foundation

/// Exterior dimension chains on the south and west faces of a plan, in three tiers from the wall out:
/// openings, wall breaks, and overall.
enum DimensionChains {
    static let style = DisplayStyle(layer: "A-ANNO-DIMS", pen: .extraFine)
    /// Paper distance from the outer wall face to each tier.
    static let tierOffsets: [Int64] = [10, 18, 26].map(mmTicks)
    /// Paper room the chains need outside the plan.
    static let reserve = mmTicks(34)

    static func items(document: ModelDocument, storey: StoreyID, view: ViewTransform) -> [DisplayItem] {
        guard let extent = FloorPlanView.extent(of: document, storey: storey) else { return [] }
        let walls = document.walls.filter { $0.storeyID == storey }
        let openings = document.openings
        var items: [DisplayItem] = []
        // South face: stops along x, chain drawn below, left to right.
        let south = stops(walls: walls, openings: openings, alongX: true, face: extent.min.y.ticks,
                          low: extent.min.x.ticks, high: extent.max.x.ticks)
        // West face: stops along y, chain drawn to the left, bottom to top.
        let west = stops(walls: walls, openings: openings, alongX: false, face: extent.min.x.ticks,
                         low: extent.min.y.ticks, high: extent.max.y.ticks)
        // A segment that is exactly one wall prints that wall's override for this face; others stay measured.
        let southLabels = wallLabels(document: document, walls: walls, alongX: true, face: .south)
        let westLabels = wallLabels(document: document, walls: walls, alongX: false, face: .west)
        for (tier, chain) in [south.openings, south.walls, south.overall].enumerated() where chain.count > 2 || tier == 2 {
            items += chainItems(chain, alongX: true, face: extent.min.y.ticks, offset: tierOffsets[tier], view: view,
                                labels: southLabels, document: document)
        }
        for (tier, chain) in [west.openings, west.walls, west.overall].enumerated() where chain.count > 2 || tier == 2 {
            items += chainItems(chain, alongX: false, face: extent.min.x.ticks, offset: tierOffsets[tier], view: view,
                                labels: westLabels, document: document)
        }
        return items
    }

    /// Sorted, distinct stop coordinates for each tier on one face.
    static func stops(
        walls: [Wall], openings: [Opening], alongX: Bool, face: Int64, low: Int64, high: Int64
    ) -> (openings: [Int64], walls: [Int64], overall: [Int64]) {
        func along(_ p: Point2) -> Int64 { alongX ? p.x.ticks : p.y.ticks }
        func across(_ p: Point2) -> Int64 { alongX ? p.y.ticks : p.x.ticks }
        // Walls running along this face whose outer side is the face.
        let faceWalls = walls.filter {
            across($0.start) == across($0.end) && abs(across($0.start) - $0.thickness.ticks / 2 - face) <= 1
        }
        let lines = Set(faceWalls.map { across($0.start) })
        var wallStops: Set<Int64> = [low, high]
        let margin = walls.map(\.thickness.ticks).max() ?? 0
        // Interior walls that meet the face; the end walls are already the overall stops.
        for wall in walls where along(wall.start) == along(wall.end)
            && along(wall.start) - low > margin && high - along(wall.start) > margin {
            if lines.contains(across(wall.start)) || lines.contains(across(wall.end)) {
                wallStops.insert(along(wall.start))
            }
        }
        var openingStops: Set<Int64> = [low, high]
        for wall in faceWalls {
            let direction: Int64 = along(wall.end) >= along(wall.start) ? 1 : -1
            for opening in openings where opening.wallID == wall.id {
                let a = along(wall.start) + direction * opening.offsetAlongWall.ticks
                openingStops.insert(a)
                openingStops.insert(a + direction * opening.width.ticks)
            }
        }
        return (openingStops.sorted(), wallStops.sorted(), [low, high])
    }

    /// Wall overrides for exterior segments that are exactly one wall: the wall's outer extent along the face.
    static func wallLabels(document: ModelDocument, walls: [Wall], alongX: Bool, face: DimensionFace) -> [Span: String] {
        var labels: [Span: String] = [:]
        for wall in walls {
            guard let text = document.dimensionOverride(for: wall.id.rawValue, face: face) else { continue }
            let runsAlong = alongX ? wall.start.y == wall.end.y : wall.start.x == wall.end.x
            guard runsAlong else { continue }
            let a = alongX ? wall.start.x.ticks : wall.start.y.ticks
            let b = alongX ? wall.end.x.ticks : wall.end.y.ticks
            let half = wall.thickness.ticks / 2
            labels[Span(min(a, b) - half, max(a, b) + half)] = text
        }
        return labels
    }

    struct Span: Hashable {
        var low: Int64
        var high: Int64
        init(_ low: Int64, _ high: Int64) {
            self.low = low
            self.high = high
        }
    }

    private static func chainItems(
        _ stops: [Int64], alongX: Bool, face: Int64, offset: Int64, view: ViewTransform, labels: [Span: String],
        document: ModelDocument
    ) -> [DisplayItem] {
        zip(stops, stops.dropFirst()).map { a, b in
            let from = view.paper(alongX ? paperPoint(a, face) : paperPoint(face, a))
            let to = view.paper(alongX ? paperPoint(b, face) : paperPoint(face, b))
            // Left of a rightward chain is inside the building, so the south chain uses a negative offset;
            // left of an upward chain is outside, so the west chain uses a positive one.
            let text = DrawingUnits.dimensionText(document, length: Length(ticks: b - a), override: labels[Span(a, b)])
            return DisplayItem(.dimension(from: from, to: to, offset: Length(ticks: alongX ? -offset : offset),
                                          override: text), style: style)
        }
    }

    /// Clear interior width and depth of every box-shaped room, face to face, a quarter of the way in from
    /// its south and west walls so they clear the room tag. Rooms that are not boxes get none.
    static func interiorItems(document: ModelDocument, storey: StoreyID, view: ViewTransform) -> [DisplayItem] {
        let walls = Dictionary(uniqueKeysWithValues: document.walls.map { ($0.id, $0) })
        var items: [DisplayItem] = []
        for room in document.rooms where room.storeyID == storey {
            let boundary = room.boundaryWallIDs.compactMap { walls[$0] }
            guard let clear = clearBox(boundary) else { continue }
            let (x0, x1, y0, y1) = clear
            let y = y0 + (y1 - y0) / 4, x = x0 + (x1 - x0) / 4
            let id = room.id.rawValue
            items.append(DisplayItem(.dimension(from: view.paper(paperPoint(x0, y)), to: view.paper(paperPoint(x1, y)),
                                                offset: Length(ticks: 0),
                                                override: DrawingUnits.dimensionText(
                                                    document, length: Length(ticks: x1 - x0),
                                                    override: document.dimensionOverride(for: id, face: .width))),
                                     style: style, elementID: room.id.rawValue))
            items.append(DisplayItem(.dimension(from: view.paper(paperPoint(x, y0)), to: view.paper(paperPoint(x, y1)),
                                                offset: Length(ticks: 0),
                                                override: DrawingUnits.dimensionText(
                                                    document, length: Length(ticks: y1 - y0),
                                                    override: document.dimensionOverride(for: id, face: .depth))),
                                     style: style, elementID: room.id.rawValue))
        }
        return items
    }

    /// Face-to-face box of a room bounded by axis-aligned walls, or nil.
    static func clearBox(_ boundary: [Wall]) -> (Int64, Int64, Int64, Int64)? {
        guard let corners = FloorPlanView.roomPolygon(boundary), corners.count == 4 else { return nil }
        let xs = corners.map(\.x.ticks), ys = corners.map(\.y.ticks)
        let (x0, x1, y0, y1) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        guard corners.allSatisfy({ ($0.x.ticks == x0 || $0.x.ticks == x1) && ($0.y.ticks == y0 || $0.y.ticks == y1) })
        else { return nil }
        func half(_ match: (Wall) -> Bool) -> Int64 { (boundary.first(where: match)?.thickness.ticks ?? 0) / 2 }
        let west = half { $0.start.x.ticks == x0 && $0.end.x.ticks == x0 }
        let east = half { $0.start.x.ticks == x1 && $0.end.x.ticks == x1 }
        let south = half { $0.start.y.ticks == y0 && $0.end.y.ticks == y0 }
        let north = half { $0.start.y.ticks == y1 && $0.end.y.ticks == y1 }
        guard x1 - east > x0 + west, y1 - north > y0 + south else { return nil }
        return (x0 + west, x1 - east, y0 + south, y1 - north)
    }
}
