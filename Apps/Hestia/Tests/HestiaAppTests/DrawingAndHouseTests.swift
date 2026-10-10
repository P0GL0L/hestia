import ATContracts
import Foundation
import Testing
@testable import HestiaApp

/// A plan point in feet.
private func feet(_ x: Double, _ y: Double) -> Point2 {
    PlanOverlay.point(x, y)
}

private func metricSession() throws -> EditSession {
    var session = EditSession(model: try HestiaModel.blank())
    let project = session.model.document.project.id
    try session.perform(SetProjectUnitsCommand(projectID: project, units: .metric).erased)
    return session
}

@Suite("Drawing tools")
struct DrawingToolTests {
    @Test("A wall drawn close to an axis stays the diagonal it was drawn")
    func nearAxisWallStaysDiagonal() throws {
        var session = EditSession(model: try HestiaModel.blank())
        let end = try session.addWall(from: feet(0, 0), to: feet(20, 0.5))
        let wall = try #require(session.model.document.walls.first)
        #expect(end == feet(20, 0.5))
        #expect(wall.start.y != wall.end.y)
    }

    @Test("A typed imperial wall keeps its length off the inch grid")
    func typedImperialWallIsExact() throws {
        var session = EditSession(model: try HestiaModel.blank())
        let length = try #require(LengthEntry.parse("12' 3 5/8\"", metric: false))
        let end = PlanGeometry.reach(from: feet(0, 0), toward: feet(30, 0), length: length)
        try session.addWall(from: feet(0, 0), to: end, exact: true)
        let wall = try #require(session.model.document.walls.first)
        #expect(PlanGeometry.distance(wall.start, wall.end) == length)
        #expect(length == Length(ticks: Length.feet(12, inchCount: 3).ticks + 40 * Length.ticksPerSixtyFourthInch))
    }

    @Test("A typed metric wall keeps its length off the 10 mm grid")
    func typedMetricWallIsExact() throws {
        var session = try metricSession()
        let length = try #require(LengthEntry.parse("3607.5 mm", metric: true))
        #expect(length == Length(ticks: 36_075 * Length.ticksPerMillimeter / 10))
        let end = PlanGeometry.reach(from: feet(0, 0), toward: feet(0, 30), length: length)
        try session.addWall(from: feet(0, 0), to: end, exact: true)
        let wall = try #require(session.model.document.walls.first)
        #expect(PlanGeometry.distance(wall.start, wall.end) == length)
    }

    @Test("A typed room keeps its size, imperial and metric")
    func typedRoomIsExact() throws {
        var imperial = EditSession(model: try HestiaModel.blank())
        let size = try #require(LengthEntry.pair("12'3 5/8\" x 10'1/2\"", metric: false))
        let corner = PlanGeometry.corner(from: feet(0, 0), toward: feet(30, 30), width: size.0, depth: size.1)
        try imperial.addRectangleRoom(from: feet(0, 0), to: corner, named: "Den", exact: true)
        let xs = imperial.model.document.walls.flatMap { [$0.start.x, $0.end.x] }
        let ys = imperial.model.document.walls.flatMap { [$0.start.y, $0.end.y] }
        #expect(xs.max() == size.0 && ys.max() == size.1)
        #expect(imperial.model.document.rooms.count == 1)

        var metric = try metricSession()
        let metricSize = try #require(LengthEntry.pair("3.605 x 2.4075", metric: true))
        let metricCorner = PlanGeometry.corner(from: feet(0, 0), toward: feet(30, 30), width: metricSize.0,
                                               depth: metricSize.1)
        try metric.addRectangleRoom(from: feet(0, 0), to: metricCorner, named: "Den", exact: true)
        #expect(metric.model.document.walls.flatMap { [$0.start.x, $0.end.x] }.max() == metricSize.0)
        #expect(metric.model.document.walls.flatMap { [$0.start.y, $0.end.y] }.max() == metricSize.1)
    }

    @Test("A typed site area keeps its size")
    func typedSiteIsExact() throws {
        var session = EditSession(model: try HestiaModel.blank())
        let size = try #require(LengthEntry.pair("40'7 1/4\" x 12'", metric: false))
        let corner = PlanGeometry.corner(from: feet(0, 0), toward: feet(-50, 50), width: size.0, depth: size.1)
        try session.addSitePatch(.driveway, from: feet(0, 0), to: corner, exact: true)
        let patch = try #require(session.model.document.terrainPatches.first)
        let xs = patch.boundary.map(\.x), ys = patch.boundary.map(\.y)
        #expect(xs.min() == Length(ticks: -size.0.ticks) && ys.max() == size.1)
    }

    @Test("A patch's survey points move with it, through undo and redo")
    func surveyPointsMoveWithPatch() throws {
        var session = EditSession(model: try HestiaModel.blank())
        let id = TerrainPatchID(UUID())
        let point = Point3(x: .feet(5), y: .feet(5), z: .feet(101))
        try session.perform(AddTerrainPatchCommand(terrainPatchID: id, name: "Lawn",
                                                   boundary: PlanGeometry.rectangle(feet(0, 0), feet(10, 10)),
                                                   surveyPoints: [point]).erased)
        try session.movePatch(id, dx: Length.feet(3).ticks, dy: -Length.feet(2).ticks)
        var patch = try #require(session.model.document.terrainPatches.first)
        #expect(patch.boundary[0] == feet(3, -2))
        #expect(patch.surveyPoints == [Point3(x: .feet(8), y: .feet(3), z: .feet(101))])
        try session.undo()
        patch = try #require(session.model.document.terrainPatches.first)
        #expect(patch.boundary[0] == feet(0, 0) && patch.surveyPoints == [point])
        try session.redo()
        patch = try #require(session.model.document.terrainPatches.first)
        #expect(patch.surveyPoints == [Point3(x: .feet(8), y: .feet(3), z: .feet(101))])
    }

    @Test("A new lot replaces only patches named Lot or Lot and a number")
    func lotusGardenSurvivesLot() throws {
        var session = EditSession(model: try HestiaModel.blank())
        for name in ["Lotus Garden", "Lot 2", "Lot"] {
            try session.perform(AddTerrainPatchCommand(terrainPatchID: TerrainPatchID(UUID()), name: name,
                                                       boundary: PlanGeometry.rectangle(feet(0, 0), feet(9, 9)),
                                                       surveyPoints: []).erased)
        }
        try session.addSitePatch(.lot, from: feet(-20, -20), to: feet(60, 60))
        let names = session.model.document.terrainPatches.map(\.name).sorted()
        #expect(names == ["Lot", "Lotus Garden"])
        #expect(SiteKind(patchName: "Lotus Garden") == .lawn)
        #expect(SiteKind(patchName: "Driveway 2") == .driveway)
        #expect(SiteKind.exact("Driveway east") == nil)
    }
}

@Suite("House in 3D")
struct HouseSceneTests {
    @Test("Doors and cased openings let the walker through; windows do not")
    func walkBarriers() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addWall(from: feet(0, 0), to: feet(30, 0))
        let wall = try #require(session.model.document.walls.first)
        try session.perform(session.model.doorCommand(on: wall.id, at: feet(5, 0)).erased)
        try session.perform(session.model.casedOpeningCommand(on: wall.id, at: feet(15, 0)).erased)
        try session.perform(session.model.windowCommand(on: wall.id, at: feet(25, 0)).erased)
        let barriers = WalkBarriers(document: session.model.document, storey: session.model.groundStorey)
        func crosses(_ x: Double) -> Bool {
            var walker = Walker(x: x, y: -4, floor: 0)
            for _ in 0..<40 { walker.step(WalkInput(forward: 1), seconds: 0.05, barriers: barriers) }
            return walker.y > 0
        }
        let openings = session.model.document.openings
        let middle = { (kind: OpeningKind) -> Double in
            let opening = openings.first { $0.kind == kind }!
            return HouseScene.feet(opening.offsetAlongWall) + HouseScene.feet(opening.width) / 2
        }
        #expect(crosses(middle(.singleDoor)))
        #expect(crosses(middle(.casedOpening)))
        #expect(!crosses(middle(.window)))
        #expect(!crosses(10))
    }

    @Test("Model space turns upright: plan north is -z and height is +y")
    func uprightConversion() throws {
        #expect(ScenePoint.plan(3, 4, 5) == ScenePoint(3, 5, -4))
        var session = EditSession(model: try HestiaModel.blank())
        try session.addRectangleRoom(from: feet(0, 0), to: feet(12, 10), named: "Room")
        let walls = try #require(session.model.house.solids.first { $0.look == .wall })
        let heights = walls.positions.map(\.y)
        #expect(abs((heights.max() ?? 0) - 8) < 0.01)
        #expect(abs(heights.min() ?? 1) < 0.01)
        let depths = walls.positions.map(\.z)
        #expect((depths.min() ?? 0) < -9 && (depths.max() ?? 0) > -1)
        // The view turns a plan rotation the same way: counterclockwise in the plan is about +y in the view.
        let floor = try #require(session.model.house.solids.first { $0.look == .woodFloor })
        let up = floor.normals.first
        #expect(up == ScenePoint(0, 1, 0))
    }
}
