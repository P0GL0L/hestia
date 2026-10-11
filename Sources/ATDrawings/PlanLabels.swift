import ATContracts
import Foundation

/// Sets a floor plan's labels where they have room, as a drafter would: no tag, size, or mark over a wall, a
/// dimension, or another label. What does not move (walls, doors, windows, stairs, the dimension chains outside)
/// is drawn first. Then:
/// - Each opening's mark goes just outside its wall, else just inside, else a little further off or along.
/// - Each room's tag goes at its middle, else nearby within the room. When it cannot fit whole, it drops its
///   size line, then its area, then sets the name smaller.
/// - Each box room's clear width and depth go a quarter of the way across it, else at other places across it,
///   their lines clear of door swings, windows, stairs, walls, and other dimensions. With no clear place they
///   are left out, since the tag already gives the size.
enum PlanLabels {
    static func items(document: ModelDocument, storey: StoreyID, areas: [RoomID: Area], view: ViewTransform,
                      drawn: [DisplayItem], units: LengthFormatStyle) -> [DisplayItem] {
        var space = LabelSpace(drawn, scale: view.scale)
        var items: [DisplayItem] = []
        let walls = Dictionary(uniqueKeysWithValues: document.walls.map { ($0.id, $0) })
        let marks = ScheduleView.marks(document)
        for opening in document.openings {
            guard let wall = walls[opening.wallID], wall.storeyID == storey, let mark = marks[opening.id] else {
                continue
            }
            var candidates: [[DisplayItem]] = []
            for beyond: Int64 in [4, 7, 10] {
                for along in [0.0, -0.35, 0.35] {
                    for side in [1.0, -1.0] {
                        candidates.append([FloorPlanView.tag(mark, for: opening, in: wall, view: view, side: side,
                                                             beyond: beyond, along: along)])
                    }
                }
            }
            items += space.place(candidates, required: true)
        }
        let rooms = document.rooms.filter { $0.storeyID == storey }
        for room in rooms {
            guard let tag = FloorPlanView.roomTag(room, document: document, areas: areas, view: view) else {
                continue
            }
            var candidates: [[DisplayItem]] = []
            for form in FloorPlanView.RoomTagForm.allCases {
                for shift in shifts() { candidates.append(tag.lines(form, at: shift)) }
            }
            items += space.place(candidates, within: tag.outline, required: true)
        }
        for room in rooms {
            let (width, depth) = DimensionChains.interiorCandidates(room, document: document, view: view, units: units)
            // Kept off door swings, windows, stairs, walls, and other dimensions.
            let crossing: Set<String> = ["A-DOOR", "A-GLAZ", "A-FLOR-STRS", "A-FLOR-OPNG", "A-WALL", "A-ANNO-DIMS"]
            items += space.place(width, crossing: crossing, required: false)
            items += space.place(depth, crossing: crossing, required: false)
        }
        return items
    }

    /// Moves to try for a room tag, in paper ticks, nearest first: up to 12 mm either way across and 10 mm
    /// up or down, on a 2 mm grid.
    static func shifts() -> [(x: Int64, y: Int64)] {
        var result: [(x: Int64, y: Int64)] = []
        for dx in stride(from: Int64(-6), through: 6, by: 1) {
            for dy in stride(from: Int64(-5), through: 5, by: 1) { result.append((dx * mmTicks(2), dy * mmTicks(2))) }
        }
        return result.sorted { a, b in
            let da = a.x * a.x + a.y * a.y * 2, db = b.x * b.x + b.y * b.y * 2
            return da != db ? da < db : (a.x, a.y) < (b.x, b.y)
        }
    }
}
