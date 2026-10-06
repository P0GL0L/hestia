import ATContracts
import ATGeometry
import Foundation
import Testing

private let storeyID = StoreyID(UUID(uuidString: "00000000-0000-4000-8000-000000000003")!)
private let wallThickness = Length.inches(6)

@Test func tenByTwelveFootRoomNetArea() throws {
    let width = Length.feet(10)
    let height = Length.feet(12)
    let half = wallThickness.ticks / 2

    func p(x: Int64, y: Int64) -> Point2 {
        Point2(x: Length(ticks: x), y: Length(ticks: y))
    }

    let walls = [
        Wall(
            id: WallID(UUID(uuidString: "00000000-0000-4000-8000-000000000031")!),
            storeyID: storeyID,
            start: p(x: -half, y: -half),
            end: p(x: width.ticks + half, y: -half),
            thickness: wallThickness,
            height: Length.feet(8)
        ),
        Wall(
            id: WallID(UUID(uuidString: "00000000-0000-4000-8000-000000000032")!),
            storeyID: storeyID,
            start: p(x: width.ticks + half, y: -half),
            end: p(x: width.ticks + half, y: height.ticks + half),
            thickness: wallThickness,
            height: Length.feet(8)
        ),
        Wall(
            id: WallID(UUID(uuidString: "00000000-0000-4000-8000-000000000033")!),
            storeyID: storeyID,
            start: p(x: width.ticks + half, y: height.ticks + half),
            end: p(x: -half, y: height.ticks + half),
            thickness: wallThickness,
            height: Length.feet(8)
        ),
        Wall(
            id: WallID(UUID(uuidString: "00000000-0000-4000-8000-000000000034")!),
            storeyID: storeyID,
            start: p(x: -half, y: height.ticks + half),
            end: p(x: -half, y: -half),
            thickness: wallThickness,
            height: Length.feet(8)
        ),
    ]

    let area = try RoomAreaCalculator().netArea(for: walls)
    let expected = Area2.fromDimensions(width: width, height: height)
    #expect(area.tickSquares == expected.tickSquares)
}
