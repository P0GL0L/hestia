import Foundation

/// Which dimension of an element an override replaces.
public enum DimensionFace: String, Codable, Hashable, Sendable, CaseIterable {
    /// A wall's or opening's length along its centerline.
    case length
    /// A room's clear east-west size, or an opening's width.
    case width
    /// A room's clear north-south size.
    case depth
    /// The element's segment in an exterior chain on that face of the plan.
    case south, east, north, west
}

/// Display text that replaces a measured dimension value, such as "14'-0\" CLR" or "VERIFY".
///
/// Only the printed text changes. The model geometry and the measured value stay the source of truth.
public struct DimensionOverride: Hashable, Codable, Sendable {
    public var elementID: UUID
    public var face: DimensionFace
    public var text: String

    public init(elementID: UUID, face: DimensionFace, text: String) {
        self.elementID = elementID
        self.face = face
        self.text = text
    }
}

extension ModelDocument {
    /// The stored override text for an element's face, if any.
    public func dimensionOverride(for elementID: UUID, face: DimensionFace) -> String? {
        dimensionOverrides.first { $0.elementID == elementID && $0.face == face }?.text
    }

    /// Whether any wall, opening, or room has this ID: the elements dimensions are drawn for.
    func hasDimensionedElement(_ id: UUID) -> Bool {
        walls.contains { $0.id.rawValue == id } || openings.contains { $0.id.rawValue == id }
            || rooms.contains { $0.id.rawValue == id }
    }
}

private let faceParameter = CommandParameter(
    "face", .choice, "Which dimension: length, width, depth, or an exterior face.",
    allowedValues: DimensionFace.allCases.map(\.rawValue)
)

/// Sets, or replaces, the printed text of one dimension.
public struct SetDimensionOverrideCommand: Command {
    public var elementID: UUID
    public var face: DimensionFace
    public var text: String
    public var index: Int?

    public init(elementID: UUID, face: DimensionFace, text: String, index: Int? = nil) {
        self.elementID = elementID
        self.face = face
        self.text = text
        self.index = index
    }

    public static let commandName = "set_dimension_override"
    public static let toolDescription =
        "Print custom text on one dimension of a wall, opening, or room; the model geometry does not change."
    public static let parameters = [
        CommandParameter("elementID", .id, "ID of the wall, opening, or room the dimension measures."),
        faceParameter,
        CommandParameter("text", .string, "Text to print instead of the measured value; must not be blank."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        guard document.hasDimensionedElement(elementID) else {
            throw CommandValidationError.elementNotFound(elementID)
        }
        _ = try CommandCheck.name(text)
        try CommandCheck.insertionIndex(index, count: document.dimensionOverrides.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let override = DimensionOverride(elementID: elementID, face: face, text: try CommandCheck.name(text))
        if let existing = document.dimensionOverrides.firstIndex(where: { $0.elementID == elementID && $0.face == face }) {
            let previous = document.dimensionOverrides[existing].text
            document.dimensionOverrides[existing] = override
            return SetDimensionOverrideCommand(elementID: elementID, face: face, text: previous).erased
        }
        document.dimensionOverrides.insert(override, atOptional: index)
        return ClearDimensionOverrideCommand(elementID: elementID, face: face).erased
    }
}

/// Removes an override so the dimension prints its measured value again.
public struct ClearDimensionOverrideCommand: Command {
    public var elementID: UUID
    public var face: DimensionFace

    public init(elementID: UUID, face: DimensionFace) {
        self.elementID = elementID
        self.face = face
    }

    public static let commandName = "clear_dimension_override"
    public static let toolDescription = "Remove custom dimension text so the measured value prints again."
    public static let parameters = [
        CommandParameter("elementID", .id, "ID of the wall, opening, or room."),
        faceParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        guard document.dimensionOverrides.contains(where: { $0.elementID == elementID && $0.face == face }) else {
            throw CommandValidationError.dimensionOverrideNotFound(elementID, face)
        }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        guard let index = document.dimensionOverrides.firstIndex(where: { $0.elementID == elementID && $0.face == face })
        else { throw CommandValidationError.dimensionOverrideNotFound(elementID, face) }
        let removed = document.dimensionOverrides.remove(at: index)
        return SetDimensionOverrideCommand(elementID: elementID, face: face, text: removed.text, index: index).erased
    }
}
