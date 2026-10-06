import ATContracts
import Foundation

/// Electrical plan: walls light, then MEP symbols with their NCS layers, and a legend of the kinds used.
enum ElectricalPlanView {
    static func items(
        document: ModelDocument, storey: StoreyID, outlines: [ClassifiedOutline], view: ViewTransform,
        legendAt origin: Point2
    ) -> [DisplayItem] {
        var items = outlines.filter { $0.kind == .wall }.map {
            DisplayItem(.polyline(points: $0.polygon.map { view.paper($0) }, closed: true),
                        style: DisplayStyle(layer: "A-WALL", pen: .thin), elementID: $0.elementID)
        }
        let symbols = document.mepSymbols.filter { $0.storeyID == storey }
        for symbol in symbols {
            items.append(DisplayItem(.symbol(name: symbol.kind.rawValue, position: view.paper(symbol.position),
                                             rotation: symbol.rotation, size: .millimeters(4)),
                                     style: DisplayStyle(layer: symbol.kind.cadLayer, pen: .thin),
                                     elementID: symbol.id.rawValue))
        }
        let kinds = MEPSymbolKind.allCases.filter { kind in symbols.contains { $0.kind == kind } }
        guard !kinds.isEmpty else { return items }
        let table = ScheduleView.Table(
            title: "Legend", columns: [("SYMBOL", mmTicks(30)), ("COUNT", mmTicks(16)), ("LAYER", mmTicks(20))],
            rows: kinds.map { kind in
                [ScheduleView.words(kind.rawValue), "\(symbols.filter { $0.kind == kind }.count)", kind.cadLayer]
            })
        return items + ScheduleView.items(table, at: origin)
    }
}
