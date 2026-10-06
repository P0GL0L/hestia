import Foundation

/// Adds a named room bounded by walls on one storey.
public struct AddRoomCommand: Command {
    public var roomID: RoomID
    public var storeyID: StoreyID
    public var name: String
    public var boundaryWallIDs: [WallID]
    public var index: Int?

    public init(roomID: RoomID, storeyID: StoreyID, name: String, boundaryWallIDs: [WallID], index: Int? = nil) {
        self.roomID = roomID
        self.storeyID = storeyID
        self.name = name
        self.boundaryWallIDs = boundaryWallIDs
        self.index = index
    }

    public static let commandName = "add_room"
    public static let toolDescription =
        "Add a named room on a storey, bounded by the listed walls of that storey."
    public static let parameters = [
        CommandParameter("roomID", .id, "New unique ID for the room."),
        CommandParameter("storeyID", .id, "ID of the storey the room is on."),
        CommandParameter("name", .string, "Room name, such as Kitchen or Bedroom 2."),
        CommandParameter("boundaryWallIDs", .idList, "IDs of the walls around the room, each once, all on the storey."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(roomID, in: document.rooms.map(\.id))
        _ = try document.storeyIndex(storeyID)
        _ = try CommandCheck.name(name)
        try RoomCheck.boundary(boundaryWallIDs, storeyID: storeyID, in: document)
        try CommandCheck.insertionIndex(index, count: document.rooms.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let room = Room(id: roomID, storeyID: storeyID, name: try CommandCheck.name(name), boundaryWallIDs: boundaryWallIDs)
        document.rooms.insert(room, atOptional: index)
        return RemoveRoomCommand(roomID: roomID).erased
    }
}

/// Renames a room.
public struct RenameRoomCommand: Command {
    public var roomID: RoomID
    public var newName: String

    public init(roomID: RoomID, newName: String) {
        self.roomID = roomID
        self.newName = newName
    }

    public static let commandName = "rename_room"
    public static let toolDescription = "Rename an existing room, for example from Bedroom 2 to Office."
    public static let parameters = [
        CommandParameter("roomID", .id, "ID of the room."),
        CommandParameter("newName", .string, "New room name; must not be blank."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.roomIndex(roomID)
        _ = try CommandCheck.name(newName)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.roomIndex(roomID)
        let previous = document.rooms[index].name
        document.rooms[index].name = try CommandCheck.name(newName)
        return RenameRoomCommand(roomID: roomID, newName: previous).erased
    }
}

/// Replaces the list of walls that bound a room.
public struct SetRoomBoundaryCommand: Command {
    public var roomID: RoomID
    public var boundaryWallIDs: [WallID]

    public init(roomID: RoomID, boundaryWallIDs: [WallID]) {
        self.roomID = roomID
        self.boundaryWallIDs = boundaryWallIDs
    }

    public static let commandName = "set_room_boundary"
    public static let toolDescription = "Replace the list of walls that bound an existing room."
    public static let parameters = [
        CommandParameter("roomID", .id, "ID of the room."),
        CommandParameter("boundaryWallIDs", .idList, "IDs of the walls around the room, each once, all on its storey."),
    ]

    public func validate(against document: ModelDocument) throws {
        let room = document.rooms[try document.roomIndex(roomID)]
        try RoomCheck.boundary(boundaryWallIDs, storeyID: room.storeyID, in: document)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.roomIndex(roomID)
        let previous = document.rooms[index].boundaryWallIDs
        document.rooms[index].boundaryWallIDs = boundaryWallIDs
        return SetRoomBoundaryCommand(roomID: roomID, boundaryWallIDs: previous).erased
    }
}

/// Removes a room. Its walls stay.
public struct RemoveRoomCommand: Command {
    public var roomID: RoomID

    public init(roomID: RoomID) {
        self.roomID = roomID
    }

    public static let commandName = "remove_room"
    public static let toolDescription = "Remove a room; its walls stay in place."
    public static let parameters = [
        CommandParameter("roomID", .id, "ID of the room to remove."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.roomIndex(roomID)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let index = try document.roomIndex(roomID)
        let removed = document.rooms.remove(at: index)
        return AddRoomCommand(
            roomID: removed.id, storeyID: removed.storeyID, name: removed.name,
            boundaryWallIDs: removed.boundaryWallIDs, index: index
        ).erased
    }
}

enum RoomCheck {
    static func boundary(_ wallIDs: [WallID], storeyID: StoreyID, in document: ModelDocument) throws {
        if wallIDs.isEmpty || Set(wallIDs).count != wallIDs.count {
            throw CommandValidationError.roomBoundaryInvalid
        }
        for id in wallIDs where document.walls[try document.wallIndex(id)].storeyID != storeyID {
            throw CommandValidationError.wallOnOtherStorey(id)
        }
    }
}
