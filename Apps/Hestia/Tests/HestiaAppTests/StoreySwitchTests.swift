import ATContracts
import Foundation
import Testing
@testable import HestiaApp

/// A plan point in feet.
private func feet(_ x: Double, _ y: Double) -> Point2 {
    PlanOverlay.point(x, y)
}

/// A blank model with a 30' by 20' room drawn on its ground floor, walls 9'-0" tall and 8" thick.
private func groundFloorDrawn() throws -> EditSession {
    var session = EditSession(model: try HestiaModel.blank())
    try session.addRectangleRoom(from: feet(0, 0), to: feet(30, 20), named: "Living")
    let commands = session.model.document.walls.map { wall in
        SetWallHeightCommand(wallID: wall.id, height: .feet(9)).erased
    } + session.model.document.walls.map { wall in
        SetWallThicknessCommand(wallID: wall.id, thickness: .inches(8)).erased
    }
    try session.perform(batch: commands)
    return session
}

/// The cottage fixture, which keeps its own sheets, in a new session.
private func cottage() throws -> EditSession {
    let repo = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let data = try Data(contentsOf: repo.appendingPathComponent("fixtures/rect-cottage.json"))
    return EditSession(model: try HestiaModel(document: try JSONDecoder().decode(ModelDocument.self, from: data)))
}

/// Whether the model-space plan draws a wall where it is: the wall's own outline spans its two ends, give or
/// take its thickness.
private func planDraws(_ model: HestiaModel, _ wall: Wall) -> Bool {
    let own = model.modelPlan().filter { $0.style.layer == "A-WALL" && $0.elementID == wall.id.rawValue }
    guard let bounds = DisplayList(items: own).bounds else { return false }
    let slack = wall.thickness.ticks
    func near(_ a: Length, _ b: Length) -> Bool { abs(a.ticks - b.ticks) <= slack }
    return near(bounds.min.x, min(wall.start.x, wall.end.x)) && near(bounds.max.x, max(wall.start.x, wall.end.x))
        && near(bounds.min.y, min(wall.start.y, wall.end.y)) && near(bounds.max.y, max(wall.start.y, wall.end.y))
}

@Suite("Storeys")
struct StoreySwitchTests {
    @Test("A storey added on top stands as high as the walls under it, and the plan shows it, empty")
    func addStoreyAbove() throws {
        var session = try groundFloorDrawn()
        let ground = try #require(session.model.planStorey)
        try session.addStoreyAbove()
        let model = session.model
        #expect(model.document.storeys.count == 2)
        let upper = try #require(model.document.storeys.first { $0.id == model.planStorey })
        #expect(upper.name == "Second Floor")
        #expect(upper.elevation == .feet(9))
        #expect(model.storeyBelow == ground)
        #expect(model.plan.isEmpty)
        #expect(model.planTransform != nil, "an empty storey can still be drawn on")
        #expect(model.planFileSuffix == "-second-floor-plan.dxf")
        // One Undo takes the storey back, and the plan returns to the ground floor.
        try session.undo()
        #expect(session.model.document.storeys.count == 1)
        #expect(session.model.planStorey == ground)
    }

    @Test("A storey on a model with no walls goes up the default wall height")
    func storeyOverAnEmptyFloor() throws {
        let model = try HestiaModel.blank()
        let command = try model.storeyAboveCommand()
        #expect(command.elevation == HestiaModel.defaultWallHeight)
        #expect(command.name == "Second Floor")
    }

    @Test("The floor below shows faint under an upper plan, and walls drawn there stand on it")
    func drawOnTheFloorAbove() throws {
        var session = try groundFloorDrawn()
        let groundWalls = session.model.document.walls
        try session.addStoreyAbove()
        let upper = try #require(session.model.planStorey)
        // The ground floor's four walls, filled and outlined, under the empty upper plan.
        let ghost = PlanOverlay(document: session.model.document, storey: upper).under
        let filledAndOutlined = 2 * groundWalls.count
        #expect(ghost.count == filledAndOutlined)
        #expect(PlanOverlay(document: session.model.document, storey: session.model.storeyBelow).under.isEmpty)
        // A wall clicked near the corner below lands on it, and takes the size of the walls below.
        try session.addWall(from: feet(0.2, 0.1), to: feet(29.9, 0.2))
        let wall = try #require(session.model.document.walls.first { $0.storeyID == upper })
        #expect(wall.start == feet(0, 0) && wall.end == feet(30, 0))
        #expect(wall.height == .feet(9) && wall.thickness == .inches(8))
        // Editing keeps the plan on the storey being drawn, now with its wall.
        #expect(session.model.planStorey == upper)
        #expect(session.model.plan.contains { $0.elementID == wall.id.rawValue })
        #expect(session.model.document.walls.filter { $0.storeyID == upper }.count == 1)
    }

    @Test("Switching storeys is not an edit, and steps up and down in order")
    func switchStoreys() throws {
        var session = try groundFloorDrawn()
        let ground = try #require(session.model.planStorey)
        try session.addStoreyAbove()
        let second = try #require(session.model.planStorey)
        try session.addStoreyAbove()
        let third = try #require(session.model.planStorey)
        #expect(session.model.document.storeys.first { $0.id == third }?.name == "Third Floor")
        #expect(session.model.storey(next: true) == nil)
        #expect(session.model.storey(next: false) == second)
        let undoable = session.undoStack.count
        try session.show(storey: ground)
        #expect(session.model.planStorey == ground)
        #expect(session.undoStack.count == undoable)
        #expect(session.model.storey(next: false) == nil)
        #expect(session.model.storey(next: true) == second)
        #expect(session.model.storeysUpward.map(\.id) == [ground, second, third])
        #expect(session.model.planFileSuffix == "-ground-floor-plan.dxf")
    }

    @Test("Each storey's plan comes from its own plan sheet")
    func eachStoreyHasItsPlan() throws {
        var session = try groundFloorDrawn()
        try session.addStoreyAbove()
        try session.addRectangleRoom(from: feet(0, 0), to: feet(15, 20), named: "Bedroom")
        let upper = try #require(session.model.planStorey)
        let upperIDs = Set(session.model.document.walls.filter { $0.storeyID == upper }.map(\.id.rawValue))
        let shown = Set(session.model.plan.filter { $0.style.layer == "A-WALL" }.compactMap(\.elementID))
        #expect(!shown.isEmpty && shown.isSubset(of: upperIDs))
        #expect(try !session.model.dxf().isEmpty)
    }

    @Test("In a project that keeps its own sheets, a storey added on top joins the set and draws where it is drawn")
    func addStoreyToStoredSheets() throws {
        var session = try cottage()
        let before = session.model.document.sheets
        #expect(!before.isEmpty)
        try session.addStoreyAbove()
        let upper = try #require(session.model.planStorey)
        let sheets = session.model.document.sheets
        let oneMore = before.count + 1
        #expect(sheets.count == oneMore)
        let added = try #require(sheets.first { $0.views == [.floorPlan(storeyID: upper)] })
        #expect(added.number == "A-102" && added.title == "Second Floor Plan")
        #expect(sheets.firstIndex(of: added) == 2, "right after the ground floor plan")
        #expect(added.paper == before[1].paper && added.scale == before[1].scale)
        #expect(session.model.planTransform != nil)

        try session.addWall(from: feet(6, 6), to: feet(16, 6))
        let wall = try #require(session.model.document.walls.first { $0.storeyID == upper })
        #expect(!session.model.plan.isEmpty, "the new floor's walls show on its plan")
        #expect(planDraws(session.model, wall))
        #expect(try !session.model.dxf().isEmpty)

        try session.undo()
        try session.undo()
        #expect(session.model.document.sheets == before)
        #expect(session.model.document.storeys.count == 1)

        // Redo restores the storey and its plan sheet as the active plan, then restores the wall on that plan.
        try session.redo()
        #expect(session.model.planStorey == upper)
        #expect(session.model.document.sheets.contains { $0.views == [.floorPlan(storeyID: upper)] })
        try session.redo()
        #expect(session.model.planStorey == upper)
        #expect(planDraws(session.model, wall))
        #expect(try !session.model.dxf().isEmpty)
    }

    @Test("A storey that none of a project's own sheets plans is drawn on a stand-in plan sheet")
    func standInPlanSheet() throws {
        var session = try cottage()
        let groundPlan = session.model.plan
        let building = try #require(session.model.document.storeys.first).buildingID
        let loft = StoreyID(UUID())
        try session.perform(AddStoreyCommand(storeyID: loft, buildingID: building, name: "Loft",
                                             elevation: .feet(9)).erased)
        try session.show(storey: loft)
        #expect(session.model.planTransform != nil)
        try session.addWall(from: feet(6, 6), to: feet(16, 6))
        let wall = try #require(session.model.document.walls.first { $0.storeyID == loft })
        #expect(!session.model.plan.isEmpty)
        #expect(planDraws(session.model, wall))
        #expect(!session.model.document.sheets.contains { $0.views.contains(.floorPlan(storeyID: loft)) },
                "the stand-in is not saved")
        try session.show(storey: try #require(session.model.storey(next: false)))
        #expect(session.model.plan == groundPlan, "the ground floor still draws from its own sheet")
    }

    @Test("A project drawn on the default set gets no stored sheet for a storey added on top")
    func defaultSetStaysDefault() throws {
        var session = try groundFloorDrawn()
        try session.addStoreyAbove()
        #expect(session.model.document.sheets.isEmpty)
    }
}
