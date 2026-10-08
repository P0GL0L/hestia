@testable import ATDrawings
import ATContracts
import Foundation
import Testing

private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
private let storey = StoreyID(uuid(3))
private let wall = WallID(uuid(10))
private func ft(_ f: Int64) -> Length { .feet(f) }

/// One 20' wall, 6" thick, with a door, a window, and a cased opening, in that order.
private func model() throws -> ModelDocument {
    var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(uuid(1)), name: "Wall"),
                                 buildings: [], storeys: [], walls: [], openings: [], rooms: [])
    let commands: [AnyCommand] = [
        AddBuildingCommand(buildingID: BuildingID(uuid(2)), name: "Wall").erased,
        AddStoreyCommand(storeyID: storey, buildingID: BuildingID(uuid(2)), name: "Ground", elevation: ft(0)).erased,
        AddWallCommand(wallID: wall, storeyID: storey, start: Point2(x: ft(0), y: ft(0)),
                       end: Point2(x: ft(20), y: ft(0)), thickness: .inches(6), height: ft(8)).erased,
        AddOpeningCommand(openingID: OpeningID(uuid(20)), wallID: wall, offsetAlongWall: ft(1), width: ft(3),
                          height: .feet(6, inchCount: 8), sillHeight: ft(0), kind: .singleDoor,
                          swing: DoorSwing(hinge: .nearStart, opensToward: .left)).erased,
        AddOpeningCommand(openingID: OpeningID(uuid(21)), wallID: wall, offsetAlongWall: ft(6), width: ft(4),
                          height: ft(4), sillHeight: ft(3), kind: .window).erased,
        AddOpeningCommand(openingID: OpeningID(uuid(22)), wallID: wall, offsetAlongWall: ft(12), width: ft(4),
                          height: ft(7), sillHeight: ft(0), kind: .casedOpening).erased,
    ]
    _ = try document.perform(batch: commands)
    return document
}

@Test func aCasedOpeningIsNeitherADoorNorAWindow() {
    #expect(!OpeningKind.casedOpening.isDoor)
    #expect(!OpeningKind.casedOpening.isWindow)
    #expect(OpeningKind.window.isWindow)
    #expect(!OpeningKind.pocketDoor.isWindow)
    // Every other kind is exactly one of the two.
    for kind in OpeningKind.allCases where kind != .casedOpening {
        #expect(kind.isDoor != kind.isWindow, "\(kind)")
    }
}

@Test func aCasedOpeningTakesNoSwing() throws {
    var document = try model()
    let swung = SetOpeningKindCommand(openingID: OpeningID(uuid(22)), kind: .casedOpening,
                                      swing: DoorSwing(hinge: .nearStart, opensToward: .left))
    #expect(throws: CommandValidationError.swingNotAllowed(OpeningID(uuid(22)))) {
        _ = try document.perform(swung.erased)
    }
}

@Test func aCasedOpeningDrawsItsTwoJambsOnly() throws {
    let document = try model()
    let host = try #require(document.walls.first)
    let cased = try #require(document.openings.first { $0.kind == .casedOpening })
    let view = ViewTransform(scale: .quarterInch, modelOrigin: Point2(x: ft(0), y: ft(0)),
                             paperOrigin: Point2(x: ft(0), y: ft(0)))
    let items = FloorPlanView.symbol(for: cased, in: host, view: view)
    #expect(items.count == 2)
    // Both lines run straight across the wall, at the opening's two edges, on the door layer: no glass, no leaf.
    for item in items {
        guard case let .line(start, end) = item.primitive else {
            Issue.record("not a line")
            continue
        }
        #expect(start.x == end.x)
        #expect(item.style.layer == "A-DOOR")
    }
    let xs: [Int64] = items.compactMap { item in
        if case let .line(start, _) = item.primitive { return start.x.ticks } else { return nil }
    }
    #expect(xs == [view.paper(ft(12)).ticks, view.paper(ft(16)).ticks])
    #expect(!items.contains { $0.style.layer == "A-GLAZ" })
}

@Test func aCasedOpeningIsInNoScheduleAndCarriesNoMark() throws {
    let document = try model()
    let marks = ScheduleView.marks(document)
    #expect(marks[OpeningID(uuid(20))] == "D1")
    #expect(marks[OpeningID(uuid(21))] == "W1")
    #expect(marks[OpeningID(uuid(22))] == nil)
    let doors = try #require(ScheduleView.table(.doors, document: document, style: .feetInchesFractions, areas: [:]))
    let windows = try #require(ScheduleView.table(.windows, document: document, style: .feetInchesFractions,
                                                  areas: [:]))
    #expect(doors.rows.count == 1)
    #expect(windows.rows.count == 1)
}

@Test func aCasedOpeningStillCountsAsAnOpening() throws {
    var document = try model()
    #expect(document.openings.count == 3)
    // It holds its place in the wall: another opening may not overlap it.
    let overlapping = AddOpeningCommand(openingID: OpeningID(uuid(23)), wallID: wall, offsetAlongWall: ft(14),
                                        width: ft(3), height: ft(4), sillHeight: ft(3), kind: .window)
    #expect(throws: (any Error).self) {
        _ = try document.perform(overlapping.erased)
    }
    // It round-trips through the saved JSON.
    let saved = try document.encodeToJSONData()
    let opened = try ModelDocument.decode(from: saved)
    #expect(opened.openings.first { $0.id == OpeningID(uuid(22)) }?.kind == .casedOpening)
}

@Test func aCasedOpeningInElevationIsTheRectangleOnly() throws {
    let document = try model()
    let view = ViewTransform(scale: .quarterInch, modelOrigin: Point2(x: ft(0), y: ft(0)),
                             paperOrigin: Point2(x: ft(0), y: ft(0)))
    let items = ElevationView.items(document, .south, view: view)
    func shapes(_ n: Int) -> (outlines: Int, lines: Int) {
        let mine = items.filter { $0.elementID == uuid(n) }
        let outlines = mine.filter { if case .polyline = $0.primitive { return true } else { return false } }.count
        let lines = mine.filter { if case .line = $0.primitive { return true } else { return false } }.count
        return (outlines, lines)
    }
    // Door: its rectangle. Window: rectangle and mullion. Cased opening: rectangle, no mullion.
    let door = shapes(20), window = shapes(21), cased = shapes(22)
    #expect(door.outlines == 1 && door.lines == 0)
    #expect(window.outlines == 1 && window.lines == 1)
    #expect(cased.outlines == 1 && cased.lines == 0)
}
