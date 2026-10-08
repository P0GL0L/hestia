import Foundation

/// A UUID-backed identifier that encodes as a plain UUID string.
public protocol UUIDIdentifier: Hashable, Codable, Sendable, RawRepresentable where RawValue == UUID {
    init(rawValue: UUID)
}

extension UUIDIdentifier {
    public init(_ rawValue: UUID) {
        self.init(rawValue: rawValue)
    }

    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let uuid = UUID(uuidString: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid UUID \(string)"))
        }
        self.init(rawValue: uuid)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString)
    }
}

public struct StairID: UUIDIdentifier {
    public var rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct RoofID: UUIDIdentifier {
    public var rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct SlabID: UUIDIdentifier {
    public var rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct SheetID: UUIDIdentifier {
    public var rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// What fills an opening. Doors usually have a zero sill; skylights belong in roofs later.
public enum OpeningKind: String, Codable, Hashable, Sendable, CaseIterable {
    case singleDoor, doubleDoor, slidingDoor, pocketDoor, foldingDoor, garageDoor
    case window, bayWindow, cornerWindow, roundWindow, floorToCeilingWindow
    /// A doorless opening, such as a hall or closet opening: jambs only, no leaf and no glass. Its name must not
    /// end in "Door", or it would count as a door.
    case casedOpening

    public var isDoor: Bool { rawValue.hasSuffix("Door") }

    /// Glazed openings: everything that is neither a door nor a cased opening.
    public var isWindow: Bool { !isDoor && self != .casedOpening }
}

/// How a hinged door swings, relative to its host wall's start → end direction.
public struct DoorSwing: Codable, Hashable, Sendable {
    public enum Hinge: String, Codable, Hashable, Sendable, CaseIterable {
        /// Hinged on the edge nearer the wall start.
        case nearStart
        /// Hinged on the edge nearer the wall end.
        case nearEnd
    }

    public enum Side: String, Codable, Hashable, Sendable, CaseIterable {
        /// Opens into the space left of the wall direction.
        case left
        /// Opens into the space right of the wall direction.
        case right
    }

    public var hinge: Hinge
    public var opensToward: Side

    public init(hinge: Hinge, opensToward: Side) {
        self.hinge = hinge
        self.opensToward = opensToward
    }
}

public enum StairKind: String, Codable, Hashable, Sendable, CaseIterable {
    case straight, lShaped, uShaped, curved, spiral
}

/// A stair rising from its storey to the storey above, along a plan run line from bottom to top.
public struct Stair: Hashable, Codable, Sendable {
    public var id: StairID
    public var storeyID: StoreyID
    public var kind: StairKind
    /// Centerline of the run in plan, from the first riser to the top landing edge.
    public var runStart: Point2
    public var runEnd: Point2
    public var width: Length
    public var riserCount: Int
    public var riserHeight: Length

    public init(
        id: StairID, storeyID: StoreyID, kind: StairKind = .straight, runStart: Point2, runEnd: Point2,
        width: Length, riserCount: Int, riserHeight: Length
    ) {
        self.id = id
        self.storeyID = storeyID
        self.kind = kind
        self.runStart = runStart
        self.runEnd = runEnd
        self.width = width
        self.riserCount = riserCount
        self.riserHeight = riserHeight
    }
}

/// One roof plane, defined by the footprint edge it rises from.
///
/// `pitchRisePer12` is rise per 12 units of run (6 means 6:12); nil makes the edge a vertical gable end,
/// and zero makes it flat. Every plane of a hip roof has the same pitch.
public struct RoofPlane: Hashable, Codable, Sendable {
    public var pitchRisePer12: Length?
    public var overhang: Length

    public init(pitchRisePer12: Length?, overhang: Length) {
        self.pitchRisePer12 = pitchRisePer12
        self.overhang = overhang
    }
}

/// A roof over a counterclockwise footprint, with one plane per footprint edge: `planes[i]` rises from
/// the edge `footprint[i] → footprint[i + 1]`. Geometry builds the surfaces; the model stores intent.
public struct Roof: Hashable, Codable, Sendable {
    public var id: RoofID
    public var storeyID: StoreyID
    public var footprint: [Point2]
    /// Eave height above the storey's floor.
    public var eaveHeight: Length
    public var planes: [RoofPlane]

    public init(id: RoofID, storeyID: StoreyID, footprint: [Point2], eaveHeight: Length, planes: [RoofPlane]) {
        self.id = id
        self.storeyID = storeyID
        self.footprint = footprint
        self.eaveHeight = eaveHeight
        self.planes = planes
    }
}

public enum SlabKind: String, Codable, Hashable, Sendable, CaseIterable {
    case floor, foundation, ceiling
}

/// A flat slab whose top sits `topOffset` above its storey's floor elevation.
public struct Slab: Hashable, Codable, Sendable {
    public var id: SlabID
    public var storeyID: StoreyID
    public var kind: SlabKind
    public var outline: [Point2]
    public var thickness: Length
    public var topOffset: Length

    public init(
        id: SlabID, storeyID: StoreyID, kind: SlabKind = .floor, outline: [Point2],
        thickness: Length, topOffset: Length = Length(ticks: 0)
    ) {
        self.id = id
        self.storeyID = storeyID
        self.kind = kind
        self.outline = outline
        self.thickness = thickness
        self.topOffset = topOffset
    }
}

public enum ElevationDirection: String, Codable, Hashable, Sendable, CaseIterable {
    case north, east, south, west
}

public enum ScheduleKind: String, Codable, Hashable, Sendable, CaseIterable {
    case doors, windows, roomFinishes, areas
}

/// What a sheet shows. The drawing generator turns each view into paper-space content.
public enum SheetView: Codable, Hashable, Sendable {
    case cover
    case floorPlan(storeyID: StoreyID)
    case roofPlan
    case sitePlan
    case elevation(direction: ElevationDirection)
    case section(line: SectionLine)
    case schedule(kind: ScheduleKind)
    case electricalPlan(storeyID: StoreyID)
}

/// A sheet the user has set up in the drawing set, such as `A-101 Ground Floor Plan`.
public struct Sheet: Hashable, Codable, Sendable {
    public var id: SheetID
    public var number: String
    public var title: String
    public var paper: PaperSize
    public var scale: DrawingScale?
    public var views: [SheetView]

    public init(id: SheetID, number: String, title: String, paper: PaperSize, scale: DrawingScale?, views: [SheetView]) {
        self.id = id
        self.number = number
        self.title = title
        self.paper = paper
        self.scale = scale
        self.views = views
    }
}

extension SheetView {
    /// The storey a plan view shows, if any.
    public var storeyID: StoreyID? {
        switch self {
        case let .floorPlan(id), let .electricalPlan(id): return id
        default: return nil
        }
    }
}
