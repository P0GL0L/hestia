import Foundation

extension Array {
    func index(_ missing: CommandValidationError, where match: (Element) -> Bool) throws -> Int {
        guard let index = firstIndex(where: match) else { throw missing }
        return index
    }
}

private let rotationParameter = CommandParameter(
    "rotation", .angle, required: false, "Counterclockwise rotation in plan; omit for none."
)

private let layerParameter = CommandParameter("layerID", .id, required: false, "User layer to put it on; omit for none.")

enum ElementCheck {
    static func layer(_ id: LayerID?, in document: ModelDocument) throws {
        if let id { _ = try document.layers.index(.layerNotFound(id)) { $0.id == id } }
    }

    static func color(_ rgb: [UInt8]) throws {
        if rgb.count != 3 { throw CommandValidationError.invalidValue(parameter: "colorRGB") }
    }
}

// MARK: - Layers

/// Adds a user layer.
public struct AddLayerCommand: Command {
    public var layerID: LayerID
    public var name: String
    public var colorRGB: [UInt8]
    public var isVisible: Bool?
    public var isLocked: Bool?
    public var index: Int?

    public init(
        layerID: LayerID, name: String, colorRGB: [UInt8], isVisible: Bool? = nil, isLocked: Bool? = nil,
        index: Int? = nil
    ) {
        self.layerID = layerID
        self.name = name
        self.colorRGB = colorRGB
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.index = index
    }

    public static let commandName = "add_layer"
    public static let toolDescription = "Add a user layer for grouping elements to show, hide, or lock together."
    public static let parameters = [
        CommandParameter("layerID", .id, "New unique ID for the layer."),
        CommandParameter("name", .string, "Layer name, such as Furniture."),
        CommandParameter("colorRGB", .integerList, "Display color as three integers 0-255: red, green, blue."),
        CommandParameter("isVisible", .boolean, required: false, "Omit for visible."),
        CommandParameter("isLocked", .boolean, required: false, "Omit for unlocked."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(layerID, in: document.layers.map(\.id))
        _ = try CommandCheck.name(name)
        try ElementCheck.color(colorRGB)
        try CommandCheck.insertionIndex(index, count: document.layers.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let layer = Layer(id: layerID, name: try CommandCheck.name(name), colorRGB: colorRGB,
                          isVisible: isVisible ?? true, isLocked: isLocked ?? false)
        document.layers.insert(layer, atOptional: index)
        return RemoveLayerCommand(layerID: layerID).erased
    }
}

/// Renames, recolors, shows or hides, and locks or unlocks a layer.
public struct SetLayerCommand: Command {
    public var layerID: LayerID
    public var name: String
    public var colorRGB: [UInt8]
    public var isVisible: Bool
    public var isLocked: Bool

    public init(layerID: LayerID, name: String, colorRGB: [UInt8], isVisible: Bool, isLocked: Bool) {
        self.layerID = layerID
        self.name = name
        self.colorRGB = colorRGB
        self.isVisible = isVisible
        self.isLocked = isLocked
    }

    public static let commandName = "set_layer"
    public static let toolDescription = "Set a layer's name, color, visibility, and lock state."
    public static let parameters = [
        CommandParameter("layerID", .id, "ID of the layer."),
        CommandParameter("name", .string, "Layer name."),
        CommandParameter("colorRGB", .integerList, "Display color as three integers 0-255."),
        CommandParameter("isVisible", .boolean, "Whether the layer's elements are shown."),
        CommandParameter("isLocked", .boolean, "Whether the layer's elements are protected from edits in the app."),
    ]

    public func validate(against document: ModelDocument) throws {
        try ElementCheck.layer(layerID, in: document)
        _ = try CommandCheck.name(name)
        try ElementCheck.color(colorRGB)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.layers.index(.layerNotFound(layerID)) { $0.id == layerID }
        let old = document.layers[index]
        document.layers[index] = Layer(id: layerID, name: try CommandCheck.name(name), colorRGB: colorRGB,
                                       isVisible: isVisible, isLocked: isLocked)
        return SetLayerCommand(layerID: layerID, name: old.name, colorRGB: old.colorRGB,
                               isVisible: old.isVisible, isLocked: old.isLocked).erased
    }
}

/// Removes an unused layer.
public struct RemoveLayerCommand: Command {
    public var layerID: LayerID

    public init(layerID: LayerID) {
        self.layerID = layerID
    }

    public static let commandName = "remove_layer"
    public static let toolDescription = "Remove a layer that no element is on; move its elements to another layer first."
    public static let parameters = [CommandParameter("layerID", .id, "ID of the layer to remove.")]

    public func validate(against document: ModelDocument) throws {
        try ElementCheck.layer(layerID, in: document)
        let used = document.columns.map(\.layerID) + document.beams.map(\.layerID)
            + document.placements.map(\.layerID) + document.mepSymbols.map(\.layerID)
        if used.contains(layerID) { throw CommandValidationError.hasDependents(layerID.rawValue) }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.layers.index(.layerNotFound(layerID)) { $0.id == layerID }
        let removed = document.layers.remove(at: index)
        return AddLayerCommand(layerID: removed.id, name: removed.name, colorRGB: removed.colorRGB,
                               isVisible: removed.isVisible, isLocked: removed.isLocked, index: index).erased
    }
}

/// Moves a column, beam, placement, or symbol onto a layer, or off every layer.
public struct SetElementLayerCommand: Command {
    public var elementID: UUID
    public var layerID: LayerID?

    public init(elementID: UUID, layerID: LayerID?) {
        self.elementID = elementID
        self.layerID = layerID
    }

    public static let commandName = "set_element_layer"
    public static let toolDescription = "Put a column, beam, placed item, or MEP symbol on a user layer, or take it off."
    public static let parameters = [
        CommandParameter("elementID", .id, "ID of the column, beam, placement, or symbol."),
        CommandParameter("layerID", .id, required: false, "Layer to put it on; omit to take it off every layer."),
    ]

    public func validate(against document: ModelDocument) throws {
        try ElementCheck.layer(layerID, in: document)
        _ = try current(in: document)
    }

    private func current(in document: ModelDocument) throws -> LayerID? {
        if let item = document.columns.first(where: { $0.id.rawValue == elementID }) { return item.layerID }
        if let item = document.beams.first(where: { $0.id.rawValue == elementID }) { return item.layerID }
        if let item = document.placements.first(where: { $0.id.rawValue == elementID }) { return item.layerID }
        if let item = document.mepSymbols.first(where: { $0.id.rawValue == elementID }) { return item.layerID }
        throw CommandValidationError.elementNotFound(elementID)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let previous = try current(in: document)
        if let i = document.columns.firstIndex(where: { $0.id.rawValue == elementID }) { document.columns[i].layerID = layerID }
        if let i = document.beams.firstIndex(where: { $0.id.rawValue == elementID }) { document.beams[i].layerID = layerID }
        if let i = document.placements.firstIndex(where: { $0.id.rawValue == elementID }) {
            document.placements[i].layerID = layerID
        }
        if let i = document.mepSymbols.firstIndex(where: { $0.id.rawValue == elementID }) {
            document.mepSymbols[i].layerID = layerID
        }
        return SetElementLayerCommand(elementID: elementID, layerID: previous).erased
    }
}

// MARK: - Columns and beams

/// Adds a column.
public struct AddColumnCommand: Command {
    public var columnID: ColumnID
    public var storeyID: StoreyID
    public var shape: ColumnShape
    public var center: Point2
    public var width: Length
    public var depth: Length
    public var height: Length
    public var rotation: Angle?
    public var layerID: LayerID?
    public var index: Int?

    public init(
        columnID: ColumnID, storeyID: StoreyID, shape: ColumnShape, center: Point2, width: Length, depth: Length,
        height: Length, rotation: Angle? = nil, layerID: LayerID? = nil, index: Int? = nil
    ) {
        self.columnID = columnID
        self.storeyID = storeyID
        self.shape = shape
        self.center = center
        self.width = width
        self.depth = depth
        self.height = height
        self.rotation = rotation
        self.layerID = layerID
        self.index = index
    }

    public static let commandName = "add_column"
    public static let toolDescription = "Add a rectangular or round column centered on a plan point."
    public static let parameters = [
        CommandParameter("columnID", .id, "New unique ID for the column."),
        CommandParameter("storeyID", .id, "ID of the storey it stands on."),
        CommandParameter("shape", .choice, "Column section.", allowedValues: ColumnShape.allCases.map(\.rawValue)),
        CommandParameter("center", .point2, "Plan center point."),
        CommandParameter("width", .length, "Width, or diameter for a round column; greater than zero."),
        CommandParameter("depth", .length, "Depth; greater than zero. Equal to width for a round column."),
        CommandParameter("height", .length, "Height above the storey floor; greater than zero."),
        rotationParameter, layerParameter, insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(columnID, in: document.columns.map(\.id))
        _ = try document.storeyIndex(storeyID)
        try CommandCheck.positive(width, "width")
        try CommandCheck.positive(depth, "depth")
        try CommandCheck.positive(height, "height")
        try ElementCheck.layer(layerID, in: document)
        try CommandCheck.insertionIndex(index, count: document.columns.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        document.columns.insert(Column(id: columnID, storeyID: storeyID, shape: shape, center: center, width: width,
                                       depth: depth, height: height, rotation: rotation ?? Angle(microDegrees: 0),
                                       layerID: layerID), atOptional: index)
        return RemoveColumnCommand(columnID: columnID).erased
    }
}

/// Moves and rotates a column.
public struct MoveColumnCommand: Command {
    public var columnID: ColumnID
    public var center: Point2
    public var rotation: Angle

    public init(columnID: ColumnID, center: Point2, rotation: Angle) {
        self.columnID = columnID
        self.center = center
        self.rotation = rotation
    }

    public static let commandName = "move_column"
    public static let toolDescription = "Move a column to a new plan center and rotation."
    public static let parameters = [
        CommandParameter("columnID", .id, "ID of the column."),
        CommandParameter("center", .point2, "New plan center point."),
        CommandParameter("rotation", .angle, "New counterclockwise rotation."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.columns.index(.columnNotFound(columnID)) { $0.id == columnID }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let i = try document.columns.index(.columnNotFound(columnID)) { $0.id == columnID }
        let old = document.columns[i]
        document.columns[i].center = center
        document.columns[i].rotation = rotation
        return MoveColumnCommand(columnID: columnID, center: old.center, rotation: old.rotation).erased
    }
}

/// Removes a column.
public struct RemoveColumnCommand: Command {
    public var columnID: ColumnID

    public init(columnID: ColumnID) {
        self.columnID = columnID
    }

    public static let commandName = "remove_column"
    public static let toolDescription = "Remove a column."
    public static let parameters = [CommandParameter("columnID", .id, "ID of the column to remove.")]

    public func validate(against document: ModelDocument) throws {
        _ = try document.columns.index(.columnNotFound(columnID)) { $0.id == columnID }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let i = try document.columns.index(.columnNotFound(columnID)) { $0.id == columnID }
        let c = document.columns.remove(at: i)
        return AddColumnCommand(columnID: c.id, storeyID: c.storeyID, shape: c.shape, center: c.center, width: c.width,
                                depth: c.depth, height: c.height, rotation: c.rotation, layerID: c.layerID,
                                index: i).erased
    }
}

/// Adds a beam.
public struct AddBeamCommand: Command {
    public var beamID: BeamID
    public var storeyID: StoreyID
    public var start: Point2
    public var end: Point2
    public var width: Length
    public var depth: Length
    public var topOffset: Length
    public var layerID: LayerID?
    public var index: Int?

    public init(
        beamID: BeamID, storeyID: StoreyID, start: Point2, end: Point2, width: Length, depth: Length,
        topOffset: Length, layerID: LayerID? = nil, index: Int? = nil
    ) {
        self.beamID = beamID
        self.storeyID = storeyID
        self.start = start
        self.end = end
        self.width = width
        self.depth = depth
        self.topOffset = topOffset
        self.layerID = layerID
        self.index = index
    }

    public static let commandName = "add_beam"
    public static let toolDescription = "Add a horizontal beam along a plan line, with its top at a height above the floor."
    public static let parameters = [
        CommandParameter("beamID", .id, "New unique ID for the beam."),
        CommandParameter("storeyID", .id, "ID of the storey."),
        CommandParameter("start", .point2, "Plan start of the beam centerline."),
        CommandParameter("end", .point2, "Plan end of the beam centerline; must differ from start."),
        CommandParameter("width", .length, "Beam width; greater than zero."),
        CommandParameter("depth", .length, "Beam depth, top to bottom; greater than zero."),
        CommandParameter("topOffset", .length, "Height of the beam top above the storey floor."),
        layerParameter, insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(beamID, in: document.beams.map(\.id))
        _ = try document.storeyIndex(storeyID)
        if start == end { throw CommandValidationError.invalidValue(parameter: "end") }
        try CommandCheck.positive(width, "width")
        try CommandCheck.positive(depth, "depth")
        try ElementCheck.layer(layerID, in: document)
        try CommandCheck.insertionIndex(index, count: document.beams.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        document.beams.insert(Beam(id: beamID, storeyID: storeyID, start: start, end: end, width: width, depth: depth,
                                   topOffset: topOffset, layerID: layerID), atOptional: index)
        return RemoveBeamCommand(beamID: beamID).erased
    }
}

/// Moves a beam's centerline.
public struct MoveBeamCommand: Command {
    public var beamID: BeamID
    public var start: Point2
    public var end: Point2

    public init(beamID: BeamID, start: Point2, end: Point2) {
        self.beamID = beamID
        self.start = start
        self.end = end
    }

    public static let commandName = "move_beam"
    public static let toolDescription = "Move a beam by setting new plan start and end points."
    public static let parameters = [
        CommandParameter("beamID", .id, "ID of the beam."),
        CommandParameter("start", .point2, "New plan start point."),
        CommandParameter("end", .point2, "New plan end point; must differ from start."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.beams.index(.beamNotFound(beamID)) { $0.id == beamID }
        if start == end { throw CommandValidationError.invalidValue(parameter: "end") }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let i = try document.beams.index(.beamNotFound(beamID)) { $0.id == beamID }
        let old = document.beams[i]
        document.beams[i].start = start
        document.beams[i].end = end
        return MoveBeamCommand(beamID: beamID, start: old.start, end: old.end).erased
    }
}

/// Removes a beam.
public struct RemoveBeamCommand: Command {
    public var beamID: BeamID

    public init(beamID: BeamID) {
        self.beamID = beamID
    }

    public static let commandName = "remove_beam"
    public static let toolDescription = "Remove a beam."
    public static let parameters = [CommandParameter("beamID", .id, "ID of the beam to remove.")]

    public func validate(against document: ModelDocument) throws {
        _ = try document.beams.index(.beamNotFound(beamID)) { $0.id == beamID }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let i = try document.beams.index(.beamNotFound(beamID)) { $0.id == beamID }
        let b = document.beams.remove(at: i)
        return AddBeamCommand(beamID: b.id, storeyID: b.storeyID, start: b.start, end: b.end, width: b.width,
                              depth: b.depth, topOffset: b.topOffset, layerID: b.layerID, index: i).erased
    }
}
