import ATContracts
import Foundation

/// Roof pitch as vertical rise per 12 inches of horizontal run.
public struct HipRoofPitch: Hashable, Sendable {
    public var risePerTwelveInches: Length

    public init(risePerTwelveInches: Length) {
        self.risePerTwelveInches = risePerTwelveInches
    }
}

public enum HipRoofError: Error, Sendable, Equatable {
    case degenerateFootprint
}

public struct HipRoofGeometry: Hashable, Sendable {
    /// Four roof planes in order: south, north, west, east (relative to +Y / +X).
    public var planes: [ClosedPolygon3]
    public var ridgeHeightAboveEave: Length
    public var ridgeStart: Point3
    public var ridgeEnd: Point3

    public init(
        planes: [ClosedPolygon3],
        ridgeHeightAboveEave: Length,
        ridgeStart: Point3,
        ridgeEnd: Point3
    ) {
        self.planes = planes
        self.ridgeHeightAboveEave = ridgeHeightAboveEave
        self.ridgeStart = ridgeStart
        self.ridgeEnd = ridgeEnd
    }
}

public struct HipRoofBuilder: Sendable {
    private static let runPerPitch: Int64 = Length.inches(12).ticks

    public init() {}

    /// Ridge height above the eave line from pitch and half of the short roof span.
    public func ridgeHeightAboveEave(pitch: HipRoofPitch, halfShortSpan: Length) -> Length {
        let rise = pitch.risePerTwelveInches.ticks
        let half = halfShortSpan.ticks
        return Length(ticks: (rise * half) / Self.runPerPitch)
    }

    /// Builds a hip roof from an axis-aligned exterior footprint, expanding by `overhang` at the eave.
    public func build(
        minCorner: Point2,
        maxCorner: Point2,
        eaveZ: Length,
        pitch: HipRoofPitch,
        overhang: Length
    ) throws -> HipRoofGeometry {
        let over = overhang.ticks
        let x0 = minCorner.x.ticks - over
        let y0 = minCorner.y.ticks - over
        let x1 = maxCorner.x.ticks + over
        let y1 = maxCorner.y.ticks + over
        let spanX = x1 - x0
        let spanY = y1 - y0
        guard spanX > 0, spanY > 0 else {
            throw HipRoofError.degenerateFootprint
        }

        let halfShort = min(spanX, spanY) / 2
        let ridgeHeight = ridgeHeightAboveEave(pitch: pitch, halfShortSpan: Length(ticks: halfShort))
        let zEave = eaveZ.ticks
        let zRidge = zEave + ridgeHeight.ticks
        let yMid = (y0 + y1) / 2
        let xMid = (x0 + x1) / 2

        func point3(x: Int64, y: Int64, z: Int64) -> Point3 {
            Point3(x: Length(ticks: x), y: Length(ticks: y), z: Length(ticks: z))
        }

        let ridgeStart: Point3
        let ridgeEnd: Point3
        let planes: [ClosedPolygon3]

        if spanX >= spanY {
            let inset = spanY / 2
            let ridgeX0 = x0 + inset
            let ridgeX1 = x1 - inset
            ridgeStart = point3(x: ridgeX0, y: yMid, z: zRidge)
            ridgeEnd = point3(x: ridgeX1, y: yMid, z: zRidge)
            planes = [
                ClosedPolygon3(vertices: [
                    point3(x: x0, y: y0, z: zEave),
                    point3(x: x1, y: y0, z: zEave),
                    point3(x: ridgeX1, y: yMid, z: zRidge),
                    point3(x: ridgeX0, y: yMid, z: zRidge),
                ]),
                ClosedPolygon3(vertices: [
                    point3(x: x1, y: y1, z: zEave),
                    point3(x: x0, y: y1, z: zEave),
                    point3(x: ridgeX0, y: yMid, z: zRidge),
                    point3(x: ridgeX1, y: yMid, z: zRidge),
                ]),
                ClosedPolygon3(vertices: [
                    point3(x: x0, y: y0, z: zEave),
                    point3(x: x0, y: y1, z: zEave),
                    point3(x: ridgeX0, y: yMid, z: zRidge),
                ]),
                ClosedPolygon3(vertices: [
                    point3(x: x1, y: y1, z: zEave),
                    point3(x: x1, y: y0, z: zEave),
                    point3(x: ridgeX1, y: yMid, z: zRidge),
                ]),
            ]
        } else {
            let inset = spanX / 2
            let ridgeY0 = y0 + inset
            let ridgeY1 = y1 - inset
            ridgeStart = point3(x: xMid, y: ridgeY0, z: zRidge)
            ridgeEnd = point3(x: xMid, y: ridgeY1, z: zRidge)
            planes = [
                ClosedPolygon3(vertices: [
                    point3(x: x0, y: y0, z: zEave),
                    point3(x: x1, y: y0, z: zEave),
                    point3(x: xMid, y: ridgeY0, z: zRidge),
                ]),
                ClosedPolygon3(vertices: [
                    point3(x: x1, y: y1, z: zEave),
                    point3(x: x0, y: y1, z: zEave),
                    point3(x: xMid, y: ridgeY1, z: zRidge),
                ]),
                ClosedPolygon3(vertices: [
                    point3(x: x0, y: y0, z: zEave),
                    point3(x: x0, y: y1, z: zEave),
                    point3(x: xMid, y: ridgeY1, z: zRidge),
                    point3(x: xMid, y: ridgeY0, z: zRidge),
                ]),
                ClosedPolygon3(vertices: [
                    point3(x: x1, y: y1, z: zEave),
                    point3(x: x1, y: y0, z: zEave),
                    point3(x: xMid, y: ridgeY0, z: zRidge),
                    point3(x: xMid, y: ridgeY1, z: zRidge),
                ]),
            ]
        }

        return HipRoofGeometry(
            planes: planes,
            ridgeHeightAboveEave: ridgeHeight,
            ridgeStart: ridgeStart,
            ridgeEnd: ridgeEnd
        )
    }

    /// Maximum tick distance between two 3D points that should meet at a roof corner.
    public func cornerGapTicks(_ a: Point3, _ b: Point3) -> Int64 {
        let dx = abs(a.x.ticks - b.x.ticks)
        let dy = abs(a.y.ticks - b.y.ticks)
        let dz = abs(a.z.ticks - b.z.ticks)
        return max(dx, dy, dz)
    }
}
