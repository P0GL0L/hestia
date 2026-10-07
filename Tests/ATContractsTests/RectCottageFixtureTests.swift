import ATContracts
import Foundation
import Testing

/// The `rect-cottage` fixture: the alpha cottage. One storey, six rooms on a 3 × 2 grid matching
/// ATGeometry's six-room cottage, multi-layer 6" exterior walls, a 6:12 hip roof, and one straight stair.
/// Built only through commands.
enum RectCottage {
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", 2000 + n))!
    }

    static func ft(_ feet: Int64, _ inches: Int64 = 0) -> Length { .feet(feet, inchCount: inches) }

    static func at(_ x: Length, _ y: Length) -> Point2 { Point2(x: x, y: y) }

    static let project = ProjectID(id(0))
    static let building = BuildingID(id(1))
    static let storey = StoreyID(id(2))
    static let walls = (11...17).map { WallID(id($0)) }

    /// The building section: across the cottage at x = 18'-0", from 3'-0" south of it to 3'-3" north of it.
    static let crossSection = SectionLine(start: at(ft(18), ft(-3)), end: at(ft(18), ft(26)))

    // Centerlines: 6" walls around interiors 14' + 10' + 12' wide and 12' + 10' deep.
    static let left = Length.inches(-3), v1 = ft(14, 3), v2 = ft(24, 9), right = ft(37, 3)
    static let bottom = Length.inches(-3), mid = ft(12, 3), top = ft(22, 9)

    /// Interior to exterior, which is the wall's left face to right face for a counterclockwise exterior loop.
    static let exteriorLayers = [
        WallLayer(material: "Gypsum board", function: .finish, thickness: .sixtyFourthInches(32)),
        WallLayer(material: "2x4 studs with batt insulation", function: .structure,
                  thickness: .sixtyFourthInches(224)),
        WallLayer(material: "OSB sheathing", function: .sheathing, thickness: .sixtyFourthInches(32)),
        WallLayer(material: "Lap siding on furring", function: .cladding, thickness: .sixtyFourthInches(96)),
    ]

    static func commands() -> [AnyCommand] {
        let w = walls
        let height = ft(8)
        func wall(_ i: Int, _ a: Point2, _ b: Point2, exterior: Bool) -> AnyCommand {
            AddWallCommand(wallID: w[i], storeyID: storey, start: a, end: b, thickness: .inches(6), height: height,
                           layers: exterior ? exteriorLayers : nil).erased
        }
        func opening(_ n: Int, _ wall: Int, _ offset: Length, _ width: Length, _ height: Length, _ sill: Length,
                     _ kind: OpeningKind, _ swing: DoorSwing? = nil) -> AnyCommand {
            AddOpeningCommand(openingID: OpeningID(id(n)), wallID: w[wall], offsetAlongWall: offset, width: width,
                              height: height, sillHeight: sill, kind: kind, swing: swing).erased
        }
        func room(_ n: Int, _ name: String, _ bounds: [Int]) -> AnyCommand {
            AddRoomCommand(roomID: RoomID(id(n)), storeyID: storey, name: name, boundaryWallIDs: bounds.map { w[$0] })
                .erased
        }
        let door = ft(6, 8)
        let inward = DoorSwing(hinge: .nearStart, opensToward: .left)
        return [
            AddBuildingCommand(buildingID: building, name: "Cottage").erased,
            AddStoreyCommand(storeyID: storey, buildingID: building, name: "Ground Floor", elevation: ft(0)).erased,
            wall(0, at(left, bottom), at(right, bottom), exterior: true),
            wall(1, at(right, bottom), at(right, top), exterior: true),
            wall(2, at(right, top), at(left, top), exterior: true),
            wall(3, at(left, top), at(left, bottom), exterior: true),
            wall(4, at(v1, bottom), at(v1, top), exterior: false),
            wall(5, at(v2, bottom), at(v2, top), exterior: false),
            wall(6, at(left, mid), at(right, mid), exterior: false),
            room(30, "Living", [0, 4, 6, 3]),
            room(31, "Kitchen", [0, 5, 6, 4]),
            room(32, "Utility", [0, 1, 6, 5]),
            room(33, "Bedroom", [6, 4, 2, 3]),
            room(34, "Bath", [6, 5, 2, 4]),
            room(35, "Bedroom 2", [6, 1, 2, 5]),
            opening(40, 0, ft(5), ft(3), door, ft(0), .singleDoor, inward),
            opening(41, 0, ft(18), ft(4), ft(4), ft(3), .window),
            opening(42, 1, ft(3), ft(3), door, ft(0), .singleDoor, inward),
            opening(43, 1, ft(16), ft(4), ft(4), ft(3), .window),
            opening(44, 2, ft(28, 3), ft(4), ft(4), ft(3), .window),
            opening(45, 2, ft(18, 3), ft(2), ft(2), ft(4, 6), .window),
            opening(46, 3, ft(15), ft(4), ft(4), ft(3), .window),
            opening(47, 4, ft(3), ft(2, 8), door, ft(0), .singleDoor, inward),
            opening(48, 6, ft(4), ft(2, 8), door, ft(0), .singleDoor, inward),
            opening(49, 6, ft(18), ft(2, 8), door, ft(0), .pocketDoor),
            opening(50, 6, ft(30), ft(2, 8), door, ft(0), .singleDoor, inward),
            AddSlabCommand(slabID: SlabID(id(60)), storeyID: storey, kind: .foundation,
                           outline: [at(.inches(-6), .inches(-6)), at(ft(37, 6), .inches(-6)), at(ft(37, 6), ft(23)),
                                     at(.inches(-6), ft(23))],
                           thickness: .inches(4)).erased,
            // 12 risers × 8" = 8'-0"; 11 treads × 10" = 9'-2" of run.
            AddStairCommand(stairID: StairID(id(61)), storeyID: storey, kind: .straight, runStart: at(ft(27), ft(1)),
                            runEnd: at(ft(27), ft(10, 2)), width: ft(3), riserCount: 12, riserHeight: .inches(8))
                .erased,
            AddRoofCommand(roofID: RoofID(id(62)), storeyID: storey,
                           footprint: [at(left, bottom), at(right, bottom), at(right, top), at(left, top)],
                           eaveHeight: height, pitchRisePer12: .inches(6), overhang: ft(1)).erased,
            AddSheetCommand(sheetID: SheetID(id(73)), number: "A-000", title: "Cover", paper: .archD, scale: nil,
                            views: [.cover]).erased,
            AddSheetCommand(sheetID: SheetID(id(70)), number: "A-101", title: "Floor Plan", paper: .archD,
                            scale: .quarterInch, views: [.floorPlan(storeyID: storey)]).erased,
            AddSheetCommand(sheetID: SheetID(id(71)), number: "A-201", title: "Elevations", paper: .archD,
                            scale: .quarterInch, views: [.elevation(direction: .south), .elevation(direction: .north),
                                    .elevation(direction: .east), .elevation(direction: .west)])
                .erased,
            // North to south through the kitchen window and the bath window, looking west.
            AddSheetCommand(sheetID: SheetID(id(74)), number: "A-301", title: "Building Section", paper: .archD,
                            scale: .quarterInch, views: [.section(line: crossSection)]).erased,
            AddSheetCommand(sheetID: SheetID(id(75)), number: "A-401", title: "Roof Plan", paper: .archD,
                            scale: .quarterInch, views: [.roofPlan]).erased,
            AddSheetCommand(sheetID: SheetID(id(72)), number: "A-601", title: "Schedules", paper: .archD, scale: nil,
                            views: [.schedule(kind: .doors), .schedule(kind: .windows)]).erased,
        ]
    }

    static func document() throws -> ModelDocument {
        var document = ModelDocument(schemaVersion: 1, project: Project(id: project, name: "Rect Cottage"),
                                     buildings: [], storeys: [], walls: [], openings: [], rooms: [])
        _ = try document.perform(batch: commands())
        return document
    }

    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/rect-cottage.json")
}

@Test func rectCottageFixtureMatchesItsCommands() throws {
    let original = try Data(contentsOf: RectCottage.fixtureURL)
    let fixture = try ModelDocument.decode(from: original)
    let built = try RectCottage.document()
    #expect(fixture == built)
    #expect(try fixture.encodeToJSONData() == original)
}

@Test func rectCottageIsTheAlphaCottage() throws {
    let cottage = try ModelDocument.decode(from: Data(contentsOf: RectCottage.fixtureURL))
    #expect(cottage.storeys.count == 1)
    #expect(cottage.rooms.map(\.name) == ["Living", "Kitchen", "Utility", "Bedroom", "Bath", "Bedroom 2"])
    let exterior = cottage.walls.filter { !$0.layers.isEmpty }
    #expect(exterior.count == 4)
    for wall in exterior {
        #expect(wall.layers.count == 4)
        #expect(wall.layers.reduce(0) { $0 + $1.thickness.ticks } == wall.thickness.ticks)
        #expect(wall.thickness == .inches(6))
    }
    let roof = try #require(cottage.roofs.first)
    #expect(roof.planes.count == 4)
    #expect(roof.planes.allSatisfy { $0.pitchRisePer12 == .inches(6) })
    // The set: cover, plan, elevations, one section, roof plan, schedules.
    let numbers: [String] = cottage.sheets.map(\.number)
    #expect(numbers == ["A-000", "A-101", "A-201", "A-301", "A-401", "A-601"])
    let sections = cottage.sheets.flatMap(\.views).filter { view in
        if case .section = view { return true }
        return false
    }
    #expect(sections.count == 1)
    #expect(cottage.stairs.count == 1)
    #expect(cottage.openings.filter { $0.kind.isDoor }.count == 6)
    let elevations = cottage.sheets.flatMap(\.views).compactMap { view -> ElevationDirection? in
        if case let .elevation(direction) = view { return direction }
        return nil
    }
    #expect(elevations == [.south, .north, .east, .west])
}
