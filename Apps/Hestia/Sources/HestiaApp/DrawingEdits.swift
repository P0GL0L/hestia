import ATContracts
import Foundation

/// The drawing tools' edits, in model space. Each is one undoable step.
extension EditSession {
    /// Adds a wall between two model points, each landing on the grid and then on a nearby wall end. Returns
    /// where the wall ends, so the next wall of a chain can start there.
    @discardableResult
    mutating func addWall(from a: Point2, to b: Point2) throws -> Point2 {
        let from = model.snappedWallEnd(a), to = model.snappedWallEnd(b)
        guard from != to else {
            throw HestiaModel.LoadError(message: "Both ends snap to the same point. Click farther apart.")
        }
        try perform(model.wallCommand(from: from, to: to).erased)
        return to
    }

    /// Adds four walls around the rectangle with corners `a` and `b`, and a room named `name` inside them, as one
    /// step. A side that lies along a wall already drawn, within its length, uses that wall instead of a second
    /// one, so rooms drawn side by side share their walls. (A room's corners come from where its walls' lines
    /// cross, so a longer wall still gives the right corner.)
    mutating func addRectangleRoom(from a: Point2, to b: Point2, named name: String) throws {
        let corners = PlanGeometry.rectangle(model.snappedWallEnd(a), model.snappedWallEnd(b))
        guard corners[0].x != corners[2].x, corners[0].y != corners[2].y else {
            throw HestiaModel.LoadError(message: "Drag out a rectangle with some width and depth.")
        }
        var commands: [AnyCommand] = []
        var boundary: [WallID] = []
        let existing = model.document.walls.filter { $0.storeyID == model.groundStorey }
        for index in corners.indices {
            let start = corners[index], end = corners[(index + 1) % corners.count]
            if let wall = existing.first(where: { covers($0, start, end) }) {
                boundary.append(wall.id)
                continue
            }
            let command = try model.wallCommand(from: start, to: end)
            commands.append(command.erased)
            boundary.append(command.wallID)
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        commands.append(try model.roomCommand(named: trimmed.isEmpty ? "Room" : trimmed, walls: boundary).erased)
        try perform(batch: commands)
    }

    /// Whether the side from `start` to `end` lies on the wall's centerline, end to end.
    private func covers(_ wall: Wall, _ start: Point2, _ end: Point2) -> Bool {
        PlanGeometry.distance(from: start, toSegment: wall.start, wall.end) <= 1
            && PlanGeometry.distance(from: end, toSegment: wall.start, wall.end) <= 1
    }

    /// Adds a rectangular terrain patch of a kind, named for it. A new lot replaces the old one.
    mutating func addSitePatch(_ kind: SiteKind, from a: Point2, to b: Point2) throws {
        let corners = PlanGeometry.rectangle(model.snapped(a), model.snapped(b))
        guard corners[0].x != corners[2].x, corners[0].y != corners[2].y else {
            throw HestiaModel.LoadError(message: "Drag out a rectangle with some width and depth.")
        }
        var commands: [AnyCommand] = []
        if kind == .lot {
            for patch in model.document.terrainPatches where SiteKind(patchName: patch.name) == .lot {
                commands.append(RemoveTerrainPatchCommand(terrainPatchID: patch.id).erased)
            }
        }
        let same = model.document.terrainPatches.filter { SiteKind(patchName: $0.name) == kind }.count
        let name = kind == .lot || same == 0 ? kind.rawValue : "\(kind.rawValue) \(same + 1)"
        commands.append(AddTerrainPatchCommand(terrainPatchID: TerrainPatchID(UUID()), name: name, boundary: corners,
                                               surveyPoints: []).erased)
        try perform(batch: commands)
    }

    /// Places a catalog item on the ground storey with its middle at a model point, turned `degrees`
    /// counterclockwise. Returns the new placement's ID.
    @discardableResult
    mutating func place(_ item: FurnitureItem, at point: Point2, degrees: Int) throws -> PlacementID {
        guard let storey = model.groundStorey else {
            throw HestiaModel.LoadError(message: "The model has no storey to place furniture on.")
        }
        let id = PlacementID(UUID())
        try perform(AddPlacementCommand(placementID: id, storeyID: storey, catalogItemID: item.catalogID,
                                        position: model.snapped(point), rotation: .degrees(Int64(degrees))).erased)
        return id
    }

    /// Moves a placed item by a model offset and turns it a further `degrees` counterclockwise.
    mutating func movePlacement(_ id: PlacementID, dx: Int64, dy: Int64, degrees: Int64 = 0) throws {
        guard let placement = model.document.placements.first(where: { $0.id == id }) else { return }
        let target = model.snapped(Point2(x: Length(ticks: placement.position.x.ticks + dx),
                                          y: Length(ticks: placement.position.y.ticks + dy)))
        let position = dx == 0 && dy == 0 ? placement.position : target
        let whole = 360 * Angle.microDegreesPerDegree
        var turn = (placement.rotation.microDegrees + degrees * Angle.microDegreesPerDegree) % whole
        if turn < 0 { turn += whole }
        try perform(MovePlacementCommand(placementID: id, position: position, rotation: Angle(microDegrees: turn),
                                         elevation: placement.elevation).erased)
    }

    mutating func removePlacement(_ id: PlacementID) throws {
        try perform(RemovePlacementCommand(placementID: id).erased)
    }

    /// Removes a wall. A wall with doors, windows, or rooms on it is refused, saying which.
    mutating func removeWall(_ id: WallID) throws {
        do {
            try perform(RemoveWallCommand(wallID: id).erased)
        } catch CommandValidationError.hasDependents {
            throw HestiaModel.LoadError(message: "Refused: that wall \(model.dependents(of: id)). Remove those first.")
        }
    }

    /// Moves a terrain patch by a model offset, on the grid, as one step.
    mutating func movePatch(_ id: TerrainPatchID, dx: Int64, dy: Int64) throws {
        guard let index = model.document.terrainPatches.firstIndex(where: { $0.id == id }) else { return }
        let patch = model.document.terrainPatches[index]
        let step = model.snapStep
        let sx = HestiaModel.snap(Length(ticks: dx), to: step).ticks
        let sy = HestiaModel.snap(Length(ticks: dy), to: step).ticks
        guard sx != 0 || sy != 0 else { return }
        let boundary = patch.boundary.map {
            Point2(x: Length(ticks: $0.x.ticks + sx), y: Length(ticks: $0.y.ticks + sy))
        }
        try perform(batch: [RemoveTerrainPatchCommand(terrainPatchID: id).erased,
                            AddTerrainPatchCommand(terrainPatchID: id, name: patch.name, boundary: boundary,
                                                   surveyPoints: patch.surveyPoints, index: index).erased])
    }

    mutating func removeTerrainPatch(_ id: TerrainPatchID) throws {
        try perform(RemoveTerrainPatchCommand(terrainPatchID: id).erased)
    }

    /// Moves a wall by a model offset, on the grid, taking the ends of walls joined to it along, so corners
    /// stay closed. Refused, with nothing moved, when a joined wall's doors or windows would no longer fit.
    mutating func moveWall(_ id: WallID, dx: Int64, dy: Int64) throws {
        guard let wall = model.document.walls.first(where: { $0.id == id }) else { return }
        let step = model.snapStep.ticks
        let (sx, sy) = (HestiaModel.snap(Length(ticks: dx), to: Length(ticks: step)).ticks,
                        HestiaModel.snap(Length(ticks: dy), to: Length(ticks: step)).ticks)
        guard sx != 0 || sy != 0 else { return }
        func shifted(_ point: Point2) -> Point2 {
            Point2(x: Length(ticks: point.x.ticks + sx), y: Length(ticks: point.y.ticks + sy))
        }
        var commands = [MoveWallCommand(wallID: id, start: shifted(wall.start), end: shifted(wall.end)).erased]
        for other in model.document.walls where other.id != id && other.storeyID == wall.storeyID {
            let start = other.start == wall.start || other.start == wall.end ? shifted(other.start) : other.start
            let end = other.end == wall.start || other.end == wall.end ? shifted(other.end) : other.end
            if start != other.start || end != other.end {
                commands.append(MoveWallCommand(wallID: other.id, start: start, end: end).erased)
            }
        }
        try perform(batch: commands)
    }
}

/// What the Select tool can pick.
enum PlanSelection: Equatable {
    case placement(PlacementID)
    case wall(WallID)
    case patch(TerrainPatchID)
}

extension HestiaModel {
    /// The placed item under a model point on the ground storey: the last placed, when items overlap.
    func placementHit(_ point: Point2) -> PlacementID? {
        for placement in document.placements.reversed() where placement.storeyID == groundStorey {
            let item = Furniture.item(placement.catalogItemID) ?? Furniture.placeholder(placement.catalogItemID)
            let turn = Double(placement.rotation.microDegrees) / 1_000_000 * .pi / 180
            let outline = item.outline(cx: HouseScene.feet(placement.position.x),
                                       cy: HouseScene.feet(placement.position.y), turn: turn)
                .map { PlanOverlay.point($0.x, $0.y) }
            if PlanGeometry.contains(outline, point) { return placement.id }
        }
        return nil
    }

    /// The ground-storey wall nearest a model point, when the point is within half its thickness plus `slack`
    /// ticks of its centerline.
    func wallNear(_ point: Point2, slack: Double) -> WallID? {
        var best: (id: WallID, distance: Double)?
        for wall in document.walls where wall.storeyID == groundStorey {
            let distance = PlanGeometry.distance(from: point, toSegment: wall.start, wall.end)
            guard distance <= Double(wall.thickness.ticks) / 2 + slack else { continue }
            if best == nil || distance < best!.distance { best = (wall.id, distance) }
        }
        return best?.id
    }

    /// The terrain patch under a model point: the smallest that holds it, so a path on a lot is the path.
    func patchHit(_ point: Point2) -> TerrainPatchID? {
        var best: (id: TerrainPatchID, area: Double)?
        for patch in document.terrainPatches where PlanGeometry.contains(patch.boundary, point) {
            let outline = patch.boundary.map { (x: HouseScene.feet($0.x), y: HouseScene.feet($0.y)) }
            let area = abs(Triangulation.twiceArea(outline))
            if best == nil || area < best!.area { best = (patch.id, area) }
        }
        return best?.id
    }
}
