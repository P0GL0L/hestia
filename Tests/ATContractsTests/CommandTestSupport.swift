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
            ]
        )
    }

    /// One valid instance of every v1 command against `document()`.
    static let commands: [AnyCommand] = core + buildingsAndStoreys + wallsAndOpenings

    static let core: [AnyCommand] = [
        RenameProjectCommand(projectID: project, newName: "Renamed").erased,
    ]

    static func json(_ value: some Encodable) throws -> Data {
        try ModelDocument.makeJSONEncoder().encode(value)
    }
}

/// Expects `command` to be refused with `expected` by both validate and apply, leaving the sample unchanged.
func expectRefused(_ expected: CommandValidationError, _ command: some Command) {
    var document = Sample.document()
    let original = document
    #expect(throws: expected) { try command.validate(against: document) }
    #expect(throws: expected) { _ = try command.apply(to: &document) }
    #expect(document == original)
}
