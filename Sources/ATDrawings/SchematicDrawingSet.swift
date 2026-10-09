import ATContracts
import Foundation

/// Builds the schematic drawing set: one paper-space sheet per `Sheet` in the model, each with the border,
/// title block, and boxed SCHEMATIC / NOT FOR CONSTRUCTION stamp. Output is not a permit set.
///
/// When the model has no sheets, it draws one floor plan sheet per storey on ARCH D at 1/4" = 1'-0"; once
/// there are walls, an elevations sheet with all four elevations, each at the largest scale that fits, and a
/// section at 1/4" = 1'-0" cut south to north through the middle of the walls; and once there is a roof, a roof
/// plan at 1/4" = 1'-0". These sheets exist only in the drawn set, never in the model.
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
        var sheets: [Sheet] = document.storeys.enumerated().map { index, storey in
            Sheet(id: SheetID(storey.id.rawValue), number: String(format: "A-%d", 101 + index),
                  title: "\(storey.name) Plan", paper: .archD, scale: .quarterInch,
                  views: [.floorPlan(storeyID: storey.id)])
        }
        if !document.walls.isEmpty {
            let views: [SheetView] = [
                .elevation(direction: .south), .elevation(direction: .north),
                .elevation(direction: .east), .elevation(direction: .west),
            ]
            sheets.append(Sheet(id: Self.defaultSheetID(document, tag: 0x21), number: "A-201", title: "Elevations",
                                paper: .archD, scale: nil, views: views))
            if let line = Self.defaultSectionLine(document) {
                sheets.append(Sheet(id: Self.defaultSheetID(document, tag: 0x31), number: "A-301",
                                    title: "Building Section", paper: .archD, scale: .quarterInch,
                                    views: [.section(line: line)]))
            }
        }
        if !document.roofs.isEmpty {
            sheets.append(Sheet(id: Self.defaultSheetID(document, tag: 0x41), number: "A-401", title: "Roof Plan",
                                paper: .archD, scale: .quarterInch, views: [.roofPlan]))
        }
        return sheets
    }

    /// The cut for the section the set adds on its own: south to north, as on the cottage, at the middle of the
    /// box around every wall's centerline, from 1'-0" south of it to 1'-0" north. A cut down a north-south wall's
    /// centerline would draw that whole wall as cut, so it moves east by half that wall's thickness plus 1", or,
    /// when that lands inside another north-south wall, west by the same amount. Nil with no walls, or when both
    /// sides land inside walls.
    static func defaultSectionLine(_ document: ModelDocument) -> SectionLine? {
        let xs: [Int64] = document.walls.flatMap { [$0.start.x.ticks, $0.end.x.ticks] }
        let ys: [Int64] = document.walls.flatMap { [$0.start.y.ticks, $0.end.y.ticks] }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
        let foot: Int64 = Length.feet(1).ticks
        guard let cut = sectionX(middle: (x0 + x1) / 2, walls: document.walls) else { return nil }
        let x = Length(ticks: cut)
        return SectionLine(start: Point2(x: x, y: Length(ticks: y0 - foot)),
                           end: Point2(x: x, y: Length(ticks: y1 + foot)))
    }

    /// Where a south-to-north cut goes near `middle`, clear of running down a north-south wall.
    static func sectionX(middle: Int64, walls: [Wall]) -> Int64? {
        let northSouth: [Wall] = walls.filter { wall in
            wall.start.x.ticks == wall.end.x.ticks && wall.start.y.ticks != wall.end.y.ticks
        }
        let onCut: [Wall] = northSouth.filter { $0.start.x.ticks == middle }
        guard let thickest = onCut.map(\.thickness.ticks).max() else { return middle }
        let shift: Int64 = thickest / 2 + Length.inches(1).ticks
        // Inside a north-south wall: within half its thickness of its centerline.
        func inside(_ x: Int64) -> Bool {
            northSouth.contains { abs($0.start.x.ticks - x) <= $0.thickness.ticks / 2 }
        }
        if !inside(middle + shift) { return middle + shift }
        if !inside(middle - shift) { return middle - shift }
        return nil
    }

    /// A stable ID for a sheet the set adds on its own: the project's ID with its last byte changed by `tag`.
    static func defaultSheetID(_ document: ModelDocument, tag: UInt8) -> SheetID {
        var bytes = document.project.id.rawValue.uuid
        bytes.15 ^= tag
        bytes.14 ^= 0xA5
        return SheetID(UUID(uuid: bytes))
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

    /// The transform a storey's floor plan is drawn with, from model space to its sheet's paper space, so a view
    /// of that sheet can map points back into the model with `ViewTransform.model`. It is the floor plan's own
    /// placement, from the first sheet that draws the plan. Nil when no sheet draws it or the storey has no walls.
    public func planTransform(for document: ModelDocument, storey: StoreyID) -> ViewTransform? {
        for sheet in sheetsToDraw(document) {
            let slots = Self.slots(in: SheetFrame.drawingArea(for: sheet.paper), count: sheet.views.count)
            for (view, slot) in zip(sheet.views, slots) where view == .floorPlan(storeyID: storey) {
                return Self.floorPlanPlacement(document, storey: storey, in: slot, sheet: sheet)?.transform
            }
        }
        return nil
    }

    /// A floor plan's placement in its slot, leaving room outside it for the dimension chains on the south and
    /// west. The one rule both drawing and `planTransform` use.
    static func floorPlanPlacement(_ document: ModelDocument, storey: StoreyID, in slot: PaperRect, sheet: Sheet)
        -> (transform: ViewTransform, fits: Bool)? {
        guard let extent = FloorPlanView.extent(of: document, storey: storey) else { return nil }
        let reserve = DimensionChains.reserve
        let inner = PaperRect(minX: slot.minX + reserve, minY: slot.minY + reserve,
                              width: slot.width - reserve, height: slot.height - reserve)
        return place(extent: extent, in: inner, sheetScale: sheet.scale)
    }

    /// A view centred in its area at the sheet's scale; or, when it does not fit there at that scale, at the
    /// largest standard scale that does, so it never runs over the title block or off the page. The view's title
    /// prints the scale it is drawn at. With no sheet scale it is the fitting scale.
    static func place(extent: (min: Point2, max: Point2), in area: PaperRect, sheetScale: DrawingScale?)
        -> (transform: ViewTransform, fits: Bool) {
        if let sheetScale {
            let placed = ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: area,
                                                 scale: sheetScale)
            if placed.fits { return placed }
        }
        let scale = fittingScale(extent: extent, in: area)
        return ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: area, scale: scale)
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
        let units = self.units(document)
        switch view {
        case let .floorPlan(storeyID):
            let storeyName = document.storeys.first { $0.id == storeyID }?.name ?? "Floor"
            guard let placed = Self.floorPlanPlacement(document, storey: storeyID, in: slot, sheet: sheet) else {
                return SheetFrame.notGenerated("\(storeyName) plan has no walls", in: slot)
            }
            let reserve = DimensionChains.reserve
            let scale = placed.transform.scale
            let outlines = try geometry.planView(of: document, storey: storeyID)
            // The engine meets each wall's line with the next one's, so give it the walls walking around.
            let areas = try geometry.roomAreas(of: RoomWalk.walked(document), storey: storeyID)
            var stairsBelow: [ClassifiedOutline] = []
            if let below = Self.storey(below: storeyID, in: document) {
                stairsBelow = try geometry.planView(of: document, storey: below.id).filter { $0.kind == .stair }
            }
            let under = paperPoint(placed.transform.paperOrigin.x.ticks - reserve,
                                   placed.transform.paperOrigin.y.ticks - reserve - mmTicks(8))
            return FloorPlanView.items(document: document, storey: storeyID, outlines: outlines, areas: areas,
                                       view: placed.transform, stairsBelow: stairsBelow)
                + DimensionChains.items(document: document, storey: storeyID, view: placed.transform,
                                        units: dimensionUnits(document, sheet: sheet))
                + DimensionChains.interiorItems(document: document, storey: storeyID, view: placed.transform,
                                                units: dimensionUnits(document, sheet: sheet))
                + SheetFrame.viewTitle("\(storeyName) Plan", scale: scale, at: placed.fits ? under : titleAt)
        case let .elevation(direction):
            let name = Self.name(of: view)
            let roofIDs = Set(document.roofs.map(\.id.rawValue))
            let slabIDs = Set(document.slabs.map(\.id.rawValue))
            let meshes = try geometry.meshes(of: document)
            let roofMeshes = meshes.filter { mesh in mesh.elementID.map { roofIDs.contains($0) } ?? false }
            let slabMeshes = meshes.filter { mesh in mesh.elementID.map { slabIDs.contains($0) } ?? false }
            guard let extent = ElevationView.extent(document, direction, roofMeshes: roofMeshes) else {
                return SheetFrame.notGenerated(name, in: slot)
            }
            let placed = Self.place(extent: extent, in: slot, sheetScale: sheet.scale)
            let scale = placed.transform.scale
            let under = paperPoint(placed.transform.paperOrigin.x.ticks,
                                   placed.transform.paperOrigin.y.ticks - mmTicks(10))
            return ElevationView.items(document, direction, view: placed.transform, roofMeshes: roofMeshes,
                                       slabMeshes: slabMeshes)
                + SheetFrame.viewTitle(name, scale: scale, at: placed.fits ? under : titleAt)
        case let .schedule(kind):
            var areas: [RoomID: Area] = [:]
            if kind == .areas {
                let walked = RoomWalk.walked(document)
                for storey in document.storeys {
                    areas.merge(try geometry.roomAreas(of: walked, storey: storey.id)) { first, _ in first }
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
            let placed = Self.place(extent: extent, in: slot, sheetScale: sheet.scale)
            let scale = placed.transform.scale
            let under = paperPoint(placed.transform.paperOrigin.x.ticks,
                                   placed.transform.paperOrigin.y.ticks - mmTicks(12))
            let roofIDs = Set(document.roofs.map(\.id.rawValue))
            let roofMeshes = try geometry.meshes(of: document).filter { mesh in
                mesh.elementID.map { roofIDs.contains($0) } ?? false
            }
            return RoofPlanView.items(document, view: placed.transform, roofMeshes: roofMeshes)
                + SheetFrame.viewTitle("Roof Plan", scale: scale, at: placed.fits ? under : titleAt)
        case .sitePlan:
            guard let extent = SitePlanView.extent(document) else {
                return SheetFrame.notGenerated("Site plan has no building or terrain", in: slot)
            }
            let placed = Self.place(extent: extent, in: slot, sheetScale: sheet.scale)
            let scale = placed.transform.scale
            return SitePlanView.items(document, view: placed.transform, area: slot)
                + SheetFrame.viewTitle("Site Plan", scale: scale, at: titleAt)
        case let .section(line):
            let outlines = try geometry.section(of: document, along: line)
            guard let extent = SectionView.extent(outlines) else {
                return SheetFrame.notGenerated("Section line crosses nothing", in: slot)
            }
            let placed = Self.place(extent: extent, in: slot, sheetScale: sheet.scale)
            let scale = placed.transform.scale
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
            let placed = Self.place(extent: extent, in: planArea, sheetScale: sheet.scale)
            let scale = placed.transform.scale
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

    /// The next storey down in the same building, or nil for the lowest.
    static func storey(below id: StoreyID, in document: ModelDocument) -> Storey? {
        guard let storey = document.storeys.first(where: { $0.id == id }) else { return nil }
        let lower = document.storeys.filter {
            $0.buildingID == storey.buildingID && $0.elevation.ticks < storey.elevation.ticks
        }
        return lower.max { $0.elevation.ticks < $1.elevation.ticks }
    }

    /// The project's display units, else imperial when any sheet uses an inch scale, metric otherwise.
    /// Units for set-wide text, such as section level marks and schedules: the project's own, else imperial
    /// when any sheet the set draws has an imperial scale, counting the sheets it adds on its own.
    func units(_ document: ModelDocument) -> LengthFormatStyle {
        if let units = document.project.displayUnits { return units }
        return sheetsToDraw(document).contains { DrawingUnits.isImperial($0.scale) } ? .feetInchesFractions : .metric
    }

    /// Units for a plan's dimensions: the project's own; else those the sheet's scale implies (an inch mark
    /// means feet and inches, otherwise millimetres); else, on a sheet with no scale, those the set's other
    /// sheets imply; else, when no sheet has a scale, feet and inches on inch paper and millimetres on ISO.
    /// A sheet with no scale is drawn at a fitted one, and its dimensions never take their units from that.
    func dimensionUnits(_ document: ModelDocument, sheet: Sheet) -> LengthFormatStyle {
        if let units = document.project.displayUnits { return units }
        if let scale = sheet.scale { return DrawingUnits.isImperial(scale) ? .feetInchesFractions : .metric }
        let scales = sheetsToDraw(document).compactMap(\.scale)
        if !scales.isEmpty { return scales.contains(where: DrawingUnits.isImperial) ? .feetInchesFractions : .metric }
        return DrawingUnits.isInchPaper(sheet.paper) ? .feetInchesFractions : .metric
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
