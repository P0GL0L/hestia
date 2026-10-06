import Foundation

public struct LayerID: UUIDIdentifier {
    public var rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct ColumnID: UUIDIdentifier {
    public var rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct BeamID: UUIDIdentifier {
    public var rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct PlacementID: UUIDIdentifier {
    public var rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct TerrainPatchID: UUIDIdentifier {
    public var rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct MEPSymbolID: UUIDIdentifier {
    public var rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// A user layer for grouping elements to show, hide, or lock together. CAD export layers come from element kinds.
public struct Layer: Hashable, Codable, Sendable {
    public var id: LayerID
    public var name: String
    /// sRGB red, green, blue.
    public var colorRGB: [UInt8]
    public var isVisible: Bool
    public var isLocked: Bool

    public init(id: LayerID, name: String, colorRGB: [UInt8], isVisible: Bool = true, isLocked: Bool = false) {
        self.id = id
        self.name = name
        self.colorRGB = colorRGB
        self.isVisible = isVisible
        self.isLocked = isLocked
    }
}

public enum ColumnShape: String, Codable, Hashable, Sendable, CaseIterable {
    case rectangular, round
}

/// A vertical column standing on a storey. A round column uses `width` as its diameter.
public struct Column: Hashable, Codable, Sendable {
    public var id: ColumnID
    public var storeyID: StoreyID
    public var shape: ColumnShape
    public var center: Point2
    public var width: Length
    public var depth: Length
    public var height: Length
    public var rotation: Angle
    public var layerID: LayerID?

    public init(
        id: ColumnID, storeyID: StoreyID, shape: ColumnShape, center: Point2, width: Length, depth: Length,
        height: Length, rotation: Angle = Angle(microDegrees: 0), layerID: LayerID? = nil
    ) {
        self.id = id
        self.storeyID = storeyID
        self.shape = shape
        self.center = center
        self.width = width
        self.depth = depth
        self.height = height
        self.rotation = rotation
        self.layerID = layerID
    }
}

/// A horizontal beam along a plan line, its top `topOffset` above the storey floor.
public struct Beam: Hashable, Codable, Sendable {
    public var id: BeamID
    public var storeyID: StoreyID
    public var start: Point2
    public var end: Point2
    public var width: Length
    public var depth: Length
    public var topOffset: Length
    public var layerID: LayerID?

    public init(
        id: BeamID, storeyID: StoreyID, start: Point2, end: Point2, width: Length, depth: Length,
        topOffset: Length, layerID: LayerID? = nil
    ) {
        self.id = id
        self.storeyID = storeyID
        self.start = start
        self.end = end
        self.width = width
        self.depth = depth
        self.topOffset = topOffset
        self.layerID = layerID
    }
}

/// A catalog item placed in the plan: furniture, fixtures, or plants.
public struct Placement: Hashable, Codable, Sendable {
    public var id: PlacementID
    public var storeyID: StoreyID
    public var catalogItemID: CatalogItemID
    /// Plan position of the item's origin.
    public var position: Point2
    public var rotation: Angle
    /// Height of the item's base above the storey floor, for wall- and ceiling-mounted items.
    public var elevation: Length
    public var layerID: LayerID?

    public init(
        id: PlacementID, storeyID: StoreyID, catalogItemID: CatalogItemID, position: Point2,
        rotation: Angle = Angle(microDegrees: 0), elevation: Length = Length(ticks: 0), layerID: LayerID? = nil
    ) {
        self.id = id
        self.storeyID = storeyID
        self.catalogItemID = catalogItemID
        self.position = position
        self.rotation = rotation
        self.elevation = elevation
        self.layerID = layerID
    }
}

/// A patch of site terrain: a counterclockwise boundary and survey points with absolute elevations.
public struct TerrainPatch: Hashable, Codable, Sendable {
    public var id: TerrainPatchID
    public var name: String
    public var boundary: [Point2]
    public var surveyPoints: [Point3]

    public init(id: TerrainPatchID, name: String, boundary: [Point2], surveyPoints: [Point3]) {
        self.id = id
        self.name = name
        self.boundary = boundary
        self.surveyPoints = surveyPoints
    }
}

/// Electrical and plumbing plan symbols.
public enum MEPSymbolKind: String, Codable, Hashable, Sendable, CaseIterable {
    case duplexOutlet, gfciOutlet, dedicatedOutlet, switchSingle, switchThreeWay, dimmer
    case ceilingLight, wallLight, recessedLight, ceilingFan, smokeDetector, panel
    case sink, toilet, shower, bathtub, waterHeater, hoseBib, radiator

    /// US National CAD Standard layer for drawings and DXF.
    public var cadLayer: String {
        switch self {
        case .duplexOutlet, .gfciOutlet, .dedicatedOutlet, .panel: return "E-POWR"
        case .switchSingle, .switchThreeWay, .dimmer, .ceilingLight, .wallLight, .recessedLight,
             .ceilingFan, .smokeDetector:
            return "E-LITE"
        case .sink, .toilet, .shower, .bathtub, .waterHeater, .hoseBib, .radiator: return "P-FIXT"
        }
    }
}

/// An electrical or plumbing symbol on a storey.
public struct MEPSymbol: Hashable, Codable, Sendable {
    public var id: MEPSymbolID
    public var storeyID: StoreyID
    public var kind: MEPSymbolKind
    public var position: Point2
    public var rotation: Angle
    /// Mounting height above the storey floor.
    public var mountingHeight: Length
    public var layerID: LayerID?

    public init(
        id: MEPSymbolID, storeyID: StoreyID, kind: MEPSymbolKind, position: Point2,
        rotation: Angle = Angle(microDegrees: 0), mountingHeight: Length = Length(ticks: 0), layerID: LayerID? = nil
    ) {
        self.id = id
        self.storeyID = storeyID
        self.kind = kind
        self.position = position
        self.rotation = rotation
        self.mountingHeight = mountingHeight
        self.layerID = layerID
    }
}
