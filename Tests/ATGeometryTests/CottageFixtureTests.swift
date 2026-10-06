import ATContracts
import ATGeometry
import Foundation
import Testing

@Test func sixRoomCottageHasClosedRoomsAndKnownAreas() throws {
    let cottage = try CottageFixture.sixRoom()
    #expect(cottage.rooms.count == 6)
    #expect(cottage.walls.count == 7)

    let living = try #require(cottage.rooms.first { $0.name == "Living" })
    let bath = try #require(cottage.rooms.first { $0.name == "Bath" })
    let livingArea = try RoomAreaCalculator().netArea(for: living.loop)
    let bathArea = try RoomAreaCalculator().netArea(for: bath.loop)
    #expect(livingArea.tickSquares == Area2.fromDimensions(width: Length.feet(14), height: Length.feet(12)).tickSquares)
    #expect(bathArea.tickSquares == Area2.fromDimensions(width: Length.feet(10), height: Length.feet(10)).tickSquares)

    let outlines = try StraightWallOutlines().outlines(for: cottage.walls)
    #expect(outlines.count == cottage.walls.count)
    for polygon in outlines.values {
        #expect(polygon.isClosed)
    }

    #expect(cottage.roof.planes.count == 4)
    try cottage.stair.validate(openingLength: Length.feet(12))
    #expect(cottage.slabCut.maxX.ticks > cottage.slabCut.minX.ticks)
}
