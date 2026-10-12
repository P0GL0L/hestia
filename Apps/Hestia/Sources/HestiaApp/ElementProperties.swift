import ATContracts
import ATDrawings
import Foundation

/// One line of the inspector for the selected element: a name and its value, and, when it can be changed there,
/// the field that changes it.
struct ElementProperty: Equatable {
    /// What a typed value changes.
    enum Field: Equatable {
        case wallLength, wallThickness, wallHeight
        case openingWidth, openingHeight, openingSill, openingOffset
        case roomName
        case stairWidth
        /// The text the drawings print on that dimension instead of the measured figure; empty prints the figure.
        case dimensionLabel(DimensionFace)
    }

    var label: String
    var value: String
    var field: Field?
}

extension HestiaModel {
    /// What the inspector says about a selection: a title, then its figures, the changeable ones with a field.
    /// Nil when the element is gone.
    func properties(of selection: PlanSelection) -> (title: String, rows: [ElementProperty])? {
        switch selection {
        case let .wall(id):
            guard let wall = document.walls.first(where: { $0.id == id }) else { return nil }
            return ("Wall", [
                ElementProperty(label: "Length", value: written(PlanGeometry.distance(wall.start, wall.end)),
                                field: .wallLength),
                ElementProperty(label: "Thickness", value: written(wall.thickness), field: .wallThickness),
                ElementProperty(label: "Height", value: written(wall.height), field: .wallHeight),
                ElementProperty(label: "Plan label", value: document.dimensionOverride(
                    for: wall.id.rawValue, face: Self.chainFaces(wall)[0]) ?? "",
                                field: .dimensionLabel(Self.chainFaces(wall)[0])),
            ])
        case let .opening(id):
            guard let opening = document.openings.first(where: { $0.id == id }) else { return nil }
            var rows = [
                ElementProperty(label: "Width", value: written(opening.width), field: .openingWidth),
                ElementProperty(label: "Height", value: written(opening.height), field: .openingHeight),
            ]
            if opening.kind.isWindow {
                rows.append(ElementProperty(label: "Sill", value: written(opening.sillHeight), field: .openingSill))
            }
            rows.append(ElementProperty(label: "From wall start", value: written(opening.offsetAlongWall),
                                        field: .openingOffset))
            rows.append(ElementProperty(label: "Schedule width",
                                        value: document.dimensionOverride(for: opening.id.rawValue, face: .width) ?? "",
                                        field: .dimensionLabel(.width)))
            return (Self.kindName(opening.kind), rows)
        case let .room(id):
            guard let room = document.rooms.first(where: { $0.id == id }) else { return nil }
            var rows = [ElementProperty(label: "Name", value: room.name, field: .roomName)]
            if let outline = RoomOutline.centerline(of: room, in: document) {
                rows.append(ElementProperty(label: "Area", value: Self.area(outline, metric: metric)))
            }
            rows.append(ElementProperty(label: "Floor", value: room.floorFinish ?? "Default"))
            for (label, face) in [("Width label", DimensionFace.width), ("Depth label", .depth)] {
                rows.append(ElementProperty(label: label,
                                            value: document.dimensionOverride(for: room.id.rawValue, face: face) ?? "",
                                            field: .dimensionLabel(face)))
            }
            return ("Room", rows)
        case let .stair(id):
            guard let stair = document.stairs.first(where: { $0.id == id }) else { return nil }
            let rise = Length(ticks: stair.riserHeight.ticks * Int64(stair.riserCount))
            return ("Stair", [
                ElementProperty(label: "Width", value: written(stair.width), field: .stairWidth),
                ElementProperty(label: "Risers", value: "\(stair.riserCount) at \(written(stair.riserHeight))"),
                ElementProperty(label: "Rise", value: written(rise)),
                ElementProperty(label: "Run", value: written(PlanGeometry.distance(stair.runStart, stair.runEnd))),
            ])
        case let .placement(id):
            guard let placement = document.placements.first(where: { $0.id == id }) else { return nil }
            let degrees = Double(placement.rotation.microDegrees) / 1_000_000
            return (Furniture.item(placement.catalogItemID)?.name ?? "Item", [
                ElementProperty(label: "Turned", value: String(format: "%g\u{00B0}", degrees)),
            ])
        case let .patch(id):
            guard let patch = document.terrainPatches.first(where: { $0.id == id }) else { return nil }
            return (patch.name, [ElementProperty(label: "Area", value: Self.area(patch.boundary, metric: metric))])
        }
    }

    /// What the Select tool picks at a model point: a placed item; then a door, window, or opening; a wall within
    /// half its thickness and `slack` ticks; a stair; a room the point is inside; else a site area.
    func pick(_ point: Point2, slack: Double) -> PlanSelection? {
        if let id = placementHit(point) { return .placement(id) }
        let paper = planTransform?.paper(point)
        if let paper, let id = openingHit(paper: paper) { return .opening(id) }
        if let id = wallNear(point, slack: slack) { return .wall(id) }
        if let paper, let id = stairHit(paper: paper) { return .stair(id) }
        if let paper, let id = roomHit(paper: paper) { return .room(id) }
        if let id = patchHit(point) { return .patch(id) }
        return nil
    }

    /// The outline the plan draws around a selected opening, stair, or room, in model space; nil for the rest,
    /// which the plan marks its own way, or when the element is gone.
    func outline(of selection: PlanSelection) -> [Point2]? {
        switch selection {
        case let .opening(id):
            guard let opening = document.openings.first(where: { $0.id == id }),
                  let wall = document.walls.first(where: { $0.id == opening.wallID }) else { return nil }
            return gap(opening, in: wall)
        case let .stair(id):
            return document.stairs.first { $0.id == id }.map(Self.stairRectangle)
        case let .room(id):
            return document.rooms.first { $0.id == id }.flatMap { RoomOutline.centerline(of: $0, in: document) }
        case .placement, .wall, .patch:
            return nil
        }
    }

    private var metric: Bool { document.project.displayUnits == .metric }

    /// The exterior chains a wall's segment can print on: south and north for a wall running east-west, west and
    /// east for one running north-south, every face for a wall at an angle (which no chain measures alone).
    static func chainFaces(_ wall: Wall) -> [DimensionFace] {
        if wall.start.y == wall.end.y { return [.south, .north] }
        if wall.start.x == wall.end.x { return [.west, .east] }
        return [.south, .east, .north, .west]
    }

    /// An opening kind as a person names it: "Single door", "Floor-to-ceiling window", "Cased opening".
    static func kindName(_ kind: OpeningKind) -> String {
        switch kind {
        case .floorToCeilingWindow: return "Floor-to-ceiling window"
        default:
            var words = ""
            for character in kind.rawValue {
                if character.isUppercase { words += " " + character.lowercased() } else { words.append(character) }
            }
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }

    /// A polygon's area in square feet, or square metres in a metric project, to one place.
    static func area(_ points: [Point2], metric: Bool) -> String {
        var twice = 0.0
        for (a, b) in zip(points, points.dropFirst() + points.prefix(1)) {
            twice += Double(a.x.ticks) * Double(b.y.ticks) - Double(b.x.ticks) * Double(a.y.ticks)
        }
        let ticks = abs(twice) / 2
        if metric {
            let perMetre = Double(Length.millimeters(1000).ticks)
            return String(format: "%.1f m\u{00B2}", ticks / (perMetre * perMetre))
        }
        let perFoot = Double(Length.feet(1).ticks)
        return String(format: "%.1f sq ft", ticks / (perFoot * perFoot))
    }
}

extension HestiaModel {
    /// Where a door or window lands when dragged by (`dx`, `dy`): its offset along its wall moved by the part of
    /// the drag that runs along the wall, to the grid. Nil when it has no wall, or when the wall can't take it
    /// there (past an end, or over another door or window), as the model's own check of that move decides.
    func slidOpening(_ id: OpeningID, dx: Int64, dy: Int64) -> Opening? {
        guard var opening = document.openings.first(where: { $0.id == id }),
              let wall = document.walls.first(where: { $0.id == opening.wallID }) else { return nil }
        let ux = Double(wall.end.x.ticks - wall.start.x.ticks), uy = Double(wall.end.y.ticks - wall.start.y.ticks)
        let length = (ux * ux + uy * uy).squareRoot()
        guard length > 0 else { return nil }
        let along = (Double(dx) * ux + Double(dy) * uy) / length
        let step = HestiaModel.snap(Length(ticks: Int64(along.rounded())), to: snapStep).ticks
        opening.offsetAlongWall = Length(ticks: opening.offsetAlongWall.ticks + step)
        let move = MoveOpeningCommand(openingID: id, offsetAlongWall: opening.offsetAlongWall)
        guard (try? move.validate(against: document)) != nil else { return nil }
        return opening
    }

    /// How far a stair moves for a drag of (`dx`, `dy`): each way to the grid, as a move commits it.
    func stairShift(dx: Int64, dy: Int64) -> (dx: Int64, dy: Int64) {
        (HestiaModel.snap(Length(ticks: dx), to: snapStep).ticks,
         HestiaModel.snap(Length(ticks: dy), to: snapStep).ticks)
    }

    /// A stair with its whole run moved by exactly (`dx`, `dy`); nil when the stair is gone.
    func shiftedStair(_ id: StairID, dx: Int64, dy: Int64) -> Stair? {
        guard var stair = document.stairs.first(where: { $0.id == id }) else { return nil }
        func shifted(_ point: Point2) -> Point2 {
            Point2(x: Length(ticks: point.x.ticks + dx), y: Length(ticks: point.y.ticks + dy))
        }
        stair.runStart = shifted(stair.runStart)
        stair.runEnd = shifted(stair.runEnd)
        return stair
    }
}

extension EditSession {
    /// Changes the selected element's `field` to the typed `text`, as one undoable step, and says what changed.
    /// A length the project's units can't read, or a change the model refuses, is refused with a sentence.
    @discardableResult
    mutating func set(_ field: ElementProperty.Field, to text: String, on selection: PlanSelection) throws -> String {
        let metric = model.document.project.displayUnits == .metric
        func length() throws -> Length {
            guard let value = LengthEntry.parse(text, metric: metric, allowingZero: true) else {
                throw HestiaModel.LoadError(message: "\u{201C}\(text)\u{201D} is not a length. Try "
                    + (metric ? "3.8 m or 380 cm." : "12'6\" or 150\"."))
            }
            return value
        }
        func positive() throws -> Length {
            let value = try length()
            guard value.ticks > 0 else { throw HestiaModel.LoadError(message: "It needs a length above zero.") }
            return value
        }
        switch (field, selection) {
        case let (.wallLength, .wall(id)):
            try setWallLength(id, to: positive())
            return "Wall is now \(text) long. Walls joined at its end followed it."
        case let (.wallThickness, .wall(id)):
            try perform(SetWallThicknessCommand(wallID: id, thickness: positive()).erased)
            return "Wall is now \(text) thick."
        case let (.wallHeight, .wall(id)):
            try perform(SetWallHeightCommand(wallID: id, height: positive()).erased)
            return "Wall is now \(text) tall."
        case let (.openingWidth, .opening(id)), let (.openingHeight, .opening(id)), let (.openingSill, .opening(id)):
            guard let opening = model.document.openings.first(where: { $0.id == id }) else { return "" }
            let width = field == .openingWidth ? try positive() : opening.width
            let height = field == .openingHeight ? try positive() : opening.height
            let sill = field == .openingSill ? try length() : opening.sillHeight
            try perform(ResizeOpeningCommand(openingID: id, width: width, height: height, sillHeight: sill).erased)
            return "Resized. Undo puts it back."
        case let (.openingOffset, .opening(id)):
            try perform(MoveOpeningCommand(openingID: id, offsetAlongWall: length()).erased)
            return "Moved along its wall. Undo puts it back."
        case let (.roomName, .room(id)):
            let name = text.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw HestiaModel.LoadError(message: "A room needs a name.") }
            try perform(RenameRoomCommand(roomID: id, newName: name).erased)
            return "Renamed the room \(name)."
        case let (.dimensionLabel(face), selection):
            return try setDimensionLabel(text, face: face, on: selection)
        case let (.stairWidth, .stair(id)):
            guard let stair = model.document.stairs.first(where: { $0.id == id }) else { return "" }
            try perform(SetStairRisersCommand(stairID: id, riserCount: stair.riserCount,
                                              riserHeight: stair.riserHeight, width: positive()).erased)
            return "Stair is now \(text) wide."
        default:
            return ""
        }
    }

    /// Prints `text` on the selection's dimension instead of the measured figure, or the figure again when `text`
    /// is empty, as one step. A wall's label goes on whichever exterior chain measures it on its own.
    private mutating func setDimensionLabel(_ text: String, face: DimensionFace,
                                            on selection: PlanSelection) throws -> String {
        let id: UUID
        var faces = [face]
        switch selection {
        case let .wall(wallID):
            guard let wall = model.document.walls.first(where: { $0.id == wallID }) else { return "" }
            id = wallID.rawValue
            faces = HestiaModel.chainFaces(wall)
        case let .opening(openingID): id = openingID.rawValue
        case let .room(roomID): id = roomID.rawValue
        default: return ""
        }
        let label = text.trimmingCharacters(in: .whitespaces)
        let commands: [AnyCommand] = faces.compactMap { face in
            if label.isEmpty {
                guard model.document.dimensionOverride(for: id, face: face) != nil else { return nil }
                return ClearDimensionOverrideCommand(elementID: id, face: face).erased
            }
            return SetDimensionOverrideCommand(elementID: id, face: face, text: label).erased
        }
        try perform(batch: commands)
        return label.isEmpty ? "The drawings print the measured figure again."
            : "The drawings now print \u{201C}\(label)\u{201D} there."
    }

    /// Moves what is selected by a model offset, as one step: an item, a wall (its joined walls following), or an
    /// area by the offset on the grid; a door or window slides along its wall by as much of it as runs that way;
    /// a stair shifts whole. A room is where its walls are, so moving one is refused with a sentence.
    mutating func move(_ selection: PlanSelection, dx: Int64, dy: Int64) throws {
        switch selection {
        case let .placement(id): try movePlacement(id, dx: dx, dy: dy)
        case let .wall(id): try moveWall(id, dx: dx, dy: dy)
        case let .patch(id): try movePatch(id, dx: dx, dy: dy)
        case let .opening(id):
            guard let opening = model.document.openings.first(where: { $0.id == id }) else { return }
            try slideOpening(id, to: try landing(of: opening, dx: dx, dy: dy))
        case let .stair(id):
            let (sx, sy) = model.stairShift(dx: dx, dy: dy)
            try shiftStair(id, dx: sx, dy: sy)
        case .room:
            throw HestiaModel.LoadError(message: "A room is where its walls are. Move a wall to change it.")
        }
    }

    /// Where a dragged door or window lands; a place its wall can't take is refused with a sentence.
    private func landing(of opening: Opening, dx: Int64, dy: Int64) throws -> Length {
        guard let target = model.slidOpening(opening.id, dx: dx, dy: dy) else {
            throw HestiaModel.LoadError(message: "Its wall has no room for it there. A door or window stays between "
                + "the wall's ends and clear of the others on it.")
        }
        return target.offsetAlongWall
    }

    /// Puts a door or window `offset` along its wall, as one step; nothing, and no step, when it is already there.
    mutating func slideOpening(_ id: OpeningID, to offset: Length) throws {
        guard let opening = model.document.openings.first(where: { $0.id == id }),
              opening.offsetAlongWall != offset else { return }
        try perform(MoveOpeningCommand(openingID: id, offsetAlongWall: offset).erased)
    }

    /// Moves a stair's whole run by exactly (`dx`, `dy`), as one step; nothing, and no step, for no movement.
    mutating func shiftStair(_ id: StairID, dx: Int64, dy: Int64) throws {
        guard dx != 0 || dy != 0, let stair = model.shiftedStair(id, dx: dx, dy: dy) else { return }
        try perform(MoveStairCommand(stairID: id, runStart: stair.runStart, runEnd: stair.runEnd).erased)
    }

    /// Removes what is selected, as one step. A wall with doors, windows, or rooms on it is refused.
    mutating func remove(_ selection: PlanSelection) throws {
        switch selection {
        case let .placement(id): try removePlacement(id)
        case let .wall(id): try removeWall(id)
        case let .patch(id): try removeTerrainPatch(id)
        case let .opening(id): try perform(RemoveOpeningCommand(openingID: id).erased)
        case let .stair(id): try perform(RemoveStairCommand(stairID: id).erased)
        case let .room(id): try perform(RemoveRoomCommand(roomID: id).erased)
        }
    }

    /// Makes a wall `length` long by moving its end along its line; every wall of its storey that met the old
    /// end meets the new one.
    mutating func setWallLength(_ id: WallID, to length: Length) throws {
        guard let wall = model.document.walls.first(where: { $0.id == id }) else { return }
        let end = PlanGeometry.reach(from: wall.start, toward: wall.end, length: length)
        guard end != wall.end else { return }
        var commands = [MoveWallCommand(wallID: id, start: wall.start, end: end).erased]
        for other in model.document.walls where other.id != id && other.storeyID == wall.storeyID {
            let start = other.start == wall.end ? end : other.start
            let otherEnd = other.end == wall.end ? end : other.end
            if start != other.start || otherEnd != other.end {
                commands.append(MoveWallCommand(wallID: other.id, start: start, end: otherEnd).erased)
            }
        }
        try perform(batch: commands)
    }
}
