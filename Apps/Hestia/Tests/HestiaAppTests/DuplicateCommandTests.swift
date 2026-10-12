import ATContracts
import Foundation
import Testing
@testable import HestiaApp

private func feet(_ x: Double, _ y: Double) -> Point2 {
    PlanOverlay.point(x, y)
}

/// The document as saved, byte for byte.
private func bytes(_ document: ModelDocument) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(document)
}

/// The app source whose wiring cannot be invoked without constructing a live SwiftUI window.
private func appSource(_ name: String) throws -> String {
    let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/HestiaApp", isDirectory: true)
    return try String(contentsOf: app.appendingPathComponent(name), encoding: .utf8)
}

/// Command-D and R through the functions the plan's key presses call, ContentView.commitDuplicate and
/// commitTurn: what they select, what they say, and what they leave alone.
@Suite("Command-D and R")
struct DuplicateCommandTests {
    @Test("Command-D selects the copy 2' right and down, and says so, as one step")
    @MainActor
    func duplicateSelectsTheCopy() throws {
        var session = EditSession(model: try HestiaModel.blank())
        let stair = StairID(UUID())
        try session.perform(AddStairCommand(stairID: stair, storeyID: try #require(session.model.planStorey),
                                            runStart: feet(50, 0), runEnd: feet(50, 10), width: .feet(3),
                                            riserCount: 14, riserHeight: .inches(7)).erased)
        let steps = session.undoStack.count
        let result = ContentView.commitDuplicate(&session, selection: .stair(stair))
        #expect(result.status == "Duplicated. Drag the copy into place; Undo removes it.")
        guard case let .stair(copy)? = result.selection else {
            Issue.record("the copy is not selected: \(String(describing: result.selection))")
            return
        }
        #expect(copy != stair)
        let copied = try #require(session.model.document.stairs.first { $0.id == copy })
        #expect(copied.runStart == feet(52, -2) && copied.runEnd == feet(52, 8))
        let added: Int = steps + 1
        #expect(session.undoStack.count == added)
    }

    @Test("Command-D with nothing selected, on a room, or on something gone changes nothing and says why")
    @MainActor
    func duplicateRefusals() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addRectangleRoom(from: feet(0, 0), to: feet(20, 15), named: "Living")
        let room = try #require(session.model.document.rooms.first)
        let saved = try bytes(session.model.document)
        let steps = session.undoStack.count

        let nothing = ContentView.commitDuplicate(&session, selection: nil)
        #expect(nothing.selection == nil && nothing.status == "Select something to duplicate first.")
        let refused = ContentView.commitDuplicate(&session, selection: .room(room.id))
        #expect(refused.selection == .room(room.id))
        #expect(refused.status == "A room is its walls. Draw another room, or duplicate its walls.")
        let gone = ContentView.commitDuplicate(&session, selection: .stair(StairID(UUID())))
        #expect(gone.selection == nil)
        #expect(gone.status == "What was selected is gone, so there is nothing to duplicate.")

        #expect(try bytes(session.model.document) == saved)
        #expect(session.undoStack.count == steps)
    }

    @Test("R turns a stair a quarter turn and says so; refusals change nothing")
    @MainActor
    func turnThroughTheKey() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addWall(from: feet(0, 0), to: feet(10, 0))
        let wall = try #require(session.model.document.walls.first)
        let stair = StairID(UUID())
        try session.perform(AddStairCommand(stairID: stair, storeyID: try #require(session.model.planStorey),
                                            runStart: feet(50, 0), runEnd: feet(50, 10), width: .feet(3),
                                            riserCount: 14, riserHeight: .inches(7)).erased)

        let untouched = try bytes(session.model.document)
        let untouchedSteps = session.undoStack.count
        #expect(ContentView.commitTurn(&session, selection: nil) == "Select furniture or a stair to turn first.")
        #expect(ContentView.commitTurn(&session, selection: .stair(StairID(UUID())))
                == "What was selected is gone, so there is nothing to turn.")
        #expect(ContentView.commitTurn(&session, selection: .placement(PlacementID(UUID())))
                == "What was selected is gone, so there is nothing to turn.")
        #expect(try bytes(session.model.document) == untouched)
        #expect(session.undoStack.count == untouchedSteps)

        let beforeTurn = try bytes(session.model.document)
        #expect(ContentView.commitTurn(&session, selection: .stair(stair))
                == "Turned a quarter turn. Undo turns it back.")
        let turned = try #require(session.model.document.stairs.first { $0.id == stair })
        #expect(turned.runStart == feet(55, 5) && turned.runEnd == feet(45, 5))
        let turnedBytes = try bytes(session.model.document)
        #expect(session.undoStack.count == untouchedSteps + 1)
        try session.undo()
        #expect(try bytes(session.model.document) == beforeTurn)
        try session.redo()
        #expect(try bytes(session.model.document) == turnedBytes)

        let saved = try bytes(session.model.document)
        let steps = session.undoStack.count
        #expect(ContentView.commitTurn(&session, selection: .wall(wall.id))
                == "Only furniture and stairs turn. R turns them a quarter turn.")
        #expect(try bytes(session.model.document) == saved)
        #expect(session.undoStack.count == steps)
    }

    @Test("Command-D, R, the inspector, and Help stay wired to the tested owner behavior")
    func commandRoutesAndHelp() throws {
        let content = try appSource("ContentView.swift")
        #expect(content.contains("Button(\"Duplicate\") { duplicateSelection() }"))
        #expect(content.contains(".keyboardShortcut(\"d\", modifiers: .command)"))

        let inspector = try appSource("InspectorPanel.swift")
        #expect(inspector.contains("Button(\"Duplicate\", systemImage: \"plus.square.on.square\") { "
                                   + "duplicateSelection() }"))

        let tools = try appSource("PlanTools.swift")
        #expect(tools.contains("if text.lowercased() == \"r\" && typed.isEmpty"))
        #expect(tools.contains("else { turnSelection() }"))
        #expect(tools.contains("status = Self.commitTurn(&current, selection: selection)"))
        #expect(tools.contains("let result = Self.commitDuplicate(&current, selection: selection)"))

        let topic = try #require(HelpGuide.topics.first { $0.title == "Select, move, turn, and delete" })
        let help = topic.lines.joined(separator: " ")
        #expect(help.contains("R turns a selected item or stair a quarter turn"))
        #expect(help.contains("Command-D duplicates what is selected beside itself"))
        #expect(help.contains("a door, window, or cased opening further along its wall"))
    }
}
