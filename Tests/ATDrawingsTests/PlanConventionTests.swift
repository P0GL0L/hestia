@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

private func pt(_ x: Double, _ y: Double) -> Point2 {
    Point2(x: Length(ticks: Int64((x * Double(Length.feet(1).ticks)).rounded())),
           y: Length(ticks: Int64((y * Double(Length.feet(1).ticks)).rounded())))
}

/// A 30' by 20' house of 8" outside walls, split by a 4 1/2" partition at 12', with a room on each side.
private func house() throws -> ModelDocument {
    var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(UUID()), name: "Weights"),
                                 buildings: [], storeys: [], walls: [], openings: [], rooms: [])
    let building = BuildingID(UUID()), storey = StoreyID(UUID())
    var commands: [AnyCommand] = [
        AddBuildingCommand(buildingID: building, name: "House").erased,
        AddStoreyCommand(storeyID: storey, buildingID: building, name: "Ground Floor", elevation: .feet(0)).erased,
    ]
    var ids: [String: WallID] = [:]
    func wall(_ name: String, _ a: (Double, Double), _ b: (Double, Double), _ thickness: Length) {
        let id = WallID(UUID())
        ids[name] = id
        commands.append(AddWallCommand(wallID: id, storeyID: storey, start: pt(a.0, a.1), end: pt(b.0, b.1),
                                       thickness: thickness, height: .feet(8)).erased)
    }
    wall("south", (0, 0), (30, 0), .inches(8))
    wall("east", (30, 0), (30, 20), .inches(8))
    wall("north", (30, 20), (0, 20), .inches(8))
    wall("west", (0, 20), (0, 0), .inches(8))
    wall("partition", (12, 0), (12, 20), Length(ticks: Length.inches(9).ticks / 2))
    commands.append(AddRoomCommand(roomID: RoomID(UUID()), storeyID: storey, name: "Bedroom",
                                   boundaryWallIDs: ["south", "partition", "north", "west"].compactMap { ids[$0] })
        .erased)
    commands.append(AddRoomCommand(roomID: RoomID(UUID()), storeyID: storey, name: "Living",
                                   boundaryWallIDs: ["south", "east", "north", "partition"].compactMap { ids[$0] })
        .erased)
    _ = try document.perform(batch: commands)
    return document
}

@Test func outsideWallsAreHeavierThanInsideWalls() throws {
    let document = try house()
    let storey = document.storeys[0].id
    let partition = try #require(document.walls.first { $0.thickness.ticks < Length.inches(8).ticks })
    let outside = FloorPlanView.exteriorWalls(document, storey: storey)
    #expect(outside.count == 4)
    #expect(!outside.contains(partition.id))
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let plan = try #require(sheets.first { $0.number == "A-101" })
    let outlines = plan.content.items.filter { item in
        guard case .polyline = item.primitive else { return false }
        return item.style.layer == "A-WALL"
    }
    let partitionPens = outlines.filter { $0.elementID == partition.id.rawValue }.map(\.style.pen)
    let outsidePens = outlines.filter { $0.elementID != partition.id.rawValue }.map(\.style.pen)
    #expect(!partitionPens.isEmpty && partitionPens.allSatisfy { $0 == FloorPlanView.interiorWallStyle.pen })
    #expect(!outsidePens.isEmpty && outsidePens.allSatisfy { $0 == FloorPlanView.wallStyle.pen })
    #expect(FloorPlanView.wallStyle.pen.rawValue > FloorPlanView.interiorWallStyle.pen.rawValue)
}

@Test func aWindowShowsItsSillsAndAPairOfGlassLines() {
    let wall = Wall(id: WallID(UUID()), storeyID: StoreyID(UUID()), start: pt(0, 0), end: pt(20, 0),
                    thickness: .inches(8), height: .feet(8))
    let view = ViewTransform(scale: .quarterInch, modelOrigin: wall.start, paperOrigin: wall.start)
    let window = Opening(id: OpeningID(UUID()), wallID: wall.id, offsetAlongWall: .feet(6), width: .feet(4),
                         height: .feet(4), sillHeight: .feet(3))
    // Lines along the wall (not the two jambs across it), by how far they sit from its centerline, in inches.
    let along: [Double] = FloorPlanView.symbol(for: window, in: wall, view: view).compactMap { item in
        guard case let .line(start, end) = item.primitive, start.y == end.y else { return nil }
        return Double(view.model(start).y.ticks) / Double(Length.inches(1).ticks)
    }.sorted()
    #expect(along.count == 4)
    // The sills at the wall's faces, 4" either side; the glass 2/3" either side of the middle.
    let expected: [Double] = [-4, -4.0 / 6, 4.0 / 6, 4]
    #expect(zip(along, expected).allSatisfy { abs($0 - $1) < 0.05 }, "\(along)")
}
