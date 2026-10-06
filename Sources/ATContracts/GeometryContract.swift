import Foundation

/// An exact area in square ticks (1 mm² = 102,400 tick²).
public struct Area: Hashable, Codable, Sendable, Comparable {
    public var tickSquares: Int64

    public init(tickSquares: Int64) {
        self.tickSquares = tickSquares
    }

    public static let tickSquaresPerSquareMillimeter = Length.ticksPerMillimeter * Length.ticksPerMillimeter

    /// Whole square millimeters, rounded down.
    public var squareMillimeters: Int64 { tickSquares / Self.tickSquaresPerSquareMillimeter }

    public static func < (lhs: Area, rhs: Area) -> Bool {
        lhs.tickSquares < rhs.tickSquares
    }
}

/// What kind of model element an outline or mesh came from.
public enum ElementKind: String, Codable, Hashable, Sendable, CaseIterable {
    case wall, opening, room, stair, roof, slab, column, beam, placement, terrain, symbol
}

/// Whether an outline is cut by the view plane (drawn heavy) or seen beyond it (drawn light).
public enum OutlineClassification: String, Codable, Hashable, Sendable, CaseIterable {
    case cut
    case beyond
}

/// One closed outline from a plan view or section, tagged with its source element.
public struct ClassifiedOutline: Codable, Hashable, Sendable {
    public var elementID: UUID
    public var kind: ElementKind
    public var classification: OutlineClassification
    public var polygon: [Point2]

    public init(elementID: UUID, kind: ElementKind, classification: OutlineClassification, polygon: [Point2]) {
        self.elementID = elementID
        self.kind = kind
        self.classification = classification
        self.polygon = polygon
    }
}

/// A vertical section plane through `start → end`, looking to the left of that direction.
public struct SectionLine: Codable, Hashable, Sendable {
    public var start: Point2
    public var end: Point2

    public init(start: Point2, end: Point2) {
        self.start = start
        self.end = end
    }
}

/// Turns the model into exact 2D outlines, 3D meshes, and section cuts. Implemented by ATGeometry (Stream A).
public protocol GeometryEngine: Sendable {
    /// Outlines on a storey's plan, classified against the plan cut height.
    func planView(of document: ModelDocument, storey: StoreyID) throws -> [ClassifiedOutline]
    /// Net area of every room on the storey.
    func roomAreas(of document: ModelDocument, storey: StoreyID) throws -> [RoomID: Area]
    /// Meshes for every element in the model, with absolute elevations.
    func meshes(of document: ModelDocument) throws -> [Mesh]
    /// Outlines in section coordinates: x is distance along the line from `start`, y is elevation.
    func section(of document: ModelDocument, along line: SectionLine) throws -> [ClassifiedOutline]
}

/// The stamp every schematic export carries.
public enum OutputHonesty {
    public static let schematicStamp = "SCHEMATIC / NOT FOR CONSTRUCTION"
}
