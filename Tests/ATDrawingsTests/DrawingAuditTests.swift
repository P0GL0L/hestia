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

/// A 24' by 12' house split into three 4' closets with long names and a great room, each closet with a door,
/// on the cottage's 1/4" sheets: tight enough that tags set at the rooms' middles would run into the walls.
private func crowded() throws -> ModelDocument {
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
    for x in [4.0, 8.0, 12.0] { wall("x\(Int(x))", (x, 0), (x, 12)) }
    let rooms: [(String, [String])] = [
        ("Linen Closet", ["south", "x4", "north", "west"]),
        ("Mechanical Room", ["south", "x8", "north", "x4"]),
        ("Powder Room", ["south", "x12", "north", "x8"]),
        ("Great Room", ["south", "east", "north", "x12"]),
    ]
    for (name, sides) in rooms {
        commands.append(AddRoomCommand(roomID: RoomID(UUID()), storeyID: storey, name: name,
                                       boundaryWallIDs: sides.compactMap { ids[$0] }).erased)
    }
    for x in [0.5, 4.5, 8.5] {
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
