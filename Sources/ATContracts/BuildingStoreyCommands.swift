import Foundation

/// Adds a building to the project.
public struct AddBuildingCommand: Command {
    public var buildingID: BuildingID
    public var name: String
    public var index: Int?

    public init(buildingID: BuildingID, name: String, index: Int? = nil) {
        self.buildingID = buildingID
        self.name = name
        self.index = index
    }

    public static let commandName = "add_building"
    public static let toolDescription = "Add a new, empty building to the project with a caller-chosen ID and a name."
    public static let parameters = [
        CommandParameter("buildingID", .id, "New unique ID for the building."),
        CommandParameter("name", .string, "Building name, such as Main House or Garage."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(buildingID, in: document.buildings.map(\.id))
        _ = try CommandCheck.name(name)
        try CommandCheck.insertionIndex(index, count: document.buildings.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let building = Building(id: buildingID, projectID: document.project.id, name: try CommandCheck.name(name))
        document.buildings.insert(building, atOptional: index)
        return RemoveBuildingCommand(buildingID: buildingID).erased
    }
}

/// Renames a building.
public struct RenameBuildingCommand: Command {
    public var buildingID: BuildingID
    public var newName: String

    public init(buildingID: BuildingID, newName: String) {
        self.buildingID = buildingID
        self.newName = newName
    }

    public static let commandName = "rename_building"
    public static let toolDescription = "Rename an existing building by building ID."
    public static let parameters = [
        CommandParameter("buildingID", .id, "ID of the building."),
        CommandParameter("newName", .string, "New building name; must not be blank."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.buildingIndex(buildingID)
        _ = try CommandCheck.name(newName)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.buildingIndex(buildingID)
        let previous = document.buildings[index].name
        document.buildings[index].name = try CommandCheck.name(newName)
        return RenameBuildingCommand(buildingID: buildingID, newName: previous).erased
    }
}

/// Removes an empty building.
public struct RemoveBuildingCommand: Command {
    public var buildingID: BuildingID

    public init(buildingID: BuildingID) {
        self.buildingID = buildingID
    }

    public static let commandName = "remove_building"
    public static let toolDescription = "Remove a building that has no storeys; remove its storeys first."
    public static let parameters = [
        CommandParameter("buildingID", .id, "ID of the building to remove."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.buildingIndex(buildingID)
        if document.storeys.contains(where: { $0.buildingID == buildingID }) {
            throw CommandValidationError.hasDependents(buildingID.rawValue)
        }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.buildingIndex(buildingID)
        let removed = document.buildings.remove(at: index)
        return AddBuildingCommand(buildingID: removed.id, name: removed.name, index: index).erased
    }
}

/// Adds a storey to a building.
public struct AddStoreyCommand: Command {
    public var storeyID: StoreyID
    public var buildingID: BuildingID
    public var name: String
    public var elevation: Length
    public var index: Int?

    public init(storeyID: StoreyID, buildingID: BuildingID, name: String, elevation: Length, index: Int? = nil) {
        self.storeyID = storeyID
        self.buildingID = buildingID
        self.name = name
        self.elevation = elevation
        self.index = index
    }

    public static let commandName = "add_storey"
    public static let toolDescription =
        "Add a storey (floor level) to a building at a given floor elevation above the project datum."
    public static let parameters = [
        CommandParameter("storeyID", .id, "New unique ID for the storey."),
        CommandParameter("buildingID", .id, "ID of the building that owns the storey."),
        CommandParameter("name", .string, "Storey name, such as Ground Floor."),
        CommandParameter("elevation", .length, "Finished floor elevation; may be negative for a basement."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(storeyID, in: document.storeys.map(\.id))
        _ = try document.buildingIndex(buildingID)
        _ = try CommandCheck.name(name)
        try CommandCheck.insertionIndex(index, count: document.storeys.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let storey = Storey(id: storeyID, buildingID: buildingID, name: try CommandCheck.name(name), elevation: elevation)
        document.storeys.insert(storey, atOptional: index)
        return RemoveStoreyCommand(storeyID: storeyID).erased
    }
}

/// Renames a storey.
public struct RenameStoreyCommand: Command {
    public var storeyID: StoreyID
    public var newName: String

    public init(storeyID: StoreyID, newName: String) {
        self.storeyID = storeyID
        self.newName = newName
    }

    public static let commandName = "rename_storey"
    public static let toolDescription = "Rename an existing storey by storey ID."
    public static let parameters = [
        CommandParameter("storeyID", .id, "ID of the storey."),
        CommandParameter("newName", .string, "New storey name; must not be blank."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.storeyIndex(storeyID)
        _ = try CommandCheck.name(newName)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.storeyIndex(storeyID)
        let previous = document.storeys[index].name
        document.storeys[index].name = try CommandCheck.name(newName)
        return RenameStoreyCommand(storeyID: storeyID, newName: previous).erased
    }
}

/// Changes a storey's floor elevation.
public struct SetStoreyElevationCommand: Command {
    public var storeyID: StoreyID
    public var elevation: Length

    public init(storeyID: StoreyID, elevation: Length) {
        self.storeyID = storeyID
        self.elevation = elevation
    }

    public static let commandName = "set_storey_elevation"
    public static let toolDescription = "Set the finished floor elevation of an existing storey."
    public static let parameters = [
        CommandParameter("storeyID", .id, "ID of the storey."),
        CommandParameter("elevation", .length, "New finished floor elevation; may be negative."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.storeyIndex(storeyID)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let index = try document.storeyIndex(storeyID)
        let previous = document.storeys[index].elevation
        document.storeys[index].elevation = elevation
        return SetStoreyElevationCommand(storeyID: storeyID, elevation: previous).erased
    }
}

/// Removes an empty storey.
public struct RemoveStoreyCommand: Command {
    public var storeyID: StoreyID

    public init(storeyID: StoreyID) {
        self.storeyID = storeyID
    }

    public static let commandName = "remove_storey"
    public static let toolDescription = "Remove a storey that has no walls or rooms; remove those first."
    public static let parameters = [
        CommandParameter("storeyID", .id, "ID of the storey to remove."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.storeyIndex(storeyID)
        if document.walls.contains(where: { $0.storeyID == storeyID })
            || document.rooms.contains(where: { $0.storeyID == storeyID }) {
            throw CommandValidationError.hasDependents(storeyID.rawValue)
        }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.storeyIndex(storeyID)
        let removed = document.storeys.remove(at: index)
        return AddStoreyCommand(
            storeyID: removed.id, buildingID: removed.buildingID, name: removed.name,
            elevation: removed.elevation, index: index
        ).erased
    }
}
