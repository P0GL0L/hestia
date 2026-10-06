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
        for (tier, chain) in [south.openings, south.walls, south.overall].enumerated() where chain.count > 2 || tier == 2 {
            items += chainItems(chain, alongX: true, face: extent.min.y.ticks, offset: tierOffsets[tier], view: view)
        }
        for (tier, chain) in [west.openings, west.walls, west.overall].enumerated() where chain.count > 2 || tier == 2 {
            items += chainItems(chain, alongX: false, face: extent.min.x.ticks, offset: tierOffsets[tier], view: view)
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

    private static func chainItems(
        _ stops: [Int64], alongX: Bool, face: Int64, offset: Int64, view: ViewTransform
    ) -> [DisplayItem] {
        zip(stops, stops.dropFirst()).map { a, b in
            let from = view.paper(alongX ? paperPoint(a, face) : paperPoint(face, a))
            let to = view.paper(alongX ? paperPoint(b, face) : paperPoint(face, b))
            // Left of a rightward chain is inside the building, so the south chain uses a negative offset;
            // left of an upward chain is outside, so the west chain uses a positive one.
            return DisplayItem(.dimension(from: from, to: to, offset: Length(ticks: alongX ? -offset : offset),
                                          override: nil), style: style)
        }
    }
}
