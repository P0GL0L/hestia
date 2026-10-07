import ATContracts
import Foundation

/// A stair on its own storey's plan: the engine's outline, a line at every tread nosing, and an UP arrow
/// along the run from the bottom riser toward the top.
enum StairPlan {
    static let arrowStyle = DisplayStyle(layer: "A-FLOR-STRS", pen: .fine)

    static func items(_ outline: ClassifiedOutline, document: ModelDocument, view: ViewTransform) -> [DisplayItem] {
        let id = outline.elementID
        var items = [DisplayItem(.polyline(points: outline.polygon.map(view.paper), closed: true),
                                 style: FloorPlanView.stairStyle, elementID: id)]
        guard let stair = document.stairs.first(where: { $0.id.rawValue == id }) else { return items }
        let sx = Double(stair.runStart.x.ticks), sy = Double(stair.runStart.y.ticks)
        let dx = Double(stair.runEnd.x.ticks) - sx, dy = Double(stair.runEnd.y.ticks) - sy
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0, stair.riserCount >= 2 else { return items }
        let (ux, uy) = (dx / length, dy / length)
        let (nx, ny) = (-uy, ux)
        let half = Double(stair.width.ticks) / 2
        func at(_ along: Double, _ across: Double) -> Point2 {
            view.paper(paperPoint(Int64((sx + ux * along + nx * across).rounded()),
                                  Int64((sy + uy * along + ny * across).rounded())))
        }
        // Treads between the first and last risers; the outline's ends are the first and last risers.
        let treads = stair.riserCount - 1
        let going = length / Double(treads)
        for step in 1..<treads {
            let along = going * Double(step)
            items.append(DisplayItem(.line(start: at(along, -half), end: at(along, half)),
                                     style: FloorPlanView.stairStyle, elementID: id))
        }
        // UP arrow on the centerline, from half a tread in to half a tread short of the top.
        let tail = going / 2, head = length - going / 2
        let barb = min(going, half) * 0.6
        items.append(DisplayItem(.line(start: at(tail, 0), end: at(head, 0)), style: arrowStyle, elementID: id))
        items.append(DisplayItem(.line(start: at(head - barb, -barb / 2), end: at(head, 0)), style: arrowStyle,
                                 elementID: id))
        items.append(DisplayItem(.line(start: at(head - barb, barb / 2), end: at(head, 0)), style: arrowStyle,
                                 elementID: id))
        items.append(DisplayItem(.text(position: upLabelPosition(from: at(0, 0), toward: at(length, 0)),
                                       string: "UP", height: .millimeters(2), rotation: .degrees(0),
                                       alignment: .center),
                                 style: arrowStyle, elementID: id))
        return items
    }

    /// Where the UP label goes: 3 mm on paper beyond the bottom riser, against the run, centred on it whatever
    /// way the stair runs. The label is 2 mm high, so its baseline sits 1 mm below that point.
    static func upLabelPosition(from bottom: Point2, toward top: Point2) -> Point2 {
        let dx = Double(top.x.ticks - bottom.x.ticks), dy = Double(top.y.ticks - bottom.y.ticks)
        let length = max((dx * dx + dy * dy).squareRoot(), 1)
        let reach = Double(mmTicks(3))
        let x: Double = Double(bottom.x.ticks) - dx / length * reach
        let y: Double = Double(bottom.y.ticks) - dy / length * reach - Double(mmTicks(1))
        return Point2(x: Length(ticks: Int64(x.rounded())), y: Length(ticks: Int64(y.rounded())))
    }
}
