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

@Test func aModelWithNoWallsGetsOnlyItsPlan() throws {
    let numbers: [String] = try draw(model(walls: false, roof: false)).map(\.number)
    #expect(numbers == ["A-101"])
}

@Test func wallsAddAnElevationsSheetWithAllFour() throws {
    let sheets = try draw(model(walls: true, roof: false))
    let numbers: [String] = sheets.map(\.number)
    #expect(numbers == ["A-101", "A-201", "A-301"])
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
    #expect(numbers == ["A-101", "A-201", "A-301", "A-401"])
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
