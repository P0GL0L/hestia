import Foundation

/// Why a command was refused. Every case names what was wrong so the UI and the agent can say it plainly.
public enum CommandValidationError: Error, Sendable, Equatable {
    case projectNotFound(ProjectID)
    case buildingNotFound(BuildingID)
    case storeyNotFound(StoreyID)
    case wallNotFound(WallID)
    case openingNotFound(OpeningID)
    case roomNotFound(RoomID)
    /// A new element reused an ID that already exists in its collection.
    case duplicateID(UUID)
    case nameEmpty
    /// The named parameter must be greater than zero.
    case notPositive(parameter: String)
    /// The named parameter must be zero or greater.
    case negative(parameter: String)
    /// An insertion index was outside the collection.
    case indexOutOfRange(Int)
    /// A wall's start and end are the same point.
    case zeroLengthWall
    /// The opening would extend past the start or end of its host wall.
    case openingOutsideWall(OpeningID)
    /// The opening would extend above the top of its host wall.
    case openingAboveWall(OpeningID)
    /// The opening would overlap another opening in the same wall.
    case openingsOverlap(OpeningID, OpeningID)
    /// A room boundary must list at least one wall, with no repeats.
    case roomBoundaryInvalid
    /// A room boundary wall is on a different storey from the room.
    case wallOnOtherStorey(WallID)
    /// The element is still referenced and cannot be removed. Remove the dependents first.
    case hasDependents(UUID)
    /// The command name is not in the catalog.
    case unknownCommand(String)
    /// The named parameter is outside its allowed range.
    case invalidValue(parameter: String)
    /// An outline needs at least three points, wound counterclockwise, enclosing some area.
    case polygonInvalid
    /// Only single and double hinged doors have a swing.
    case swingNotAllowed(OpeningID)
    case stairNotFound(StairID)
    case roofNotFound(RoofID)
    case slabNotFound(SlabID)
    case sheetNotFound(SheetID)
    /// Another sheet already uses this number.
    case duplicateSheetNumber(String)
}

/// The JSON shape of one command parameter, so tool schemas can be generated from the catalog.
public enum CommandParameterKind: String, Sendable, Hashable, CaseIterable {
    /// A JSON string.
    case string
    /// A JSON integer.
    case integer
    /// A `Length`: `{"ticks": Int}` where 1 mm = 320 ticks and 1/64 inch = 127 ticks.
    case length
    /// A `Point2`: `{"x": Length, "y": Length}`.
    case point2
    /// A UUID string identifying one element.
    case id
    /// An array of UUID strings.
    case idList
    /// An array of `Point2` objects.
    case point2List
    /// A string from `CommandParameter.allowedValues`.
    case choice
    /// A JSON object whose shape the parameter description gives.
    case object
    /// An array of JSON objects whose shape the parameter description gives.
    case objectList
}

/// One typed, documented command parameter. `name` is the JSON key.
public struct CommandParameter: Hashable, Sendable {
    public var name: String
    public var kind: CommandParameterKind
    public var isRequired: Bool
    public var description: String
    /// The allowed strings for a `.choice` parameter.
    public var allowedValues: [String]?

    public init(
        _ name: String, _ kind: CommandParameterKind, required: Bool = true, _ description: String,
        allowedValues: [String]? = nil
    ) {
        self.name = name
        self.kind = kind
        self.isRequired = required
        self.description = description
        self.allowedValues = allowedValues
    }
}

/// Edits the model through validate → apply → inverse.
///
/// `apply` validates first, mutates the document, and returns the command that undoes it.
/// Applying the inverse restores the document exactly, including collection order.
public protocol Command: Codable, Hashable, Sendable {
    /// Stable snake_case name, used as the LLM tool name and the `name` in the JSON envelope.
    static var commandName: String { get }
    /// One line, written for an LLM tool description.
    static var toolDescription: String { get }
    /// Every parameter, in the order the tool schema should list them.
    static var parameters: [CommandParameter] { get }

    func validate(against document: ModelDocument) throws
    func apply(to document: inout ModelDocument) throws -> AnyCommand
}

extension Command {
    /// This command wrapped for storage in undo stacks, batches, and JSON.
    public var erased: AnyCommand { AnyCommand(self) }
}

/// Name, description, and parameters of a catalog command.
public struct CommandDescriptor: Hashable, Sendable {
    public var name: String
    public var toolDescription: String
    public var parameters: [CommandParameter]
}

/// A type-erased command. Encodes as `{"name": "<commandName>", "parameters": {...}}`.
public struct AnyCommand: Codable, Hashable, Sendable {
    public let base: any Command

    public init(_ base: some Command) {
        self.base = base
    }

    public var name: String { type(of: base).commandName }

    public func validate(against document: ModelDocument) throws {
        try base.validate(against: document)
    }

    /// Validates, applies, and returns the inverse.
    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try base.apply(to: &document)
    }

    public static func == (lhs: AnyCommand, rhs: AnyCommand) -> Bool {
        AnyHashable(lhs.base) == AnyHashable(rhs.base)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(AnyHashable(base))
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        guard let type = CommandCatalog.commandType(named: name) else {
            throw CommandValidationError.unknownCommand(name)
        }
        base = try type.init(from: container.superDecoder(forKey: .parameters))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try base.encode(to: container.superEncoder(forKey: .parameters))
    }
}

/// The v1 command catalog: every command the UI, agent, and importers may submit.
public enum CommandCatalog {
    public static let v1: [any Command.Type] = [
        RenameProjectCommand.self,
        AddBuildingCommand.self,
        RenameBuildingCommand.self,
        RemoveBuildingCommand.self,
        AddStoreyCommand.self,
        RenameStoreyCommand.self,
        SetStoreyElevationCommand.self,
        RemoveStoreyCommand.self,
        AddWallCommand.self,
        MoveWallCommand.self,
        SetWallThicknessCommand.self,
        SetWallHeightCommand.self,
        RemoveWallCommand.self,
        SetWallLayersCommand.self,
        SetWallPhaseCommand.self,
        AddOpeningCommand.self,
        MoveOpeningCommand.self,
        ResizeOpeningCommand.self,
        RemoveOpeningCommand.self,
        AddRoomCommand.self,
        RenameRoomCommand.self,
        SetRoomBoundaryCommand.self,
        RemoveRoomCommand.self,
        SetOpeningKindCommand.self,
        AddStairCommand.self,
        MoveStairCommand.self,
        SetStairRisersCommand.self,
        RemoveStairCommand.self,
        AddRoofCommand.self,
        SetRoofEdgeCommand.self,
        RemoveRoofCommand.self,
        AddSlabCommand.self,
        SetSlabOutlineCommand.self,
        RemoveSlabCommand.self,
        AddSheetCommand.self,
        SetSheetTitleCommand.self,
        RemoveSheetCommand.self,
    ]

    public static var descriptors: [CommandDescriptor] {
        v1.map { CommandDescriptor(name: $0.commandName, toolDescription: $0.toolDescription, parameters: $0.parameters) }
    }

    public static func commandType(named name: String) -> (any Command.Type)? {
        v1.first { $0.commandName == name }
    }
}

extension ModelDocument {
    /// Applies one command and returns its inverse. The document is unchanged if the command is refused.
    public mutating func perform(_ command: AnyCommand) throws -> AnyCommand {
        try command.apply(to: &self)
    }

    /// Applies commands in order as one undoable step. If any command is refused, the document is unchanged
    /// and the error is rethrown. Returns the inverse batch, already in undo order.
    public mutating func perform(batch commands: [AnyCommand]) throws -> [AnyCommand] {
        var working = self
        var inverses: [AnyCommand] = []
        inverses.reserveCapacity(commands.count)
        for command in commands {
            inverses.append(try command.apply(to: &working))
        }
        self = working
        return inverses.reversed()
    }
}
