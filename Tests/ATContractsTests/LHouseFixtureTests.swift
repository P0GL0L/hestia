import ATContracts
import Foundation
import Testing

/// The `l-house` fixture: two storeys on an L-shaped footprint, one straight stair, a hip roof.
/// Built only through commands, so the fixture is always a model the commands accept.
enum LHouse {
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", 1000 + n))!
    }

    static func mm(_ x: Int64, _ y: Int64) -> Point2 {
        Point2(x: .millimeters(x), y: .millimeters(y))
    }

    static let project = ProjectID(id(0))
    static let building = BuildingID(id(1))
    static let ground = StoreyID(id(2))
    static let upper = StoreyID(id(3))

    /// Counterclockwise L: a 10 m × 6 m south wing and a 5 m × 4 m north-west wing.
    static let footprint = [mm(0, 0), mm(10000, 0), mm(10000, 6000), mm(5000, 6000), mm(5000, 10000), mm(0, 10000)]

    /// The footprint moved out 150 mm to the outer face of the 300 mm exterior walls, so slab edges reach it.
    /// The building section: north through the hall stair at x = 1200 mm, from 1.5 m south of the house to 1.5 m
    /// north of it, looking west, so both storeys, both slabs, the stair, and the roof are cut.
    static let crossSection = SectionLine(start: mm(1200, -1500), end: mm(1200, 11500))

    static let slabOutline = [mm(-150, -150), mm(10150, -150), mm(10150, 6150), mm(5150, 6150), mm(5150, 10150),
                              mm(-150, 10150)]

    static func commands() -> [AnyCommand] {
        var list: [AnyCommand] = [
            SetProjectUnitsCommand(projectID: project, units: .metric).erased,
            AddBuildingCommand(buildingID: building, name: "L House").erased,
            AddStoreyCommand(storeyID: ground, buildingID: building, name: "Ground Floor",
                             elevation: .millimeters(0)).erased,
            AddStoreyCommand(storeyID: upper, buildingID: building, name: "Upper Floor",
                             elevation: .millimeters(2800)).erased,
        ]
        var next = 10
        func newID() -> UUID { next += 1; return id(next) }
        // The two partitions on each storey, ground floor first, for the interior doors added at the end.
        var partitions: [WallID] = []
        var splits: [WallID] = []

        for storey in [ground, upper] {
            var exterior: [WallID] = []
            for i in footprint.indices {
                let wall = WallID(newID())
                exterior.append(wall)
                list.append(AddWallCommand(wallID: wall, storeyID: storey, start: footprint[i],
                                           end: footprint[(i + 1) % footprint.count],
                                           thickness: .millimeters(300), height: .millimeters(2700)).erased)
            }
            // Partition between the two wings.
            let partition = WallID(newID())
            partitions.append(partition)
            list.append(AddWallCommand(wallID: partition, storeyID: storey, start: mm(5000, 6000), end: mm(0, 6000),
                                       thickness: .millimeters(100), height: .millimeters(2700)).erased)
            // Partition splitting the south wing.
            let split = WallID(newID())
            splits.append(split)
            list.append(AddWallCommand(wallID: split, storeyID: storey, start: mm(5000, 0), end: mm(5000, 6000),
                                       thickness: .millimeters(100), height: .millimeters(2700)).erased)

            let isGround = storey == ground
            list += [
                AddRoomCommand(roomID: RoomID(newID()), storeyID: storey, name: isGround ? "Living" : "Bedroom 1",
                               boundaryWallIDs: [exterior[0], split, partition, exterior[5]]).erased,
                AddRoomCommand(roomID: RoomID(newID()), storeyID: storey, name: isGround ? "Kitchen" : "Bedroom 2",
                               boundaryWallIDs: [exterior[0], exterior[1], exterior[2], split]).erased,
                AddRoomCommand(roomID: RoomID(newID()), storeyID: storey, name: isGround ? "Hall" : "Landing",
                               boundaryWallIDs: [partition, exterior[3], exterior[4], exterior[5]]).erased,
                AddSlabCommand(slabID: SlabID(newID()), storeyID: storey, kind: isGround ? .foundation : .floor,
                               outline: slabOutline, thickness: .millimeters(isGround ? 150 : 250)).erased,
            ]
            if isGround {
                list += [
                    AddOpeningCommand(openingID: OpeningID(newID()), wallID: exterior[0],
                                      offsetAlongWall: .millimeters(2000), width: .millimeters(1000),
                                      height: .millimeters(2100), sillHeight: .millimeters(0), kind: .singleDoor,
                                      swing: DoorSwing(hinge: .nearStart, opensToward: .left)).erased,
                    AddOpeningCommand(openingID: OpeningID(newID()), wallID: exterior[1],
                                      offsetAlongWall: .millimeters(2000), width: .millimeters(1800),
                                      height: .millimeters(2100), sillHeight: .millimeters(0),
                                      kind: .slidingDoor).erased,
                ]
            }
            list.append(AddOpeningCommand(openingID: OpeningID(newID()), wallID: exterior[0],
                                          offsetAlongWall: .millimeters(6500), width: .millimeters(1500),
                                          height: .millimeters(1200), sillHeight: .millimeters(900)).erased)
            list.append(AddOpeningCommand(openingID: OpeningID(newID()), wallID: exterior[4],
                                          offsetAlongWall: .millimeters(1000), width: .millimeters(1200),
                                          height: .millimeters(1200), sillHeight: .millimeters(900)).erased)
        }

        // Interior doors, 900 by 2100 mm, so every room is reached. The partition at y = 6000 runs west from
        // x = 5000, so its door at x = 3500 to 2600 joins the hall and living room (landing and bedroom 1) clear of
        // the stair at x = 750 to 1650. The split at x = 5000 runs north from y = 0; its door at y = 3500 to 4400
        // joins the living room and kitchen (bedroom 1 and bedroom 2).
        for (index, (partition, split)) in zip(partitions, splits).enumerated() {
            list.append(AddOpeningCommand(openingID: OpeningID(id(904 + 2 * index)), wallID: partition,
                                          offsetAlongWall: .millimeters(1500), width: .millimeters(900),
                                          height: .millimeters(2100), sillHeight: .millimeters(0), kind: .singleDoor,
                                          swing: DoorSwing(hinge: .nearStart, opensToward: .left)).erased)
            list.append(AddOpeningCommand(openingID: OpeningID(id(905 + 2 * index)), wallID: split,
                                          offsetAlongWall: .millimeters(3500), width: .millimeters(900),
                                          height: .millimeters(2100), sillHeight: .millimeters(0), kind: .singleDoor,
                                          swing: DoorSwing(hinge: .nearStart, opensToward: .left)).erased)
        }

        list += [
            // 16 risers × 175 mm = 2800 mm, the storey-to-storey height; 15 treads × 230 mm along the run.
            AddStairCommand(stairID: StairID(id(900)), storeyID: ground, kind: .straight, runStart: mm(1200, 6300),
                            runEnd: mm(1200, 9750), width: .millimeters(900), riserCount: 16,
                            riserHeight: .millimeters(175)).erased,
            AddRoofCommand(roofID: RoofID(id(901)), storeyID: upper, footprint: footprint,
                           eaveHeight: .millimeters(2700), pitchRisePer12: .inches(6),
                           overhang: .millimeters(450)).erased,
            AddSheetCommand(sheetID: SheetID(id(908)), number: "A-000", title: "Cover", paper: .archD, scale: nil,
                            views: [.cover]).erased,
            AddSheetCommand(sheetID: SheetID(id(902)), number: "A-101", title: "Ground Floor Plan", paper: .archD,
                            scale: .quarterInch, views: [.floorPlan(storeyID: ground)]).erased,
            AddSheetCommand(sheetID: SheetID(id(903)), number: "A-102", title: "Upper Floor Plan", paper: .archD,
                            scale: .quarterInch, views: [.floorPlan(storeyID: upper)]).erased,
            // Four elevations stacked on one sheet, each at the largest scale that fits.
            AddSheetCommand(sheetID: SheetID(id(909)), number: "A-201", title: "Elevations", paper: .archD, scale: nil,
                            views: [.elevation(direction: .south), .elevation(direction: .north),
                                    .elevation(direction: .east), .elevation(direction: .west)]).erased,
            AddSheetCommand(sheetID: SheetID(id(910)), number: "A-301", title: "Building Section", paper: .archD,
                            scale: .quarterInch, views: [.section(line: crossSection)]).erased,
            AddSheetCommand(sheetID: SheetID(id(911)), number: "A-401", title: "Roof Plan", paper: .archD,
                            scale: .quarterInch, views: [.roofPlan]).erased,
        ]
        return list
    }

    static func document() throws -> ModelDocument {
        var document = ModelDocument(schemaVersion: 1, project: Project(id: project, name: "L House"),
                                     buildings: [], storeys: [], walls: [], openings: [], rooms: [])
        _ = try document.perform(batch: commands())
        return document
    }

    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/l-house.json")
}

@Test func lHouseFixtureMatchesItsCommands() throws {
    let original = try Data(contentsOf: LHouse.fixtureURL)
    let fixture = try ModelDocument.decode(from: original)
    let built = try LHouse.document()
    #expect(fixture == built)
    #expect(try fixture.encodeToJSONData() == original)
}

@Test func lHouseHasTwoStoreysAndOneStairBetweenThem() throws {
    let house = try ModelDocument.decode(from: Data(contentsOf: LHouse.fixtureURL))
    #expect(house.storeys.map(\.name) == ["Ground Floor", "Upper Floor"])
    #expect(house.stairs.count == 1)
    let stair = try #require(house.stairs.first)
    let rise = Int64(stair.riserCount) * stair.riserHeight.ticks
    #expect(rise == house.storeys[1].elevation.ticks - house.storeys[0].elevation.ticks)
    #expect(house.walls.count == 16)
    #expect(house.rooms.count == 6)
    #expect(house.roofs.first?.planes.allSatisfy { $0.pitchRisePer12 == .inches(6) } == true)
    #expect(house.project.displayUnits == .metric)
    let numbers: [String] = house.sheets.map(\.number)
    #expect(numbers == ["A-000", "A-101", "A-102", "A-201", "A-301", "A-401"])
    let sections = house.sheets.flatMap(\.views).filter { view in
        if case .section = view { return true }
        return false
    }
    #expect(sections.count == 1)
}

@Test func lHouseRoomsConnectThroughInteriorDoors() throws {
    let house = try ModelDocument.decode(from: Data(contentsOf: LHouse.fixtureURL))
    let stair = try #require(house.stairs.first)
    for storey in house.storeys {
        let rooms = house.rooms.filter { $0.storeyID == storey.id }
        // Interior walls: not along the footprint outline. A door in one joins the two rooms it bounds.
        let outline = Set(LHouse.footprint)
        let interior = house.walls.filter { wall in
            let onOutline: Bool = outline.contains(wall.start) && outline.contains(wall.end)
            return wall.storeyID == storey.id && !onOutline
        }
        let walls = Set(interior.map(\.id))
        var links: [Set<RoomID>] = []
        for opening in house.openings where walls.contains(opening.wallID) && opening.kind.isDoor {
            let sides = rooms.filter { $0.boundaryWallIDs.contains(opening.wallID) }.map(\.id)
            if sides.count == 2 { links.append(Set(sides)) }
        }
        #expect(links.count == 2, "\(storey.name)")
        var reached: Set<RoomID> = [rooms[0].id]
        for _ in rooms {
            for link in links where !link.isDisjoint(with: reached) { reached.formUnion(link) }
        }
        let roomCount: Int = rooms.count
        let reachedCount: Int = reached.count
        #expect(reachedCount == roomCount, "\(storey.name)")
    }
    // The hall door stays clear of the stair, which runs at x = 750 to 1650 mm north of the partition.
    let stairEast: Int64 = stair.runStart.x.ticks + stair.width.ticks / 2
    let partitionDoors = house.openings.filter { $0.offsetAlongWall == .millimeters(1500) }
    #expect(partitionDoors.count == 2)
    for door in partitionDoors {
        // The partition runs west from x = 5000 mm, so the door's west jamb is at 5000 - offset - width.
        let westJamb: Int64 = Length.millimeters(5000).ticks - door.offsetAlongWall.ticks - door.width.ticks
        #expect(westJamb > stairEast)
    }
}
