import ATContracts
import Foundation

/// Roof plan: walls below dashed, the eave line, ridge and hip lines, and the pitch of each sloped plane.
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

    static func items(_ document: ModelDocument, view: ViewTransform) -> [DisplayItem] {
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
                // Not a box: draw the footprint and say the planes are not resolved here.
                items.append(DisplayItem(.polyline(points: roof.footprint.map { view.paper($0) }, closed: true),
                                         style: roofStyle, elementID: id))
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

    static func label(_ text: String, at point: Point2) -> DisplayItem {
        DisplayItem(.text(position: point, string: text, height: Length(ticks: mmTicks(5) / 2), rotation: .degrees(0),
                          alignment: .center), style: textStyle)
    }
}

/// Site plan: property and terrain boundaries, the building footprint hatched, and a north arrow.
enum SitePlanView {
    static let lineStyle = DisplayStyle(layer: "C-PROP", pen: .medium, pattern: .center)
    static let buildingStyle = DisplayStyle(layer: "A-AREA", pen: .heavy)

    static func footprint(_ document: ModelDocument) -> [Point2]? {
        let ground = document.storeys.min { $0.elevation < $1.elevation }
        guard let ground, let extent = FloorPlanView.extent(of: document, storey: ground.id) else { return nil }
        return [extent.min, Point2(x: extent.max.x, y: extent.min.y), extent.max, Point2(x: extent.min.x, y: extent.max.y)]
    }

    static func extent(_ document: ModelDocument) -> (min: Point2, max: Point2)? {
        let points = (footprint(document) ?? []) + document.terrainPatches.flatMap(\.boundary)
        guard let x0 = points.map(\.x.ticks).min(), let x1 = points.map(\.x.ticks).max(),
              let y0 = points.map(\.y.ticks).min(), let y1 = points.map(\.y.ticks).max() else { return nil }
        let pad = Length.millimeters(3000).ticks
        return (paperPoint(x0 - pad, y0 - pad), paperPoint(x1 + pad, y1 + pad))
    }

    static func items(_ document: ModelDocument, view: ViewTransform, area: PaperRect) -> [DisplayItem] {
        var items: [DisplayItem] = []
        for patch in document.terrainPatches {
            items.append(DisplayItem(.polyline(points: patch.boundary.map { view.paper($0) }, closed: true),
                                     style: lineStyle, elementID: patch.id.rawValue))
            if let first = patch.boundary.first {
                items.append(RoofPlanView.label(patch.name.uppercased(), at: view.paper(first)))
            }
        }
        if let footprint = footprint(document) {
            let paper = footprint.map { view.paper($0) }
            items.append(DisplayItem(.hatch(boundary: paper, pattern: .diagonal, spacing: .millimeters(2),
                                            angle: .degrees(45)), style: DisplayStyle(layer: "A-AREA-PATT", pen: .extraFine)))
            items.append(DisplayItem(.polyline(points: paper, closed: true), style: buildingStyle))
            items.append(RoofPlanView.label(document.project.name.uppercased(), at: SheetFrame.center(of: paper)))
        }
        items.append(DisplayItem(.symbol(name: "north-arrow", position: paperPoint(area.maxX - mmTicks(20),
                                                                                    area.maxY - mmTicks(20)),
                                         rotation: .degrees(0), size: .millimeters(16)),
                                 style: DisplayStyle(layer: "A-ANNO-SYMB", pen: .thin)))
        return items
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
        return items
    }
}

extension SheetFrame {
    static func center(of points: [Point2]) -> Point2 {
        let xs = points.map(\.x.ticks), ys = points.map(\.y.ticks)
        return paperPoint((xs.min()! + xs.max()!) / 2, (ys.min()! + ys.max()!) / 2)
    }
}
