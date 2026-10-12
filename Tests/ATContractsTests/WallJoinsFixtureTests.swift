import ATContracts
import Foundation
import Testing

/// The `wall-joins` fixture: the ways walls meet, side by side on one storey, for the geometry engine to join.
/// Built only through commands, so the fixture is always a model the commands accept.
///
/// From west to east, each in its own 8 m bay: an L corner, a T (a wall ending on another's side), an X (two
/// walls crossing), two walls meeting at 30°, and an arc. Walls are straight segments in the v1 model, so the arc
/// is a half circle of 3 m radius drawn as eight chords; a true arc wall needs a contract change.
enum WallJoins {
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", 3000 + n))!
    }

    static func mm(_ x: Int64, _ y: Int64) -> Point2 {
        Point2(x: .millimeters(x), y: .millimeters(y))
    }

    static let project = ProjectID(id(0))
    static let building = BuildingID(id(1))
    static let storey = StoreyID(id(2))
    static let thickness = Length.millimeters(200)
    static let height = Length.millimeters(2700)

    /// Each join's walls, as (start, end) pairs in millimetres, west to east.
    static let joins: [(name: String, walls: [(Point2, Point2)])] = [
        ("L", [(mm(0, 0), mm(4000, 0)), (mm(4000, 0), mm(4000, 3000))]),
        ("T", [(mm(8000, 0), mm(14000, 0)), (mm(11000, 0), mm(11000, 3000))]),
        ("X", [(mm(16000, 1500), mm(22000, 1500)), (mm(19000, -1500), mm(19000, 4500))]),
        // The second wall turns back 150° from the first's direction: the two meet at 30°.
        ("30° oblique", [(mm(24000, 0), mm(30000, 0)), (mm(30000, 0), mm(30000 - 5196, 3000))]),
        ("Arc", arc(center: mm(36000, 0), radius: 3000, chords: 8)),
    ]

    /// A half circle from east of `center` through north to west, as `chords` straight walls end to end; every
    /// vertex is on the circle to the nearest millimetre.
    static func arc(center: Point2, radius: Double, chords: Int) -> [(Point2, Point2)] {
        let cx = center.x.ticks / Length.ticksPerMillimeter, cy = center.y.ticks / Length.ticksPerMillimeter
        let points = (0...chords).map { step -> Point2 in
            let angle = Double(step) / Double(chords) * .pi
            return mm(cx + Int64((radius * cos(angle)).rounded()), cy + Int64((radius * sin(angle)).rounded()))
        }
        return (0..<chords).map { (points[$0], points[$0 + 1]) }
    }

    static func commands() -> [AnyCommand] {
        var list: [AnyCommand] = [
            SetProjectUnitsCommand(projectID: project, units: .metric).erased,
            AddBuildingCommand(buildingID: building, name: "Wall Joins").erased,
            AddStoreyCommand(storeyID: storey, buildingID: building, name: "Ground Floor",
                             elevation: .millimeters(0)).erased,
        ]
        var next = 10
        for join in joins {
            for (start, end) in join.walls {
                next += 1
                list.append(AddWallCommand(wallID: WallID(id(next)), storeyID: storey, start: start, end: end,
                                           thickness: thickness, height: height).erased)
            }
        }
        return list
    }

    static func document() throws -> ModelDocument {
        var document = ModelDocument(schemaVersion: 1, project: Project(id: project, name: "Wall Joins"),
                                     buildings: [], storeys: [], walls: [], openings: [], rooms: [])
        _ = try document.perform(batch: commands())
        return document
    }

    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/wall-joins.json")
}

@Test func wallJoinsFixtureMatchesItsCommands() throws {
    let original = try Data(contentsOf: WallJoins.fixtureURL)
    let fixture = try ModelDocument.decode(from: original)
    let built = try WallJoins.document()
    #expect(fixture == built)
    #expect(try fixture.encodeToJSONData() == original)
}

@Test func wallJoinsHasEachKindOfJoin() throws {
    let model = try ModelDocument.decode(from: Data(contentsOf: WallJoins.fixtureURL))
    // Two walls for each of the L, T, X, and 30° joins, and eight for the arc.
    #expect(model.walls.count == 16)
    #expect(model.storeys.count == 1 && model.project.displayUnits == .metric)
    #expect(model.walls.allSatisfy { $0.thickness == WallJoins.thickness && $0.height == WallJoins.height })
    let walls = model.walls
    func direction(_ wall: Wall) -> (Double, Double) {
        let dx = Double(wall.end.x.ticks - wall.start.x.ticks), dy = Double(wall.end.y.ticks - wall.start.y.ticks)
        let length = (dx * dx + dy * dy).squareRoot()
        return (dx / length, dy / length)
    }
    // L: the second wall starts where the first ends, square to it.
    #expect(walls[0].end == walls[1].start)
    let (first, second) = (direction(walls[0]), direction(walls[1]))
    let dot: Double = first.0 * second.0 + first.1 * second.1
    #expect(abs(dot) < 1e-9)
    // T: the vertical stem starts strictly inside the horizontal top, not at either end.
    let (stem, top) = (walls[3], walls[2])
    #expect(top.start.y == top.end.y)
    #expect(stem.start.y == top.start.y)
    #expect(stem.start.x > min(top.start.x, top.end.x) && stem.start.x < max(top.start.x, top.end.x))
    #expect(stem.start.x == stem.end.x && stem.start.y != stem.end.y)
    // X: the two segments have the same midpoint, so both cross at their centres.
    let firstMidX: Int64 = walls[4].start.x.ticks + walls[4].end.x.ticks
    let firstMidY: Int64 = walls[4].start.y.ticks + walls[4].end.y.ticks
    let secondMidX: Int64 = walls[5].start.x.ticks + walls[5].end.x.ticks
    let secondMidY: Int64 = walls[5].start.y.ticks + walls[5].end.y.ticks
    #expect(firstMidX == secondMidX)
    #expect(firstMidY == secondMidY)
    // 30°: the walls share an endpoint, and the second turns back 30° from the first.
    #expect(walls[6].end == walls[7].start)
    let (a, b) = (direction(walls[6]), direction(walls[7]))
    let cosine: Double = -(a.0 * b.0 + a.1 * b.1)
    let between: Double = acos(cosine) * 180 / .pi
    let error: Double = abs(between - 30)
    #expect(error < 0.01, "\(between)")
    // Arc: eight chords run continuously from east to west across the upper half of the 3 m circle.
    let arc = Array(walls[8...])
    #expect(zip(arc, arc.dropFirst()).allSatisfy { $0.end == $1.start })
    let center = WallJoins.mm(36000, 0)
    let vertices = arc.map(\.start) + [arc[arc.count - 1].end]
    #expect(vertices.first == WallJoins.mm(39000, 0))
    #expect(vertices.last == WallJoins.mm(33000, 0))
    #expect(vertices.dropFirst().dropLast().allSatisfy { $0.y > center.y })
    #expect(zip(vertices, vertices.dropFirst()).allSatisfy { $0.x > $1.x })
    for point in vertices {
        let dx = Double(point.x.ticks - center.x.ticks), dy = Double(point.y.ticks - center.y.ticks)
        let radius: Double = (dx * dx + dy * dy).squareRoot() / Double(Length.ticksPerMillimeter)
        let miss: Double = abs(radius - 3000)
        #expect(miss <= 1, "\(radius)")
    }
}
