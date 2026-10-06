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
    /// Build-up from the left face to the right face, looking from start to end. Empty means one homogeneous
    /// layer. When present, the layer thicknesses add up to `thickness`.
    public var layers: [WallLayer]
    public var phase: WallPhase

    public init(
        id: WallID,
        storeyID: StoreyID,
        start: Point2,
        end: Point2,
        thickness: Length,
        height: Length,
        layers: [WallLayer] = [],
        phase: WallPhase = .new
    ) {
        self.id = id
        self.storeyID = storeyID
        self.start = start
        self.end = end
        self.thickness = thickness
        self.height = height
        self.layers = layers
        self.phase = phase
    }

    private enum CodingKeys: String, CodingKey {
        case id, storeyID, start, end, thickness, height, layers, phase
    }

    /// Files written before layers and phase existed open as a homogeneous new wall.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(WallID.self, forKey: .id),
            storeyID: try c.decode(StoreyID.self, forKey: .storeyID),
            start: try c.decode(Point2.self, forKey: .start),
            end: try c.decode(Point2.self, forKey: .end),
            thickness: try c.decode(Length.self, forKey: .thickness),
            height: try c.decode(Length.self, forKey: .height),
            layers: try c.decodeIfPresent([WallLayer].self, forKey: .layers) ?? [],
            phase: try c.decodeIfPresent(WallPhase.self, forKey: .phase) ?? .new
        )
    }
}

/// What a wall layer does, for hatching and schedules.
public enum WallLayerFunction: String, Codable, Hashable, Sendable, CaseIterable {
    case finish, structure, insulation, sheathing, airGap, cladding
}

/// One layer of a wall build-up, such as 1/2" gypsum board.
public struct WallLayer: Hashable, Codable, Sendable {
    public var material: String
    public var function: WallLayerFunction
    public var thickness: Length

    public init(material: String, function: WallLayerFunction, thickness: Length) {
        self.material = material
        self.function = function
        self.thickness = thickness
    }
}

/// Renovation phase: existing walls stay, new walls are built, demolished walls are shown dashed.
public enum WallPhase: String, Codable, Hashable, Sendable, CaseIterable {
    case new, existing, demolish
}

public struct Opening: Hashable, Codable, Sendable {
    public var id: OpeningID
    public var wallID: WallID
    public var offsetAlongWall: Length
    public var width: Length
    public var height: Length
    public var sillHeight: Length
    public var kind: OpeningKind
    /// Swing for hinged doors; nil for windows and sliding, pocket, folding, and garage doors.
    public var swing: DoorSwing?

    public init(
        id: OpeningID,
        wallID: WallID,
        offsetAlongWall: Length,
        width: Length,
        height: Length,
        sillHeight: Length,
        kind: OpeningKind? = nil,
        swing: DoorSwing? = nil
    ) {
        self.id = id
        self.wallID = wallID
        self.offsetAlongWall = offsetAlongWall
        self.width = width
        self.height = height
        self.sillHeight = sillHeight
        self.kind = kind ?? Opening.defaultKind(sillHeight: sillHeight)
        self.swing = swing
    }

    /// A zero sill reads as a single door, anything higher as a window.
    public static func defaultKind(sillHeight: Length) -> OpeningKind {
        sillHeight.ticks == 0 ? .singleDoor : .window
    }

    private enum CodingKeys: String, CodingKey {
        case id, wallID, offsetAlongWall, width, height, sillHeight, kind, swing
    }

    /// Files written before `kind` existed decode with `defaultKind(sillHeight:)`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(OpeningID.self, forKey: .id),
            wallID: try c.decode(WallID.self, forKey: .wallID),
            offsetAlongWall: try c.decode(Length.self, forKey: .offsetAlongWall),
            width: try c.decode(Length.self, forKey: .width),
            height: try c.decode(Length.self, forKey: .height),
            sillHeight: try c.decode(Length.self, forKey: .sillHeight),
            kind: try c.decodeIfPresent(OpeningKind.self, forKey: .kind),
            swing: try c.decodeIfPresent(DoorSwing.self, forKey: .swing)
        )
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
