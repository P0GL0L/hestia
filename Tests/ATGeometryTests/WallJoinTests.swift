import ATContracts
import ATGeometry
import Foundation
import Testing

private let storeyID = StoreyID(UUID(uuidString: "00000000-0000-4000-8000-000000000003")!)
private let thickness = Length.inches(6)

private func wall(
    id: UInt8,
    start: Point2,
    end: Point2
) -> Wall {
    Wall(
        id: WallID(UUID(uuidString: String(format: "00000000-0000-4000-8000-0000000000%02x", id))!),
        storeyID: storeyID,
        start: start,
        end: end,
        thickness: thickness,
        height: Length.feet(8)
    )
}

private func point(feetX: Int64, feetY: Int64) -> Point2 {
    Point2(x: Length.feet(feetX), y: Length.feet(feetY))
}

@Test func lJoinOutlinesAreClosedWithoutSelfIntersection() throws {
    let walls = [
        wall(id: 0x01, start: point(feetX: 0, feetY: 0), end: point(feetX: 10, feetY: 0)),
        wall(id: 0x02, start: point(feetX: 0, feetY: 0), end: point(feetX: 0, feetY: 10)),
    ]
    let outlines = try StraightWallOutlines().outlines(for: walls)
    for polygon in outlines.values {
        #expect(polygon.isClosed)
        #expect(!PolygonValidation.hasSelfIntersection(polygon))
    }
}

@Test func tJoinOutlinesAreClosedWithoutSelfIntersection() throws {
    let walls = [
        wall(id: 0x11, start: point(feetX: 0, feetY: 0), end: point(feetX: 20, feetY: 0)),
        wall(id: 0x12, start: point(feetX: 10, feetY: 0), end: point(feetX: 10, feetY: 10)),
    ]
    let outlines = try StraightWallOutlines().outlines(for: walls)
    for polygon in outlines.values {
        #expect(polygon.isClosed)
        #expect(!PolygonValidation.hasSelfIntersection(polygon))
    }
}

@Test func xJoinOutlinesAreClosedWithoutSelfIntersection() throws {
    let walls = [
        wall(id: 0x21, start: point(feetX: 0, feetY: 10), end: point(feetX: 20, feetY: 10)),
        wall(id: 0x22, start: point(feetX: 10, feetY: 0), end: point(feetX: 10, feetY: 20)),
    ]
    let outlines = try StraightWallOutlines().outlines(for: walls)
    for polygon in outlines.values {
        #expect(polygon.isClosed)
        #expect(!PolygonValidation.hasSelfIntersection(polygon))
    }
}
