import ATContracts
import Foundation

/// Duplicating and turning what is selected, each as one undoable step.
extension EditSession {
    /// How far a copy lands from what it copies: two feet right and down, or 600 mm in a metric project, so it
    /// shows clear of the original and can be dragged into place.
    var duplicateOffset: Length {
        model.document.project.displayUnits == .metric ? .millimeters(600) : .feet(2)
    }

    /// Copies the selection beside itself and returns the copy, to select it: an item, a wall (on its own,
    /// without its doors and windows), a stair, or a site area shifted right and down by `duplicateOffset`; a
    /// door or window further along its own wall, past its own width and a foot more. A room is its walls, so
    /// one is refused with a sentence, as is a door or window with no room left on its wall.
    mutating func duplicate(_ selection: PlanSelection) throws -> PlanSelection? {
        let step = duplicateOffset.ticks
        func shifted(_ point: Point2) -> Point2 {
            Point2(x: Length(ticks: point.x.ticks + step), y: Length(ticks: point.y.ticks - step))
        }
        let document = model.document
        switch selection {
        case let .placement(id):
            guard let item = document.placements.first(where: { $0.id == id }) else { return nil }
            let copy = PlacementID(UUID())
            try perform(AddPlacementCommand(placementID: copy, storeyID: item.storeyID,
                                            catalogItemID: item.catalogItemID, position: shifted(item.position),
                                            rotation: item.rotation, elevation: item.elevation,
                                            layerID: item.layerID).erased)
            return .placement(copy)
        case let .wall(id):
            guard let wall = document.walls.first(where: { $0.id == id }) else { return nil }
            let copy = WallID(UUID())
            try perform(AddWallCommand(wallID: copy, storeyID: wall.storeyID, start: shifted(wall.start),
                                       end: shifted(wall.end), thickness: wall.thickness, height: wall.height,
                                       layers: wall.layers, phase: wall.phase).erased)
            return .wall(copy)
        case let .stair(id):
            guard let stair = document.stairs.first(where: { $0.id == id }) else { return nil }
            let copy = StairID(UUID())
            try perform(AddStairCommand(stairID: copy, storeyID: stair.storeyID, kind: stair.kind,
                                        runStart: shifted(stair.runStart), runEnd: shifted(stair.runEnd),
                                        width: stair.width, riserCount: stair.riserCount,
                                        riserHeight: stair.riserHeight).erased)
            return .stair(copy)
        case let .patch(id):
            guard let patch = document.terrainPatches.first(where: { $0.id == id }) else { return nil }
            let copy = TerrainPatchID(UUID())
            let points = patch.surveyPoints.map {
                Point3(x: Length(ticks: $0.x.ticks + step), y: Length(ticks: $0.y.ticks - step), z: $0.z)
            }
            try perform(AddTerrainPatchCommand(terrainPatchID: copy, name: patch.name,
                                               boundary: patch.boundary.map(shifted), surveyPoints: points).erased)
            return .patch(copy)
        case let .opening(id):
            guard let opening = document.openings.first(where: { $0.id == id }) else { return nil }
            let copy = OpeningID(UUID())
            let along = Length(ticks: opening.offsetAlongWall.ticks + opening.width.ticks + Length.feet(1).ticks)
            do {
                try perform(AddOpeningCommand(openingID: copy, wallID: opening.wallID, offsetAlongWall: along,
                                              width: opening.width, height: opening.height,
                                              sillHeight: opening.sillHeight, kind: opening.kind,
                                              swing: opening.swing).erased)
            } catch is CommandValidationError {
                throw HestiaModel.LoadError(message: "There is no room for another one further along that wall.")
            }
            return .opening(copy)
        case .room:
            throw HestiaModel.LoadError(message: "A room is its walls. Draw another room, or duplicate its walls.")
        }
    }

    /// Turns the selection a quarter turn counterclockwise: an item about its middle, a stair about the middle
    /// of its run. Nothing else turns; walls and areas keep the shape they were drawn with.
    mutating func turn(_ selection: PlanSelection) throws {
        switch selection {
        case let .placement(id):
            guard model.document.placements.contains(where: { $0.id == id }) else {
                throw HestiaModel.LoadError(message: "What was selected is gone, so there is nothing to turn.")
            }
            try movePlacement(id, dx: 0, dy: 0, degrees: 90)
        case let .stair(id):
            guard let stair = model.document.stairs.first(where: { $0.id == id }) else {
                throw HestiaModel.LoadError(message: "What was selected is gone, so there is nothing to turn.")
            }
            let cx = (stair.runStart.x.ticks + stair.runEnd.x.ticks) / 2
            let cy = (stair.runStart.y.ticks + stair.runEnd.y.ticks) / 2
            func turned(_ point: Point2) -> Point2 {
                let dx = point.x.ticks - cx, dy = point.y.ticks - cy
                return Point2(x: Length(ticks: cx - dy), y: Length(ticks: cy + dx))
            }
            try perform(MoveStairCommand(stairID: id, runStart: turned(stair.runStart),
                                         runEnd: turned(stair.runEnd)).erased)
        case .wall, .patch, .opening, .room:
            throw HestiaModel.LoadError(message: "Only furniture and stairs turn. R turns them a quarter turn.")
        }
    }
}
