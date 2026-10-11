@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

private func fixture(_ name: String) throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/\(name).json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

private func pt(_ x: Double, _ y: Double) -> Point2 {
    Point2(x: Length(ticks: Int64((x * Double(Length.feet(1).ticks)).rounded())),
           y: Length(ticks: Int64((y * Double(Length.feet(1).ticks)).rounded())))
}

private func text(_ string: String, at x: Int64, _ y: Int64, height: Int64 = 2) -> DisplayItem {
    DisplayItem(.text(position: paperPoint(x, y), string: string, height: .millimeters(height),
                      rotation: .degrees(0), alignment: .left), style: DisplayStyle(layer: "A-ANNO-TEXT", pen: .fine))
}

private func line(_ x0: Int64, _ y0: Int64, _ x1: Int64, _ y1: Int64) -> DisplayItem {
    DisplayItem(.line(start: paperPoint(x0, y0), end: paperPoint(x1, y1)), style: DisplayStyle(layer: "A-WALL",
                                                                                               pen: .heavy))
}

/// A 24' by 12' house split into three `closet`-wide closets with long names and a great room, each 4' closet
/// with a door, on the cottage's 1/4" sheets: tight enough that tags set at the rooms' middles would run into
/// the walls, and with narrower closets too tight for any tag at all.
private func crowded(closet: Double = 4) throws -> ModelDocument {
    var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(UUID()), name: "Closets"),
                                 buildings: [], storeys: [], walls: [], openings: [], rooms: [])
    let building = BuildingID(UUID()), storey = StoreyID(UUID())
    var commands: [AnyCommand] = [
        AddBuildingCommand(buildingID: building, name: "House").erased,
        AddStoreyCommand(storeyID: storey, buildingID: building, name: "Ground Floor", elevation: .feet(0)).erased,
    ]
    var ids: [String: WallID] = [:]
    func wall(_ name: String, _ a: (Double, Double), _ b: (Double, Double)) {
        let id = WallID(UUID())
        ids[name] = id
        commands.append(AddWallCommand(wallID: id, storeyID: storey, start: pt(a.0, a.1), end: pt(b.0, b.1),
                                       thickness: .inches(6), height: .feet(8)).erased)
    }
    wall("south", (0, 0), (24, 0))
    wall("east", (24, 0), (24, 12))
    wall("north", (24, 12), (0, 12))
    wall("west", (0, 12), (0, 0))
    for index in 1...3 { wall("x\(index)", (closet * Double(index), 0), (closet * Double(index), 12)) }
    let rooms: [(String, [String])] = [
        ("Linen Closet", ["south", "x1", "north", "west"]),
        ("Mechanical Room", ["south", "x2", "north", "x1"]),
        ("Powder Room", ["south", "x3", "north", "x2"]),
        ("Great Room", ["south", "east", "north", "x3"]),
    ]
    for (name, sides) in rooms {
        commands.append(AddRoomCommand(roomID: RoomID(UUID()), storeyID: storey, name: name,
                                       boundaryWallIDs: sides.compactMap { ids[$0] }).erased)
    }
    for x in closet >= 4 ? [0.5, 4.5, 8.5] : [] {
        commands.append(AddOpeningCommand(openingID: OpeningID(UUID()), wallID: ids["south"]!,
                                          offsetAlongWall: pt(x, 0).x, width: .inches(32), height: .inches(80),
                                          sillHeight: .feet(0), kind: .singleDoor,
                                          swing: DoorSwing(hinge: .nearStart, opensToward: .left)).erased)
    }
    commands.append(AddOpeningCommand(openingID: OpeningID(UUID()), wallID: ids["south"]!, offsetAlongWall: .feet(16),
                                      width: .feet(4), height: .feet(4), sillHeight: .feet(3), kind: .window).erased)
    _ = try document.perform(batch: commands)
    return document
}

@Test func aLabelsBoxIsTheWidthPdfSetsItAt() {
    // "W1" at 2 mm cap height: Helvetica's W is 0.944 em and 1 is 0.556 em, the em 2 / 0.718 mm.
    let box = DrawingAudit.box("W1", at: paperPoint(0, 0), height: .millimeters(2), rotation: .degrees(0),
                               alignment: .left)
    let em = Double(Length.millimeters(2).ticks) / 0.718
    #expect(abs(box.maxX - box.minX - 1.5 * em) < 1)
    // Turned a quarter, it stands on end.
    let turned = DrawingAudit.box("W1", at: paperPoint(0, 0), height: .millimeters(2), rotation: .degrees(90),
                                  alignment: .left)
    #expect(abs(turned.maxY - turned.minY - 1.5 * em) < 1)
}

@Test func theAuditFindsTextOverLinesAndOverText() {
    let mm = mmTicks(1)
    let clear = [text("ROOM", at: 0, 0), line(0, -mm * 2, mm * 20, -mm * 2)]
    #expect(DrawingAudit.findings(clear, scale: nil).isEmpty)
    let struck = [text("ROOM", at: 0, 0), line(0, mm, mm * 20, mm)]
    #expect(DrawingAudit.findings(struck, scale: nil).map(\.other) == ["A-WALL linework"])
    let stacked = [text("ROOM", at: 0, 0), text("AREA", at: mm, mm)]
    #expect(DrawingAudit.findings(stacked, scale: nil).count == 1)
}

@Test func everyFixtureSheetPassesTheAudit() throws {
    for name in ["rect-cottage", "l-house"] {
        let sheets = try SchematicDrawingSet().sheets(for: fixture(name), geometry: HestiaGeometryEngine())
        for sheet in sheets {
            let found = DrawingAudit.findings(sheet)
            #expect(found.isEmpty, "\(name) \(sheet.number): \(found)")
        }
    }
}

@Test func tagsInRoomsTooSmallForThemStillClearTheWalls() throws {
    let sheets = try SchematicDrawingSet().sheets(for: crowded(), geometry: HestiaGeometryEngine())
    let plan = try #require(sheets.first { $0.number == "A-101" })
    let found = DrawingAudit.findings(plan)
    #expect(found.isEmpty, "\(found)")
    // Every room keeps at least its name.
    let strings = Set(plan.content.items.compactMap { item -> String? in
        guard case let .text(_, string, _, _, _) = item.primitive else { return nil }
        return string
    })
    for name in ["LINEN CLOSET", "MECHANICAL ROOM", "POWDER ROOM", "GREAT ROOM"] {
        #expect(strings.contains(name), "\(name) is missing")
    }
    // Every door keeps its mark.
    #expect(["D1", "D2", "D3", "W1"].allSatisfy(strings.contains))
}

@Test func aFigureWiderThanItsDimensionMovesBesideIt() {
    let mm = mmTicks(1)
    let style = DisplayStyle(layer: "A-ANNO-DIMS", pen: .fine)
    // A 3 mm step in a chain between two long ones: its figure cannot sit within it.
    let spans: [(Int64, Int64)] = [(0, 40), (40, 43), (43, 83)]
    var chain: [DisplayItem] = []
    for (a, b) in spans {
        let from = paperPoint(a * mm, 0), to = paperPoint(b * mm, 0)
        chain.append(DisplayItem(.dimension(from: from, to: to, offset: Length(ticks: -mm * 8), override: "9'-0\""),
                                 style: style))
    }
    #expect(!DrawingAudit.findings(chain, scale: nil).isEmpty)
    let fitted = DimensionText.fit(chain, scale: nil)
    #expect(DrawingAudit.findings(fitted, scale: nil).isEmpty)
    // The step keeps its lines, and its figure is still printed once.
    let figures = fitted.filter { item in
        if case let .text(_, string, _, _, _) = item.primitive { return string == "9'-0\"" }
        return false
    }
    #expect(figures.count == 1)
}

@Test func theSitePlansNamesStandClearOfTheHatchAndTheLines() throws {
    var document = try crowded()
    document.terrainPatches = [
        TerrainPatch(id: TerrainPatchID(rawValue: UUID()), name: "Lot",
                     boundary: [pt(-30, -30), pt(54, -30), pt(54, 42), pt(-30, 42)], surveyPoints: []),
    ]
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let site = try #require(sheets.first { $0.number == "A-001" })
    let found = DrawingAudit.findings(site)
    #expect(found.isEmpty, "\(found)")
    #expect(site.content.items.contains { item in
        if case let .text(_, string, _, _, _) = item.primitive { return string == "CLOSETS" }
        return false
    })
}

@Test func aLabelOverASymbolIsAFindingInsideItsRingToo() {
    let mm = mmTicks(1)
    let arrow = DisplayItem(.symbol(name: "north-arrow", position: paperPoint(0, 0), rotation: .degrees(0),
                                    size: .millimeters(16)), style: DisplayStyle(layer: "A-ANNO-SYMB", pen: .thin))
    // Wholly inside the 8 mm ring: no line crosses it, but it is over the symbol.
    let inside = [arrow, text("N", at: -mm, -mm)]
    #expect(DrawingAudit.findings(inside, scale: nil).map(\.other) == ["A-ANNO-SYMB symbol"])
    let beside = [arrow, text("N", at: mm * 10, -mm)]
    #expect(DrawingAudit.findings(beside, scale: nil).isEmpty)
    // Placement sees the disk too.
    var space = LabelSpace([arrow], scale: nil)
    #expect(space.collisions([text("N", at: -mm, -mm)]) > 0)
    #expect(space.place([[text("N", at: -mm, -mm)], [text("N", at: mm * 10, -mm)]]).count == 1)
    #expect(DrawingAudit.findings([arrow] + space.place([[text("N", at: -mm, -mm)]]), scale: nil).isEmpty)
}

@Test func aLabelWithNoClearPlaceIsLeftOut() {
    let mm = mmTicks(1)
    // A line through every place on offer.
    var space = LabelSpace([line(-mm * 50, mm, mm * 50, mm)], scale: nil)
    let candidates = [-20, 0, 20].map { [text("ROOM", at: Int64($0) * mm, 0)] }
    #expect(space.place(candidates).isEmpty)
    #expect(space.labels.isEmpty)
}

@Test func tagsInRoomsTooTightForAnyFormAreLeftOutNotPrintedOver() throws {
    // Nine-inch closets: no tag form fits within them clear of their walls.
    let sheets = try SchematicDrawingSet().sheets(for: crowded(closet: 0.75), geometry: HestiaGeometryEngine())
    let plan = try #require(sheets.first { $0.number == "A-101" })
    let found = DrawingAudit.findings(plan)
    #expect(found.isEmpty, "\(found)")
    let strings = Set(plan.content.items.compactMap { item -> String? in
        guard case let .text(_, string, _, _, _) = item.primitive else { return nil }
        return string
    })
    #expect(strings.contains("GREAT ROOM"))
    #expect(!strings.contains("LINEN CLOSET"), "a tag with no room is left out")
}

@Test func aDimensionWhoseFigureHasNoClearPlaceIsLeftOutWhole() {
    let mm = mmTicks(1)
    let style = DisplayStyle(layer: "A-ANNO-DIMS", pen: .fine)
    let spans: [(Int64, Int64, String)] = [(0, 40, "9'-0\""), (40, 43, "10'-0\""), (43, 83, "9'-0\"")]
    var chain: [DisplayItem] = []
    for (a, b, figure) in spans {
        chain.append(DisplayItem(.dimension(from: paperPoint(a * mm, 0), to: paperPoint(b * mm, 0),
                                            offset: Length(ticks: -mm * 8), override: figure), style: style))
    }
    // Hatch over everywhere the short step's figure could move to.
    let field = [paperPoint(-mm * 60, -mm * 60), paperPoint(mm * 140, -mm * 60), paperPoint(mm * 140, mm * 60),
                 paperPoint(-mm * 60, mm * 60)]
    let hatch = DisplayItem(.hatch(boundary: field, pattern: .diagonal, spacing: .millimeters(2), angle: .degrees(45)),
                            style: DisplayStyle(layer: "A-PATT", pen: .fine))
    let fitted = DimensionText.fit(chain + [hatch], scale: nil)
    let shortStep = fitted.contains { item in
        guard case let .dimension(from, to, _, _) = item.primitive else { return false }
        return from == paperPoint(mm * 40, 0) && to == paperPoint(mm * 43, 0)
    }
    #expect(!shortStep, "the step with no room for its figure is left out")
    #expect(!fitted.contains { item in
        if case let .text(_, string, _, _, _) = item.primitive { return string == "10'-0\"" }
        return false
    })
    #expect(fitted.filter { if case .dimension = $0.primitive { return true } else { return false } }.count == 2)
}
