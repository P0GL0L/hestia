import ATContracts
import Foundation

public struct CottageRoomPlan: Hashable, Sendable {
    public var name: String
    public var interiorWidth: Length
    public var interiorHeight: Length
    public var interiorMin: Point2
    public var loop: [Wall]
}

public struct SixRoomCottage: Sendable {
    public var walls: [Wall]
    public var rooms: [CottageRoomPlan]
    public var stair: StraightStair
    public var slabCut: AxisAlignedRectangle2
    public var roof: HipRoofGeometry
    public var wallHeight: Length
    public var exteriorMin: Point2
    public var exteriorMax: Point2
}

public enum CottageFixture {
    public static let wallThickness = Length.inches(6)
    public static let wallHeight = Length.feet(8)

    public static func sixRoom() throws -> SixRoomCottage {
        let thickness = wallThickness.ticks
        let half = thickness / 2
        let columnWidths = [Length.feet(14).ticks, Length.feet(10).ticks, Length.feet(12).ticks]
        let rowHeights = [Length.feet(12).ticks, Length.feet(10).ticks]
        let storeyID = StoreyID(UUID(uuidString: "00000000-0000-4000-8000-0000000000c1")!)

        func interiorOriginX(_ column: Int) -> Int64 {
            var x: Int64 = 0
            if column > 0 {
                for index in 0..<column {
                    x += columnWidths[index] + thickness
                }
            }
            return x
        }

        func interiorOriginY(_ row: Int) -> Int64 {
            var y: Int64 = 0
            if row > 0 {
                for index in 0..<row {
                    y += rowHeights[index] + thickness
                }
            }
            return y
        }

        func verticalCenterline(_ index: Int) -> Int64 {
            if index == 0 {
                return -half
            }
            return interiorOriginX(index) - half
        }

        func horizontalCenterline(_ index: Int) -> Int64 {
            if index == 0 {
                return -half
            }
            return interiorOriginY(index) - half
        }

        func point(_ x: Int64, _ y: Int64) -> Point2 {
            Point2(x: Length(ticks: x), y: Length(ticks: y))
        }

        func wall(number: Int, from: Point2, to: Point2) -> Wall {
            Wall(
                id: WallID(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", number))!),
                storeyID: storeyID,
                start: from,
                end: to,
                thickness: wallThickness,
                height: wallHeight
            )
        }

        let rightInterior = interiorOriginX(2) + columnWidths[2]
        let topInterior = interiorOriginY(1) + rowHeights[1]
        let left = verticalCenterline(0)
        let right = verticalCenterline(3)
        let bottom = horizontalCenterline(0)
        let top = horizontalCenterline(2)
        let midY = horizontalCenterline(1)

        let walls = [
            wall(number: 0x101, from: point(left, bottom), to: point(right, bottom)),
            wall(number: 0x102, from: point(right, bottom), to: point(right, top)),
            wall(number: 0x103, from: point(right, top), to: point(left, top)),
            wall(number: 0x104, from: point(left, top), to: point(left, bottom)),
            wall(number: 0x105, from: point(verticalCenterline(1), bottom), to: point(verticalCenterline(1), top)),
            wall(number: 0x106, from: point(verticalCenterline(2), bottom), to: point(verticalCenterline(2), top)),
            wall(number: 0x107, from: point(left, midY), to: point(right, midY)),
        ]

        let names = [
            (0, 0, "Living"),
            (1, 0, "Kitchen"),
            (2, 0, "Utility"),
            (0, 1, "Bedroom"),
            (1, 1, "Bath"),
            (2, 1, "Bedroom 2"),
        ]
        let rooms: [CottageRoomPlan] = names.enumerated().map { offset, item in
            let x0 = interiorOriginX(item.0)
            let y0 = interiorOriginY(item.1)
            let x1 = x0 + columnWidths[item.0]
            let y1 = y0 + rowHeights[item.1]
            let idBase = 0x200 + offset * 4
            let loop = [
                wall(number: idBase, from: point(x0 - half, y0 - half), to: point(x1 + half, y0 - half)),
                wall(number: idBase + 1, from: point(x1 + half, y0 - half), to: point(x1 + half, y1 + half)),
                wall(number: idBase + 2, from: point(x1 + half, y1 + half), to: point(x0 - half, y1 + half)),
                wall(number: idBase + 3, from: point(x0 - half, y1 + half), to: point(x0 - half, y0 - half)),
            ]
            return CottageRoomPlan(
                name: item.2,
                interiorWidth: Length(ticks: columnWidths[item.0]),
                interiorHeight: Length(ticks: rowHeights[item.1]),
                interiorMin: point(x0, y0),
                loop: loop
            )
        }

        let stair = StraightStair(
            riserRise: Length.inches(8),
            treadRun: Length.inches(10),
            riserCount: 12
        )
        let slabCut = try StraightStairSlabCut().opening(
            for: stair,
            origin: Point2(x: Length.feet(2), y: Length.feet(2)),
            cutWidth: Length.feet(3),
            runsAlongX: true,
            openingLengthLimit: Length.feet(12)
        )
        let exteriorMin = point(-thickness, -thickness)
        let exteriorMax = point(rightInterior + thickness, topInterior + thickness)
        let roof = try HipRoofBuilder().build(
            minCorner: exteriorMin,
            maxCorner: exteriorMax,
            eaveZ: wallHeight,
            pitch: HipRoofPitch(risePerTwelveInches: Length.inches(4)),
            overhang: Length.inches(12)
        )

        return SixRoomCottage(
            walls: walls,
            rooms: rooms,
            stair: stair,
            slabCut: slabCut,
            roof: roof,
            wallHeight: wallHeight,
            exteriorMin: exteriorMin,
            exteriorMax: exteriorMax
        )
    }
}
