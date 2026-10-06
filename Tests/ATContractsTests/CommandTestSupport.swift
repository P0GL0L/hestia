import ATContracts
import Foundation
import Testing

/// Deterministic IDs and a small one-storey model for command tests.
enum Sample {
    static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!
    }

    static let project = ProjectID(uuid(1))
    static let building = BuildingID(uuid(2))
    static let emptyBuilding = BuildingID(uuid(3))
    static let newBuilding = BuildingID(uuid(4))
    static let storey = StoreyID(uuid(10))
    static let emptyStorey = StoreyID(uuid(11))
    static let newStorey = StoreyID(uuid(12))
    static let wallSouth = WallID(uuid(20))
    static let wallSpare = WallID(uuid(21))
    static let wallEast = WallID(uuid(22))
    static let newWall = WallID(uuid(23))
    static let door = OpeningID(uuid(30))
    static let newWindow = OpeningID(uuid(31))
    static let room = RoomID(uuid(40))
    static let newRoom = RoomID(uuid(41))
    static let stair = StairID(uuid(50))
    static let newStair = StairID(uuid(51))
    static let roof = RoofID(uuid(52))
    static let newRoof = RoofID(uuid(53))
    static let slab = SlabID(uuid(54))
    static let newSlab = SlabID(uuid(55))
    static let sheet = SheetID(uuid(56))
    static let newSheet = SheetID(uuid(57))
    static let layer = LayerID(uuid(70))
    static let newLayer = LayerID(uuid(71))
    static let spareLayer = LayerID(uuid(82))
    static let column = ColumnID(uuid(72))
    static let newColumn = ColumnID(uuid(73))
    static let beam = BeamID(uuid(74))
    static let newBeam = BeamID(uuid(75))
    static let placement = PlacementID(uuid(76))
    static let newPlacement = PlacementID(uuid(77))
    static let symbol = MEPSymbolID(uuid(78))
    static let newSymbol = MEPSymbolID(uuid(79))
    static let terrain = TerrainPatchID(uuid(80))
    static let newTerrain = TerrainPatchID(uuid(81))
    static let footprint = [point(0, 0), point(4000, 0), point(4000, 3000), point(0, 3000)]

    static func point(_ xMM: Int64, _ yMM: Int64) -> Point2 {
        Point2(x: .millimeters(xMM), y: .millimeters(yMM))
    }

    /// South wall 4 m long and 2.4 m high with a 900 mm door at 500 mm; a spare wall between it and the east wall.
    static func document() -> ModelDocument {
        let wallHeight = Length.millimeters(2400)
        let thickness = Length.millimeters(200)
        return ModelDocument(
            schemaVersion: 1,
            project: Project(id: project, name: "Command Test"),
            buildings: [
                Building(id: building, projectID: project, name: "House"),
                Building(id: emptyBuilding, projectID: project, name: "Shed"),
            ],
            storeys: [
                Storey(id: storey, buildingID: building, name: "Ground", elevation: .millimeters(0)),
                Storey(id: emptyStorey, buildingID: building, name: "Loft", elevation: .millimeters(2700)),
            ],
            walls: [
                Wall(id: wallSouth, storeyID: storey, start: point(0, 0), end: point(4000, 0),
                     thickness: thickness, height: wallHeight),
                Wall(id: wallSpare, storeyID: storey, start: point(0, 3000), end: point(0, 0),
                     thickness: thickness, height: wallHeight),
                Wall(id: wallEast, storeyID: storey, start: point(4000, 0), end: point(4000, 3000),
                     thickness: thickness, height: wallHeight),
            ],
            openings: [
                Opening(id: door, wallID: wallSouth, offsetAlongWall: .millimeters(500),
                        width: .millimeters(900), height: .millimeters(2100), sillHeight: .millimeters(0)),
            ],
            rooms: [
                Room(id: room, storeyID: storey, name: "Living", boundaryWallIDs: [wallSouth, wallEast]),
            ],
            stairs: [
                Stair(id: stair, storeyID: storey, runStart: point(1000, 2000), runEnd: point(1000, 4500),
                      width: .millimeters(900), riserCount: 15, riserHeight: .millimeters(180)),
            ],
            roofs: [
                Roof(id: roof, storeyID: storey, footprint: footprint, eaveHeight: .millimeters(2400),
                     planes: Array(repeating: RoofPlane(pitchRisePer12: .inches(6), overhang: .millimeters(450)),
                                   count: 4)),
            ],
            slabs: [
                Slab(id: slab, storeyID: storey, outline: footprint, thickness: .millimeters(150)),
            ],
            sheets: [
                Sheet(id: sheet, number: "A-101", title: "Ground Floor Plan", paper: .archD,
                      scale: .quarterInch, views: [.floorPlan(storeyID: storey)]),
            ],
            layers: [
                Layer(id: layer, name: "Structure", colorRGB: [200, 40, 40]),
                Layer(id: spareLayer, name: "Old", colorRGB: [9, 9, 9], isVisible: false, isLocked: true),
            ],
            columns: [
                Column(id: column, storeyID: storey, shape: .rectangular, center: point(2000, 1500),
                       width: .millimeters(300), depth: .millimeters(300), height: .millimeters(2400), layerID: layer),
            ],
            beams: [
                Beam(id: beam, storeyID: storey, start: point(0, 1500), end: point(4000, 1500),
                     width: .millimeters(200), depth: .millimeters(300), topOffset: .millimeters(2400)),
            ],
            placements: [
                Placement(id: placement, storeyID: storey, catalogItemID: CatalogItemID(rawValue: "living/sofa"),
                          position: point(1000, 2500)),
            ],
            terrainPatches: [
                TerrainPatch(id: terrain, name: "Lot", boundary: [point(-5000, -5000), point(9000, -5000),
                                                                  point(9000, 8000), point(-5000, 8000)],
                             surveyPoints: [Point3(x: .millimeters(0), y: .millimeters(0), z: .millimeters(100))]),
            ],
            mepSymbols: [
                MEPSymbol(id: symbol, storeyID: storey, kind: .duplexOutlet, position: point(100, 1000),
                          mountingHeight: .millimeters(300)),
            ],
            dimensionOverrides: [DimensionOverride(elementID: room.rawValue, face: .width, text: "VERIFY")]
        )
    }

    /// One valid instance of every v1 command against `document()`.
    static let commands: [AnyCommand] = core + buildingsAndStoreys + wallsAndOpenings + rooms + alphaElements + siteAndFurnishing + overrides

    static let core: [AnyCommand] = [
        RenameProjectCommand(projectID: project, newName: "Renamed").erased,
    ]

    static func json(_ value: some Encodable) throws -> Data {
        try ModelDocument.makeJSONEncoder().encode(value)
    }
}

/// Expects `command` to be refused with `expected` by both validate and apply, leaving the sample unchanged.
func expectRefused(_ expected: CommandValidationError, _ command: some Command) {
    expectRefusedOn(Sample.document(), expected, command)
}

/// Expects `command` to be refused on `start` by both validate and apply, leaving it unchanged.
func expectRefusedOn(_ start: ModelDocument, _ expected: CommandValidationError, _ command: some Command) {
    var document = start
    let original = document
    #expect(throws: expected) { try command.validate(against: document) }
    #expect(throws: expected) { _ = try command.apply(to: &document) }
    #expect(document == original)
}
