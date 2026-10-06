import ATContracts
import ATExchange
import ATGeometry
import Foundation
import Testing

private let storeyID = StoreyID(UUID(uuidString: "00000000-0000-4000-8000-000000000003")!)
private let wallThickness = Length.inches(6)

@Test func dxfLengthUnitsRoundTripTicks() {
    let sample = Length.feet(10)
    let inches = DXFDrawingUnits.inches
    let millimeters = DXFDrawingUnits.millimeters

    let inchCoord = inches.coordinate(from: sample)
    #expect(inches.length(from: inchCoord).ticks == sample.ticks)

    let mmCoord = millimeters.coordinate(from: sample)
    #expect(millimeters.length(from: mmCoord).ticks == sample.ticks)

    #expect(inches.coordinate(from: Length.inches(1)) == 1.0)
    #expect(millimeters.coordinate(from: Length.millimeters(1)) == 1.0)
}

@Test func tenByTwelveFootRectangleDXFExportsAndRecoversEndpoints() throws {
    let width = Length.feet(10)
    let height = Length.feet(12)
    let half = wallThickness.ticks / 2

    func p(x: Int64, y: Int64) -> Point2 {
        Point2(x: Length(ticks: x), y: Length(ticks: y))
    }

    let expectedEndpoints = [
        p(x: 0, y: 0),
        p(x: width.ticks, y: 0),
        p(x: width.ticks, y: height.ticks),
        p(x: 0, y: height.ticks),
    ]

    let walls = [
        Wall(
            id: WallID(UUID(uuidString: "00000000-0000-4000-8000-000000000041")!),
            storeyID: storeyID,
            start: p(x: 0, y: 0),
            end: p(x: width.ticks, y: 0),
            thickness: wallThickness,
            height: Length.feet(8)
        ),
        Wall(
            id: WallID(UUID(uuidString: "00000000-0000-4000-8000-000000000042")!),
            storeyID: storeyID,
            start: p(x: width.ticks, y: 0),
            end: p(x: width.ticks, y: height.ticks),
            thickness: wallThickness,
            height: Length.feet(8)
        ),
        Wall(
            id: WallID(UUID(uuidString: "00000000-0000-4000-8000-000000000043")!),
            storeyID: storeyID,
            start: p(x: width.ticks, y: height.ticks),
            end: p(x: 0, y: height.ticks),
            thickness: wallThickness,
            height: Length.feet(8)
        ),
        Wall(
            id: WallID(UUID(uuidString: "00000000-0000-4000-8000-000000000044")!),
            storeyID: storeyID,
            start: p(x: 0, y: height.ticks),
            end: p(x: 0, y: 0),
            thickness: wallThickness,
            height: Length.feet(8)
        ),
    ]

    let dxf = try SchematicWallOutlineDXF.export(walls: walls, units: .inches)
    #expect(dxf.contains("AC1027"))
    #expect(dxf.contains("$INSUNITS"))

    let parsed = SchematicWallOutlineDXFReader.parse(dxf)
    #expect(parsed.insunits == DXFDrawingUnits.inches.insunitsCode)
    #expect(parsed.layers.contains(SchematicWallOutlineDXF.wallLayer))
    #expect(parsed.layers.contains(SchematicWallOutlineDXF.annotationTextLayer))
    #expect(parsed.textByLayer[SchematicWallOutlineDXF.annotationTextLayer]?.contains(SchematicWallOutlineDXF.schematicStamp) == true)
    #expect(parsed.closedPolylinesByLayer[SchematicWallOutlineDXF.wallLayer]?.count == 4)

    let recovered = SchematicWallOutlineDXFReader.recoveredRectangleEndpoints(
        from: parsed,
        units: .inches,
        halfWallThickness: Length(ticks: half)
    )
    #expect(recovered.count == 4)

    for expected in expectedEndpoints {
        let match = recovered.contains { point in
            abs(point.x.ticks - expected.x.ticks) <= 1 && abs(point.y.ticks - expected.y.ticks) <= 1
        }
        #expect(match)
    }
}
