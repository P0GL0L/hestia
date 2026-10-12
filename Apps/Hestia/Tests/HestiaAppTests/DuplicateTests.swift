import ATContracts
import Foundation
import Testing
@testable import HestiaApp

private func feet(_ x: Double, _ y: Double) -> Point2 {
    PlanOverlay.point(x, y)
}

private func millimeters(_ x: Int64, _ y: Int64) -> Point2 {
    Point2(x: .millimeters(x), y: .millimeters(y))
}

@Suite("Duplicate and turn")
struct DuplicateTests {
    private func drawn() throws -> EditSession {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addRectangleRoom(from: feet(0, 0), to: feet(20, 15), named: "Living")
        let south = try #require(session.model.document.walls.first { $0.start.y == .feet(0) && $0.end.y == .feet(0) })
        try session.perform(AddOpeningCommand(openingID: OpeningID(UUID()), wallID: south.id,
                                              offsetAlongWall: .feet(3), width: .feet(3), height: .feet(4),
                                              sillHeight: .feet(3), kind: .window).erased)
        try session.perform(session.model.stairCommand(from: feet(14, 3), toward: feet(14, 12)).erased)
        let sofa = try #require(Furniture.item(CatalogItemID(rawValue: "hestia.sofa")))
        try session.place(sofa, at: feet(6, 8), degrees: 0)
        return session
    }

    @Test("An item, a wall, and a stair copy two feet right and down, and the copy is what is selected")
    func copies() throws {
        var session = try drawn()
        let placement = try #require(session.model.document.placements.first)
        guard case let .placement(copy)? = try session.duplicate(.placement(placement.id)) else {
            Issue.record("no placement copy")
            return
        }
        #expect(session.model.document.placements.first { $0.id == copy }?.position == feet(8, 6))
        let wall = try #require(session.model.document.walls.first { $0.start.y == .feet(15) && $0.end.y == .feet(15) })
        guard case let .wall(wallCopy)? = try session.duplicate(.wall(wall.id)),
              let copied = session.model.document.walls.first(where: { $0.id == wallCopy }) else {
            Issue.record("no wall copy")
            return
        }
        #expect(copied.thickness == wall.thickness && copied.height == wall.height)
        #expect(copied.start.y == .feet(13))
        let stair = try #require(session.model.document.stairs.first)
        _ = try session.duplicate(.stair(stair.id))
        #expect(session.model.document.stairs.count == 2)
        // Each copy is one Undo.
        try session.undo()
        #expect(session.model.document.stairs.count == 1)
    }

    @Test("A window copies further along its wall, until the wall has no room; a room is refused")
    func openingsAndRooms() throws {
        var session = try drawn()
        let window = try #require(session.model.document.openings.first)
        guard case let .opening(copy)? = try session.duplicate(.opening(window.id)) else {
            Issue.record("no window copy")
            return
        }
        let copiedWindow = try #require(session.model.document.openings.first { $0.id == copy })
        #expect(copiedWindow.offsetAlongWall == .feet(7))
        #expect(copiedWindow.wallID == window.wallID && copiedWindow.kind == .window && copiedWindow.swing == nil)
        #expect(copiedWindow.width == .feet(3) && copiedWindow.height == .feet(4))
        #expect(copiedWindow.sillHeight == .feet(3))
        var last = copy
        var refused = false
        for _ in 0..<6 {
            do {
                guard case let .opening(next)? = try session.duplicate(.opening(last)) else { break }
                last = next
            } catch is HestiaModel.LoadError {
                refused = true
                break
            }
        }
        #expect(refused, "a 20' wall runs out of room for 3' windows four feet apart")
        let room = try #require(session.model.document.rooms.first)
        #expect(throws: HestiaModel.LoadError.self) { try session.duplicate(.room(room.id)) }
    }

    @Test("R turns a stair a quarter turn about the middle of its run; walls don't turn")
    func turns() throws {
        var session = try drawn()
        let stair = try #require(session.model.document.stairs.first)
        try session.turn(.stair(stair.id))
        let turned = try #require(session.model.document.stairs.first)
        let middle = PlanGeometry.distance(turned.runStart, turned.runEnd)
        #expect(middle == PlanGeometry.distance(stair.runStart, stair.runEnd))
        #expect(turned.runStart.y == turned.runEnd.y, "a north-running stair now runs east-west")
        let wall = try #require(session.model.document.walls.first)
        #expect(throws: HestiaModel.LoadError.self) { try session.turn(.wall(wall.id)) }
    }
}

/// The document as saved, byte for byte.
private func bytes(_ document: ModelDocument) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(document)
}

/// One of each copyable element at fixed places: a sofa at (6', 8'); an oblique wall from (30', 0) to (42', 5')
/// holding a 3' cased opening 3' from its start; a stair running north from (50', 0) to (50', 10'); a lawn from
/// (60', 0) to (70', 10') with a survey point at (61', 1', 10'); and a 20' by 15' room with a 3' door, hinged
/// at its far edge and swung left, 3' along its south wall.
private struct Placed {
    var session: EditSession
    var sofa: PlacementID, wall: WallID, cased: OpeningID, door: OpeningID, stair: StairID, lawn: TerrainPatchID
}

private func placed() throws -> Placed {
    var session = EditSession(model: try HestiaModel.blank())
    let storey = try #require(session.model.planStorey)
    let sofa = PlacementID(UUID()), cased = OpeningID(UUID()), door = OpeningID(UUID())
    let stair = StairID(UUID()), lawn = TerrainPatchID(UUID())
    try session.perform(AddPlacementCommand(placementID: sofa, storeyID: storey,
                                            catalogItemID: CatalogItemID(rawValue: "hestia.sofa"),
                                            position: feet(6, 8)).erased)
    try session.addWall(from: feet(30, 0), to: feet(42, 5))
    let wall = try #require(session.model.document.walls.first)
    try session.addRectangleRoom(from: feet(0, 0), to: feet(20, 15), named: "Living")
    let south = try #require(session.model.document.walls.first {
        $0.id != wall.id && $0.start.y == .feet(0) && $0.end.y == .feet(0)
    })
    try session.perform(batch: [
        AddOpeningCommand(openingID: cased, wallID: wall.id, offsetAlongWall: .feet(3), width: .feet(3),
                          height: .feet(7), sillHeight: .feet(0), kind: .casedOpening).erased,
        AddOpeningCommand(openingID: door, wallID: south.id, offsetAlongWall: .feet(3), width: .feet(3),
                          height: .feet(7), sillHeight: .feet(0), kind: .singleDoor,
                          swing: DoorSwing(hinge: .nearEnd, opensToward: .left)).erased,
        AddStairCommand(stairID: stair, storeyID: storey, runStart: feet(50, 0), runEnd: feet(50, 10),
                        width: .feet(3), riserCount: 14, riserHeight: .inches(7)).erased,
        AddTerrainPatchCommand(terrainPatchID: lawn, name: "Lawn",
                               boundary: PlanGeometry.rectangle(feet(60, 0), feet(70, 10)),
                               surveyPoints: [Point3(x: .feet(61), y: .feet(1), z: .feet(10))]).erased,
    ])
    return Placed(session: session, sofa: sofa, wall: wall.id, cased: cased, door: door, stair: stair, lawn: lawn)
}

@Suite("Duplicate and turn, exactly")
struct DuplicateExactTests {
    @Test("Each copy lands exactly 2' right and 2' down, is selected, and is one step that Undo and Redo repeat")
    func copiesLandExactly() throws {
        let fixture = try placed()
        let (sofa, wall, stair, lawn) = (fixture.sofa, fixture.wall, fixture.stair, fixture.lawn)
        var session = fixture.session
        /// Where each copy lands, worked out by hand: everything 2' east and 2' south of its original.
        func check(_ session: EditSession, _ copy: PlanSelection) throws {
            let document = session.model.document
            switch copy {
            case let .placement(id):
                let original = try #require(document.placements.first { $0.id == sofa })
                let moved = try #require(document.placements.first { $0.id == id })
                #expect(id != sofa && moved.position == feet(8, 6))
                #expect(moved.storeyID == original.storeyID && moved.catalogItemID == original.catalogItemID)
                #expect(moved.rotation == original.rotation && moved.elevation == original.elevation)
                #expect(moved.layerID == original.layerID)
            case let .wall(id):
                let original = try #require(document.walls.first { $0.id == wall })
                let moved = try #require(document.walls.first { $0.id == id })
                #expect(id != wall && moved.start == feet(32, -2) && moved.end == feet(44, 3))
                #expect(moved.storeyID == original.storeyID && moved.thickness == original.thickness)
                #expect(moved.height == original.height && moved.layers == original.layers)
                #expect(moved.phase == original.phase)
                #expect(!document.openings.contains { $0.wallID == id }, "a wall copies bare")
            case let .stair(id):
                let original = try #require(document.stairs.first { $0.id == stair })
                let moved = try #require(document.stairs.first { $0.id == id })
                #expect(id != stair && moved.runStart == feet(52, -2) && moved.runEnd == feet(52, 8))
                #expect(moved.storeyID == original.storeyID && moved.kind == original.kind)
                #expect(moved.width == .feet(3) && moved.riserCount == 14 && moved.riserHeight == .inches(7))
            case let .patch(id):
                let moved = try #require(document.terrainPatches.first { $0.id == id })
                #expect(id != lawn)
                #expect(moved.boundary == [feet(62, -2), feet(72, -2), feet(72, 8), feet(62, 8)])
                #expect(moved.surveyPoints == [Point3(x: .feet(63), y: .feet(-1), z: .feet(10))])
                #expect(moved.name == "Lawn")
            case .opening, .room:
                Issue.record("unexpected copy \(copy)")
            }
        }
        let originals: [PlanSelection] = [.placement(sofa), .wall(wall), .stair(stair), .patch(lawn)]
        for selection in originals {
            let before = try bytes(session.model.document)
            let steps = session.undoStack.count
            let copy = try #require(try session.duplicate(selection))
            #expect(copy != selection)
            try check(session, copy)
            let after = try bytes(session.model.document)
            let added: Int = steps + 1
            #expect(session.undoStack.count == added)
            try session.undo()
            #expect(try bytes(session.model.document) == before)
            try session.redo()
            #expect(try bytes(session.model.document) == after, "Redo brings back the same copy")
        }
    }

    @Test("A metric project copies 600 mm right and 600 mm down")
    func metricOffset() throws {
        var document = try HestiaModel.blank().document
        document.project.displayUnits = .metric
        var session = EditSession(model: try HestiaModel(document: document))
        let original = StairID(UUID())
        try session.perform(AddStairCommand(stairID: original, storeyID: try #require(session.model.planStorey),
                                            runStart: millimeters(1_000, 2_000),
                                            runEnd: millimeters(1_000, 5_000), width: .millimeters(900),
                                            riserCount: 14, riserHeight: .millimeters(180)).erased)
        let before = try bytes(session.model.document)
        let steps = session.undoStack.count
        guard case let .stair(copy)? = try session.duplicate(.stair(original)) else {
            Issue.record("no metric stair copy")
            return
        }
        let moved = try #require(session.model.document.stairs.first { $0.id == copy })
        #expect(copy != original)
        #expect(moved.runStart == millimeters(1_600, 1_400))
        #expect(moved.runEnd == millimeters(1_600, 4_400))
        #expect(session.undoStack.count == steps + 1)
        try session.undo()
        #expect(try bytes(session.model.document) == before)
    }

    @Test("Every opening kind copies 1' past itself; end and overlap refusals preserve bytes and history")
    @MainActor
    func openingsCopyAlongTheirWalls() throws {
        let fixture = try placed()
        var session = fixture.session
        let (wall, cased, door) = (fixture.wall, fixture.cased, fixture.door)
        var casedCopy: OpeningID?
        for id in [cased, door] {
            let original = try #require(session.model.document.openings.first { $0.id == id })
            let before = try bytes(session.model.document)
            let steps = session.undoStack.count
            let result = ContentView.commitDuplicate(&session, selection: .opening(id))
            #expect(result.status == "Duplicated. Drag the copy into place; Undo removes it.")
            guard case let .opening(copyID)? = result.selection else {
                Issue.record("the opening copy is not selected")
                return
            }
            let copy = try #require(session.model.document.openings.first { $0.id == copyID })
            #expect(copyID != id && copy.offsetAlongWall == .feet(7))
            #expect(copy.wallID == original.wallID && copy.kind == original.kind && copy.swing == original.swing)
            #expect(copy.width == original.width && copy.height == original.height)
            #expect(copy.sillHeight == original.sillHeight)
            let after = try bytes(session.model.document)
            #expect(session.undoStack.count == steps + 1)
            try session.undo()
            #expect(try bytes(session.model.document) == before)
            try session.redo()
            #expect(try bytes(session.model.document) == after)
            #expect(session.model.document.openings.contains { $0.id == copyID })
            if id == cased { casedCopy = copyID }
        }

        // The cased opening's copy runs 7'-0" to 10'-0" on a 13'-0" wall; one more would end at 14'-0".
        let full = try #require(casedCopy)
        let saved = try bytes(session.model.document)
        let steps = session.undoStack.count
        let refused = ContentView.commitDuplicate(&session, selection: .opening(full))
        #expect(refused.selection == .opening(full))
        #expect(refused.status == "There is no room for another one further along that wall.")
        #expect(try bytes(session.model.document) == saved)
        #expect(session.undoStack.count == steps)
        #expect(session.model.document.openings.first { $0.id == full }?.wallID == wall)

        // A separate opening occupying the hand-worked 7'-0" to 10'-0" destination is refused as an overlap.
        var blocked = EditSession(model: try HestiaModel.blank())
        try blocked.addWall(from: feet(0, 0), to: feet(20, 0))
        let host = try #require(blocked.model.document.walls.first)
        let source = OpeningID(UUID()), obstacle = OpeningID(UUID())
        try blocked.perform(batch: [
            AddOpeningCommand(openingID: source, wallID: host.id, offsetAlongWall: .feet(3), width: .feet(3),
                              height: .feet(4), sillHeight: .feet(3), kind: .window).erased,
            AddOpeningCommand(openingID: obstacle, wallID: host.id, offsetAlongWall: .feet(7), width: .feet(3),
                              height: .feet(7), sillHeight: .feet(0), kind: .casedOpening).erased,
        ])
        let blockedBytes = try bytes(blocked.model.document)
        let blockedSteps = blocked.undoStack.count
        let overlap = ContentView.commitDuplicate(&blocked, selection: .opening(source))
        #expect(overlap.selection == .opening(source))
        #expect(overlap.status == "There is no room for another one further along that wall.")
        #expect(try bytes(blocked.model.document) == blockedBytes)
        #expect(blocked.undoStack.count == blockedSteps)
    }

    @Test("A room copy is refused, changing nothing; a copy stays on the storey it was made on")
    @MainActor
    func roomRefusedAndStoreyKept() throws {
        var session = try placed().session
        let room = try #require(session.model.document.rooms.first)
        let saved = try bytes(session.model.document)
        let steps = session.undoStack.count
        #expect(throws: HestiaModel.LoadError.self) { try session.duplicate(.room(room.id)) }
        #expect(try bytes(session.model.document) == saved)
        #expect(session.undoStack.count == steps)

        // Coincident walls prove the active-floor hit test supplies the wall that Duplicate copies.
        let ground = try #require(session.model.planStorey)
        try session.addWall(from: feet(0, 30), to: feet(10, 30))
        let lower = try #require(session.model.document.walls.first {
            $0.storeyID == ground && $0.start == feet(0, 30)
        })
        try session.addStoreyAbove()
        let upper = try #require(session.model.planStorey)
        try session.addWall(from: feet(0, 30), to: feet(10, 30))
        let upstairs = try #require(session.model.document.walls.first {
            $0.storeyID == upper && $0.start == feet(0, 30)
        })
        let picked = try #require(session.model.pick(feet(5, 30), slack: 0))
        #expect(picked == .wall(upstairs.id) && picked != .wall(lower.id))
        let result = ContentView.commitDuplicate(&session, selection: picked)
        guard case let .wall(copy)? = result.selection else {
            Issue.record("the active-storey wall copy is not selected")
            return
        }
        #expect(result.status == "Duplicated. Drag the copy into place; Undo removes it.")
        #expect(session.model.document.walls.first { $0.id == copy }?.storeyID == upper)
        #expect(session.model.document.walls.first { $0.id == lower.id }?.storeyID != upper)
        #expect(session.model.planStorey == upper)
    }

    @Test("R turns stairs and furniture counterclockwise as exact one-step edits")
    func stairTurnsExactly() throws {
        let fixture = try placed()
        var session = fixture.session
        let (sofa, wall, stair) = (fixture.sofa, fixture.wall, fixture.stair)
        let before = try bytes(session.model.document)
        let beforeSteps = session.undoStack.count
        try session.turn(.stair(stair))
        // About (50', 5'): the foot at (50', 0) goes to (55', 5'), the head at (50', 10') to (45', 5').
        let turned = try #require(session.model.document.stairs.first { $0.id == stair })
        #expect(turned.runStart == feet(55, 5) && turned.runEnd == feet(45, 5))
        let once = try bytes(session.model.document)
        #expect(session.undoStack.count == beforeSteps + 1)
        try session.undo()
        #expect(try bytes(session.model.document) == before)
        try session.redo()
        #expect(try bytes(session.model.document) == once)
        for index in 2...4 {
            try session.turn(.stair(stair))
            #expect(session.undoStack.count == beforeSteps + index)
        }
        #expect(try bytes(session.model.document) == before)

        let steps = session.undoStack.count
        #expect(throws: HestiaModel.LoadError.self) { try session.turn(.wall(wall)) }
        #expect(try bytes(session.model.document) == before)
        #expect(session.undoStack.count == steps)

        let itemSteps = session.undoStack.count
        try session.turn(.placement(sofa))
        let item = try #require(session.model.document.placements.first { $0.id == sofa })
        #expect(item.position == feet(6, 8) && item.rotation == .degrees(90))
        #expect(session.undoStack.count == itemSteps + 1)
    }
}
