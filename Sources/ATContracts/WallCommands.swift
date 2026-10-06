import Foundation

/// Adds a straight wall on a storey.
public struct AddWallCommand: Command {
    public var wallID: WallID
    public var storeyID: StoreyID
    public var start: Point2
    public var end: Point2
    public var thickness: Length
    public var height: Length
    public var layers: [WallLayer]?
    public var phase: WallPhase?
    public var index: Int?

    public init(
        wallID: WallID, storeyID: StoreyID, start: Point2, end: Point2,
        thickness: Length, height: Length, layers: [WallLayer]? = nil, phase: WallPhase? = nil, index: Int? = nil
    ) {
        self.wallID = wallID
        self.storeyID = storeyID
        self.start = start
        self.end = end
        self.thickness = thickness
        self.height = height
        self.layers = layers
        self.phase = phase
        self.index = index
    }

    public static let commandName = "add_wall"
    public static let toolDescription =
        "Add a straight wall on a storey from a start point to an end point along its centerline."
    public static let parameters = [
        CommandParameter("wallID", .id, "New unique ID for the wall."),
        CommandParameter("storeyID", .id, "ID of the storey the wall stands on."),
        CommandParameter("start", .point2, "Centerline start point in plan."),
        CommandParameter("end", .point2, "Centerline end point in plan; must differ from start."),
        CommandParameter("thickness", .length, "Total wall thickness; greater than zero."),
        CommandParameter("height", .length, "Wall height above the storey floor; greater than zero."),
        wallLayersParameter,
        CommandParameter("phase", .choice, required: false, "Renovation phase; omit for new.",
                         allowedValues: WallPhase.allCases.map(\.rawValue)),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(wallID, in: document.walls.map(\.id))
        _ = try document.storeyIndex(storeyID)
        if start == end { throw CommandValidationError.zeroLengthWall }
        try CommandCheck.positive(thickness, "thickness")
        try CommandCheck.positive(height, "height")
        if let layers { try WallCheck.layers(layers, total: thickness) }
        try CommandCheck.insertionIndex(index, count: document.walls.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let wall = Wall(id: wallID, storeyID: storeyID, start: start, end: end, thickness: thickness, height: height,
                        layers: layers ?? [], phase: phase ?? .new)
        document.walls.insert(wall, atOptional: index)
        return RemoveWallCommand(wallID: wallID).erased
    }
}

/// Moves a wall's centerline endpoints. Hosted openings keep their offsets and must still fit.
public struct MoveWallCommand: Command {
    public var wallID: WallID
    public var start: Point2
    public var end: Point2

    public init(wallID: WallID, start: Point2, end: Point2) {
        self.wallID = wallID
        self.start = start
        self.end = end
    }

    public static let commandName = "move_wall"
    public static let toolDescription =
        "Move or resize a wall by setting new centerline start and end points; its doors and windows must still fit."
    public static let parameters = [
        CommandParameter("wallID", .id, "ID of the wall."),
        CommandParameter("start", .point2, "New centerline start point."),
        CommandParameter("end", .point2, "New centerline end point; must differ from start."),
    ]

    public func validate(against document: ModelDocument) throws {
        var wall = document.walls[try document.wallIndex(wallID)]
        if start == end { throw CommandValidationError.zeroLengthWall }
        wall.start = start
        wall.end = end
        try document.checkOpenings(on: wall)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.wallIndex(wallID)
        let previous = document.walls[index]
        document.walls[index].start = start
        document.walls[index].end = end
        return MoveWallCommand(wallID: wallID, start: previous.start, end: previous.end).erased
    }
}

/// Changes a wall's total thickness.
public struct SetWallThicknessCommand: Command {
    public var wallID: WallID
    public var thickness: Length

    public init(wallID: WallID, thickness: Length) {
        self.wallID = wallID
        self.thickness = thickness
    }

    public static let commandName = "set_wall_thickness"
    public static let toolDescription =
        "Set the total thickness of a homogeneous wall, centered on its centerline; layered walls use set_wall_layers."
    public static let parameters = [
        CommandParameter("wallID", .id, "ID of the wall."),
        CommandParameter("thickness", .length, "New total thickness; greater than zero."),
    ]

    public func validate(against document: ModelDocument) throws {
        let wall = document.walls[try document.wallIndex(wallID)]
        try CommandCheck.positive(thickness, "thickness")
        if !wall.layers.isEmpty { throw CommandValidationError.invalidValue(parameter: "thickness") }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.wallIndex(wallID)
        let previous = document.walls[index].thickness
        document.walls[index].thickness = thickness
        return SetWallThicknessCommand(wallID: wallID, thickness: previous).erased
    }
}

/// Changes a wall's height. Hosted openings must still fit below the top.
public struct SetWallHeightCommand: Command {
    public var wallID: WallID
    public var height: Length

    public init(wallID: WallID, height: Length) {
        self.wallID = wallID
        self.height = height
    }

    public static let commandName = "set_wall_height"
    public static let toolDescription =
        "Set the height of an existing wall above its storey floor; its doors and windows must still fit."
    public static let parameters = [
        CommandParameter("wallID", .id, "ID of the wall."),
        CommandParameter("height", .length, "New wall height; greater than zero."),
    ]

    public func validate(against document: ModelDocument) throws {
        var wall = document.walls[try document.wallIndex(wallID)]
        try CommandCheck.positive(height, "height")
        wall.height = height
        try document.checkOpenings(on: wall)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.wallIndex(wallID)
        let previous = document.walls[index].height
        document.walls[index].height = height
        return SetWallHeightCommand(wallID: wallID, height: previous).erased
    }
}

/// Removes a wall that hosts no openings and bounds no rooms.
public struct RemoveWallCommand: Command {
    public var wallID: WallID

    public init(wallID: WallID) {
        self.wallID = wallID
    }

    public static let commandName = "remove_wall"
    public static let toolDescription =
        "Remove a wall; first remove its doors and windows and take it out of every room boundary."
    public static let parameters = [
        CommandParameter("wallID", .id, "ID of the wall to remove."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.wallIndex(wallID)
        if document.openings.contains(where: { $0.wallID == wallID })
            || document.rooms.contains(where: { $0.boundaryWallIDs.contains(wallID) }) {
            throw CommandValidationError.hasDependents(wallID.rawValue)
        }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.wallIndex(wallID)
        let removed = document.walls.remove(at: index)
        return AddWallCommand(
            wallID: removed.id, storeyID: removed.storeyID, start: removed.start, end: removed.end,
            thickness: removed.thickness, height: removed.height, layers: removed.layers, phase: removed.phase,
            index: index
        ).erased
    }
}

/// Replaces a wall's layer build-up; the wall thickness becomes the sum of the layers.
public struct SetWallLayersCommand: Command {
    public var wallID: WallID
    public var layers: [WallLayer]
    /// Thickness to keep when `layers` is empty; ignored otherwise. Undo uses it.
    public var thickness: Length?

    public init(wallID: WallID, layers: [WallLayer], thickness: Length? = nil) {
        self.wallID = wallID
        self.layers = layers
        self.thickness = thickness
    }

    var resolvedThickness: Length? {
        layers.isEmpty ? thickness : Length(ticks: layers.reduce(0) { $0 + $1.thickness.ticks })
    }

    public static let commandName = "set_wall_layers"
    public static let toolDescription =
        "Set a wall's layer build-up, such as gypsum, studs, and siding; the wall thickness becomes their sum."
    public static let parameters = [
        CommandParameter("wallID", .id, "ID of the wall."),
        CommandParameter("layers", .objectList,
                         "Layers from the wall's left face to its right face, looking from start to end, each "
                            + "{\"material\", \"function\", \"thickness\": Length}; empty for a homogeneous wall."),
        CommandParameter("thickness", .length, required: false, "Thickness to use when layers is empty."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.wallIndex(wallID)
        try WallCheck.layers(layers, total: nil)
        if let resolvedThickness { try CommandCheck.positive(resolvedThickness, "thickness") }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.wallIndex(wallID)
        let previous = document.walls[index]
        document.walls[index].layers = layers
        if let resolvedThickness { document.walls[index].thickness = resolvedThickness }
        return SetWallLayersCommand(wallID: wallID, layers: previous.layers, thickness: previous.thickness).erased
    }
}

/// Sets a wall's renovation phase.
public struct SetWallPhaseCommand: Command {
    public var wallID: WallID
    public var phase: WallPhase

    public init(wallID: WallID, phase: WallPhase) {
        self.wallID = wallID
        self.phase = phase
    }

    public static let commandName = "set_wall_phase"
    public static let toolDescription = "Mark a wall as new, existing, or to be demolished."
    public static let parameters = [
        CommandParameter("wallID", .id, "ID of the wall."),
        CommandParameter("phase", .choice, "Renovation phase.", allowedValues: WallPhase.allCases.map(\.rawValue)),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.wallIndex(wallID)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let index = try document.wallIndex(wallID)
        let previous = document.walls[index].phase
        document.walls[index].phase = phase
        return SetWallPhaseCommand(wallID: wallID, phase: previous).erased
    }
}

let wallLayersParameter = CommandParameter(
    "layers", .objectList, required: false,
    "Optional build-up from left face to right face, each {\"material\", \"function\", \"thickness\": Length}; "
        + "thicknesses must add up to the wall thickness."
)

enum WallCheck {
    static func layers(_ layers: [WallLayer], total: Length?) throws {
        for layer in layers {
            _ = try CommandCheck.name(layer.material)
            try CommandCheck.positive(layer.thickness, "layers")
        }
        if let total, !layers.isEmpty, layers.reduce(0, { $0 + $1.thickness.ticks }) != total.ticks {
            throw CommandValidationError.invalidValue(parameter: "layers")
        }
    }
}
