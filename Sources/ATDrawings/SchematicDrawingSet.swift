import ATContracts
import Foundation

/// Builds the schematic drawing set: one paper-space sheet per `Sheet` in the model, each with the border,
/// title block, and boxed SCHEMATIC / NOT FOR CONSTRUCTION stamp. Output is not a permit set.
///
/// When the model has no sheets, it draws one floor plan sheet per storey on ARCH D at 1/4" = 1'-0".
public struct SchematicDrawingSet: DrawingGenerator {
    /// Printed in the title block's date field, such as `2026-10-06`. Nil prints a dash.
    public var issueDate: String?

    public init(issueDate: String? = nil) {
        self.issueDate = issueDate
    }

    public func sheets(for document: ModelDocument, geometry: any GeometryEngine) throws -> [SheetDrawing] {
        try sheetsToDraw(document).map { try draw($0, document: document, geometry: geometry) }
    }

    func sheetsToDraw(_ document: ModelDocument) -> [Sheet] {
        if !document.sheets.isEmpty { return document.sheets }
        return document.storeys.enumerated().map { index, storey in
            Sheet(id: SheetID(storey.id.rawValue), number: String(format: "A-%d", 101 + index),
                  title: "\(storey.name) Plan", paper: .archD, scale: .quarterInch,
                  views: [.floorPlan(storeyID: storey.id)])
        }
    }

    func draw(_ sheet: Sheet, document: ModelDocument, geometry: any GeometryEngine) throws -> SheetDrawing {
        var items = SheetFrame.items(number: sheet.number, title: sheet.title, scale: sheet.scale, paper: sheet.paper,
                                     projectName: document.project.name, issueDate: issueDate)
        let area = SheetFrame.drawingArea(for: sheet.paper)
        let slots = Self.slots(in: area, count: sheet.views.count)
        for (view, slot) in zip(sheet.views, slots) {
            items += try drawView(view, in: slot, sheet: sheet, document: document, geometry: geometry)
        }
        return SheetDrawing(number: sheet.number, title: sheet.title, paper: sheet.paper, scale: sheet.scale,
                            content: DisplayList(items: items))
    }

    /// Stacks views top to bottom in equal bands, leaving room under each for its title.
    static func slots(in area: PaperRect, count: Int) -> [PaperRect] {
        guard count > 0 else { return [] }
        let band = area.height / Int64(count)
        return (0..<count).map { index in
            PaperRect(minX: area.minX, minY: area.maxY - band * Int64(index + 1) + mmTicks(14), width: area.width,
                      height: band - mmTicks(14))
        }
    }

    private func drawView(
        _ view: SheetView, in slot: PaperRect, sheet: Sheet, document: ModelDocument, geometry: any GeometryEngine
    ) throws -> [DisplayItem] {
        let titleAt = paperPoint(slot.minX, slot.minY - mmTicks(8))
        switch view {
        case let .floorPlan(storeyID):
            let storeyName = document.storeys.first { $0.id == storeyID }?.name ?? "Floor"
            guard let extent = FloorPlanView.extent(of: document, storey: storeyID) else {
                return SheetFrame.notGenerated("\(storeyName) plan has no walls", in: slot)
            }
            let scale = sheet.scale ?? Self.fittingScale(extent: extent, in: slot)
            let placed = ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: slot, scale: scale)
            let outlines = try geometry.planView(of: document, storey: storeyID)
            let areas = try geometry.roomAreas(of: document, storey: storeyID)
            let under = paperPoint(placed.transform.paperOrigin.x.ticks, placed.transform.paperOrigin.y.ticks - mmTicks(15))
            return FloorPlanView.items(document: document, storey: storeyID, outlines: outlines, areas: areas,
                                       view: placed.transform)
                + SheetFrame.viewTitle("\(storeyName) Plan", scale: scale, at: placed.fits ? under : titleAt)
        case .cover, .roofPlan, .sitePlan, .elevation, .section, .schedule, .electricalPlan:
            return SheetFrame.notGenerated(Self.name(of: view), in: slot)
        }
    }

    static func name(of view: SheetView) -> String {
        switch view {
        case .cover: return "Cover"
        case .floorPlan: return "Floor plan"
        case .roofPlan: return "Roof plan"
        case .sitePlan: return "Site plan"
        case let .elevation(direction): return "\(direction.rawValue.capitalized) elevation"
        case .section: return "Section"
        case let .schedule(kind): return "\(kind.rawValue.capitalized) schedule"
        case .electricalPlan: return "Electrical plan"
        }
    }

    /// The largest standard scale at which the extent fits the slot, falling back to 1:200.
    static func fittingScale(extent: (min: Point2, max: Point2), in slot: PaperRect) -> DrawingScale {
        let candidates: [DrawingScale] = [.quarterInch, .oneTo50, .eighthInch, .oneTo100]
        for scale in candidates {
            let placed = ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: slot, scale: scale)
            if placed.fits { return scale }
        }
        return DrawingScale(label: "1:200", modelUnitsPerPaperUnit: 200)
    }
}

/// Writes sheets as a multi-page vector PDF, one page per sheet, at true scale.
public struct SheetPDFExporter: Exporter {
    public init() {}

    public var format: ExchangeFormat { .pdf }

    public func export(_ payload: ExportPayload) throws -> Data {
        guard case let .sheets(sheets) = payload else {
            throw ExchangeError.unsupportedPayload(format: ExchangeFormat.pdf.id)
        }
        return SheetPDF.render(sheets)
    }
}
