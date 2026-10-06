import Foundation

/// Adds a stair rising from a storey to the one above.
public struct AddStairCommand: Command {
    public var stairID: StairID
    public var storeyID: StoreyID
    public var kind: StairKind?
    public var runStart: Point2
    public var runEnd: Point2
    public var width: Length
    public var riserCount: Int
    public var riserHeight: Length
    public var index: Int?

    public init(
        stairID: StairID, storeyID: StoreyID, kind: StairKind? = nil, runStart: Point2, runEnd: Point2,
        width: Length, riserCount: Int, riserHeight: Length, index: Int? = nil
    ) {
        self.stairID = stairID
        self.storeyID = storeyID
        self.kind = kind
        self.runStart = runStart
        self.runEnd = runEnd
        self.width = width
        self.riserCount = riserCount
        self.riserHeight = riserHeight
        self.index = index
    }

    public static let commandName = "add_stair"
    public static let toolDescription =
        "Add a stair on a storey, climbing along a plan run line from its bottom riser to the floor above."
    public static let parameters = [
        CommandParameter("stairID", .id, "New unique ID for the stair."),
        CommandParameter("storeyID", .id, "ID of the storey the stair starts on."),
        CommandParameter("kind", .choice, required: false, "Stair shape; omit for straight.",
                         allowedValues: StairKind.allCases.map(\.rawValue)),
        CommandParameter("runStart", .point2, "Plan point at the bottom riser, on the stair centerline."),
        CommandParameter("runEnd", .point2, "Plan point at the top edge, on the stair centerline."),
        CommandParameter("width", .length, "Clear stair width; greater than zero."),
        CommandParameter("riserCount", .integer, "Number of risers; at least 2."),
        CommandParameter("riserHeight", .length, "Height of each riser; greater than zero."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(stairID, in: document.stairs.map(\.id))
        _ = try document.storeyIndex(storeyID)
        try StairCheck.run(runStart, runEnd)
        try CommandCheck.positive(width, "width")
        try StairCheck.risers(riserCount, riserHeight)
        try CommandCheck.insertionIndex(index, count: document.stairs.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let stair = Stair(id: stairID, storeyID: storeyID, kind: kind ?? .straight, runStart: runStart,
                          runEnd: runEnd, width: width, riserCount: riserCount, riserHeight: riserHeight)
        document.stairs.insert(stair, atOptional: index)
        return RemoveStairCommand(stairID: stairID).erased
    }
}

/// Moves a stair's run line, which also sets its plan length and direction.
public struct MoveStairCommand: Command {
    public var stairID: StairID
    public var runStart: Point2
    public var runEnd: Point2

    public init(stairID: StairID, runStart: Point2, runEnd: Point2) {
        self.stairID = stairID
        self.runStart = runStart
        self.runEnd = runEnd
    }

    public static let commandName = "move_stair"
    public static let toolDescription = "Move a stair by setting new bottom and top points of its run line."
    public static let parameters = [
        CommandParameter("stairID", .id, "ID of the stair."),
        CommandParameter("runStart", .point2, "New bottom point of the run line."),
        CommandParameter("runEnd", .point2, "New top point of the run line."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.stairIndex(stairID)
        try StairCheck.run(runStart, runEnd)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.stairIndex(stairID)
        let previous = document.stairs[index]
        document.stairs[index].runStart = runStart
        document.stairs[index].runEnd = runEnd
        return MoveStairCommand(stairID: stairID, runStart: previous.runStart, runEnd: previous.runEnd).erased
    }
}

/// Changes a stair's riser count, riser height, and width.
public struct SetStairRisersCommand: Command {
    public var stairID: StairID
    public var riserCount: Int
    public var riserHeight: Length
    public var width: Length

    public init(stairID: StairID, riserCount: Int, riserHeight: Length, width: Length) {
        self.stairID = stairID
        self.riserCount = riserCount
        self.riserHeight = riserHeight
        self.width = width
    }

    public static let commandName = "set_stair_risers"
    public static let toolDescription = "Set a stair's number of risers, riser height, and clear width."
    public static let parameters = [
        CommandParameter("stairID", .id, "ID of the stair."),
        CommandParameter("riserCount", .integer, "Number of risers; at least 2."),
        CommandParameter("riserHeight", .length, "Height of each riser; greater than zero."),
        CommandParameter("width", .length, "Clear stair width; greater than zero."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.stairIndex(stairID)
        try StairCheck.risers(riserCount, riserHeight)
        try CommandCheck.positive(width, "width")
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.stairIndex(stairID)
        let previous = document.stairs[index]
        document.stairs[index].riserCount = riserCount
        document.stairs[index].riserHeight = riserHeight
        document.stairs[index].width = width
        return SetStairRisersCommand(stairID: stairID, riserCount: previous.riserCount,
                                     riserHeight: previous.riserHeight, width: previous.width).erased
    }
}

/// Removes a stair.
public struct RemoveStairCommand: Command {
    public var stairID: StairID

    public init(stairID: StairID) {
        self.stairID = stairID
    }

    public static let commandName = "remove_stair"
    public static let toolDescription = "Remove a stair."
    public static let parameters = [CommandParameter("stairID", .id, "ID of the stair to remove.")]

    public func validate(against document: ModelDocument) throws {
        _ = try document.stairIndex(stairID)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let index = try document.stairIndex(stairID)
        let removed = document.stairs.remove(at: index)
        return AddStairCommand(
            stairID: removed.id, storeyID: removed.storeyID, kind: removed.kind, runStart: removed.runStart,
            runEnd: removed.runEnd, width: removed.width, riserCount: removed.riserCount,
            riserHeight: removed.riserHeight, index: index
        ).erased
    }
}

enum StairCheck {
    static func run(_ start: Point2, _ end: Point2) throws {
        if start == end { throw CommandValidationError.invalidValue(parameter: "runEnd") }
    }

    static func risers(_ count: Int, _ height: Length) throws {
        if count < 2 { throw CommandValidationError.invalidValue(parameter: "riserCount") }
        try CommandCheck.positive(height, "riserHeight")
    }
}

/// Adds a flat slab.
public struct AddSlabCommand: Command {
    public var slabID: SlabID
    public var storeyID: StoreyID
    public var kind: SlabKind?
    public var outline: [Point2]
    public var thickness: Length
    public var topOffset: Length?
    public var index: Int?

    public init(
        slabID: SlabID, storeyID: StoreyID, kind: SlabKind? = nil, outline: [Point2],
        thickness: Length, topOffset: Length? = nil, index: Int? = nil
    ) {
        self.slabID = slabID
        self.storeyID = storeyID
        self.kind = kind
        self.outline = outline
        self.thickness = thickness
        self.topOffset = topOffset
        self.index = index
    }

    public static let commandName = "add_slab"
    public static let toolDescription = "Add a flat floor, foundation, or ceiling slab with a counterclockwise plan outline."
    public static let parameters = [
        CommandParameter("slabID", .id, "New unique ID for the slab."),
        CommandParameter("storeyID", .id, "ID of the storey the slab belongs to."),
        CommandParameter("kind", .choice, required: false, "Slab use; omit for floor.",
                         allowedValues: SlabKind.allCases.map(\.rawValue)),
        CommandParameter("outline", .point2List, "Plan outline, at least three points, counterclockwise."),
        CommandParameter("thickness", .length, "Slab thickness; greater than zero."),
        CommandParameter("topOffset", .length, required: false,
                         "Height of the slab top above the storey floor; omit for zero."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(slabID, in: document.slabs.map(\.id))
        _ = try document.storeyIndex(storeyID)
        try CommandCheck.polygon(outline)
        try CommandCheck.positive(thickness, "thickness")
        try CommandCheck.insertionIndex(index, count: document.slabs.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let slab = Slab(id: slabID, storeyID: storeyID, kind: kind ?? .floor, outline: outline,
                        thickness: thickness, topOffset: topOffset ?? Length(ticks: 0))
        document.slabs.insert(slab, atOptional: index)
        return RemoveSlabCommand(slabID: slabID).erased
    }
}

/// Replaces a slab's outline.
public struct SetSlabOutlineCommand: Command {
    public var slabID: SlabID
    public var outline: [Point2]

    public init(slabID: SlabID, outline: [Point2]) {
        self.slabID = slabID
        self.outline = outline
    }

    public static let commandName = "set_slab_outline"
    public static let toolDescription = "Replace a slab's plan outline with a new counterclockwise outline."
    public static let parameters = [
        CommandParameter("slabID", .id, "ID of the slab."),
        CommandParameter("outline", .point2List, "New plan outline, at least three points, counterclockwise."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.slabIndex(slabID)
        try CommandCheck.polygon(outline)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.slabIndex(slabID)
        let previous = document.slabs[index].outline
        document.slabs[index].outline = outline
        return SetSlabOutlineCommand(slabID: slabID, outline: previous).erased
    }
}

/// Removes a slab.
public struct RemoveSlabCommand: Command {
    public var slabID: SlabID

    public init(slabID: SlabID) {
        self.slabID = slabID
    }

    public static let commandName = "remove_slab"
    public static let toolDescription = "Remove a slab."
    public static let parameters = [CommandParameter("slabID", .id, "ID of the slab to remove.")]

    public func validate(against document: ModelDocument) throws {
        _ = try document.slabIndex(slabID)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let index = try document.slabIndex(slabID)
        let removed = document.slabs.remove(at: index)
        return AddSlabCommand(
            slabID: removed.id, storeyID: removed.storeyID, kind: removed.kind, outline: removed.outline,
            thickness: removed.thickness, topOffset: removed.topOffset, index: index
        ).erased
    }
}
