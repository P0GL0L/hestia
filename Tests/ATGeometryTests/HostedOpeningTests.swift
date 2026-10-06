import ATContracts
import ATGeometry
import Foundation
import Testing

@Test func hostedOpeningRejectsPastWallEnd() throws {
    let wall = Wall(
        id: WallID(UUID()),
        storeyID: StoreyID(UUID()),
        start: Point2(x: .feet(0), y: .feet(0)),
        end: Point2(x: .feet(10), y: .feet(0)),
        thickness: .inches(6),
        height: .feet(8)
    )
    let opening = Opening(
        id: OpeningID(UUID()),
        wallID: wall.id,
        offsetAlongWall: .feet(9),
        width: .feet(2),
        height: .feet(6, inchCount: 8),
        sillHeight: .feet(0)
    )
    #expect(throws: HostedOpeningValidationError.extendsPastWallEnd) {
        try HostedOpeningValidator().validate(opening: opening, on: wall)
    }
}

@Test func hostedOpeningRejectsPastWallStart() throws {
    let wall = Wall(
        id: WallID(UUID()),
        storeyID: StoreyID(UUID()),
        start: Point2(x: .feet(0), y: .feet(0)),
        end: Point2(x: .feet(10), y: .feet(0)),
        thickness: .inches(6),
        height: .feet(8)
    )
    let opening = Opening(
        id: OpeningID(UUID()),
        wallID: wall.id,
        offsetAlongWall: .inches(-1),
        width: .feet(3),
        height: .feet(6, inchCount: 8),
        sillHeight: .feet(0)
    )
    #expect(throws: HostedOpeningValidationError.extendsPastWallStart) {
        try HostedOpeningValidator().validate(opening: opening, on: wall)
    }
}
