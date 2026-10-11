import ATContracts
import Foundation

/// Builds the schematic drawing set: one paper-space sheet per `Sheet` in the model, each with the border,
/// title block, and boxed SCHEMATIC / NOT FOR CONSTRUCTION stamp. Output is not a permit set.
///
/// When the model has no sheets, it draws one floor plan sheet per storey on ARCH D at 1/4" = 1'-0"; once
/// there are walls, an elevations sheet with all four elevations, each at the largest scale that fits, and a
/// section at 1/4" = 1'-0" cut south to north through the middle of the walls; and once there is a roof, a roof
/// plan at 1/4" = 1'-0". With walls the set also opens with a cover sheet (index, notes, and legend), then a
/// site plan at 1/8" = 1'-0" when the model has terrain, and closes with door and window schedules when it has
/// doors or windows. These sheets exist only in the drawn set, never in the model.
///
/// A view that does not fit its sheet at the sheet's scale is drawn at the largest standard scale that does, and
/// the title block prints the scale the views were actually drawn at, or AS NOTED when they differ.
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
        guard !document.walls.isEmpty else { return sheets }
        // A set reads as a set: the cover with its index, notes, and legend first; the site plan next when there
        // is a site; and the door and window schedules last when there are doors and windows to list.
        var front = [Sheet(id: Self.defaultSheetID(document, tag: 0x01), number: "A-000", title: "Cover",
                           paper: .archD, scale: nil, views: [.cover])]
        if !document.terrainPatches.isEmpty {
            front.append(Sheet(id: Self.defaultSheetID(document, tag: 0x02), number: "A-001", title: "Site Plan",
                               paper: .archD, scale: .eighthInch, views: [.sitePlan]))
        }
        var back: [Sheet] = []
        let schedules: [SheetView] = [
            document.openings.contains { $0.kind.isDoor } ? .schedule(kind: .doors) : nil,
            document.openings.contains { $0.kind.isWindow } ? .schedule(kind: .windows) : nil,
        ].compactMap { $0 }
        if !schedules.isEmpty {
            back.append(Sheet(id: Self.defaultSheetID(document, tag: 0x61), number: "A-601", title: "Schedules",
                              paper: .archD, scale: nil, views: schedules))
        }
        return front + sheets + back
    }

    /// The cut for the section the set adds on its own: through the middle of the largest roof and across its
    /// ridge, as blueprints cut, so the section shows that roof's pitch. That is south to north, as on the
    /// cottage, unless the roof's footprint is longer north to south, when it runs west to east. With no roof
    /// it crosses the middle of the box around every wall's centerline. Either way it runs from 1'-0" before
    /// that box to 1'-0" past it. A cut down a wall's centerline would draw that whole wall as cut, so it moves
    /// over by half that wall's thickness plus 1", or, when that lands inside another wall in line with the
    /// cut, back by the same amount. Nil with no walls, or when both sides land inside walls.
    static func defaultSectionLine(_ document: ModelDocument) -> SectionLine? {
        let xs: [Int64] = document.walls.flatMap { [$0.start.x.ticks, $0.end.x.ticks] }
        let ys: [Int64] = document.walls.flatMap { [$0.start.y.ticks, $0.end.y.ticks] }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
        let foot: Int64 = Length.feet(1).ticks
        let roof = mainRoofBox(document)
        if let roof, roof.y1 - roof.y0 > roof.x1 - roof.x0 {
            // The south-to-north rule with x and y swapped.
            let swapped = document.walls.map { wall -> Wall in
                var turned = wall
                turned.start = Point2(x: wall.start.y, y: wall.start.x)
                turned.end = Point2(x: wall.end.y, y: wall.end.x)
                return turned
            }
            guard let cut = sectionX(middle: (roof.y0 + roof.y1) / 2, walls: swapped) else { return nil }
            let y = Length(ticks: cut)
            return SectionLine(start: Point2(x: Length(ticks: x0 - foot), y: y),
                               end: Point2(x: Length(ticks: x1 + foot), y: y))
        }
        let middle = roof.map { ($0.x0 + $0.x1) / 2 } ?? (x0 + x1) / 2
        guard let cut = sectionX(middle: middle, walls: document.walls) else { return nil }
        let x = Length(ticks: cut)
        return SectionLine(start: Point2(x: x, y: Length(ticks: y0 - foot)),
                           end: Point2(x: x, y: Length(ticks: y1 + foot)))
    }

    /// The box around the largest roof's footprint, by that box's area; nil with no roof.
    static func mainRoofBox(_ document: ModelDocument) -> (x0: Int64, x1: Int64, y0: Int64, y1: Int64)? {
        let boxes = document.roofs.compactMap { roof -> (x0: Int64, x1: Int64, y0: Int64, y1: Int64)? in
            let xs = roof.footprint.map(\.x.ticks), ys = roof.footprint.map(\.y.ticks)
            guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
            return (x0, x1, y0, y1)
        }
        func area(_ box: (x0: Int64, x1: Int64, y0: Int64, y1: Int64)) -> Double {
            Double(box.x1 - box.x0) * Double(box.y1 - box.y0)
        }
        return boxes.max { area($0) < area($1) }
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
        let area = SheetFrame.drawingArea(for: sheet.paper)
        let slots = Self.slots(in: area, count: sheet.views.count)
        var drawn: [ViewDrawing] = []
        for (view, slot) in zip(sheet.views, slots) {
            drawn.append(try drawView(view, in: slot, sheet: sheet, document: document, geometry: geometry))
        }
        let scale = Self.printedScale(drawn.compactMap(\.scale), sheet: sheet)
        let items = SheetFrame.items(number: sheet.number, title: sheet.title, scale: scale, paper: sheet.paper,
                                     projectName: document.project.name, issueDate: issueDate)
            + drawn.flatMap(\.items)
        return SheetDrawing(number: sheet.number, title: sheet.title, paper: sheet.paper, scale: scale,
                            content: DisplayList(items: items))
    }

    /// A view's drawing and the scale it was drawn at; nil for views with no scale, such as a schedule.
    struct ViewDrawing {
        var items: [DisplayItem]
        var scale: DrawingScale?
    }

    /// The scale a sheet's title block prints: the one every scaled view on it was drawn at, which is the sheet's
    /// own unless a view had to be drawn smaller to fit; nil (AS NOTED) when its views differ. A sheet with no
    /// scaled views keeps its own.
    static func printedScale(_ scales: [DrawingScale], sheet: Sheet) -> DrawingScale? {
        guard let first = scales.first else { return sheet.scale }
        return scales.allSatisfy { $0 == first } ? first : nil
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
        return place(extent: extent, in: inner, sheetScale: sheet.scale,
                                imperial: Self.imperial(document, sheet: sheet))
    }

    /// A view centred in its area at the sheet's scale; or, when it does not fit there at that scale, at the
    /// largest standard scale that does, so it never runs over the title block or off the page. The view's title
    /// prints the scale it is drawn at. With no sheet scale it is the fitting scale.
    /// Whether a sheet's fallback scales are imperial: whether it measures in feet and inches, by the same
    /// rule as its dimensions (the project's units, its own scale, the set's other sheets, its paper).
    static func imperial(_ document: ModelDocument, sheet: Sheet) -> Bool {
        SchematicDrawingSet().dimensionUnits(document, sheet: sheet) == .feetInchesFractions
    }

    static func place(extent: (min: Point2, max: Point2), in area: PaperRect, sheetScale: DrawingScale?,
                      imperial: Bool) -> (transform: ViewTransform, fits: Bool) {
        if let sheetScale {
            let placed = ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: area,
                                                 scale: sheetScale)
            if placed.fits { return placed }
        }
        let scale = fittingScale(extent: extent, in: area, imperial: imperial)
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
    ) throws -> ViewDrawing {
        let titleAt = paperPoint(slot.minX, slot.minY - mmTicks(8))
        let units = self.units(document)
        func missing(_ text: String) -> ViewDrawing {
            ViewDrawing(items: SheetFrame.notGenerated(text, in: slot), scale: nil)
        }
        switch view {
        case let .floorPlan(storeyID):
            let storeyName = document.storeys.first { $0.id == storeyID }?.name ?? "Floor"
            guard let placed = Self.floorPlanPlacement(document, storey: storeyID, in: slot, sheet: sheet) else {
                return missing("\(storeyName) plan has no walls")
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
            // The walls, openings, stairs, and outside chains first; then the labels where they have room.
            let drawn = DimensionText.fit(
                FloorPlanView.items(document: document, storey: storeyID, outlines: outlines, areas: areas,
                                    view: placed.transform, stairsBelow: stairsBelow, labels: false)
                    + DimensionChains.items(document: document, storey: storeyID, view: placed.transform,
                                            units: dimensionUnits(document, sheet: sheet)),
                scale: scale)
            let items = drawn
                + PlanLabels.items(document: document, storey: storeyID, areas: areas, view: placed.transform,
                                   drawn: drawn, units: dimensionUnits(document, sheet: sheet))
                + SheetFrame.viewTitle("\(storeyName) Plan", scale: scale, at: placed.fits ? under : titleAt)
            return ViewDrawing(items: items, scale: scale)
        case let .elevation(direction):
            let name = Self.name(of: view)
            let roofIDs = Set(document.roofs.map(\.id.rawValue))
            let slabIDs = Set(document.slabs.map(\.id.rawValue))
            let meshes = try geometry.meshes(of: document)
            let roofMeshes = meshes.filter { mesh in mesh.elementID.map { roofIDs.contains($0) } ?? false }
            let slabMeshes = meshes.filter { mesh in mesh.elementID.map { slabIDs.contains($0) } ?? false }
            // Drawn from the meshes, an elevation needs no wall square to it: any house has one.
            let found = meshes.isEmpty ? ElevationView.extent(document, direction, roofMeshes: roofMeshes)
                : ElevationView.meshExtent(document, direction, meshes: meshes)
            guard let extent = found else {
                return missing(name)
            }
            let placed = Self.place(extent: extent, in: slot, sheetScale: sheet.scale,
                                imperial: Self.imperial(document, sheet: sheet))
            let scale = placed.transform.scale
            let under = paperPoint(placed.transform.paperOrigin.x.ticks,
                                   placed.transform.paperOrigin.y.ticks - mmTicks(10))
            let items = ElevationView.items(document, direction, view: placed.transform, roofMeshes: roofMeshes,
                                            slabMeshes: slabMeshes, meshes: meshes)
                + SheetFrame.viewTitle(name, scale: scale, at: placed.fits ? under : titleAt)
            return ViewDrawing(items: items, scale: scale)
        case let .schedule(kind):
            var areas: [RoomID: Area] = [:]
            if kind == .areas {
                let walked = RoomWalk.walked(document)
                for storey in document.storeys {
                    areas.merge(try geometry.roomAreas(of: walked, storey: storey.id)) { first, _ in first }
                }
            }
            guard let table = ScheduleView.table(kind, document: document, style: units, areas: areas) else {
                return missing(Self.name(of: view))
            }
            return ViewDrawing(items: ScheduleView.items(table, at: paperPoint(slot.minX, slot.maxY - mmTicks(8)),
                                                         height: slot.height - mmTicks(8), width: slot.width),
                               scale: nil)
        case .cover:
            return ViewDrawing(items: CoverSheet.items(project: document.project.name, index: sheetsToDraw(document),
                                                       in: slot),
                               scale: nil)
        case .roofPlan:
            guard let extent = RoofPlanView.extent(document) else {
                return missing("Roof plan has no roof")
            }
            let placed = Self.place(extent: extent, in: slot, sheetScale: sheet.scale,
                                imperial: Self.imperial(document, sheet: sheet))
            let scale = placed.transform.scale
            let under = paperPoint(placed.transform.paperOrigin.x.ticks,
                                   placed.transform.paperOrigin.y.ticks - mmTicks(12))
            let roofIDs = Set(document.roofs.map(\.id.rawValue))
            let roofMeshes = try geometry.meshes(of: document).filter { mesh in
                mesh.elementID.map { roofIDs.contains($0) } ?? false
            }
            let items = RoofPlanView.items(document, view: placed.transform, roofMeshes: roofMeshes)
                + SheetFrame.viewTitle("Roof Plan", scale: scale, at: placed.fits ? under : titleAt)
            return ViewDrawing(items: items, scale: scale)
        case .sitePlan:
            let roofIDs = Set(document.roofs.map(\.id.rawValue))
            let roofMeshes = try geometry.meshes(of: document).filter { mesh in
                mesh.elementID.map { roofIDs.contains($0) } ?? false
            }
            guard let extent = SitePlanView.extent(document, roofMeshes: roofMeshes) else {
                return missing("Site plan has no building or terrain")
            }
            let placed = Self.place(extent: extent, in: slot, sheetScale: sheet.scale,
                                imperial: Self.imperial(document, sheet: sheet))
            let scale = placed.transform.scale
            let items = SitePlanView.items(document, view: placed.transform, area: slot, units: units,
                                           roofMeshes: roofMeshes)
                + SheetFrame.viewTitle("Site Plan", scale: scale, at: titleAt)
            return ViewDrawing(items: items, scale: scale)
        case let .section(line):
            var outlines = try geometry.section(of: document, along: line)
            // What lies beyond the cut comes from the meshes with hidden lines removed, when the engine gives them.
            // Below the lowest floor, not below grade: a section shows a basement.
            let grade = document.storeys.map(\.elevation.ticks).min() ?? 0
            let meshes = try geometry.meshes(of: document)
            var beyond: [HiddenLines.Segment] = []
            if !outlines.isEmpty, !meshes.isEmpty, let projection = ElevationView.lines(line) {
                beyond = ElevationView.visibleSegments(meshes, view: projection, grade: grade, near: 0)
                outlines.removeAll { $0.classification != .cut }
            }
            guard let extent = SectionView.extent(outlines, beyond: beyond) else {
                return missing("Section line crosses nothing")
            }
            let placed = Self.place(extent: extent, in: slot, sheetScale: sheet.scale,
                                imperial: Self.imperial(document, sheet: sheet))
            let scale = placed.transform.scale
            let under = paperPoint(placed.transform.paperOrigin.x.ticks,
                                   placed.transform.paperOrigin.y.ticks - mmTicks(10))
            let items = ElevationView.lineItems(beyond, transform: placed.transform, openings: [],
                                                beyond: SectionView.beyondStyle)
                + SectionView.items(outlines, view: placed.transform)
                + SectionView.annotations(document, extent: extent, view: placed.transform, units: units)
                + SheetFrame.viewTitle("Building Section", scale: scale, at: placed.fits ? under : titleAt)
            return ViewDrawing(items: items, scale: scale)
        case let .electricalPlan(storeyID):
            let storeyName = document.storeys.first { $0.id == storeyID }?.name ?? "Floor"
            guard document.mepSymbols.contains(where: { $0.storeyID == storeyID }),
                  let extent = FloorPlanView.extent(of: document, storey: storeyID) else {
                return missing(Self.name(of: view))
            }
            let legendWidth = mmTicks(80)
            let planArea = PaperRect(minX: slot.minX, minY: slot.minY, width: slot.width - legendWidth,
                                     height: slot.height)
            let placed = Self.place(extent: extent, in: planArea, sheetScale: sheet.scale,
                                imperial: Self.imperial(document, sheet: sheet))
            let scale = placed.transform.scale
            let outlines = try geometry.planView(of: document, storey: storeyID)
            let under = paperPoint(placed.transform.paperOrigin.x.ticks,
                                   placed.transform.paperOrigin.y.ticks - mmTicks(12))
            let items = ElectricalPlanView.items(document: document, storey: storeyID, outlines: outlines,
                                                 view: placed.transform,
                                                 legendAt: paperPoint(slot.maxX - legendWidth + mmTicks(6),
                                                                      slot.maxY - mmTicks(8)))
                + SheetFrame.viewTitle("\(storeyName) Electrical Plan", scale: scale,
                                       at: placed.fits ? under : titleAt)
            return ViewDrawing(items: items, scale: scale)
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

    /// 3/16" = 1'-0", the step between 1/4" and 1/8" for houses too long for 1/4" on the sheet.
    static let threeSixteenthsInch = DrawingScale(label: "3/16\" = 1'-0\"", modelUnitsPerPaperUnit: 64)

    /// The fallback scales an architect would reach for, largest drawing first: feet and inches for an imperial
    /// sheet, ratios for a metric one.
    static let imperialScales: [DrawingScale] = [
        .quarterInch, threeSixteenthsInch, .eighthInch,
        DrawingScale(label: "1\" = 10'-0\"", modelUnitsPerPaperUnit: 120),
        DrawingScale(label: "1/16\" = 1'-0\"", modelUnitsPerPaperUnit: 192),
        DrawingScale(label: "1\" = 20'-0\"", modelUnitsPerPaperUnit: 240),
        DrawingScale(label: "1\" = 40'-0\"", modelUnitsPerPaperUnit: 480),
        DrawingScale(label: "1\" = 100'-0\"", modelUnitsPerPaperUnit: 1200),
    ]
    static let metricScales: [DrawingScale] = [
        .oneTo50, .oneTo100,
        DrawingScale(label: "1:200", modelUnitsPerPaperUnit: 200),
        DrawingScale(label: "1:500", modelUnitsPerPaperUnit: 500),
        DrawingScale(label: "1:1000", modelUnitsPerPaperUnit: 1000),
    ]

    /// The largest scale of the sheet's family at which the extent fits the slot, else the family's smallest.
    static func fittingScale(extent: (min: Point2, max: Point2), in slot: PaperRect, imperial: Bool)
        -> DrawingScale {
        let candidates = imperial ? imperialScales : metricScales
        for scale in candidates {
            let placed = ViewTransform.centering(modelMin: extent.min, modelMax: extent.max, in: slot, scale: scale)
            if placed.fits { return scale }
        }
        return candidates[candidates.count - 1]
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
