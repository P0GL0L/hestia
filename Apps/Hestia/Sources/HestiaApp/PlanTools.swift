import ATContracts
import AppKit
import SwiftUI

/// The plan view's pointer, scroll, and key handling, and what each tool does with it.
extension ContentView {
    /// What the current tool is about to add, drawn over the plan.
    struct Preview {
        var shapes: [PlanOverlay.Shape] = []
        var labels: [PlanOverlay.Label] = []
    }

    func planInput(_ input: PlanInput, fit view: PlanFit) {
        guard let model = session?.model else { return }
        switch input {
        case let .moved(point):
            let pointer = Self.pointerState(view.paper(point), tool: tool, anchor: anchor, model: model)
            pointerPosition = pointer.position
            hover = pointer.target
        case .exited:
            pointerPosition = nil
            hover = nil
        case let .down(point, clicks):
            press = Press(model: view.paper(point), view: point)
            dragging = false
            if clicks == 2 && tool == .wall {
                press = nil
                stopChain()
            }
        case let .dragged(point):
            drag(to: point, view: view, model: model)
        case let .up(point):
            release(at: point, view: view, model: model)
        case .secondary:
            stopChain()
        case let .scroll(dx, dy, precise, at):
            if precise {
                pan = CGSize(width: pan.width + CGFloat(dx), height: pan.height + CGFloat(dy))
            } else if dy != 0 {
                zoom(by: dy > 0 ? 1.15 : 1 / 1.15, at: at, view: view)
            }
        case let .magnify(amount, at):
            zoom(by: 1 + amount, at: at, view: view)
        case let .key(key):
            keyInput(key, model: model)
        }
    }

    /// Where the current tool would put a point under the pointer: on the grid, then, for walls, rooms, and
    /// stairs, on a nearby wall end. The direction from the last corner is never squared to an axis, so a
    /// shallow diagonal stays the diagonal that was drawn.
    func target(_ raw: Point2, _ model: HestiaModel) -> Point2 {
        Self.target(raw, tool: tool, anchor: anchor, model: model)
    }

    struct PointerState: Equatable {
        var position: Point2
        var target: Point2
    }

    /// The point reported for the pointer and the separately resolved point used by the active drawing tool.
    static func pointerState(_ raw: Point2, tool: Tool, anchor: Point2?, model: HestiaModel) -> PointerState {
        let resolved = target(raw, tool: tool, anchor: anchor, model: model)
        return PointerState(position: raw, target: resolved)
    }

    /// `target` for a given tool and chain anchor. The anchor is taken but never used to square the point, so a
    /// near-axis wall from it stays as drawn.
    static func target(_ raw: Point2, tool: Tool, anchor: Point2?, model: HestiaModel) -> Point2 {
        switch tool {
        case .wall, .room, .stair:
            return model.snappedWallEnd(raw)
        case .site, .furniture:
            return model.snapped(raw)
        default:
            return raw
        }
    }

    private func zoom(by factor: Double, at location: CGPoint, view: PlanFit) {
        guard let model = session?.model, let id = session?.id else { return }
        let next = min(max(zoom * factor, 0.25), 40)
        let paper = view.paper(location)
        pan = PlanFit.pan(keeping: paper, at: location, bounds: fit.current(for: model, session: id), size: view.size,
                          zoom: next)
        zoom = next
    }

    private func drag(to point: CGPoint, view: PlanFit, model: HestiaModel) {
        guard let press else { return }
        if !dragging && hypot(point.x - press.view.x, point.y - press.view.y) > 4 {
            dragging = true
            if tool == .select {
                selection = pick(press.model, view: view, model: model)
            }
        }
        let pointer = Self.pointerState(view.paper(point), tool: tool, anchor: anchor, model: model)
        pointerPosition = pointer.position
        hover = pointer.target
    }

    private func release(at point: CGPoint, view: PlanFit, model: HestiaModel) {
        let here = view.paper(point)
        defer {
            press = nil
            dragging = false
        }
        guard let press, dragging else {
            if press != nil { click(here, view: view, model: model) }
            return
        }
        let start = target(press.model, model), end = target(here, model)
        switch tool {
        case .wall:
            chainStart = chainStart ?? start
            addWallSegment(from: anchor ?? start, to: end)
        case .room:
            addRoomBox(from: start, to: end)
        case .site:
            addSiteBox(from: start, to: end)
        case .select:
            move(by: here, from: press.model)
        default:
            click(here, view: view, model: model)
        }
    }

    private func click(_ point: Point2, view: PlanFit, model: HestiaModel) {
        let paper = model.planTransform?.paper(point)
        switch tool {
        case .select:
            selection = pick(point, view: view, model: model)
            status = describeSelection(model)
        case .wall:
            wallClick(target(point, model))
        case .room, .site:
            let corner = target(point, model)
            guard let start = anchor else {
                anchor = corner
                status = "Click the opposite corner, or type a size such as 12 x 10 and press Return."
                return
            }
            anchor = nil
            if tool == .room { addRoomBox(from: start, to: corner) } else { addSiteBox(from: start, to: corner) }
        case .furniture:
            placeFurniture(at: target(point, model))
        case .delete:
            deleteAt(point, paper: paper, model: model)
        case .stair:
            stairClick(target(point, model))
        case .door:
            if let paper { addOnWall(paper, tool: .door) }
        case .window:
            if let paper { addOnWall(paper, tool: .window) }
        case .opening:
            if let paper { addOnWall(paper, tool: .opening) }
        case .roomFromWalls:
            if let paper { toggleRoomWall(paper) }
        }
    }

    // MARK: - Walls

    private func wallClick(_ point: Point2) {
        guard let start = anchor else {
            anchor = point
            chainStart = point
            typed = ""
            status = "Click the next corner, or type a length and press Return. Esc or right-click stops."
            return
        }
        addWallSegment(from: start, to: point)
    }

    /// Adds a wall and carries on from its end; reaching the chain's first corner closes the outline. A typed
    /// wall is `exact`: its end is not moved to the grid.
    private func addWallSegment(from start: Point2, to end: Point2, exact: Bool = false) {
        guard var current = session else { return }
        do {
            let reached = try current.addWall(from: start, to: end, exact: exact)
            session = current
            typed = ""
            let length = current.model.written(PlanGeometry.distance(start, reached))
            if reached == chainStart {
                anchor = nil
                chainStart = nil
                status = "Closed the outline with a \(length) wall. Room > Pick Walls… makes it a room."
            } else {
                anchor = reached
                status = "Added a \(length) wall. Click the next corner, or Esc to stop. Undo removes it."
            }
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    private func stopChain() {
        let wasDrawing = anchor != nil
        clearDrawing()
        if wasDrawing { status = "Stopped. " + tool.hint }
    }

    // MARK: - Rooms, site, furniture

    private func addRoomBox(from a: Point2, to b: Point2, exact: Bool = false) {
        guard var current = session else { return }
        do {
            try current.addRectangleRoom(from: a, to: b, named: roomName, exact: exact)
            session = current
            let size = PlanGeometry.rectangle(a, b)
            status = "Added \(roomName.isEmpty ? "Room" : roomName), "
                + "\(current.model.written(PlanGeometry.distance(size[0], size[1]))) by "
                + "\(current.model.written(PlanGeometry.distance(size[1], size[2]))). Undo removes it."
            typed = ""
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    private func addSiteBox(from a: Point2, to b: Point2, exact: Bool = false) {
        guard var current = session else { return }
        do {
            try current.addSitePatch(siteKind, from: a, to: b, exact: exact)
            session = current
            status = "Added the \(siteKind.rawValue.lowercased()). Undo removes it."
            typed = ""
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    private func placeFurniture(at point: Point2) {
        guard var current = session, let item = Furniture.item(CatalogItemID(rawValue: furnitureID)) else { return }
        do {
            let id = try current.place(item, at: point, degrees: furnitureTurn)
            session = current
            selection = .placement(id)
            status = "Placed the \(item.name.lowercased()). Click to place another; R turns it. Undo removes it."
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    // MARK: - Select, move, delete

    /// What a click picks: a placed item first, then a wall within a few points, then a terrain patch.
    private func pick(_ point: Point2, view: PlanFit, model: HestiaModel) -> PlanSelection? {
        model.pick(point, slack: 6 / max(view.scale, 1e-12))
    }

    private func describeSelection(_ model: HestiaModel) -> String {
        switch selection {
        case let .placement(id):
            let name = model.document.placements.first { $0.id == id }
                .map { Furniture.item($0.catalogItemID)?.name ?? $0.catalogItemID.rawValue } ?? "Item"
            return "\(name) selected. Drag to move it, R turns it, Delete removes it."
        case let .wall(id):
            let length = model.document.walls.first { $0.id == id }
                .map { model.written(PlanGeometry.distance($0.start, $0.end)) }
            return "A \(length ?? "") wall selected. Drag to move it; the walls joined to it follow. Delete removes it."
        case let .patch(id):
            let name = model.document.terrainPatches.first { $0.id == id }?.name ?? "Area"
            return "\(name) selected. Drag to move it; Delete removes it."
        case let .opening(id):
            let kind = model.document.openings.first { $0.id == id }.map { HestiaModel.kindName($0.kind) } ?? "Opening"
            return "\(kind) selected. Drag to slide it along its wall; the inspector sets its size. Delete removes it."
        case .stair:
            return "Stair selected. Drag to move it; the inspector sets its width. Delete removes it."
        case let .room(id):
            let name = model.document.rooms.first { $0.id == id }?.name ?? "Room"
            return "\(name) selected. The inspector renames it. Delete removes the room, not its walls."
        case nil:
            return Tool.select.hint
        }
    }

    private func move(by end: Point2, from start: Point2) {
        guard var current = session, let selection else { return }
        do {
            guard try Self.commitSelectionMove(&current, selection: selection, from: start, to: end) != nil else {
                return
            }
            session = current
            status = "Moved. Undo puts it back."
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    /// Applies the same resolved displacement drawn by `selectionPreview`, returning what the edit committed.
    static func commitSelectionMove(_ current: inout EditSession, selection: PlanSelection, from start: Point2,
                                    to end: Point2) throws -> SelectionMove? {
        // A room is where its walls are: dragging it is refused, saying so.
        if case .room = selection { try current.move(selection, dx: 0, dy: 0) }
        guard let move = selectionMove(current.model, selection: selection, from: start, to: end) else { return nil }
        switch selection {
        case let .placement(id): try current.movePlacement(id, dx: move.dx, dy: move.dy)
        case let .wall(id): try current.moveWall(id, dx: move.dx, dy: move.dy)
        case let .patch(id): try current.movePatch(id, dx: move.dx, dy: move.dy)
        case let .opening(id):
            guard let offset = move.offsetAlongWall else { return nil }
            try current.slideOpening(id, to: offset)
        case let .stair(id): try current.shiftStair(id, dx: move.dx, dy: move.dy)
        case .room: break
        }
        return move
    }

    private func deleteSelection() {
        guard var current = session, let selection else { return }
        do {
            try current.remove(selection)
            session = current
            self.selection = nil
            status = "Removed. Undo puts it back."
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    private func turnSelection() {
        guard var current = session, case let .placement(id) = selection else { return }
        do {
            try current.movePlacement(id, dx: 0, dy: 0, degrees: 90)
            session = current
            status = "Turned a quarter turn. Undo turns it back."
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    /// Removes a placed item under the point; else what the plan's delete finds (an opening, stair, wall, or
    /// room); else a terrain patch.
    private func deleteAt(_ point: Point2, paper: Point2?, model: HestiaModel) {
        guard var current = session else { return }
        do {
            if let id = model.placementHit(point) {
                try current.removePlacement(id)
                session = current
                status = "Removed the item. Undo puts it back."
            } else if let paper, let removed = try current.delete(atPaper: paper) {
                session = current
                forgetRemoved()
                status = "Removed \(removed.phrase). Undo puts it back."
            } else if let id = model.patchHit(point) {
                try current.removeTerrainPatch(id)
                session = current
                status = "Removed the area. Undo puts it back."
            } else {
                status = "That missed everything that can be removed. " + Tool.delete.hint
            }
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    // MARK: - Keys

    private func keyInput(_ key: PlanKey, model: HestiaModel) {
        switch key {
        case .escape:
            if !typed.isEmpty {
                typed = ""
            } else if anchor != nil || press != nil {
                stopChain()
            } else {
                selection = nil
                status = tool.hint
            }
        case .backspace:
            if typed.isEmpty { deleteSelection() } else { typed.removeLast() }
        case .delete:
            deleteSelection()
        case .enter:
            commitTyped(model)
        case let .text(text):
            if text.lowercased() == "r" && typed.isEmpty {
                if tool == .furniture { furnitureTurn = (furnitureTurn + 90) % 360 } else { turnSelection() }
                return
            }
            let allowed = Set("0123456789.'\"-/ xmc×")
            guard anchor != nil, [.wall, .room, .site].contains(tool),
                  text.allSatisfy({ allowed.contains($0) }) else { return }
            typed += text
            status = "Typed \(typed). Press Return to draw it, Esc to clear."
        }
    }

    /// Draws the wall, room, or area typed: a wall `typed` long from the last corner toward the pointer, or a
    /// room or area `typed` in size ("12 x 10") from its first corner toward the pointer.
    private func commitTyped(_ model: HestiaModel) {
        guard let start = anchor, !typed.isEmpty else { return }
        let metric = model.document.project.displayUnits == .metric
        let toward = hover ?? Point2(x: Length(ticks: start.x.ticks + 1), y: Length(ticks: start.y.ticks + 1))
        if tool == .wall {
            guard let length = LengthEntry.parse(typed, metric: metric) else {
                status = "\u{201C}\(typed)\u{201D} is not a length. Try 12'6\" or 3.8 m."
                return
            }
            let end = PlanGeometry.reach(from: start, toward: toward, length: length)
            addWallSegment(from: start, to: end, exact: true)
            return
        }
        guard let size = LengthEntry.pair(typed, metric: metric) else {
            status = "\u{201C}\(typed)\u{201D} is not a size. Try 12 x 10."
            return
        }
        let corner = PlanGeometry.corner(from: start, toward: toward, width: size.0, depth: size.1)
        anchor = nil
        if tool == .room {
            addRoomBox(from: start, to: corner, exact: true)
        } else {
            addSiteBox(from: start, to: corner, exact: true)
        }
    }

    // MARK: - Preview

    func preview(_ model: HestiaModel) -> Preview {
        var result = Preview()
        guard let hover else { return result }
        let start = anchor ?? (dragging ? press.map { target($0.model, model) } : nil)
        switch tool {
        case .wall, .stair:
            guard let start else { return result }
            result = Self.segmentPreview(model, tool: tool, from: start, to: hover, typed: typed)
        case .room, .site:
            guard let start else { return result }
            result.shapes += PlanOverlay.box(start, hover, fill: tool == .site ? siteKind.look : .woodFloor)
            let corners = PlanGeometry.rectangle(start, hover)
            let size = typed.isEmpty
                ? "\(model.written(PlanGeometry.distance(corners[0], corners[1]))) \u{00D7} "
                    + model.written(PlanGeometry.distance(corners[1], corners[2]))
                : typed + " \u{21A9}"
            if let middle = PlanOverlay.middle(corners) {
                result.labels.append(.init(position: middle, text: size, size: 12, highlighted: true))
            }
        case .furniture:
            if let item = Furniture.item(CatalogItemID(rawValue: furnitureID)) {
                result.shapes += PlanOverlay.furniture(item, at: hover, rotation: .degrees(Int64(furnitureTurn)),
                                                       ghost: true)
            }
        case .select:
            if dragging, let press, let selection {
                result = Self.selectionPreview(model, selection: selection, from: press.model, to: hover)
            }
        default:
            break
        }
        return result
    }

    /// The wall or stair run under the pointer, including the live measurement label.
    static func segmentPreview(_ model: HestiaModel, tool: Tool, from start: Point2, to end: Point2,
                               typed: String) -> Preview {
        guard tool == .wall || tool == .stair else { return Preview() }
        var result = Preview(shapes: [PlanOverlay.band(start, end)])
        // A wall reads its length and direction; a stair, its run.
        let drawn = tool == .wall ? PlanReadout.wall(from: start, to: end, model: model)
            : model.written(PlanGeometry.distance(start, end))
        let length = typed.isEmpty ? drawn : typed + " \u{21A9}"
        if let middle = PlanOverlay.middle([start, end]) {
            result.labels.append(.init(position: middle, text: length, size: 12, highlighted: true))
        }
        return result
    }

    struct SelectionMove: Equatable {
        var dx: Int64
        var dy: Int64
        /// For a door or window, where along its wall the move puts it: its checked landing, which the ghost draws
        /// and the commit sets, so neither works it out again.
        var offsetAlongWall: Length?

        func end(from start: Point2) -> Point2 {
            Point2(x: Length(ticks: start.x.ticks + dx), y: Length(ticks: start.y.ticks + dy))
        }
    }

    /// The grid-resolved displacement shared by a selection's preview, readout, and committed edit.
    static func selectionMove(_ model: HestiaModel, selection: PlanSelection, from start: Point2,
                              to end: Point2) -> SelectionMove? {
        let raw = (dx: end.x.ticks - start.x.ticks, dy: end.y.ticks - start.y.ticks)
        switch selection {
        case let .placement(id):
            guard let placement = model.document.placements.first(where: { $0.id == id }) else { return nil }
            guard raw.dx != 0 || raw.dy != 0 else { return SelectionMove(dx: 0, dy: 0) }
            let target = model.snapped(Point2(x: Length(ticks: placement.position.x.ticks + raw.dx),
                                              y: Length(ticks: placement.position.y.ticks + raw.dy)))
            return SelectionMove(dx: target.x.ticks - placement.position.x.ticks,
                                 dy: target.y.ticks - placement.position.y.ticks)
        case let .wall(id):
            guard model.document.walls.contains(where: { $0.id == id }) else { return nil }
        case let .patch(id):
            guard model.document.terrainPatches.contains(where: { $0.id == id }) else { return nil }
        case let .opening(id):
            // A door or window lands where its wall can take it, or nowhere: no ghost and no readout. The move is
            // how far the regenerated outline's first corner goes, which is what the plan redraws.
            guard let opening = model.document.openings.first(where: { $0.id == id }),
                  let wall = model.document.walls.first(where: { $0.id == opening.wallID }),
                  let target = model.slidOpening(id, dx: raw.dx, dy: raw.dy),
                  let before = model.gap(opening, in: wall).first,
                  let after = model.gap(target, in: wall).first else { return nil }
            return SelectionMove(dx: after.x.ticks - before.x.ticks, dy: after.y.ticks - before.y.ticks,
                                 offsetAlongWall: target.offsetAlongWall)
        case let .stair(id):
            guard model.document.stairs.contains(where: { $0.id == id }) else { return nil }
            let shift = model.stairShift(dx: raw.dx, dy: raw.dy)
            return SelectionMove(dx: shift.dx, dy: shift.dy)
        case .room:
            return nil
        }
        return SelectionMove(dx: HestiaModel.snap(Length(ticks: raw.dx), to: model.snapStep).ticks,
                             dy: HestiaModel.snap(Length(ticks: raw.dy), to: model.snapStep).ticks)
    }

    /// The selected object as it would look after a drag, with the movement readout beside its resolved target.
    static func selectionPreview(_ model: HestiaModel, selection: PlanSelection, from start: Point2,
                                 to end: Point2) -> Preview {
        guard let move = selectionMove(model, selection: selection, from: start, to: end) else { return Preview() }
        let target = move.end(from: start)
        return Preview(shapes: movedGhost(model, selection: selection, move: move),
                       labels: [.init(position: target, text: PlanReadout.move(from: start, to: target, model: model),
                                      size: 12, highlighted: true)])
    }

    /// The selection as it would land after the resolved movement.
    private static func movedGhost(_ model: HestiaModel, selection: PlanSelection,
                                   move: SelectionMove) -> [PlanOverlay.Shape] {
        func shifted(_ point: Point2) -> Point2 {
            Point2(x: Length(ticks: point.x.ticks + move.dx), y: Length(ticks: point.y.ticks + move.dy))
        }
        switch selection {
        case let .placement(id):
            guard let placement = model.document.placements.first(where: { $0.id == id }) else { return [] }
            let item = Furniture.item(placement.catalogItemID) ?? Furniture.placeholder(placement.catalogItemID)
            return PlanOverlay.furniture(item, at: shifted(placement.position), rotation: placement.rotation,
                                         highlighted: true, ghost: true)
        case let .wall(id):
            guard let wall = model.document.walls.first(where: { $0.id == id }) else { return [] }
            return [PlanOverlay.band(shifted(wall.start), shifted(wall.end))]
        case let .patch(id):
            guard let patch = model.document.terrainPatches.first(where: { $0.id == id }) else { return [] }
            let corners = patch.boundary.map(shifted)
            return [PlanOverlay.Shape(points: corners, closed: true,
                                      paint: .stroke(red: 0.95, green: 0.45, blue: 0.05, width: 2, dashed: true))]
        case let .opening(id):
            // Drawn from the landing itself, as the plan draws the opening once it is there.
            guard let offset = move.offsetAlongWall,
                  var opening = model.document.openings.first(where: { $0.id == id }),
                  let wall = model.document.walls.first(where: { $0.id == opening.wallID }) else { return [] }
            opening.offsetAlongWall = offset
            return [ghost(model.gap(opening, in: wall))]
        case let .stair(id):
            guard let stair = model.shiftedStair(id, dx: move.dx, dy: move.dy) else { return [] }
            return [ghost(HestiaModel.stairRectangle(stair))]
        case .room:
            return []
        }
    }

    private static func ghost(_ outline: [Point2]) -> PlanOverlay.Shape {
        PlanOverlay.Shape(points: outline, closed: true,
                          paint: .stroke(red: 0.95, green: 0.45, blue: 0.05, width: 2, dashed: true))
    }
}
