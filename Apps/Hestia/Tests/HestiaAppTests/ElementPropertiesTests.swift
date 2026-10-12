import ATContracts
import Foundation
import Testing
@testable import HestiaApp

/// A plan point in feet.
private func feet(_ x: Double, _ y: Double) -> Point2 {
    PlanOverlay.point(x, y)
}

/// A blank model with a 20' by 15' room, a door in its south wall, a window in its north wall, and a stair.
private func furnished() throws -> EditSession {
    var session = EditSession(model: try HestiaModel.blank())
    try session.addRectangleRoom(from: feet(0, 0), to: feet(20, 15), named: "Living")
    let walls = session.model.document.walls
    let south = try #require(walls.first { $0.start.y == .feet(0) && $0.end.y == .feet(0) })
    let north = try #require(walls.first { $0.start.y == .feet(15) && $0.end.y == .feet(15) })
    try session.perform(batch: [
        AddOpeningCommand(openingID: OpeningID(UUID()), wallID: south.id, offsetAlongWall: .feet(4),
                          width: .feet(3), height: .feet(7), sillHeight: .feet(0), kind: .singleDoor).erased,
        AddOpeningCommand(openingID: OpeningID(UUID()), wallID: north.id, offsetAlongWall: .feet(8),
                          width: .feet(4), height: .feet(4), sillHeight: .feet(3), kind: .window).erased,
    ])
    try session.perform(session.model.stairCommand(from: feet(14, 3), toward: feet(14, 12)).erased)
    return session
}

/// The document as saved, byte for byte.
private func bytes(_ document: ModelDocument) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(document)
}

@Suite("Element inspector")
struct ElementPropertiesTests {
    @Test("Select picks a door before its wall, a stair, then the room around a point")
    func pickOrder() throws {
        let session = try furnished()
        let model = session.model
        let door = try #require(model.document.openings.first { $0.kind == .singleDoor })
        #expect(model.pick(feet(5.5, 0), slack: 0) == .opening(door.id))
        let stair = try #require(model.document.stairs.first)
        #expect(model.pick(feet(14, 6), slack: 0) == .stair(stair.id))
        let room = try #require(model.document.rooms.first)
        #expect(model.pick(feet(5, 8), slack: 0) == .room(room.id))
        #expect(model.pick(feet(40, 40), slack: 0) == nil)
        #expect(model.outline(of: .room(room.id))?.count == 4)
        #expect(model.outline(of: .opening(door.id))?.count == 4)
    }

    @Test("A wall lists its length, thickness, and height, and a new length stretches the walls joined at its end")
    func wallLength() throws {
        var session = try furnished()
        let wall = try #require(session.model.document.walls.first { $0.start == feet(0, 0) })
        let rows = try #require(session.model.properties(of: .wall(wall.id))).rows
        #expect(rows.map(\.label) == ["Length", "Thickness", "Height", "Plan label"])
        #expect(rows.allSatisfy { $0.field != nil })
        try session.set(.wallLength, to: "24'", on: .wall(wall.id))
        let moved = try #require(session.model.document.walls.first { $0.id == wall.id })
        #expect(PlanGeometry.distance(moved.start, moved.end) == .feet(24))
        // The wall that met the old end meets the new one, so the corner stays closed.
        let joined = session.model.document.walls.filter {
            $0.id != wall.id && ($0.start == moved.end || $0.end == moved.end)
        }
        #expect(joined.count == 1)
        try session.undo()
        #expect(session.model.document.walls.first { $0.id == wall.id }?.end == wall.end)
    }

    @Test("Thickness and height take typed lengths; nonsense and zero are refused")
    func wallFigures() throws {
        var session = try furnished()
        let wall = try #require(session.model.document.walls.first)
        try session.set(.wallThickness, to: "8\"", on: .wall(wall.id))
        try session.set(.wallHeight, to: "9'", on: .wall(wall.id))
        let changed = try #require(session.model.document.walls.first { $0.id == wall.id })
        #expect(changed.thickness == .inches(8) && changed.height == .feet(9))
        #expect(throws: HestiaModel.LoadError.self) { try session.set(.wallHeight, to: "tall", on: .wall(wall.id)) }
        #expect(throws: HestiaModel.LoadError.self) { try session.set(.wallHeight, to: "0", on: .wall(wall.id)) }
    }

    @Test("A window resizes, moves along its wall, and slides when dragged across it")
    func windowFigures() throws {
        var session = try furnished()
        let window = try #require(session.model.document.openings.first { $0.kind == .window })
        let labels = try #require(session.model.properties(of: .opening(window.id))).rows.map(\.label)
        #expect(labels == ["Width", "Height", "Sill", "From wall start", "Schedule width"])
        try session.set(.openingWidth, to: "5'", on: .opening(window.id))
        try session.set(.openingSill, to: "2'6\"", on: .opening(window.id))
        try session.set(.openingOffset, to: "6'", on: .opening(window.id))
        var changed = try #require(session.model.document.openings.first { $0.id == window.id })
        #expect(changed.width == .feet(5) && changed.sillHeight == .inches(30) && changed.offsetAlongWall == .feet(6))
        #expect(changed.height == .feet(4))
        // A drag slides it by the part of the drag that runs along the wall.
        try session.move(.opening(window.id), dx: Length.feet(2).ticks,
                         dy: Length.feet(5).ticks)
        changed = try #require(session.model.document.openings.first { $0.id == window.id })
        #expect(abs(changed.offsetAlongWall.ticks - Length.feet(6).ticks) == Length.feet(2).ticks)
        // A size that won't fit in the wall is refused, and nothing changes.
        #expect(throws: (any Error).self) { try session.set(.openingWidth, to: "40'", on: .opening(window.id)) }
        #expect(session.model.document.openings.first { $0.id == window.id }?.width == .feet(5))
    }

    @Test("A room renames and can't be dragged; a stair widens and moves whole; each deletes")
    func roomAndStair() throws {
        var session = try furnished()
        let room = try #require(session.model.document.rooms.first)
        try session.set(.roomName, to: " Great Room ", on: .room(room.id))
        #expect(session.model.document.rooms.first?.name == "Great Room")
        #expect(throws: HestiaModel.LoadError.self) { try session.set(.roomName, to: "  ", on: .room(room.id)) }
        #expect(throws: HestiaModel.LoadError.self) { try session.move(.room(room.id), dx: 100, dy: 0) }
        let stair = try #require(session.model.document.stairs.first)
        try session.set(.stairWidth, to: "3'6\"", on: .stair(stair.id))
        #expect(session.model.document.stairs.first?.width == .inches(42))
        try session.move(.stair(stair.id), dx: -Length.feet(1).ticks, dy: 0)
        #expect(session.model.document.stairs.first?.runStart == feet(13, 3))
        try session.remove(.stair(stair.id))
        try session.remove(.room(room.id))
        #expect(session.model.document.stairs.isEmpty && session.model.document.rooms.isEmpty)
        #expect(session.model.properties(of: .room(room.id)) == nil)
        #expect(session.model.document.walls.count == 4, "removing a room keeps its walls")
    }

    @Test("Select picks doors, stairs, and rooms only on the storey shown, where two floors overlap in plan")
    func pickOnShownStorey() throws {
        var session = try furnished()
        let ground = try #require(session.model.planStorey)
        let groundDoor = try #require(session.model.document.openings.first { $0.kind == .singleDoor })
        let groundStair = try #require(session.model.document.stairs.first)
        let groundRoom = try #require(session.model.document.rooms.first)
        let (doorPoint, stairPoint, roomPoint) = (feet(5.5, 0), feet(14, 6), feet(5, 8))

        try session.addStoreyAbove()
        let upper = try #require(session.model.planStorey)
        #expect(upper != ground)
        // The empty floor above picks nothing of the floor below through it.
        #expect(session.model.pick(doorPoint, slack: 0) == nil)
        #expect(session.model.pick(stairPoint, slack: 0) == nil)
        #expect(session.model.pick(roomPoint, slack: 0) == nil)

        // The same room, door, and stair drawn upstairs, over the ones below.
        try session.addRectangleRoom(from: feet(0, 0), to: feet(20, 15), named: "Bedroom")
        let south = try #require(session.model.document.walls.first {
            $0.storeyID == upper && $0.start.y == .feet(0) && $0.end.y == .feet(0)
        })
        try session.perform(AddOpeningCommand(openingID: OpeningID(UUID()), wallID: south.id,
                                              offsetAlongWall: .feet(4), width: .feet(3), height: .feet(7),
                                              sillHeight: .feet(0), kind: .singleDoor).erased)
        try session.perform(session.model.stairCommand(from: feet(14, 3), toward: feet(14, 12)).erased)
        let upperDoor = try #require(session.model.document.openings.first { $0.wallID == south.id })
        let upperStair = try #require(session.model.document.stairs.first { $0.storeyID == upper })
        let upperRoom = try #require(session.model.document.rooms.first { $0.storeyID == upper })
        #expect(upperDoor.id != groundDoor.id && upperStair.id != groundStair.id && upperRoom.id != groundRoom.id)
        #expect(session.model.pick(doorPoint, slack: 0) == .opening(upperDoor.id))
        #expect(session.model.pick(stairPoint, slack: 0) == .stair(upperStair.id))
        #expect(session.model.pick(roomPoint, slack: 0) == .room(upperRoom.id))

        try session.show(storey: ground)
        #expect(session.model.pick(doorPoint, slack: 0) == .opening(groundDoor.id))
        #expect(session.model.pick(stairPoint, slack: 0) == .stair(groundStair.id))
        #expect(session.model.pick(roomPoint, slack: 0) == .room(groundRoom.id))
    }

    @Test("Deleting a door, a stair, or a room is one step: Undo brings back the same one, and Redo removes it")
    func deleteUndoRedo() throws {
        var session = try furnished()
        let door = try #require(session.model.document.openings.first { $0.kind == .singleDoor })
        let stair = try #require(session.model.document.stairs.first)
        let room = try #require(session.model.document.rooms.first)
        let cases: [(selection: PlanSelection, point: Point2)] = [
            (.opening(door.id), feet(5.5, 0)), (.stair(stair.id), feet(14, 6)), (.room(room.id), feet(5, 8)),
        ]
        for (selection, point) in cases {
            let before = try bytes(session.model.document)
            let shown = try #require(session.model.properties(of: selection))
            let steps = session.undoStack.count
            #expect(session.model.pick(point, slack: 0) == selection)

            try session.remove(selection)
            let removed = try bytes(session.model.document)
            #expect(removed != before)
            #expect(session.model.properties(of: selection) == nil)
            #expect(session.model.pick(point, slack: 0) != selection)
            let added: Int = steps + 1
            #expect(session.undoStack.count == added)

            try session.undo()
            #expect(try bytes(session.model.document) == before)
            #expect(session.model.pick(point, slack: 0) == selection)
            let restored = try #require(session.model.properties(of: selection))
            #expect(restored.title == shown.title && restored.rows == shown.rows)
            #expect(session.undoStack.count == steps)

            try session.redo()
            #expect(try bytes(session.model.document) == removed)
            #expect(session.model.properties(of: selection) == nil)
            #expect(session.undoStack.count == added)

            try session.undo()
            #expect(try bytes(session.model.document) == before)
        }
    }

    @Test("A door's distance from its wall's start and a window's sill take zero; sizes still need a length")
    func zeroWhereZeroFits() throws {
        var session = try furnished()
        let door = try #require(session.model.document.openings.first { $0.kind == .singleDoor })
        let window = try #require(session.model.document.openings.first { $0.kind == .window })
        try session.set(.openingOffset, to: "0", on: .opening(door.id))
        try session.set(.openingSill, to: "0'-0\"", on: .opening(window.id))
        #expect(session.model.document.openings.first { $0.id == door.id }?.offsetAlongWall == .feet(0))
        #expect(session.model.document.openings.first { $0.id == window.id }?.sillHeight == .feet(0))
        for field in [ElementProperty.Field.openingWidth, .openingHeight] {
            #expect(throws: HestiaModel.LoadError.self) { try session.set(field, to: "0", on: .opening(door.id)) }
        }
        #expect(throws: HestiaModel.LoadError.self) { try session.set(.openingSill, to: "-1", on: .opening(window.id)) }
        #expect(LengthEntry.parse("0", metric: false) == nil)
        #expect(LengthEntry.parse("0 mm", metric: true, allowingZero: true) == .millimeters(0))
    }

    @Test("A typed label replaces a dimension's figure on the drawings, and clearing it brings the figure back")
    func dimensionLabels() throws {
        var session = try furnished()
        let room = try #require(session.model.document.rooms.first)
        try session.set(.dimensionLabel(.width), to: " 20'-0\" CLR ", on: .room(room.id))
        #expect(session.model.document.dimensionOverride(for: room.id.rawValue, face: .width) == "20'-0\" CLR")
        let rows = try #require(session.model.properties(of: .room(room.id))).rows
        #expect(rows.first { $0.label == "Width label" }?.value == "20'-0\" CLR")
        // The plan sheet prints a label where it draws that dimension (here the depth, beside the stair), and
        // prints the measured figure there again once the label is cleared.
        func dimensions(_ model: HestiaModel) -> [String] {
            model.sheets.flatMap(\.content.items).compactMap { item in
                guard case let .dimension(from, to, offset, text) = item.primitive else { return nil }
                return "\(from.x.ticks),\(from.y.ticks) \(to.x.ticks),\(to.y.ticks) \(offset.ticks) \(text ?? "")"
            }
        }
        try session.set(.dimensionLabel(.width), to: "", on: .room(room.id))
        let measured = dimensions(session.model)
        try session.set(.dimensionLabel(.depth), to: "VERIFY", on: .room(room.id))
        let labelled = dimensions(session.model)
        // Exactly one figure, the room's 14'-6" depth, gives way to the label, at the same place on the sheet.
        let replaced = measured.filter { !labelled.contains($0) }
        let added = labelled.filter { !measured.contains($0) }
        #expect(replaced.count == 1 && added.count == 1)
        #expect(replaced.first?.hasSuffix(" 14'-6\"") == true)
        #expect(added.first?.hasSuffix(" VERIFY") == true)
        let figurePlace: String = String(replaced.first?.dropLast(7) ?? "")
        let labelPlace: String = String(added.first?.dropLast(7) ?? "?")
        #expect(figurePlace == labelPlace)
        try session.set(.dimensionLabel(.depth), to: "", on: .room(room.id))
        #expect(session.model.document.dimensionOverrides.isEmpty)
        #expect(dimensions(session.model) == measured)
        // Clearing a label that isn't there changes nothing and leaves nothing to undo.
        let steps = session.undoStack.count
        try session.set(.dimensionLabel(.depth), to: "", on: .room(room.id))
        #expect(session.undoStack.count == steps)
        // A wall's label goes on both chains that could measure it; one Undo takes both back.
        let wall = try #require(session.model.document.walls.first { $0.start.y == $0.end.y })
        try session.set(.dimensionLabel(.south), to: "VERIFY", on: .wall(wall.id))
        let faces = Set(session.model.document.dimensionOverrides
            .filter { $0.elementID == wall.id.rawValue }.map(\.face))
        #expect(faces == [.south, .north])
        try session.undo()
        #expect(session.model.document.dimensionOverrides.isEmpty)
        // A door's schedule width.
        let door = try #require(session.model.document.openings.first { $0.kind == .singleDoor })
        try session.set(.dimensionLabel(.width), to: "3'-0\" NOM", on: .opening(door.id))
        #expect(session.model.document.dimensionOverride(for: door.id.rawValue, face: .width) == "3'-0\" NOM")
    }

    @Test("Areas read in square feet, or square metres in a metric project")
    func areas() throws {
        let square = [feet(0, 0), feet(20, 0), feet(20, 15), feet(0, 15)]
        #expect(HestiaModel.area(square, metric: false) == "300.0 sq ft")
        #expect(HestiaModel.area(square, metric: true) == "27.9 m\u{00B2}")
        #expect(HestiaModel.kindName(.singleDoor) == "Single door")
        #expect(HestiaModel.kindName(.floorToCeilingWindow) == "Floor-to-ceiling window")
        #expect(HestiaModel.kindName(.casedOpening) == "Cased opening")
    }
}
