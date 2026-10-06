import ATContracts
import ATGeometry
import Foundation
import Testing

private func cottageStair(riserCount: Int) -> StraightStair {
    StraightStair(
        riserRise: Length.inches(7),
        treadRun: Length.inches(10),
        riserCount: riserCount
    )
}

@Test func straightStairFitsOpeningAndCutsSlab() throws {
    let stair = cottageStair(riserCount: 14)
    let openingLimit = Length.feet(12)
    try stair.validate(openingLength: openingLimit)

    let cut = try StraightStairSlabCut().opening(
        for: stair,
        origin: Point2(x: Length.feet(2), y: Length.feet(3)),
        cutWidth: Length.feet(3),
        runsAlongX: true,
        openingLengthLimit: openingLimit
    )

    let expectedRun = Length.inches(130)
    #expect(cut.maxX.ticks - cut.minX.ticks == expectedRun.ticks)
    #expect(cut.maxY.ticks - cut.minY.ticks == Length.feet(3).ticks)
}

@Test func straightStairRejectsRunLongerThanOpening() {
    let stair = cottageStair(riserCount: 14)
    let tightOpening = Length.inches(120)
    #expect(throws: StraightStairError.runExceedsOpeningLength) {
        try stair.validate(openingLength: tightOpening)
    }
    #expect(throws: StraightStairError.runExceedsOpeningLength) {
        try StraightStairSlabCut().opening(
            for: stair,
            origin: Point2(x: Length(ticks: 0), y: Length(ticks: 0)),
            cutWidth: Length.feet(3),
            runsAlongX: true,
            openingLengthLimit: tightOpening
        )
    }
}
