@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
private func pt(_ x: Int64, _ y: Int64) -> Point2 { Point2(x: .feet(x), y: .feet(y)) }
private let room = RoomID(uuid(4))

/// A room bounded by walls through `corners` in order, closed back to the first, each `thicknesses[i]` thick.
private func model(_ corners: [Point2], thicknesses: [Length], units: LengthFormatStyle? = nil) throws -> ModelDocument {
    var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(uuid(1)), name: "Box",
                                                                    displayUnits: units),
                                 buildings: [], storeys: [], walls: [], openings: [], rooms: [])
    var commands: [AnyCommand] = [
        AddBuildingCommand(buildingID: BuildingID(uuid(2)), name: "Box").erased,
        AddStoreyCommand(storeyID: StoreyID(uuid(3)), buildingID: BuildingID(uuid(2)), name: "Ground",
                         elevation: .feet(0)).erased,
    ]
    for i in corners.indices {
        commands.append(AddWallCommand(wallID: WallID(uuid(10 + i)), storeyID: StoreyID(uuid(3)), start: corners[i],
                                       end: corners[(i + 1) % corners.count], thickness: thicknesses[i],
                                       height: .feet(8)).erased)
    }
    commands.append(AddRoomCommand(roomID: room, storeyID: StoreyID(uuid(3)), name: "Den",
                                   boundaryWallIDs: corners.indices.map { WallID(uuid(10 + $0)) }).erased)
    _ = try document.perform(batch: commands)
    return document
}

/// The room's tag lines on the plan sheet, top to bottom, as (text, y on paper).
private func tag(_ document: ModelDocument) throws -> [(String, Int64)] {
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let plan = try #require(sheets.first { $0.number == "A-101" })
    return plan.content.items.compactMap { item -> (String, Int64)? in
        guard item.elementID == room.rawValue, case let .text(position, string, _, _, _) = item.primitive else {
            return nil
        }
        return (string, position.y.ticks)
    }
}

private let box: [Point2] = [pt(0, 0), pt(20, 0), pt(20, 15), pt(0, 15)]
private let six = [Length](repeating: .inches(6), count: 4)

@Test func aRectangularRoomPrintsItsClearSizeUnderItsName() throws {
    let lines = try tag(try model(box, thicknesses: six))
    let text: [String] = lines.map(\.0)
    // 20' by 15' on centerlines, less 3" at each face; 19.5 x 14.5 = 282.75, the area's 283 SF.
    #expect(text == ["DEN", "19'-6\" x 14'-6\"", "283 SF"])
    // Name, then the size 5 mm below it, then the area 4 mm further down.
    let ys: [Int64] = lines.map(\.1)
    #expect(ys[0] - ys[1] == mmTicks(5))
    #expect(ys[1] - ys[2] == mmTicks(4))
}

@Test func eachSideTakesItsOwnWallsThickness() throws {
    // South 6", east 8", north 4", west 8": width 20' - 4" - 4" = 19'-4", depth 15' - 3" - 2" = 14'-7".
    let lines = try tag(try model(box, thicknesses: [.inches(6), .inches(8), .inches(4), .inches(8)]))
    let size = try #require(lines.dropFirst().first?.0)
    #expect(size == "19'-4\" x 14'-7\"")
}

@Test func aRoomThatIsNotASquareRectangleGetsNoSize() throws {
    // The north wall slopes: four corners, but not a box square to the axes.
    let lines = try tag(try model([pt(0, 0), pt(20, 0), pt(20, 15), pt(0, 12)], thicknesses: six))
    let text: [String] = lines.map(\.0)
    #expect(text.count == 2)
    #expect(text.first == "DEN")
    #expect(text.last?.hasSuffix("SF") == true)
    // With no size, the area keeps its place 5 mm under the name.
    let ys: [Int64] = lines.map(\.1)
    #expect(ys[0] - ys[1] == mmTicks(5))
}

@Test func aMetricProjectPrintsMillimetres() throws {
    let lines = try tag(try model(box, thicknesses: six, units: .metric))
    let size = try #require(lines.dropFirst().first?.0)
    // 19'-6" is 5943.6 mm and 14'-6" is 4419.6 mm, rounded to the millimetre.
    #expect(size == "5944 mm x 4420 mm")
}
