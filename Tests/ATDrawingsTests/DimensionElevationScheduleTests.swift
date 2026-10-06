@testable import ATDrawings
import ATContracts
import Foundation
import Testing

private func cottage() throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/rect-cottage.json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

private func ft(_ feet: Int64, _ inches: Int64 = 0) -> Int64 { Length.feet(feet, inchCount: inches).ticks }

@Test func southChainsStopAtOpeningsWallsAndCorners() throws {
    let document = try cottage()
    let storey = document.storeys[0].id
    let extent = try #require(FloorPlanView.extent(of: document, storey: storey))
    let walls = document.walls.filter { $0.storeyID == storey }
    let south = DimensionChains.stops(walls: walls, openings: document.openings, alongX: true,
                                      face: extent.min.y.ticks, low: extent.min.x.ticks, high: extent.max.x.ticks)
    let corner = Length.inches(-6).ticks, far = ft(37, 6)
    #expect(south.overall == [corner, far])
    // Interior walls at 14'-3" and 24'-9" on center; the end walls are the overall stops.
    #expect(south.walls == [corner, ft(14, 3), ft(24, 9), far])
    // Front door 4'-9" to 7'-9", kitchen window 17'-9" to 21'-9".
    #expect(south.openings == [corner, ft(4, 9), ft(7, 9), ft(17, 9), ft(21, 9), far])
}

@Test func planCarriesThreeTiersOfDimensionsAndOpeningMarks() throws {
    let document = try cottage()
    let view = ViewTransform(scale: .quarterInch, modelOrigin: Point2(x: .feet(0), y: .feet(0)),
                             paperOrigin: Point2(x: .millimeters(200), y: .millimeters(200)))
    let dims = DimensionChains.items(document: document, storey: document.storeys[0].id, view: view)
    // South: 5 opening segments, 3 wall segments, 1 overall. West: 3 + 2 + 1.
    #expect(dims.count == 15)
    let marks = ScheduleView.marks(document)
    #expect(marks.values.filter { $0.hasPrefix("D") }.count == 6)
    #expect(marks.values.filter { $0.hasPrefix("W") }.count == 5)
    let items = FloorPlanView.items(document: document, storey: document.storeys[0].id, outlines: [], areas: [:],
                                    view: view)
    let tags = items.compactMap { item -> String? in
        if case let .text(_, string, _, _, _) = item.primitive, item.style.layer == "A-ANNO-TEXT" { return string }
        return nil
    }
    #expect(Set(tags) == Set(marks.values))
}

@Test func southElevationShowsOnlyTheFrontWallAndAHipRoof() throws {
    let document = try cottage()
    let faces = ElevationView.faces(document, .south)
    #expect(faces.map(\.wall.id) == [document.walls[0].id])
    let roofs = ElevationView.roofOutlines(document, .south)
    let roof = try #require(roofs.first)
    #expect(roof.count == 4)
    // 6:12 over half of the 25'-0" deep footprint with overhangs: 6'-3" above the 8'-0" eave.
    #expect(roof.map(\.y.ticks).max() == ft(14, 3))
    let view = ViewTransform(scale: .quarterInch, modelOrigin: Point2(x: .feet(-5), y: .feet(0)),
                             paperOrigin: Point2(x: .millimeters(100), y: .millimeters(100)))
    let items = ElevationView.items(document, .south, view: view)
    let openingIDs = Set(items.compactMap(\.elementID)).subtracting([document.walls[0].id.rawValue])
    let onSouthWall = Set(document.openings.filter { $0.wallID == document.walls[0].id }.map(\.id.rawValue))
    #expect(openingIDs == onSouthWall)
    #expect(items.contains { $0.style.layer == "A-ELEV-GRND" })
}

@Test func eastElevationSeesTheBackDoorWall() throws {
    let document = try cottage()
    #expect(ElevationView.faces(document, .east).map(\.wall.id) == [document.walls[1].id])
    #expect(ElevationView.faces(document, .west).map(\.wall.id) == [document.walls[3].id])
}

@Test func hiddenIntervalsAreSubtracted() {
    let visible = ElevationView.subtract([(0, 100)], [(10, 20), (50, 120)])
    #expect(visible.map { [$0.0, $0.1] } == [[0, 10], [20, 50]])
}

@Test func schedulesListDoorsAndWindowsInModelOrder() throws {
    let document = try cottage()
    let doors = try #require(ScheduleView.table(.doors, document: document, style: .feetInchesFractions, areas: [:]))
    #expect(doors.rows.count == 6)
    #expect(doors.rows[0] == ["D1", "Single door", "3'-0\"", "6'-8\"", "Start hinge, left"])
    #expect(doors.rows[4][1] == "Pocket door" && doors.rows[4][4] == "-")
    let windows = try #require(ScheduleView.table(.windows, document: document, style: .feetInchesFractions,
                                                  areas: [:]))
    #expect(windows.rows.count == 5)
    #expect(windows.rows.first == ["W1", "Window", "4'-0\"", "4'-0\"", "3'-0\""])
    let areas = try #require(ScheduleView.table(.areas, document: document, style: .metric,
                                                areas: [document.rooms[0].id: Area(tickSquares: 15_600_000 * 102_400)]))
    #expect(areas.rows[0] == ["Living", "Ground Floor", "15.6 SQ M"])
    #expect(ScheduleView.words("floorToCeilingWindow") == "Floor to ceiling window")
}
