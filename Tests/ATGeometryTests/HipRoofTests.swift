import ATContracts
import ATGeometry
import Foundation
import Testing

@Test func hipRoofRidgeHeightFromPitchAndHalfSpan() throws {
    let builder = HipRoofBuilder()
    let pitch = HipRoofPitch(risePerTwelveInches: Length.inches(4))
    let halfShort = Length.feet(5)
    let expectedRise = Length.inches(20)
    let computed = builder.ridgeHeightAboveEave(pitch: pitch, halfShortSpan: halfShort)
    #expect(computed.ticks == expectedRise.ticks)
}

@Test func hipRoofPlanesMeetAtRidgeWithExpectedHeight() throws {
    let builder = HipRoofBuilder()
    let width = Length.feet(10)
    let length = Length.feet(12)
    let eaveZ = Length.feet(8)
    let pitch = HipRoofPitch(risePerTwelveInches: Length.inches(4))
    let overhang = Length.inches(12)

    let roof = try builder.build(
        minCorner: Point2(x: Length(ticks: 0), y: Length(ticks: 0)),
        maxCorner: Point2(x: length, y: width),
        eaveZ: eaveZ,
        pitch: pitch,
        overhang: overhang
    )

    #expect(roof.planes.count == 4)
    for plane in roof.planes {
        #expect(plane.isClosed)
        #expect(plane.vertices.count >= 3)
    }

    let spanX = length.ticks + 2 * overhang.ticks
    let spanY = width.ticks + 2 * overhang.ticks
    let halfShort = Length(ticks: min(spanX, spanY) / 2)
    let expectedRidgeHeight = builder.ridgeHeightAboveEave(pitch: pitch, halfShortSpan: halfShort)
    #expect(roof.ridgeHeightAboveEave.ticks == expectedRidgeHeight.ticks)

    let expectedRidgeZ = eaveZ.ticks + expectedRidgeHeight.ticks
    #expect(roof.ridgeStart.z.ticks == expectedRidgeZ)
    #expect(roof.ridgeEnd.z.ticks == expectedRidgeZ)

    let south = roof.planes[0]
    let north = roof.planes[1]
    let west = roof.planes[2]
    let east = roof.planes[3]

    #expect(builder.cornerGapTicks(roof.ridgeStart, south.vertices[3]) <= 1)
    #expect(builder.cornerGapTicks(roof.ridgeEnd, south.vertices[2]) <= 1)
    #expect(builder.cornerGapTicks(roof.ridgeStart, north.vertices[2]) <= 1)
    #expect(builder.cornerGapTicks(roof.ridgeEnd, north.vertices[3]) <= 1)
    #expect(builder.cornerGapTicks(west.vertices[2], roof.ridgeStart) <= 1)
    #expect(builder.cornerGapTicks(east.vertices[2], roof.ridgeEnd) <= 1)
    #expect(builder.cornerGapTicks(south.vertices[0], west.vertices[0]) == 0)
    #expect(builder.cornerGapTicks(south.vertices[1], east.vertices[1]) == 0)
}
