import Foundation

/// Adds a door or window opening hosted in a wall.
public struct AddOpeningCommand: Command {
    public var openingID: OpeningID
    public var wallID: WallID
    public var offsetAlongWall: Length
    public var width: Length
    public var height: Length
    public var sillHeight: Length
    public var index: Int?

    public init(
        openingID: OpeningID, wallID: WallID, offsetAlongWall: Length,
        width: Length, height: Length, sillHeight: Length, index: Int? = nil
    ) {
        self.openingID = openingID
        self.wallID = wallID
        self.offsetAlongWall = offsetAlongWall
        self.width = width
        self.height = height
        self.sillHeight = sillHeight
        self.index = index
    }

    var opening: Opening {
        Opening(
            id: openingID, wallID: wallID, offsetAlongWall: offsetAlongWall,
            width: width, height: height, sillHeight: sillHeight
        )
    }

    public static let commandName = "add_opening"
    public static let toolDescription =
        "Add a door or window opening in a wall, placed by its distance from the wall start; it must fit inside the wall."
    public static let parameters = [
        CommandParameter("openingID", .id, "New unique ID for the opening."),
        CommandParameter("wallID", .id, "ID of the host wall."),
        CommandParameter("offsetAlongWall", .length, "Distance from the wall's start point to the opening's near edge."),
        CommandParameter("width", .length, "Opening width along the wall; greater than zero."),
        CommandParameter("height", .length, "Opening height; greater than zero."),
        CommandParameter("sillHeight", .length, "Height of the opening's bottom above the floor; zero for a door."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(openingID, in: document.openings.map(\.id))
        let wall = document.walls[try document.wallIndex(wallID)]
        try OpeningCheck.dimensions(opening)
        try CommandCheck.insertionIndex(index, count: document.openings.count)
        try document.checkOpenings(on: wall, replacing: opening)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        document.openings.insert(opening, atOptional: index)
        return RemoveOpeningCommand(openingID: openingID).erased
    }
}

/// Slides an opening along its host wall.
public struct MoveOpeningCommand: Command {
    public var openingID: OpeningID
    public var offsetAlongWall: Length

    public init(openingID: OpeningID, offsetAlongWall: Length) {
        self.openingID = openingID
        self.offsetAlongWall = offsetAlongWall
    }

    public static let commandName = "move_opening"
    public static let toolDescription =
        "Slide an existing door or window along its wall to a new distance from the wall start."
    public static let parameters = [
        CommandParameter("openingID", .id, "ID of the opening."),
        CommandParameter("offsetAlongWall", .length, "New distance from the wall's start point to the near edge."),
    ]

    public func validate(against document: ModelDocument) throws {
        var opening = document.openings[try document.openingIndex(openingID)]
        opening.offsetAlongWall = offsetAlongWall
        try OpeningCheck.fits(opening, in: document)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.openingIndex(openingID)
        let previous = document.openings[index].offsetAlongWall
        document.openings[index].offsetAlongWall = offsetAlongWall
        return MoveOpeningCommand(openingID: openingID, offsetAlongWall: previous).erased
    }
}

/// Changes an opening's width, height, and sill height.
public struct ResizeOpeningCommand: Command {
    public var openingID: OpeningID
    public var width: Length
    public var height: Length
    public var sillHeight: Length

    public init(openingID: OpeningID, width: Length, height: Length, sillHeight: Length) {
        self.openingID = openingID
        self.width = width
        self.height = height
        self.sillHeight = sillHeight
    }

    public static let commandName = "resize_opening"
    public static let toolDescription =
        "Change the width, height, and sill height of an existing door or window; its near edge stays put."
    public static let parameters = [
        CommandParameter("openingID", .id, "ID of the opening."),
        CommandParameter("width", .length, "New width along the wall; greater than zero."),
        CommandParameter("height", .length, "New height; greater than zero."),
        CommandParameter("sillHeight", .length, "New sill height above the floor; zero for a door."),
    ]

    public func validate(against document: ModelDocument) throws {
        var opening = document.openings[try document.openingIndex(openingID)]
        opening.width = width
        opening.height = height
        opening.sillHeight = sillHeight
        try OpeningCheck.fits(opening, in: document)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.openingIndex(openingID)
        let previous = document.openings[index]
        document.openings[index].width = width
        document.openings[index].height = height
        document.openings[index].sillHeight = sillHeight
        return ResizeOpeningCommand(
            openingID: openingID, width: previous.width, height: previous.height, sillHeight: previous.sillHeight
        ).erased
    }
}

/// Removes an opening; the wall closes up.
public struct RemoveOpeningCommand: Command {
    public var openingID: OpeningID

    public init(openingID: OpeningID) {
        self.openingID = openingID
    }

    public static let commandName = "remove_opening"
    public static let toolDescription = "Remove a door or window from its wall."
    public static let parameters = [
        CommandParameter("openingID", .id, "ID of the opening to remove."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.openingIndex(openingID)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let index = try document.openingIndex(openingID)
        let removed = document.openings.remove(at: index)
        return AddOpeningCommand(
            openingID: removed.id, wallID: removed.wallID, offsetAlongWall: removed.offsetAlongWall,
            width: removed.width, height: removed.height, sillHeight: removed.sillHeight, index: index
        ).erased
    }
}

enum OpeningCheck {
    static func dimensions(_ opening: Opening) throws {
        try CommandCheck.nonNegative(opening.offsetAlongWall, "offsetAlongWall")
        try CommandCheck.positive(opening.width, "width")
        try CommandCheck.positive(opening.height, "height")
        try CommandCheck.nonNegative(opening.sillHeight, "sillHeight")
    }

    /// Checks a changed opening against its host wall and neighbours.
    static func fits(_ opening: Opening, in document: ModelDocument) throws {
        try dimensions(opening)
        let wall = document.walls[try document.wallIndex(opening.wallID)]
        try document.checkOpenings(on: wall, replacing: opening)
    }
}

extension ModelDocument {
    /// Checks that every opening hosted in `wall` fits it and that none overlap.
    /// `replacing` substitutes a proposed opening for the stored one with the same ID, or adds it if new.
    func checkOpenings(on wall: Wall, replacing proposed: Opening? = nil) throws {
        var hosted = openings.filter { $0.wallID == wall.id && $0.id != proposed?.id }
        if let proposed { hosted.append(proposed) }
        let wallLength = CommandMath.centerlineLength(start: wall.start, end: wall.end)
        for opening in hosted {
            if opening.offsetAlongWall.ticks + opening.width.ticks > wallLength {
                throw CommandValidationError.openingOutsideWall(opening.id)
            }
            if opening.sillHeight.ticks + opening.height.ticks > wall.height.ticks {
                throw CommandValidationError.openingAboveWall(opening.id)
            }
        }
        let sorted = hosted.sorted { $0.offsetAlongWall < $1.offsetAlongWall }
        for (left, right) in zip(sorted, sorted.dropFirst())
        where left.offsetAlongWall.ticks + left.width.ticks > right.offsetAlongWall.ticks {
            throw CommandValidationError.openingsOverlap(left.id, right.id)
        }
    }
}

enum CommandMath {
    /// Wall centerline length in ticks, rounded down, matching ATGeometry's integer square root.
    static func centerlineLength(start: Point2, end: Point2) -> Int64 {
        let dx = end.x.ticks - start.x.ticks
        let dy = end.y.ticks - start.y.ticks
        return integerSqrt(dx * dx + dy * dy)
    }

    static func integerSqrt(_ value: Int64) -> Int64 {
        guard value > 0 else { return 0 }
        var x = value
        var y = (x + 1) / 2
        while y < x {
            x = y
            y = (x + value / x) / 2
        }
        return x
    }
}
