@testable import ATDrawings
import ATContracts
import Foundation
import Testing

private let foot = Double(Length.feet(1).ticks)

private func p(_ x: Double, _ y: Double, _ z: Double) -> Point3 {
    Point3(x: Length(ticks: Int64(x * foot)), y: Length(ticks: Int64(y * foot)), z: Length(ticks: Int64(z * foot)))
}

/// Triangles with their corners counterclockwise seen from outside, as one mesh.
private func mesh(_ faces: [[Point3]], id: UUID = UUID()) -> Mesh {
    var positions: [Point3] = []
    var indices: [UInt32] = []
    for face in faces {
        let base = UInt32(positions.count)
        positions += face
        for k in 1..<(face.count - 1) { indices += [base, base + UInt32(k), base + UInt32(k + 1)] }
    }
    return Mesh(elementID: id, materialID: MaterialID(rawValue: "wall"), positions: positions,
                normals: Array(repeating: Vector3f(x: 0, y: 0, z: 1), count: positions.count),
                uvs: Array(repeating: TextureCoordinate(u: 0, v: 0), count: positions.count), indices: indices)
}

private func box(_ x0: Double, _ y0: Double, _ z0: Double, _ x1: Double, _ y1: Double, _ z1: Double) -> Mesh {
    mesh([
        [p(x0, y0, z0), p(x1, y0, z0), p(x1, y0, z1), p(x0, y0, z1)],   // south, facing -y
        [p(x1, y1, z0), p(x0, y1, z0), p(x0, y1, z1), p(x1, y1, z1)],   // north
        [p(x1, y0, z0), p(x1, y1, z0), p(x1, y1, z1), p(x1, y0, z1)],   // east
        [p(x0, y1, z0), p(x0, y0, z0), p(x0, y0, z1), p(x0, y1, z1)],   // west
        [p(x0, y0, z1), p(x1, y0, z1), p(x1, y1, z1), p(x0, y1, z1)],   // top
        [p(x0, y1, z0), p(x1, y1, z0), p(x1, y0, z0), p(x0, y0, z0)],   // bottom
    ])
}

/// A gable roof over x0...x1 by y0...y1, its ridge running along y when `alongY`.
private func gable(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, eave: Double, ridge: Double,
                   alongY: Bool) -> Mesh {
    if alongY {
        let mx = (x0 + x1) / 2
        return mesh([[p(x0, y0, eave), p(mx, y0, ridge), p(mx, y1, ridge), p(x0, y1, eave)],
                     [p(x1, y0, eave), p(x1, y1, eave), p(mx, y1, ridge), p(mx, y0, ridge)],
                     [p(x0, y0, eave), p(x1, y0, eave), p(mx, y0, ridge)],
                     [p(x1, y1, eave), p(x0, y1, eave), p(mx, y1, ridge)]])
    }
    let my = (y0 + y1) / 2
    return mesh([[p(x0, y0, eave), p(x1, y0, eave), p(x1, my, ridge), p(x0, my, ridge)],
                 [p(x1, y1, eave), p(x0, y1, eave), p(x0, my, ridge), p(x1, my, ridge)],
                 [p(x0, y1, eave), p(x0, y0, eave), p(x0, my, ridge)],
                 [p(x1, y0, eave), p(x1, y1, eave), p(x1, my, ridge)]])
}

/// Looking north from the south: h is x, v is height, depth is y.
private let southElevation = HiddenLines.View(project: { x, y, z in (x, z, y) }, toward: (0, -1, 0))
/// Looking down from above: h is x, v is y, depth is minus the height.
private let fromAbove = HiddenLines.View(project: { x, y, z in (x, y, -z) }, toward: (0, 0, 1))

private func draw(_ meshes: [Mesh], _ view: HiddenLines.View) -> [HiddenLines.Segment] {
    HiddenLines.segments(meshes, view: view, cell: foot / 12, tolerance: foot / 12)
}

/// Total drawn length, in feet, of segments lying on the line through a and b, within an inch.
private func drawn(_ segments: [HiddenLines.Segment], from a: (Double, Double), to b: (Double, Double)) -> Double {
    let (ax, ay, bx, by) = (a.0 * foot, a.1 * foot, b.0 * foot, b.1 * foot)
    let length = ((bx - ax) * (bx - ax) + (by - ay) * (by - ay)).squareRoot()
    func off(_ h: Double, _ v: Double) -> Double { abs((bx - ax) * (ay - v) - (ax - h) * (by - ay)) / length }
    func along(_ h: Double, _ v: Double) -> Double { ((h - ax) * (bx - ax) + (v - ay) * (by - ay)) / length }
    var total = 0.0
    for segment in segments where off(segment.start.h, segment.start.v) < foot / 12
        && off(segment.end.h, segment.end.v) < foot / 12 {
        let t0 = max(min(along(segment.start.h, segment.start.v), along(segment.end.h, segment.end.v)), 0)
        let t1 = min(max(along(segment.start.h, segment.start.v), along(segment.end.h, segment.end.v)), length)
        total += max(t1 - t0, 0)
    }
    return total / foot
}

@Test func aBoxShowsItsOutlineAgainstTheSky() {
    let segments = draw([box(0, 0, 0, 20, 10, 8)], southElevation)
    #expect(abs(drawn(segments, from: (0, 0), to: (20, 0)) - 20) < 0.3)
    #expect(abs(drawn(segments, from: (0, 8), to: (20, 8)) - 20) < 0.3)
    #expect(abs(drawn(segments, from: (0, 0), to: (0, 8)) - 8) < 0.3)
    #expect(abs(drawn(segments, from: (20, 0), to: (20, 8)) - 8) < 0.3)
    #expect(segments.allSatisfy { $0.kind == .profile }, "every edge is against the sky")
}

@Test func whatIsBehindIsHidden() {
    // A tall box behind a low one: its foot is hidden, its top shows.
    let segments = draw([box(0, 0, 0, 20, 10, 8), box(5, 20, 0, 15, 30, 16)], southElevation)
    #expect(abs(drawn(segments, from: (5, 16), to: (15, 16)) - 10) < 0.3, "the tall box's top shows")
    #expect(abs(drawn(segments, from: (5, 0), to: (5, 16)) - 8) < 0.3, "its sides show only above the low box")
    #expect(drawn(segments, from: (5, 1), to: (15, 1)) < 0.3, "nothing of it shows through the low box")
}

@Test func aJointBetweenWallsInLineIsNotDrawn() {
    let segments = draw([box(0, 0, 0, 10, 1, 8), box(10, 0, 0, 20, 1, 8)], southElevation)
    #expect(drawn(segments, from: (10, 0), to: (10, 8)) < 0.3)
    #expect(abs(drawn(segments, from: (0, 8), to: (20, 8)) - 20) < 0.3)
}

@Test func aRoofThroughAWallShowsWhereItCutsIn() {
    // A porch roof sloping up toward a wall and through its face: the line where it enters the wall shows.
    let roof = mesh([[p(2, -6, 8), p(18, -6, 8), p(18, 2, 12), p(2, 2, 12)]])
    let segments = draw([box(0, 0, 0, 20, 1, 12), roof], southElevation)
    #expect(segments.contains { $0.kind == .intersection })
    let cutIn: Double = drawn(segments, from: (2, 11), to: (18, 11))
    #expect(abs(cutIn - 16) < 0.3)
}

@Test func touchingFacesDoNotCut() {
    let first = box(0, 0, 0, 10, 1, 8), second = box(10, 0, 0, 20, 1, 8)
    let triangles = HiddenLines.triangles([first, second], view: southElevation)
    #expect(HiddenLines.intersections(triangles, view: southElevation).isEmpty)
}

@Test func crossingGablesMeetInValleys() {
    // A ridge running north meeting a lower ridge running east, seen from above.
    let segments = draw([gable(0, 0, 20, 40, eave: 10, ridge: 20, alongY: true),
                         gable(10, 10, 40, 24, eave: 10, ridge: 16, alongY: false)], fromAbove)
    #expect(segments.contains { $0.kind == .intersection }, "the valleys where the roofs meet")
    #expect(abs(drawn(segments, from: (10, 0), to: (10, 40)) - 40) < 0.5, "the tall ridge shows its full length")
    // The lower ridge shows from the tall roof's slope to its east end; under the tall roof it is hidden.
    let lowRidge = drawn(segments, from: (10, 17), to: (40, 17))
    #expect(lowRidge > 20 && lowRidge < 30, "lower ridge: \(lowRidge)")
}

@Test func aSectionDrawsOnlyWhatIsBeyondItsCut() {
    // Cut at 5' into a low box, with a tall box beyond it.
    let meshes = [box(0, 0, 0, 20, 10, 8), box(5, 20, 0, 15, 30, 16)]
    let segments = HiddenLines.segments(meshes, view: southElevation, cell: foot / 12, tolerance: foot / 12,
                                        near: 5 * foot)
    // The low box's face in front of the cut is gone, and the cut draws no lines of its own.
    #expect(drawn(segments, from: (0, 0), to: (20, 0)) < 0.3)
    #expect(drawn(segments, from: (0, 8), to: (20, 8)) < 0.3)
    #expect(drawn(segments, from: (0, 0), to: (0, 8)) < 0.3)
    // What is left of the low box still hides the tall one's foot; the tall one shows above it.
    #expect(abs(drawn(segments, from: (5, 16), to: (15, 16)) - 10) < 0.3)
    #expect(abs(drawn(segments, from: (5, 0), to: (5, 16)) - 8) < 0.3)
}
