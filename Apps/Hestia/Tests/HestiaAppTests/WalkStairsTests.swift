import ATContracts
import Foundation
import Testing
@testable import HestiaApp

/// A length in feet, to the nearest tick.
private func feet(_ value: Double) -> Length {
    Length(ticks: Int64((value / HouseScene.feetPerTick).rounded()))
}

private func point(_ x: Double, _ y: Double) -> Point2 {
    Point2(x: feet(x), y: feet(y))
}

/// Two storeys nine feet apart and one straight stair on the ground floor, climbing north from (10, 2) to
/// (10, 14), three feet wide, fifteen risers of 7.2 inches.
private func twoStoreys() throws -> (document: ModelDocument, ground: StoreyID, upper: StoreyID) {
    var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(UUID()), name: "Stairs"),
                                 buildings: [], storeys: [], walls: [], openings: [], rooms: [])
    let building = BuildingID(UUID()), ground = StoreyID(UUID()), upper = StoreyID(UUID())
    _ = try document.perform(batch: [
        AddBuildingCommand(buildingID: building, name: "House").erased,
        AddStoreyCommand(storeyID: ground, buildingID: building, name: "Ground", elevation: .feet(0)).erased,
        AddStoreyCommand(storeyID: upper, buildingID: building, name: "Upper", elevation: .feet(9)).erased,
    ])
    document.stairs = [Stair(id: StairID(UUID()), storeyID: ground, runStart: point(10, 2), runEnd: point(10, 14),
                             width: feet(3), riserCount: 15, riserHeight: feet(0.6))]
    return (document, ground, upper)
}

/// Walks `seconds` at `heading` (0 north, clockwise) through the house.
private func walk(_ start: Walker, heading: Double, seconds: Double, in house: WalkHouse) -> Walker {
    var walker = start
    walker.heading = heading
    for _ in 0..<Int(seconds / 0.05) {
        walker.step(WalkInput(forward: 1), seconds: 0.05, house: house)
    }
    return walker
}

@Suite("Walking up and down stairs")
struct WalkStairsTests {
    @Test("A walk up the stair reaches the floor above and its storey, and back down again")
    func climbAndDescend() throws {
        let (document, ground, upper) = try twoStoreys()
        let house = WalkHouse(document: document)
        #expect(house.flights.count == 1)
        let start = Walker(x: 10, y: 0, floor: 0, storey: ground)
        let top = walk(start, heading: 0, seconds: 4, in: house)
        #expect(top.y > 14)
        #expect(abs(top.floor - 9) < 1e-3)
        #expect(top.storey == upper)
        // Halfway, the walker stands halfway up.
        let middle = walk(start, heading: 0, seconds: 1.6, in: house)
        #expect(middle.y > 2 && middle.y < 14)
        #expect(abs(middle.floor - 9 * (middle.y - 2) / 12) < 0.05)
        let bottom = walk(top, heading: .pi, seconds: 4, in: house)
        #expect(bottom.y < 2)
        #expect(abs(bottom.floor) < 1e-3)
        #expect(bottom.storey == ground)
    }

    @Test("On the stair the walker keeps within its width")
    func staysOnTheTreads() throws {
        let (document, ground, _) = try twoStoreys()
        let house = WalkHouse(document: document)
        let onIt = walk(Walker(x: 10, y: 0, floor: 0, storey: ground), heading: 0, seconds: 1.4, in: house)
        // Step sideways, hard, while on the stair.
        let pushed = walk(onIt, heading: .pi / 2, seconds: 2, in: house)
        #expect(abs(pushed.x - 10) <= 1.5 - WalkHouse.sideRoom + 1e-6)
        #expect(pushed.floor > 0)
    }

    @Test("The stair's high side blocks a walk on the floor below, and its opening blocks one on the floor above")
    func sidesBlock() throws {
        let (document, ground, upper) = try twoStoreys()
        let house = WalkHouse(document: document)
        // Below, walking east into the stair where it is six feet up.
        let below = walk(Walker(x: 6, y: 10, floor: 0, storey: ground), heading: .pi / 2, seconds: 3, in: house)
        #expect(below.x <= 8.5 - Walker.radius + 1e-6)
        #expect(below.floor == 0)
        // Above, walking east toward the stairwell where it is low.
        let above = walk(Walker(x: 6, y: 4, floor: 9, storey: upper), heading: .pi / 2, seconds: 3, in: house)
        #expect(above.x <= 8.5 - Walker.radius + 1e-6)
        #expect(above.floor == 9)
        // The east side blocks in the same two situations.
        let belowEast = walk(Walker(x: 14, y: 10, floor: 0, storey: ground), heading: -.pi / 2,
                             seconds: 3, in: house)
        #expect(belowEast.x >= 11.5 + Walker.radius - 1e-6 && belowEast.floor == 0)
        let aboveEast = walk(Walker(x: 14, y: 4, floor: 9, storey: upper), heading: -.pi / 2,
                             seconds: 3, in: house)
        #expect(aboveEast.x >= 11.5 + Walker.radius - 1e-6 && aboveEast.floor == 9)
        // Beside the stair, past its foot, nothing is in the way.
        let past = walk(Walker(x: 6, y: 0, floor: 0, storey: ground), heading: .pi / 2, seconds: 3, in: house)
        #expect(past.x > 14)
    }

    @Test("From the floor above, a walk into the top of the stair goes down it")
    func downFromAbove() throws {
        let (document, ground, upper) = try twoStoreys()
        let house = WalkHouse(document: document)
        let down = walk(Walker(x: 10, y: 16, floor: 9, storey: upper), heading: .pi, seconds: 4, in: house)
        #expect(down.y < 2)
        #expect(abs(down.floor) < 1e-3)
        #expect(down.storey == ground)
    }

    @Test("A stair connects to the next storey in the same building")
    func upperStoreyStaysInTheBuilding() throws {
        var (document, _, upper) = try twoStoreys()
        let otherBuilding = BuildingID(UUID()), otherStorey = StoreyID(UUID())
        _ = try document.perform(batch: [
            AddBuildingCommand(buildingID: otherBuilding, name: "Other house").erased,
            AddStoreyCommand(storeyID: otherStorey, buildingID: otherBuilding, name: "Other floor",
                              elevation: .feet(4)).erased,
        ])
        let flight = try #require(WalkHouse.flights(document).first)
        #expect(flight.upper == upper)
    }

    @Test("An overlapping stair in another building does not affect this building's walker")
    func foreignBuildingFlightIsIgnored() throws {
        var (document, ground, _) = try twoStoreys()
        let template = try #require(document.stairs.first)
        document.stairs = []
        let otherBuilding = BuildingID(UUID()), otherGround = StoreyID(UUID()), otherUpper = StoreyID(UUID())
        _ = try document.perform(batch: [
            AddBuildingCommand(buildingID: otherBuilding, name: "Other house").erased,
            AddStoreyCommand(storeyID: otherGround, buildingID: otherBuilding, name: "Other ground",
                              elevation: .feet(0)).erased,
            AddStoreyCommand(storeyID: otherUpper, buildingID: otherBuilding, name: "Other upper",
                              elevation: .feet(9)).erased,
        ])
        var foreign = template
        foreign.id = StairID(UUID())
        foreign.storeyID = otherGround
        document.stairs = [foreign]
        let crossed = walk(Walker(x: 6, y: 7, floor: 0, storey: ground), heading: .pi / 2,
                           seconds: 2, in: WalkHouse(document: document))
        #expect(crossed.x > 14)
        #expect(crossed.floor == 0 && crossed.storey == ground)
    }

    @Test("Only a straight stair that reaches a higher floor becomes a walk flight")
    func flightNeedsAReachedUpperStorey() throws {
        var (document, _, upper) = try twoStoreys()
        document.storeys.removeAll { $0.id == upper }
        #expect(WalkHouse.flights(document).isEmpty)

        (document, _, _) = try twoStoreys()
        document.stairs[0].riserHeight = feet(0.5)
        #expect(WalkHouse.flights(document).isEmpty)

        (document, _, _) = try twoStoreys()
        document.stairs[0].kind = .lShaped
        #expect(WalkHouse.flights(document).isEmpty)
    }

    @Test("A stair can be entered only through an end level with the floor")
    func entersOnlyAtLevelEnds() throws {
        let (document, ground, upper) = try twoStoreys()
        let house = WalkHouse(document: document)
        let below = walk(Walker(x: 6, y: 2.9, floor: 0, storey: ground), heading: .pi / 2,
                         seconds: 3, in: house)
        #expect(below.x <= 8.5 - Walker.radius + 1e-6)
        #expect(below.floor == 0 && below.storey == ground)
        let above = walk(Walker(x: 6, y: 13.1, floor: 9, storey: upper), heading: .pi / 2,
                         seconds: 3, in: house)
        #expect(above.x <= 8.5 - Walker.radius + 1e-6)
        #expect(above.floor == 9 && above.storey == upper)
    }

    @Test("A wall across a flight's top holds the walker there without pushing it back down")
    func wallAtTopHoldsTheWalker() throws {
        var (document, ground, upper) = try twoStoreys()
        document.walls.append(Wall(id: WallID(UUID()), storeyID: upper, start: point(0, 14), end: point(20, 14),
                                   thickness: feet(0.5), height: feet(8)))
        let house = WalkHouse(document: document)
        let start = Walker(x: 10, y: 0, floor: 0, storey: ground)
        let held = walk(start, heading: 0, seconds: 4, in: house)
        #expect(held.y > 13 && held.y <= 14)
        #expect(abs(held.floor - 9) < 1e-3 && held.storey == upper)
        let stillHeld = walk(held, heading: 0, seconds: 1, in: house)
        #expect(stillHeld.y > 13 && stillHeld.y <= 14)
        #expect(abs(stillHeld.floor - 9) < 1e-3 && stillHeld.storey == upper)
    }

    @Test("A wall across a flight's bottom holds a descending walker without pushing it back up")
    func wallAtBottomHoldsTheWalker() throws {
        var (document, ground, upper) = try twoStoreys()
        document.walls.append(Wall(id: WallID(UUID()), storeyID: ground, start: point(0, 2), end: point(20, 2),
                                   thickness: feet(0.5), height: feet(8)))
        let house = WalkHouse(document: document)
        let start = Walker(x: 10, y: 16, floor: 9, storey: upper)
        let held = walk(start, heading: .pi, seconds: 4, in: house)
        #expect(held.y >= 2 && held.y < 3)
        #expect(abs(held.floor) < 1e-3 && held.storey == ground)
        let stillHeld = walk(held, heading: .pi, seconds: 1, in: house)
        #expect(stillHeld.y >= 2 && stillHeld.y < 3)
        #expect(abs(stillHeld.floor) < 1e-3 && stillHeld.storey == ground)
    }

    @Test("The active storey's wall stops a walker partway up a flight")
    func wallAcrossAFlightStopsTheClimb() throws {
        var (document, ground, _) = try twoStoreys()
        document.walls.append(Wall(id: WallID(UUID()), storeyID: ground, start: point(0, 6), end: point(20, 6),
                                   thickness: feet(0.5), height: feet(8)))
        let house = WalkHouse(document: document)
        let start = Walker(x: 10, y: 0, floor: 0, storey: ground)
        let held = walk(start, heading: 0, seconds: 4, in: house)
        #expect(held.y > 4 && held.y < 6)
        #expect(held.floor > 1 && held.floor < 4)
        #expect(held.storey == ground)
        let stillHeld = walk(held, heading: 0, seconds: 1, in: house)
        #expect(stillHeld.y > 4 && stillHeld.y < 6)
        #expect(stillHeld.floor > 1 && stillHeld.floor < 4)
    }

    @Test("The active storey's barriers switch halfway up a flight")
    func barriersSwitchAtTheMiddle() throws {
        let (document, ground, upper) = try twoStoreys()
        let flight = try #require(WalkHouse.flights(document).first)
        let acrossUpperHalf = WalkBarriers.Segment(ax: 0, ay: 10, bx: 20, by: 10, half: 0.25)
        let start = Walker(x: 10, y: 0, floor: 0, storey: ground)
        let upperBlocked = WalkHouse(levels: [ground: WalkBarriers(segments: []),
                                              upper: WalkBarriers(segments: [acrossUpperHalf])],
                                     flights: [flight])
        let held = walk(start, heading: 0, seconds: 4, in: upperBlocked)
        #expect(held.y > 8 && held.y < 10 && held.storey == upper)

        let lowerOnly = WalkHouse(levels: [ground: WalkBarriers(segments: [acrossUpperHalf]),
                                           upper: WalkBarriers(segments: [])],
                                  flights: [flight])
        let passed = walk(start, heading: 0, seconds: 4, in: lowerOnly)
        #expect(abs(passed.floor - 9) < 1e-3 && passed.storey == upper)
        #expect(passed.y > 14)
    }

    @Test("A diagonal walk slides along a flight's body-width side barrier")
    func sideBarrierSlides() throws {
        let (document, ground, _) = try twoStoreys()
        let start = Walker(x: 6, y: 7, floor: 0, storey: ground)
        let slid = walk(start, heading: .pi / 4, seconds: 0.5, in: WalkHouse(document: document))
        #expect(slid.x <= 8.5 - Walker.radius + 1e-6)
        #expect(slid.y > start.y + 0.5)
        #expect(slid.floor == 0 && slid.storey == ground)
    }

    @Test("A house with one storey walks as before: its walls stop the walker")
    func oneStorey() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addWall(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(30, 0))
        let storey = try #require(session.model.groundStorey)
        let house = WalkHouse(document: session.model.document)
        let stopped = walk(Walker(x: 10, y: -4, floor: 0, storey: storey), heading: 0, seconds: 3, in: house)
        #expect(stopped.y < 0)
    }
}
