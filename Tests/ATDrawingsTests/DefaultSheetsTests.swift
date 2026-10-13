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

private func ft(_ feet: Int64) -> Length { .feet(feet) }
private func pt(_ x: Int64, _ y: Int64) -> Point2 { Point2(x: ft(x), y: ft(y)) }
private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }

private let storey = StoreyID(uuid(3))

/// One building with one ground storey and no sheets; with `walls`, a 20' by 15' box of 8' walls; with
/// `roof`, the cottage's hip roof over it.
private func model(walls: Bool, roof: Bool) throws -> ModelDocument {
    var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(uuid(1)), name: "Box"),
                                 buildings: [], storeys: [], walls: [], openings: [], rooms: [])
    var commands: [AnyCommand] = [
        AddBuildingCommand(buildingID: BuildingID(uuid(2)), name: "Box").erased,
        AddStoreyCommand(storeyID: storey, buildingID: BuildingID(uuid(2)), name: "Ground Floor",
                         elevation: ft(0)).erased,
    ]
    let corners: [Point2] = [pt(0, 0), pt(20, 0), pt(20, 15), pt(0, 15)]
    if walls {
        for i in 0..<4 {
            commands.append(AddWallCommand(wallID: WallID(uuid(10 + i)), storeyID: storey, start: corners[i],
                                           end: corners[(i + 1) % 4], thickness: .inches(6), height: ft(8)).erased)
        }
    }
    if roof {
        commands.append(AddRoofCommand(roofID: RoofID(uuid(20)), storeyID: storey, footprint: corners,
                                       eaveHeight: ft(8), pitchRisePer12: .inches(6), overhang: ft(1)).erased)
    }
    _ = try document.perform(batch: commands)
    return document
}

private func draw(_ document: ModelDocument) throws -> [SheetDrawing] {
    try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
}

/// Text on a sheet saying a view was not generated.
private func notGenerated(_ sheet: SheetDrawing) -> [String] {
    sheet.content.items.compactMap { item in
        guard case let .text(_, string, _, _, _) = item.primitive, string.contains("not generated") else { return nil }
        return string
    }
}

private func count(_ sheet: SheetDrawing, layerPrefix: String) -> Int {
    sheet.content.items.filter { $0.style.layer.hasPrefix(layerPrefix) }.count
}

/// The true paper box around linework, labels, and filled areas, using the same Helvetica cap-height geometry
/// as the PDF renderer rather than `DisplayList.bounds`, which deliberately counts text at its anchor only.
private func drawnExtent(_ sheet: SheetDrawing, excludingTitleBlock: Bool = false)
    -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    let items = excludingTitleBlock
        ? sheet.content.items.filter { !$0.style.layer.hasPrefix("A-ANNO-TTLB") }
        : sheet.content.items
    let parts = DrawingAudit.parts(items, scale: sheet.scale)
    var xs: [Double] = [], ys: [Double] = []
    for stroke in parts.strokes { xs += [stroke.a.x, stroke.b.x]; ys += [stroke.a.y, stroke.b.y] }
    for label in parts.labels { xs += label.box.corners.map(\.x); ys += label.box.corners.map(\.y) }
    for area in parts.areas { xs += area.boundary.map(\.x); ys += area.boundary.map(\.y) }
    return (xs.min() ?? 0, ys.min() ?? 0, xs.max() ?? 0, ys.max() ?? 0)
}

@Test func aModelWithNoWallsGetsOnlyItsPlan() throws {
    let numbers: [String] = try draw(model(walls: false, roof: false)).map(\.number)
    #expect(numbers == ["A-101"])
}

@Test func wallsAddAnElevationsSheetWithAllFour() throws {
    let sheets = try draw(model(walls: true, roof: false))
    let numbers: [String] = sheets.map(\.number)
    #expect(numbers == ["A-000", "A-101", "A-201", "A-301"])
    let elevations = try #require(sheets.first { $0.number == "A-201" })
    #expect(elevations.title == "Elevations")
    #expect(notGenerated(elevations).isEmpty)
    // Four view titles, one per direction.
    let titles: [String] = elevations.content.items.compactMap { item in
        guard case let .text(_, string, _, _, _) = item.primitive, string.hasSuffix("ELEVATION") else { return nil }
        return string
    }
    #expect(Set(titles) == ["SOUTH ELEVATION", "NORTH ELEVATION", "EAST ELEVATION", "WEST ELEVATION"])
}

@Test func aRoofAddsARoofPlan() throws {
    let sheets = try draw(model(walls: true, roof: true))
    let numbers: [String] = sheets.map(\.number)
    #expect(numbers == ["A-000", "A-101", "A-201", "A-301", "A-401"])
    let roofPlan = try #require(sheets.first { $0.number == "A-401" })
    #expect(roofPlan.title == "Roof Plan")
    #expect(notGenerated(roofPlan).isEmpty)
    #expect(count(roofPlan, layerPrefix: "A-ROOF") > 0)
}

@Test func wallsAddASectionCutSouthToNorthThroughTheMiddle() throws {
    let document = try model(walls: true, roof: true)
    // The wall box runs 0' to 20' east and 0' to 15' north.
    let line = try #require(SchematicDrawingSet.defaultSectionLine(document))
    #expect(line == SectionLine(start: pt(10, -1), end: pt(10, 16)))
    let sheets = try draw(document)
    let section = try #require(sheets.first { $0.number == "A-301" })
    #expect(section.title == "Building Section")
    #expect(section.scale == .quarterInch)
    #expect(notGenerated(section).isEmpty)
    // The cut walls on the south and north, and the roof over them.
    #expect(count(section, layerPrefix: "A-SECT") > 0)
    // With no units set, its level marks read in feet and inches like the 1/4" sheets around it.
    let marks: [String] = section.content.items.compactMap { item in
        guard case let .text(_, string, _, _, _) = item.primitive, string.hasPrefix("GROUND FLOOR") else { return nil }
        return string
    }
    #expect(marks == ["GROUND FLOOR 0'-0\""])
}

@Test func aRoofRunningNorthSouthIsCutWestToEast() throws {
    var document = try model(walls: true, roof: true)
    // The roof narrowed to 10' east to west and left 15' north to south, so its ridge runs north to south.
    document.roofs[0].footprint = [pt(5, 0), pt(15, 0), pt(15, 15), pt(5, 15)]
    let line = try #require(SchematicDrawingSet.defaultSectionLine(document))
    let middle = Length.feet(7, inchCount: 6)
    #expect(line == SectionLine(start: Point2(x: ft(-1), y: middle), end: Point2(x: ft(21), y: middle)))
    let section = try #require(try draw(document).first { $0.number == "A-301" })
    #expect(notGenerated(section).isEmpty)
    #expect(count(section, layerPrefix: "A-SECT-MCUT") > 0)
}

@Test func noWallsNoSection() throws {
    let document = try model(walls: false, roof: false)
    #expect(SchematicDrawingSet.defaultSectionLine(document) == nil)
    let numbers: [String] = try draw(document).map(\.number)
    #expect(!numbers.contains("A-301"))
}

@Test func theAddedSheetsAreNotWrittenIntoTheModel() throws {
    let document = try model(walls: true, roof: true)
    let before = document
    _ = try draw(document)
    #expect(document == before)
    #expect(document.sheets.isEmpty)
    // The same IDs each time the set is drawn.
    let set = SchematicDrawingSet()
    let first: [SheetID] = set.sheetsToDraw(document).map(\.id)
    let again: [SheetID] = set.sheetsToDraw(document).map(\.id)
    #expect(first == again)
    #expect(Set(first).count == first.count)
}

@Test func aModelWithSheetsIsUnchanged() throws {
    for name in ["rect-cottage", "l-house"] {
        let document = try fixture(name)
        let drawn: [String] = try draw(document).map(\.number)
        let stored: [String] = document.sheets.map(\.number)
        #expect(drawn == stored, "\(name)")
    }
}

/// A north-south wall at `x`, 6" thick unless given, across the 15' box.
private func northSouth(_ x: Length, _ n: Int, thickness: Length = .inches(6)) -> Wall {
    Wall(id: WallID(uuid(40 + n)), storeyID: storey, start: Point2(x: x, y: ft(0)), end: Point2(x: x, y: ft(15)),
         thickness: thickness, height: ft(8))
}

private func inches(_ feet: Int64, _ inches: Int64) -> Int64 { Length.feet(feet, inchCount: inches).ticks }

@Test func aCutDownAPartitionMovesEastByHalfItsThicknessAndAnInch() throws {
    var document = try model(walls: true, roof: true)
    document.walls.append(northSouth(ft(10), 0))
    let line = try #require(SchematicDrawingSet.defaultSectionLine(document))
    // 3" half thickness plus 1": 10'-4".
    #expect(line.start.x.ticks == inches(10, 4))
    #expect(line.end.x.ticks == inches(10, 4))
    let sheets = try draw(document)
    let numbers: [String] = sheets.map(\.number)
    #expect(numbers.contains("A-301"))
}

@Test func aWallEastOfTheMoveSendsTheCutWest() throws {
    let walls: [Wall] = [northSouth(ft(10), 0), northSouth(Length.feet(10, inchCount: 4), 1, thickness: .inches(4))]
    let x: Int64? = SchematicDrawingSet.sectionX(middle: ft(10).ticks, walls: walls)
    #expect(x == inches(9, 8))
}

@Test func wallsOnBothSidesGiveNoCut() throws {
    let walls: [Wall] = [
        northSouth(ft(10), 0), northSouth(Length.feet(10, inchCount: 4), 1),
        northSouth(Length.feet(9, inchCount: 8), 2),
    ]
    let x: Int64? = SchematicDrawingSet.sectionX(middle: ft(10).ticks, walls: walls)
    #expect(x == nil)
    var document = try model(walls: true, roof: true)
    document.walls += walls
    #expect(SchematicDrawingSet.defaultSectionLine(document) == nil)
    let numbers: [String] = try draw(document).map(\.number)
    #expect(!numbers.contains("A-301"))
}

@Test func aMiddleClearOfWallsStaysAtTheMiddle() throws {
    // A partition off the middle, and east-west walls, leave the cut alone.
    let walls: [Wall] = [northSouth(ft(6), 0)]
    let x: Int64? = SchematicDrawingSet.sectionX(middle: ft(10).ticks, walls: walls)
    #expect(x == ft(10).ticks)
}

@Test func aSetOpensWithACoverThatIndexesItAndExplainsItsSymbols() throws {
    let sheets = try draw(model(walls: true, roof: true))
    let cover = try #require(sheets.first)
    #expect(cover.number == "A-000" && cover.title == "Cover")
    let words: [String] = cover.content.items.compactMap { item in
        guard case let .text(_, string, _, _, _) = item.primitive else { return nil }
        return string
    }
    for number in sheets.map(\.number) {
        #expect(words.contains(number), "the cover indexes \(number)")
    }
    #expect(words.contains("SYMBOLS") && words.contains("ABBREVIATIONS"))
    #expect(words.contains("WIC") && words.contains("Walk-in closet"))
    #expect(cover.content.items.contains { if case .symbol("north-arrow", _, _, _) = $0.primitive { return true }
        return false })
}

@Test func terrainAddsASitePlanAndOpeningsAddSchedules() throws {
    var document = try model(walls: true, roof: false)
    let wall = try #require(document.walls.first)
    _ = try document.perform(batch: [
        AddTerrainPatchCommand(terrainPatchID: TerrainPatchID(uuid(30)), name: "Lot",
                               boundary: [pt(-20, -20), pt(40, -20), pt(40, 35), pt(-20, 35)], surveyPoints: []).erased,
        AddOpeningCommand(openingID: OpeningID(uuid(31)), wallID: wall.id, offsetAlongWall: ft(2), width: ft(3),
                          height: .inches(80), sillHeight: ft(0), kind: .singleDoor).erased,
        AddOpeningCommand(openingID: OpeningID(uuid(32)), wallID: wall.id, offsetAlongWall: ft(10), width: ft(4),
                          height: ft(4), sillHeight: ft(3), kind: .window).erased,
    ])
    let sheets = try draw(document)
    #expect(sheets.map(\.number) == ["A-000", "A-001", "A-101", "A-201", "A-301", "A-601"])
    let site = try #require(sheets.first { $0.number == "A-001" })
    #expect(site.title == "Site Plan" && notGenerated(site).isEmpty)
    let schedules = try #require(sheets.last)
    let words: [String] = schedules.content.items.compactMap { item in
        guard case let .text(_, string, _, _, _) = item.primitive else { return nil }
        return string
    }
    #expect(words.contains("DOOR SCHEDULE") && words.contains("WINDOW SCHEDULE"))
}

@Test func aTitleBlockPrintsTheScaleItsViewsAreDrawnAt() throws {
    // 120' of walls cannot sit on ARCH D at 1/4" = 1'-0", so the plan is drawn smaller, and the title block
    // must say so rather than claim 1/4".
    var document = try model(walls: false, roof: false)
    let corners: [Point2] = [pt(0, 0), pt(120, 0), pt(120, 20), pt(0, 20)]
    _ = try document.perform(batch: (0..<4).map { i in
        AddWallCommand(wallID: WallID(uuid(40 + i)), storeyID: storey, start: corners[i], end: corners[(i + 1) % 4],
                       thickness: .inches(6), height: ft(8)).erased
    })
    let plan = try #require(try draw(document).first { $0.number == "A-101" })
    let scale = try #require(plan.scale)
    #expect(scale != .quarterInch)
    let words: [String] = plan.content.items.compactMap { item in
        guard case let .text(_, string, _, _, _) = item.primitive else { return nil }
        return string
    }
    #expect(words.contains(scale.label), "the title block prints \(scale.label)")
    #expect(!words.contains(DrawingScale.quarterInch.label))
}

/// A long, low row of walls: 120' of 8' walls in a line, so its elevations are many times wider than tall.
private func longRow(storeyName: String = "Ground Floor") throws -> ModelDocument {
    var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(uuid(1)), name: "Row"),
                                 buildings: [], storeys: [], walls: [], openings: [], rooms: [])
    var commands: [AnyCommand] = [
        AddBuildingCommand(buildingID: BuildingID(uuid(2)), name: "Row").erased,
        AddStoreyCommand(storeyID: storey, buildingID: BuildingID(uuid(2)), name: storeyName,
                         elevation: ft(0)).erased,
    ]
    for i in 0..<4 {
        let x = Int64(i) * 30
        commands.append(AddWallCommand(wallID: WallID(uuid(10 + i)), storeyID: storey, start: pt(x, 0),
                                       end: pt(x + 30, 0), thickness: .inches(6), height: ft(8)).erased)
    }
    _ = try document.perform(batch: commands)
    return document
}

@Test func belowGradeLevelNamesDoNotShrinkMeshElevations() throws {
    var document = try longRow()
    let basement = StoreyID(uuid(50))
    let basementName = String(repeating: "BELOW GRADE BASEMENT ", count: 20)
    _ = try document.perform(batch: [
        AddStoreyCommand(storeyID: basement, buildingID: BuildingID(uuid(2)), name: basementName,
                         elevation: ft(-8)).erased,
        AddWallCommand(wallID: WallID(uuid(51)), storeyID: basement, start: pt(0, 0), end: pt(120, 0),
                       thickness: .inches(6), height: ft(8)).erased,
    ])

    let sheet = try #require(try SchematicDrawingSet(paper: .archD)
        .sheets(for: document, geometry: HestiaGeometryEngine()).first { $0.number == "A-201" })
    let scales = sheet.content.items.compactMap { item -> String? in
        guard case let .text(_, string, _, _, _) = item.primitive, string.hasPrefix("SCALE:") else { return nil }
        return string
    }
    let levelLabels = sheet.content.items.compactMap { item -> String? in
        guard item.style == ElevationView.levelStyle,
              case let .text(_, string, _, _, _) = item.primitive else { return nil }
        return string
    }
    #expect(scales.filter { $0 == "SCALE: \(SchematicDrawingSet.threeSixteenthsInch.label)" }.count == 2)
    #expect(levelLabels.allSatisfy { !$0.hasPrefix(basementName) })
}

@Test func ordinaryFixtureElevationScalesStayAtTheirStoredValues() throws {
    let expected: [(fixture: String, number: String, scale: DrawingScale, titleCount: Int)] = [
        ("rect-cottage", "A-201", .quarterInch, 4),
        ("rect-cottage", "A-301", .quarterInch, 1),
        ("l-house", "A-201", .oneTo100, 4),
        ("l-house", "A-301", .quarterInch, 1),
    ]

    for item in expected {
        let sheet = try #require(draw(fixture(item.fixture)).first { $0.number == item.number })
        let scaleTitles = sheet.content.items.compactMap { display -> String? in
            guard case let .text(_, string, _, _, _) = display.primitive,
                  string.hasPrefix("SCALE:") else { return nil }
            return string
        }
        #expect(sheet.scale == item.scale, "\(item.fixture) \(item.number)")
        #expect(scaleTitles.count == item.titleCount, "\(item.fixture) \(item.number)")
        #expect(scaleTitles.allSatisfy { $0 == "SCALE: \(item.scale.label)" },
                "\(item.fixture) \(item.number)")
    }
}

@Test func longElevationsAndSectionsKeepTheirGroundLineAndLabelsOnTheirSheet() throws {
    let document = try longRow()
    for paper in SchematicDrawingSet.papers {
        let sheets = try SchematicDrawingSet(paper: paper).sheets(for: document, geometry: HestiaGeometryEngine())
        for number in ["A-201", "A-301"] {
            let sheet = try #require(sheets.first { $0.number == number })
            #expect(DrawingAudit.findings(sheet).isEmpty, "\(number) \(paper.name)")
            // Everything, including the true Helvetica boxes rather than only text anchors, stays in the area.
            let area = SheetFrame.drawingArea(for: paper)
            let bounds = drawnExtent(sheet, excludingTitleBlock: true)
            #expect(bounds.minX >= Double(area.minX) && bounds.maxX <= Double(area.minX + area.width),
                    "\(number) \(paper.name): \(bounds)")
            #expect(bounds.minY >= Double(area.minY) && bounds.maxY <= Double(area.minY + area.height),
                    "\(number) \(paper.name): \(bounds)")
        }
    }
}

@Test func levelLabelRoomUsesPDFCapHeightAndActualUnits() {
    let levels = [(name: "WEST WING UPPER FLOOR REFERENCE", z: Length.feet(999, inchCount: 11).ticks)]
    let labels = [LengthFormatStyle.feetInchesFractions, .metric].map { units in
        levels[0].name + " " + LengthFormatting.format(Length(ticks: levels[0].z), style: units)
    }
    let expectedWidth = labels.map {
        HelveticaMetrics.width(of: $0) * Double(ElevationView.levelTextHeight) / 0.718
    }.max() ?? 0
    let expected = Int64(expectedWidth.rounded(.up)) + mmTicks(1)
    #expect(ElevationView.labelRoom(levels) == expected)
}

@Test func longElevationLabelsUseTheirRenderedHelveticaBounds() throws {
    let name = "WEST WING UPPER FLOOR REFERENCE"
    let document = try longRow(storeyName: name)
    for paper in SchematicDrawingSet.papers {
        let sheets = try SchematicDrawingSet(paper: paper).sheets(for: document, geometry: HestiaGeometryEngine())
        let sheet = try #require(sheets.first { $0.number == "A-201" })
        let labels = DrawingAudit.parts(sheet.content.items, scale: sheet.scale).labels.filter {
            $0.layer == ElevationView.levelStyle.layer && $0.string.hasPrefix(name)
        }
        #expect(labels.count == 4, "\(paper.name)")
        let area = SheetFrame.drawingArea(for: paper)
        for label in labels {
            #expect(label.box.minX >= Double(area.minX), "\(paper.name): \(label.string)")
            #expect(label.box.maxX <= Double(area.minX + area.width), "\(paper.name): \(label.string)")
        }
    }
}

/// The long elevations' scale and ground line, worked out by hand: the row is 120'-0" long and its ground line
/// runs 1500 mm past each end, 129.8425' in all; at 3/16" = 1'-0" that is 24.3455" of paper, 197880 ticks at
/// 8128 to the inch; at 1/8", 131920; at 1/16", 65960. Each sheet takes the largest scale whose padded view still
/// fits beside the level labels.
@Test func longElevationsStepDownToTheScaleThatHoldsTheirGroundLine() throws {
    let document = try longRow()
    let sixteenth = DrawingScale(label: "1/16\" = 1'-0\"", modelUnitsPerPaperUnit: 192)
    let expected: [(paper: PaperSize, scale: DrawingScale, ground: Int64)] = [
        (.archD, SchematicDrawingSet.threeSixteenthsInch, 197_880),
        (.isoA1, SchematicDrawingSet.threeSixteenthsInch, 197_880),
        (.archC, .eighthInch, 131_920),
        (.isoA3, sixteenth, 65_960),
        (.ansiB, sixteenth, 65_960),
    ]
    for (paper, scale, ground) in expected {
        let sheets = try SchematicDrawingSet(paper: paper).sheets(for: document, geometry: HestiaGeometryEngine())
        let sheet = try #require(sheets.first { $0.number == "A-201" })
        var groundLines: [(start: Point2, end: Point2)] = []
        var scales: [String] = []
        var titles: [String: Point2] = [:]
        for item in sheet.content.items {
            if item.style == ElevationView.groundStyle, case let .line(start, end) = item.primitive {
                groundLines.append((start, end))
            }
            if case let .text(position, text, _, _, _) = item.primitive {
                if text.hasPrefix("SCALE:") { scales.append(text) }
                if text == "SOUTH ELEVATION" || text == "NORTH ELEVATION" { titles[text] = position }
            }
        }
        // South and north are the long ones, drawn first; east and west are each 6" across.
        let longLines = groundLines.filter { abs(($0.end.x.ticks - $0.start.x.ticks) - ground) <= 1 }
            .sorted { $0.start.y.ticks > $1.start.y.ticks }
        #expect(longLines.count == 2, "\(paper.name): \(groundLines)")
        #expect(scales.filter { $0 == "SCALE: \(scale.label)" }.count == 2, "\(paper.name): \(scales)")
        let reach = scale.paper(.millimeters(1500)).ticks
        let house = scale.paper(.feet(120)).ticks
        for (line, titleName) in zip(longLines, ["SOUTH ELEVATION", "NORTH ELEVATION"]) {
            let title = try #require(titles[titleName])
            let westError = abs((title.x.ticks - line.start.x.ticks) - reach)
            let eastError = abs((line.end.x.ticks - title.x.ticks) - house - reach)
            #expect(westError <= 1, "\(paper.name) \(titleName): west reach \(westError)")
            #expect(eastError <= 1, "\(paper.name) \(titleName): east reach \(eastError)")
        }
    }
}
