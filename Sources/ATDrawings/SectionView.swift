import ATContracts
import Foundation

/// Schematic building section along a sheet's section line, looking to the left of start → end.
///
/// Draws the geometry engine's cut, in (distance along the line from its start, elevation): cut outlines
/// heavy and hatched (concrete for slabs), outlines beyond light. Schematic only.
enum SectionView {
    static let cutStyle = DisplayStyle(layer: "A-SECT-MCUT", pen: .heavy)
    static let hatchStyle = DisplayStyle(layer: "A-SECT-PATT", pen: .extraFine)
    static let beyondStyle = DisplayStyle(layer: "A-SECT-BYND", pen: .thin)

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
