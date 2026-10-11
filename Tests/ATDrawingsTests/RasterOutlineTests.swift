@testable import ATDrawings
import ATContracts
import Testing

private func ft(_ x: Double, _ y: Double) -> Point2 {
    paperPoint(Int64(x * Double(Length.feet(1).ticks)), Int64(y * Double(Length.feet(1).ticks)))
}

private func area(_ loop: [Point2]) -> Double {
    var twice = 0.0
    for index in loop.indices {
        let a = loop[index], b = loop[(index + 1) % loop.count]
        twice += Double(a.x.ticks) * Double(b.y.ticks) - Double(b.x.ticks) * Double(a.y.ticks)
    }
    return twice / 2 / Double(Length.feet(1).ticks * Length.feet(1).ticks)
}

@Test func overlappingRectanglesMakeOneOutlineWithTheirCorners() {
    // A 20' by 10' box and a 10' by 20' box sharing a corner region make an L.
    let loops = RasterOutline.union([[ft(0, 0), ft(20, 0), ft(20, 10), ft(0, 10)],
                                     [ft(0, 0), ft(10, 0), ft(10, 20), ft(0, 20)]], cell: Length.inches(3).ticks)
    #expect(loops.count == 1)
    let loop = loops[0]
    #expect(loop.count == 6)
    #expect(abs(area(loop) - 300) < 0.5, "counterclockwise, 20x10 + 10x10")
    let corners = Set(loop.map { [$0.x.ticks, $0.y.ticks] })
    #expect(corners.contains([ft(20, 10).x.ticks, ft(20, 10).y.ticks]))
    #expect(corners.contains([ft(10, 20).x.ticks, ft(10, 20).y.ticks]))
}

@Test func aRingOfWallsHasAnOuterOutlineAndAHole() {
    let walls = [[ft(0, 0), ft(30, 0), ft(30, 1), ft(0, 1)], [ft(29, 0), ft(30, 0), ft(30, 20), ft(29, 20)],
                 [ft(0, 19), ft(30, 19), ft(30, 20), ft(0, 20)], [ft(0, 0), ft(1, 0), ft(1, 20), ft(0, 20)]]
    let loops = RasterOutline.union(walls, cell: Length.inches(3).ticks)
    #expect(loops.count == 2)
    let areas = loops.map(area).sorted()
    #expect(abs(areas[0] + 28 * 18) < 0.5, "the courtyard runs clockwise")
    #expect(abs(areas[1] - 30 * 20) < 0.5)
}

@Test func anAngledShapeComesBackAsItsLines() {
    let triangle = [ft(0, 0), ft(24, 0), ft(0, 18)]
    let loops = RasterOutline.union([triangle], cell: Length.inches(3).ticks)
    #expect(loops.count == 1)
    #expect(loops[0].count <= 5, "the staircase along the hypotenuse is simplified: \(loops[0].count) corners")
    // How close it must come: the traced staircase lies within one 3" cell of each true edge (a cell is filled
    // when its middle is inside), and simplifying moves the outline at most a cell and a half further. So every
    // corner is within two and a half cells, 7 1/2", of the triangle's sides.
    let sides = [(triangle[0], triangle[1]), (triangle[1], triangle[2]), (triangle[2], triangle[0])]
    let reach: Double = 2.5 * Double(Length.inches(3).ticks)
    for corner in loops[0] {
        let nearest: Double = sides.map { distance(corner, $0.0, $0.1) }.min() ?? .infinity
        #expect(nearest <= reach, "a corner \(nearest / Double(Length.inches(1).ticks))\" off the triangle")
    }
    // The staircase sits half a cell inside or outside each edge on average, so the area is within the perimeter
    // times half a cell: 72' x 1 1/2" = 9 square feet.
    let error: Double = abs(area(loops[0]) - 216)
    #expect(error <= 9)
}

@Test func theSameShapesAlwaysComeBackAsTheSameLoops() {
    // A dictionary's order changes from run to run; the loops must not. Each starts at its lowest, leftmost
    // corner, so tracing never depends on which edge happened to come first.
    let shapes = [[ft(0, 0), ft(24, 0), ft(0, 18)], [ft(30, 2), ft(40, 2), ft(40, 9), ft(30, 9)]]
    let loops = RasterOutline.union(shapes, cell: Length.inches(3).ticks)
    #expect(loops.count == 2)
    for loop in loops {
        let lowest = loop.min { a, b in (a.y.ticks, a.x.ticks) < (b.y.ticks, b.x.ticks) }
        #expect(loop.first == lowest)
    }
    for _ in 0..<5 {
        let again = RasterOutline.union(shapes, cell: Length.inches(3).ticks)
        #expect(again == loops)
    }
}

/// The distance from a point to a segment, in ticks.
private func distance(_ p: Point2, _ a: Point2, _ b: Point2) -> Double {
    let (px, py) = (Double(p.x.ticks), Double(p.y.ticks))
    let (ax, ay) = (Double(a.x.ticks), Double(a.y.ticks)), (bx, by) = (Double(b.x.ticks), Double(b.y.ticks))
    let (dx, dy) = (bx - ax, by - ay)
    let t: Double = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    let (cx, cy) = (ax + dx * t, ay + dy * t)
    return ((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot()
}
