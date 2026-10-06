import Foundation

public struct Project: Hashable, Codable, Sendable {
    public var id: ProjectID
    public var name: String

    public init(id: ProjectID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Building: Hashable, Codable, Sendable {
    public var id: BuildingID
    public var projectID: ProjectID
    public var name: String

    public init(id: BuildingID, projectID: ProjectID, name: String) {
        self.id = id
        self.projectID = projectID
        self.name = name
    }
}

public struct Storey: Hashable, Codable, Sendable {
    public var id: StoreyID
    public var buildingID: BuildingID
    public var name: String
    public var elevation: Length

    public init(id: StoreyID, buildingID: BuildingID, name: String, elevation: Length) {
        self.id = id
        self.buildingID = buildingID
        self.name = name
        self.elevation = elevation
    }
}

public struct Wall: Hashable, Codable, Sendable {
    public var id: WallID
    public var storeyID: StoreyID
    public var start: Point2
    public var end: Point2
    public var thickness: Length
    public var height: Length

    public init(
        id: WallID,
        storeyID: StoreyID,
        start: Point2,
        end: Point2,
        thickness: Length,
        height: Length
    ) {
        self.id = id
        self.storeyID = storeyID
        self.start = start
        self.end = end
        self.thickness = thickness
        self.height = height
    }
}

public struct Opening: Hashable, Codable, Sendable {
    public var id: OpeningID
    public var wallID: WallID
    public var offsetAlongWall: Length
    public var width: Length
    public var height: Length
    public var sillHeight: Length

    public init(
        id: OpeningID,
        wallID: WallID,
        offsetAlongWall: Length,
        width: Length,
        height: Length,
        sillHeight: Length
    ) {
        self.id = id
        self.wallID = wallID
        self.offsetAlongWall = offsetAlongWall
        self.width = width
        self.height = height
        self.sillHeight = sillHeight
    }
}

public struct Room: Hashable, Codable, Sendable {
    public var id: RoomID
    public var storeyID: StoreyID
    public var name: String
    public var boundaryWallIDs: [WallID]

    public init(id: RoomID, storeyID: StoreyID, name: String, boundaryWallIDs: [WallID]) {
        self.id = id
        self.storeyID = storeyID
        self.name = name
        self.boundaryWallIDs = boundaryWallIDs
    }
}
