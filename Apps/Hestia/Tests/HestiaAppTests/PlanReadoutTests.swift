import ATContracts
import Foundation
import Testing
@testable import HestiaApp

/// A plan point in feet.
private func feet(_ x: Double, _ y: Double) -> Point2 {
    PlanOverlay.point(x, y)
}

private func millimeters(_ x: Int64, _ y: Int64) -> Point2 {
    Point2(x: .millimeters(x), y: .millimeters(y))
}

private func metricModel() throws -> HestiaModel {
    var session = EditSession(model: try HestiaModel.blank())
    try session.perform(SetProjectUnitsCommand(projectID: session.model.document.project.id, units: .metric).erased)
    return session.model
}

@Suite("Plan readouts")
struct PlanReadoutTests {
    @Test("A direction reads in degrees counterclockwise from east, to a tenth")
    func angles() {
        let origin = feet(0, 0)
        #expect(PlanReadout.angle(from: origin, to: feet(10, 0)) == "0\u{00B0}")
        #expect(PlanReadout.angle(from: origin, to: feet(0, 10)) == "90\u{00B0}")
        #expect(PlanReadout.angle(from: origin, to: feet(-10, 0)) == "180\u{00B0}")
        #expect(PlanReadout.angle(from: origin, to: feet(0, -10)) == "270\u{00B0}")
        #expect(PlanReadout.angle(from: origin, to: feet(10, 10)) == "45\u{00B0}")
        #expect(PlanReadout.angle(from: origin, to: feet(-10, 4.1421)) == "157.5\u{00B0}")
        // Just under a full turn rounds to 0, never 360.
        #expect(PlanReadout.angle(from: origin, to: feet(100, -0.01)) == "0\u{00B0}")
        #expect(PlanReadout.angle(from: origin, to: origin).isEmpty)
    }

    @Test("Imperial wall, move, and position values use the project's written lengths")
    func imperialReadouts() throws {
        let model = try HestiaModel.blank()
        #expect(PlanReadout.wall(from: feet(0, 0), to: feet(0, 12.5), model: model) == "12'-6\"  90\u{00B0}")
        #expect(PlanReadout.wall(from: feet(3, 3), to: feet(3, 3), model: model) == "0'-0\"")
        #expect(PlanReadout.move(from: feet(1, 1), to: feet(4, 5), model: model) == "moved 5'-0\" at 53.1\u{00B0}")
        #expect(PlanReadout.position(feet(12.25, -8), model: model) == "X 12'-3\"   Y \u{2212}8'-0\"")
    }

    @Test("Metric wall, move, and position values stay in project units")
    func metricReadouts() throws {
        let model = try metricModel()
        #expect(PlanReadout.wall(from: millimeters(0, 0), to: millimeters(1000, 0), model: model)
                == "1000 mm  0\u{00B0}")
        #expect(PlanReadout.move(from: millimeters(0, 0), to: millimeters(3000, 4000), model: model)
                == "moved 5000 mm at 53.1\u{00B0}")
        #expect(PlanReadout.position(millimeters(-1000, 500), model: model) == "X \u{2212}1000 mm   Y 500 mm")
    }

    @Test("Selection preview reports the grid movement each edit will commit")
    @MainActor
    func snappedSelectionPreview() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addWall(from: feet(0, 0), to: feet(10, 0))
        let wall = try #require(session.model.document.walls.first)
        let storey = try #require(session.model.planStorey)
        let placement = PlacementID(UUID())
        try session.perform(AddPlacementCommand(placementID: placement, storeyID: storey,
                                                catalogItemID: CatalogItemID(rawValue: "hestia.sofa"),
                                                position: feet(1, 1)).erased)
        let patch = TerrainPatchID(UUID())
        try session.perform(AddTerrainPatchCommand(terrainPatchID: patch, name: "Lawn",
                                                   boundary: PlanGeometry.rectangle(feet(0, 0), feet(10, 10)),
                                                   surveyPoints: []).erased)

        for selection in [PlanSelection.wall(wall.id), .placement(placement), .patch(patch)] {
            let still = ContentView.selectionPreview(session.model, selection: selection,
                                                     from: feet(0, 0), to: feet(0, 0))
            let dragged = ContentView.selectionPreview(session.model, selection: selection,
                                                       from: feet(0, 0), to: feet(0.04, 0.04))
            let label = try #require(dragged.labels.last)
            #expect(label.text == "moved 0'-0\"")
            #expect(label.position == feet(0, 0))
            #expect(dragged.shapes == still.shapes)
        }
    }

    @Test("Selection preview and readout equal the committed edit")
    @MainActor
    func selectionCommitMatchesPreview() throws {
        let start = feet(0, 0)
        let rawEnd = feet(0.3667, 0.2)
        let expectedEnd = Point2(x: .inches(4), y: .inches(2))
        let expectedDX = Length.inches(4).ticks
        let expectedDY = Length.inches(2).ticks
        let expectedLabel = "moved 0'-4 15/32\" at 26.6\u{00B0}"

        func verify(_ initial: EditSession, selection: PlanSelection,
                    anchor: (HestiaModel) -> Point2?) throws -> HestiaModel {
            var committed = initial
            let preview = ContentView.selectionPreview(initial.model, selection: selection,
                                                       from: start, to: rawEnd)
            let label = try #require(preview.labels.last)
            let beforeAnchor = try #require(anchor(initial.model))

            let move = try #require(ContentView.commitSelectionMove(&committed, selection: selection,
                                                                     from: start, to: rawEnd))

            let afterAnchor = try #require(anchor(committed.model))
            let committedGhost = ContentView.selectionPreview(committed.model, selection: selection,
                                                               from: start, to: start)
            #expect(move.dx == expectedDX)
            #expect(move.dy == expectedDY)
            #expect(move.dx != 0 && move.dy != 0)
            #expect(expectedEnd != rawEnd)
            #expect(afterAnchor.x.ticks - beforeAnchor.x.ticks == expectedDX)
            #expect(afterAnchor.y.ticks - beforeAnchor.y.ticks == expectedDY)
            #expect(preview.shapes == committedGhost.shapes)
            #expect(label.position == expectedEnd)
            #expect(label.text == expectedLabel)
            return committed.model
        }

        var placementSession = EditSession(model: try HestiaModel.blank())
        let storey = try #require(placementSession.model.planStorey)
        let placement = PlacementID(UUID())
        try placementSession.perform(AddPlacementCommand(placementID: placement, storeyID: storey,
                                                         catalogItemID: CatalogItemID(rawValue: "hestia.sofa"),
                                                         position: start).erased)
        _ = try verify(placementSession, selection: .placement(placement)) { model in
            model.document.placements.first(where: { $0.id == placement })?.position
        }

        var wallSession = EditSession(model: try HestiaModel.blank())
        try wallSession.addWall(from: feet(-0.5, 0), to: feet(0.5, 0))
        let wall = try #require(wallSession.model.document.walls.first)
        _ = try verify(wallSession, selection: .wall(wall.id)) { model in
            model.document.walls.first(where: { $0.id == wall.id })?.start
        }

        var patchSession = EditSession(model: try HestiaModel.blank())
        let patch = TerrainPatchID(UUID())
        let survey = Point3(x: .inches(1), y: .inches(2), z: .feet(10))
        try patchSession.perform(AddTerrainPatchCommand(terrainPatchID: patch, name: "Lawn",
                                                        boundary: PlanGeometry.rectangle(feet(-0.5, -0.5),
                                                                                         feet(0.5, 0.5)),
                                                        surveyPoints: [survey]).erased)
        let movedPatch = try verify(patchSession, selection: .patch(patch)) { model in
            model.document.terrainPatches.first(where: { $0.id == patch })?.boundary.first
        }
        let movedSurvey = try #require(movedPatch.document.terrainPatches
            .first(where: { $0.id == patch })?.surveyPoints.first)
        #expect(movedSurvey.x == .inches(5))
        #expect(movedSurvey.y == .inches(4))
        #expect(movedSurvey.z == .feet(10))
    }

    @Test("Metric selection movement resolves on its ten-millimeter grid")
    @MainActor
    func metricSelectionPreview() throws {
        var session = EditSession(model: try metricModel())
        try session.addWall(from: millimeters(0, 0), to: millimeters(1000, 0))
        let wall = try #require(session.model.document.walls.first)
        let preview = ContentView.selectionPreview(session.model, selection: .wall(wall.id),
                                                   from: millimeters(0, 0), to: millimeters(4, 4))
        let label = try #require(preview.labels.last)
        #expect(label.text == "moved 0 mm")
        #expect(label.position == millimeters(0, 0))
    }

    @Test("Pointer coordinates stay raw while a wall endpoint snaps to the drawing grid")
    @MainActor
    func rawPointerAndSnappedTarget() throws {
        let model = try HestiaModel.blank()
        let raw = feet(0.04, 0.04)
        let pointer = ContentView.pointerState(raw, tool: .wall, anchor: nil, model: model)
        #expect(pointer.position == raw)
        #expect(pointer.target == feet(0, 0))
    }

    @Test("Wall preview includes both snapped length and direction")
    @MainActor
    func wallPreview() throws {
        let model = try HestiaModel.blank()
        let preview = ContentView.segmentPreview(model, tool: .wall, from: feet(0, 0), to: feet(0, 12.5), typed: "")
        #expect(preview.labels.map(\.text) == ["12'-6\"  90\u{00B0}"])
    }

    @Test("Stair preview keeps its run without a direction")
    @MainActor
    func stairPreview() throws {
        let model = try HestiaModel.blank()
        let preview = ContentView.segmentPreview(model, tool: .stair, from: feet(0, 0), to: feet(0, 12.5),
                                                 typed: "")
        #expect(preview.labels.map(\.text) == ["12'-6\""])
    }

    @Test("Pointer coordinates appear only while a plan is visible")
    @MainActor
    func pointerVisibility() throws {
        let model = try HestiaModel.blank()
        let point = feet(2, 3)
        #expect(ContentView.pointerReadout(point, model: model, layout: .plan) == "X 2'-0\"   Y 3'-0\"")
        #expect(ContentView.pointerReadout(point, model: model, layout: .split) == "X 2'-0\"   Y 3'-0\"")
        #expect(ContentView.pointerReadout(point, model: model, layout: .house) == nil)
        #expect(ContentView.pointerReadout(nil, model: model, layout: .plan) == nil)
    }
}
