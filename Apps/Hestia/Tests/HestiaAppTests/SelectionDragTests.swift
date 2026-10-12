import ATContracts
import Foundation
import Testing
@testable import HestiaApp

/// A plan point in feet.
private func feet(_ x: Double, _ y: Double) -> Point2 {
    PlanOverlay.point(x, y)
}

private func ticks(_ x: Int64, _ y: Int64) -> Point2 {
    Point2(x: Length(ticks: x), y: Length(ticks: y))
}

/// The document as saved, byte for byte.
private func bytes(_ document: ModelDocument) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(document)
}

/// A blank model with one oblique wall, 12' east and 5' north (13' long), holding a 3' window 3' from its
/// start and a 2' window 9'-6" from its start; a stair running north from (20', 0) to (20', 10'); and a 10'
/// square room off to the east.
private func oblique() throws -> (session: EditSession, window: OpeningID, stair: StairID, room: RoomID) {
    var session = EditSession(model: try HestiaModel.blank())
    try session.addWall(from: feet(0, 0), to: feet(12, 5))
    let wall = try #require(session.model.document.walls.first)
    let storey = try #require(session.model.planStorey)
    let window = OpeningID(UUID()), stair = StairID(UUID())
    try session.perform(batch: [
        AddOpeningCommand(openingID: window, wallID: wall.id, offsetAlongWall: .feet(3), width: .feet(3),
                          height: .feet(4), sillHeight: .feet(3), kind: .window).erased,
        AddOpeningCommand(openingID: OpeningID(UUID()), wallID: wall.id, offsetAlongWall: .inches(114),
                          width: .feet(2), height: .feet(4), sillHeight: .feet(3), kind: .window).erased,
        AddStairCommand(stairID: stair, storeyID: storey, runStart: feet(20, 0), runEnd: feet(20, 10),
                        width: .feet(3), riserCount: 14, riserHeight: .inches(7)).erased,
    ])
    try session.addRectangleRoom(from: feet(30, 0), to: feet(40, 10), named: "Den")
    let room = try #require(session.model.document.rooms.first)
    return (session, window, stair, room.id)
}

/// Drags go through the same calls the plan makes: `selectionPreview` for the ghost and readout while the mouse
/// moves, and `commitSelectionMove` when it lets go. Every expectation is a fixed figure worked out by hand from
/// the geometry (8128 ticks to the inch; the wall's direction is (12, 5)/13; its half thickness is 3"), never
/// from the helpers under test.
@Suite("Selection drags")
struct SelectionDragTests {
    @Test("An oblique door or window slides by the snapped run of the drag, and the ghost, readout, and commit agree")
    @MainActor
    func obliqueOpeningDrag() throws {
        let (initial, window, _, _) = try oblique()
        let start = feet(0, 0)
        // Forward: the drag runs 29.45" along the wall, which snaps to 29", from 3'-0" to 5'-5". The outline's
        // first corner goes from (279478, 90033) to (497058, 180692) ticks.
        // Back: 12.92" snaps to 13", to 1'-11"; the corner goes to (181942, 49393).
        let cases: [(end: Point2, offset: Length, corner: Point2, label: String)] = [
            (feet(2.2, 1.1), .inches(65), ticks(497_058, 180_692), "moved 2'-5\" at 22.6\u{00B0}"),
            (feet(-1, -0.4), .inches(23), ticks(181_942, 49_393), "moved 1'-1\" at 202.6\u{00B0}"),
            // Flush: 42" ahead ends it at 9'-6", exactly where the other window starts, which the wall takes.
            (feet(3.2308, 1.3462), .inches(78), ticks(594_594, 221_332), "moved 3'-6\" at 22.6\u{00B0}"),
        ]
        for expected in cases {
            var session = initial
            let preview = ContentView.selectionPreview(session.model, selection: .opening(window),
                                                       from: start, to: expected.end)
            let label = try #require(preview.labels.last)
            let ghost = try #require(preview.shapes.first)
            let shift = ticks(expected.corner.x.ticks - 279_478, expected.corner.y.ticks - 90_033)
            #expect(ghost.points.first == expected.corner)
            #expect(label.text == expected.label)
            #expect(label.position == shift)

            let move = try #require(ContentView.commitSelectionMove(&session, selection: .opening(window),
                                                                     from: start, to: expected.end))
            #expect(move.dx == shift.x.ticks && move.dy == shift.y.ticks)
            let moved = try #require(session.model.document.openings.first { $0.id == window })
            #expect(moved.offsetAlongWall == expected.offset)
            // The plan's own outline of the landed window is the ghost that was shown.
            #expect(session.model.outline(of: .opening(window)) == ghost.points)
            let steps: Int = initial.undoStack.count + 1
            #expect(session.undoStack.count == steps)
            try session.undo()
            #expect(session.model.document == initial.model.document)
        }
    }

    @Test("A drag across an oblique wall, past either end of it, or over another window moves nothing")
    @MainActor
    func openingDragRefusals() throws {
        let (initial, window, _, _) = try oblique()
        let start = feet(0, 0)
        var session = initial
        // Square across the wall: no run along it, so a zero move, read as such, with no Undo step.
        let across = ContentView.selectionPreview(session.model, selection: .opening(window), from: start,
                                                  to: feet(-0.5, 1.2))
        #expect(across.labels.last?.text == "moved 0'-0\"")
        #expect(across.labels.last?.position == start)
        #expect(across.shapes.first?.points.first == ticks(279_478, 90_033))
        let none = try ContentView.commitSelectionMove(&session, selection: .opening(window), from: start,
                                                       to: feet(-0.5, 1.2))
        #expect(none == ContentView.SelectionMove(dx: 0, dy: 0, offsetAlongWall: .feet(3)))
        #expect(session.undoStack.count == initial.undoStack.count)

        // 144" ahead would end the window at 18'-0" on a 13'-0" wall; 39" back would start it at -0'-3"; 48" ahead
        // fits the wall but ends it at 10'-0", over the other window, which starts at 9'-6".
        let saved = try bytes(initial.model.document)
        for end in [feet(11.1, 4.6), feet(-3, -1.25), feet(3.7, 1.5)] {
            let preview = ContentView.selectionPreview(session.model, selection: .opening(window), from: start,
                                                       to: end)
            #expect(preview.shapes.isEmpty)
            #expect(preview.labels.isEmpty)
            let committed = try ContentView.commitSelectionMove(&session, selection: .opening(window), from: start,
                                                                to: end)
            #expect(committed == nil)
            #expect(try bytes(session.model.document) == saved)
            #expect(session.undoStack.count == initial.undoStack.count)
        }
    }

    @Test("A stair moves whole by the snapped drag: both run ends, the ghost, and the readout")
    @MainActor
    func stairDrag() throws {
        var (session, _, stair, _) = try oblique()
        let start = feet(0, 0), end = feet(0.3667, 0.2)
        let preview = ContentView.selectionPreview(session.model, selection: .stair(stair), from: start, to: end)
        let label = try #require(preview.labels.last)
        #expect(label.text == "moved 0'-4 15/32\" at 26.6\u{00B0}")
        #expect(label.position == Point2(x: .inches(4), y: .inches(2)))

        let move = try #require(ContentView.commitSelectionMove(&session, selection: .stair(stair),
                                                                 from: start, to: end))
        #expect(move == ContentView.SelectionMove(dx: Length.inches(4).ticks, dy: Length.inches(2).ticks))
        let moved = try #require(session.model.document.stairs.first { $0.id == stair })
        #expect(moved.runStart == Point2(x: .inches(244), y: .inches(2)))
        #expect(moved.runEnd == Point2(x: .inches(244), y: .inches(122)))
        #expect(session.model.outline(of: .stair(stair)) == preview.shapes.first?.points)
    }

    @Test("The Select hint names everything Select picks, and how each one drags")
    @MainActor
    func selectHint() {
        let hint = ContentView.Tool.select.hint
        for word in ["wall", "door", "window", "cased opening", "stair", "room", "item", "patch",
                     "a door, window, or cased opening slides along its wall", "a stair moves whole",
                     "a room stays with its walls", "Delete removes it"] {
            #expect(hint.contains(word), "\(word)")
        }
        // Help says the same.
        let help = HelpGuide.topics.first { $0.title == "Select, move, turn, and delete" }?.lines.joined() ?? ""
        #expect(help.contains("door, window, cased opening, stair, room"))
        #expect(help.contains("a door, window, or cased opening slides along its wall"))
    }

    @Test("A cased opening is picked ahead of its wall, and drags along it by the same landing as a window")
    @MainActor
    func casedOpeningDrag() throws {
        // The oblique wall again, moved 20' north, holding a 3' cased opening 3' from its start.
        var session = EditSession(model: try HestiaModel.blank())
        try session.addWall(from: feet(0, 20), to: feet(12, 25))
        let wall = try #require(session.model.document.walls.first)
        let cased = OpeningID(UUID())
        try session.perform(AddOpeningCommand(openingID: cased, wallID: wall.id, offsetAlongWall: .feet(3),
                                              width: .feet(3), height: .feet(7), sillHeight: .feet(0),
                                              kind: .casedOpening).erased)
        // Its middle, 4'-6" along the wall, is also on the wall itself, but Select takes the opening.
        let middle = feet(4.5 * 12 / 13, 20 + 4.5 * 5 / 13)
        let slack = Double(Length.feet(1).ticks)
        #expect(session.model.wallNear(middle, slack: slack) == wall.id)
        #expect(session.model.pick(middle, slack: slack) == .opening(cased))
        #expect(session.model.properties(of: .opening(cased))?.title == "Cased opening")

        // The forward drag of the window test: 29" along, to 5'-5". Every corner sits exactly 20' (1950720
        // ticks) north of that test's, so the first corner lands at (497058, 2131412) and moves (217580, 90659).
        let initial = session
        let start = feet(0, 0), end = feet(2.2, 1.1)
        let preview = ContentView.selectionPreview(session.model, selection: .opening(cased), from: start, to: end)
        let label = try #require(preview.labels.last)
        let ghost = try #require(preview.shapes.first)
        #expect(ghost.points.first == ticks(497_058, 2_131_412))
        #expect(label.text == "moved 2'-5\" at 22.6\u{00B0}")
        #expect(label.position == ticks(217_580, 90_659))
        let move = try #require(ContentView.commitSelectionMove(&session, selection: .opening(cased),
                                                                 from: start, to: end))
        #expect(move == ContentView.SelectionMove(dx: 217_580, dy: 90_659, offsetAlongWall: .inches(65)))
        #expect(session.model.document.openings.first { $0.id == cased }?.offsetAlongWall == .inches(65))
        #expect(session.model.outline(of: .opening(cased)) == ghost.points)
        let steps: Int = initial.undoStack.count + 1
        #expect(session.undoStack.count == steps)

        // Past the wall's end it shows nothing and commits nothing, like a door or window.
        let saved = try bytes(session.model.document)
        let far = ContentView.selectionPreview(session.model, selection: .opening(cased), from: start,
                                               to: feet(11.1, 4.6))
        #expect(far.shapes.isEmpty && far.labels.isEmpty)
        #expect(try ContentView.commitSelectionMove(&session, selection: .opening(cased), from: start,
                                                    to: feet(11.1, 4.6)) == nil)
        #expect(try bytes(session.model.document) == saved)
    }

    @Test("A room drag is refused with its sentence, shows nothing, and changes nothing")
    @MainActor
    func roomDragRefused() throws {
        let (initial, _, _, room) = try oblique()
        var session = initial
        let preview = ContentView.selectionPreview(session.model, selection: .room(room), from: feet(35, 5),
                                                   to: feet(37, 6))
        #expect(preview.shapes.isEmpty && preview.labels.isEmpty)
        #expect(throws: HestiaModel.LoadError.self) {
            try ContentView.commitSelectionMove(&session, selection: .room(room), from: feet(35, 5), to: feet(37, 6))
        }
        #expect(session.model.document == initial.model.document)
        #expect(session.undoStack.count == initial.undoStack.count)
    }
}
