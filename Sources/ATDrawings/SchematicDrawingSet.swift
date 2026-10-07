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
        let units = Self.units(document)
        switch view {
        case let .floorPlan(storeyID):
            let storeyName = document.storeys.first { $0.id == storeyID }?.name ?? "Floor"
            guard let extent = FloorPlanView.extent(of: document, storey: storeyID) else {
                return SheetFrame.notGenerated("\(storeyName) plan has no walls", in: slot)
            }
            // Leave room outside the plan for the dimension chains on the south and west.
            let reserve = DimensionChains.reserve
            let inner = PaperRect(minX: slot.minX + reserve, minY: slot.minY + reserve,
                                  width: slot.width - reserve, height: slot.height - reserve)
            let scale = sheet.scale ?? Self.fittingScale(extent: extent, in: inner)
            let placed = ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: inner, scale: scale)
            let outlines = try geometry.planView(of: document, storey: storeyID)
            let areas = try geometry.roomAreas(of: document, storey: storeyID)
            let under = paperPoint(placed.transform.paperOrigin.x.ticks - reserve,
                                   placed.transform.paperOrigin.y.ticks - reserve - mmTicks(8))
            return FloorPlanView.items(document: document, storey: storeyID, outlines: outlines, areas: areas,
                                       view: placed.transform)
                + DimensionChains.items(document: document, storey: storeyID, view: placed.transform)
                + DimensionChains.interiorItems(document: document, storey: storeyID, view: placed.transform)
                + SheetFrame.viewTitle("\(storeyName) Plan", scale: scale, at: placed.fits ? under : titleAt)
        case let .elevation(direction):
            let name = Self.name(of: view)
            guard let extent = ElevationView.extent(document, direction) else {
                return SheetFrame.notGenerated(name, in: slot)
            }
            let scale = sheet.scale ?? Self.fittingScale(extent: extent, in: slot)
            let placed = ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: slot, scale: scale)
            let under = paperPoint(placed.transform.paperOrigin.x.ticks,
                                   placed.transform.paperOrigin.y.ticks - mmTicks(10))
            return ElevationView.items(document, direction, view: placed.transform)
                + SheetFrame.viewTitle(name, scale: scale, at: placed.fits ? under : titleAt)
        case let .schedule(kind):
            var areas: [RoomID: Area] = [:]
            if kind == .areas {
                for storey in document.storeys {
                    areas.merge(try geometry.roomAreas(of: document, storey: storey.id)) { first, _ in first }
                }
            }
            guard let table = ScheduleView.table(kind, document: document, style: units, areas: areas) else {
                return SheetFrame.notGenerated(Self.name(of: view), in: slot)
            }
            return ScheduleView.items(table, at: paperPoint(slot.minX, slot.maxY - mmTicks(8)))
        case .cover:
            return CoverSheet.items(project: document.project.name, index: sheetsToDraw(document), in: slot)
        case .roofPlan:
            guard let extent = RoofPlanView.extent(document) else {
                return SheetFrame.notGenerated("Roof plan has no roof", in: slot)
            }
            let scale = sheet.scale ?? Self.fittingScale(extent: extent, in: slot)
            let placed = ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: slot, scale: scale)
            let under = paperPoint(placed.transform.paperOrigin.x.ticks,
                                   placed.transform.paperOrigin.y.ticks - mmTicks(12))
            return RoofPlanView.items(document, view: placed.transform)
                + SheetFrame.viewTitle("Roof Plan", scale: scale, at: placed.fits ? under : titleAt)
        case .sitePlan:
            guard let extent = SitePlanView.extent(document) else {
                return SheetFrame.notGenerated("Site plan has no building or terrain", in: slot)
            }
            let scale = sheet.scale ?? Self.fittingScale(extent: extent, in: slot)
            let placed = ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: slot, scale: scale)
            return SitePlanView.items(document, view: placed.transform, area: slot)
                + SheetFrame.viewTitle("Site Plan", scale: scale, at: titleAt)
        case let .section(line):
            let outlines = try geometry.section(of: document, along: line)
            guard let extent = SectionView.extent(outlines) else {
                return SheetFrame.notGenerated("Section line crosses nothing", in: slot)
            }
            let scale = sheet.scale ?? Self.fittingScale(extent: extent, in: slot)
            let placed = ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: slot, scale: scale)
            let under = paperPoint(placed.transform.paperOrigin.x.ticks,
                                   placed.transform.paperOrigin.y.ticks - mmTicks(10))
            return SectionView.items(outlines, view: placed.transform)
                + SectionView.annotations(document, extent: extent, view: placed.transform,
                                          units: units)
                + SheetFrame.viewTitle("Building Section", scale: scale, at: placed.fits ? under : titleAt)
        case let .electricalPlan(storeyID):
            let storeyName = document.storeys.first { $0.id == storeyID }?.name ?? "Floor"
            guard document.mepSymbols.contains(where: { $0.storeyID == storeyID }),
                  let extent = FloorPlanView.extent(of: document, storey: storeyID) else {
                return SheetFrame.notGenerated(Self.name(of: view), in: slot)
            }
            let legendWidth = mmTicks(80)
            let planArea = PaperRect(minX: slot.minX, minY: slot.minY, width: slot.width - legendWidth,
                                     height: slot.height)
            let scale = sheet.scale ?? Self.fittingScale(extent: extent, in: planArea)
            let placed = ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: planArea, scale: scale)
            let outlines = try geometry.planView(of: document, storey: storeyID)
            let under = paperPoint(placed.transform.paperOrigin.x.ticks,
                                   placed.transform.paperOrigin.y.ticks - mmTicks(12))
            return ElectricalPlanView.items(document: document, storey: storeyID, outlines: outlines,
                                            view: placed.transform,
                                            legendAt: paperPoint(slot.maxX - legendWidth + mmTicks(6),
                                                                 slot.maxY - mmTicks(8)))
                + SheetFrame.viewTitle("\(storeyName) Electrical Plan", scale: scale, at: placed.fits ? under : titleAt)
        }
    }

    /// The project's display units, else imperial when any sheet uses an inch scale, metric otherwise.
    static func units(_ document: ModelDocument) -> LengthFormatStyle {
        DrawingUnits.style(document)
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
        let candidates: [DrawingScale] = [.quarterInch, .oneTo50, .eighthInch, .oneTo100,
                                          DrawingScale(label: "1\" = 20'-0\"", modelUnitsPerPaperUnit: 240),
                                          DrawingScale(label: "1:500", modelUnitsPerPaperUnit: 500)]
        for scale in candidates {
            let placed = ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: slot, scale: scale)
            if placed.fits { return scale }
        }
        return DrawingScale(label: "1:1000", modelUnitsPerPaperUnit: 1000)
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
