import Foundation

// MARK: - Placements

/// Places a catalog item.
public struct AddPlacementCommand: Command {
    public var placementID: PlacementID
    public var storeyID: StoreyID
    public var catalogItemID: CatalogItemID
    public var position: Point2
    public var rotation: Angle?
    public var elevation: Length?
    public var layerID: LayerID?
    public var index: Int?

    public init(
        placementID: PlacementID, storeyID: StoreyID, catalogItemID: CatalogItemID, position: Point2,
        rotation: Angle? = nil, elevation: Length? = nil, layerID: LayerID? = nil, index: Int? = nil
    ) {
        self.placementID = placementID
        self.storeyID = storeyID
        self.catalogItemID = catalogItemID
        self.position = position
        self.rotation = rotation
        self.elevation = elevation
        self.layerID = layerID
        self.index = index
    }

    public static let commandName = "add_placement"
    public static let toolDescription = "Place a catalog item, such as a sofa or a sink, at a plan point on a storey."
    public static let parameters = [
        CommandParameter("placementID", .id, "New unique ID for the placed item."),
        CommandParameter("storeyID", .id, "ID of the storey."),
        CommandParameter("catalogItemID", .string, "Catalog slug of the item, such as living/sofa-3-seat."),
        CommandParameter("position", .point2, "Plan position of the item's origin."),
        CommandParameter("rotation", .angle, required: false, "Counterclockwise rotation; omit for none."),
        CommandParameter("elevation", .length, required: false, "Base height above the floor; omit for zero."),
        CommandParameter("layerID", .id, required: false, "User layer to put it on; omit for none."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(placementID, in: document.placements.map(\.id))
        _ = try document.storeyIndex(storeyID)
        if catalogItemID.rawValue.trimmingCharacters(in: .whitespaces).isEmpty {
            throw CommandValidationError.invalidValue(parameter: "catalogItemID")
        }
        try ElementCheck.layer(layerID, in: document)
        try CommandCheck.insertionIndex(index, count: document.placements.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        document.placements.insert(Placement(
            id: placementID, storeyID: storeyID, catalogItemID: catalogItemID, position: position,
            rotation: rotation ?? Angle(microDegrees: 0), elevation: elevation ?? Length(ticks: 0), layerID: layerID
        ), atOptional: index)
        return RemovePlacementCommand(placementID: placementID).erased
    }
}

/// Moves, rotates, and raises a placed item.
public struct MovePlacementCommand: Command {
    public var placementID: PlacementID
    public var position: Point2
    public var rotation: Angle
    public var elevation: Length

    public init(placementID: PlacementID, position: Point2, rotation: Angle, elevation: Length) {
        self.placementID = placementID
        self.position = position
        self.rotation = rotation
        self.elevation = elevation
    }

    public static let commandName = "move_placement"
    public static let toolDescription = "Move a placed item to a new plan position, rotation, and base height."
    public static let parameters = [
        CommandParameter("placementID", .id, "ID of the placed item."),
        CommandParameter("position", .point2, "New plan position."),
        CommandParameter("rotation", .angle, "New counterclockwise rotation."),
        CommandParameter("elevation", .length, "New base height above the floor."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.placements.index(.placementNotFound(placementID)) { $0.id == placementID }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let i = try document.placements.index(.placementNotFound(placementID)) { $0.id == placementID }
        let old = document.placements[i]
        document.placements[i].position = position
        document.placements[i].rotation = rotation
        document.placements[i].elevation = elevation
        return MovePlacementCommand(placementID: placementID, position: old.position, rotation: old.rotation,
                                    elevation: old.elevation).erased
    }
}

/// Removes a placed item.
public struct RemovePlacementCommand: Command {
    public var placementID: PlacementID

    public init(placementID: PlacementID) {
        self.placementID = placementID
    }

    public static let commandName = "remove_placement"
    public static let toolDescription = "Remove a placed catalog item."
    public static let parameters = [CommandParameter("placementID", .id, "ID of the placed item to remove.")]

    public func validate(against document: ModelDocument) throws {
        _ = try document.placements.index(.placementNotFound(placementID)) { $0.id == placementID }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let i = try document.placements.index(.placementNotFound(placementID)) { $0.id == placementID }
        let p = document.placements.remove(at: i)
        return AddPlacementCommand(placementID: p.id, storeyID: p.storeyID, catalogItemID: p.catalogItemID,
                                   position: p.position, rotation: p.rotation, elevation: p.elevation,
                                   layerID: p.layerID, index: i).erased
    }
}

// MARK: - MEP symbols

/// Adds an electrical or plumbing symbol.
public struct AddMEPSymbolCommand: Command {
    public var symbolID: MEPSymbolID
    public var storeyID: StoreyID
    public var kind: MEPSymbolKind
    public var position: Point2
    public var rotation: Angle?
    public var mountingHeight: Length?
    public var layerID: LayerID?
    public var index: Int?

    public init(
        symbolID: MEPSymbolID, storeyID: StoreyID, kind: MEPSymbolKind, position: Point2, rotation: Angle? = nil,
        mountingHeight: Length? = nil, layerID: LayerID? = nil, index: Int? = nil
    ) {
        self.symbolID = symbolID
        self.storeyID = storeyID
        self.kind = kind
        self.position = position
        self.rotation = rotation
        self.mountingHeight = mountingHeight
        self.layerID = layerID
        self.index = index
    }

    public static let commandName = "add_mep_symbol"
    public static let toolDescription = "Add an outlet, switch, light, fan, panel, or plumbing fixture symbol at a plan point."
    public static let parameters = [
        CommandParameter("symbolID", .id, "New unique ID for the symbol."),
        CommandParameter("storeyID", .id, "ID of the storey."),
        CommandParameter("kind", .choice, "Symbol type.", allowedValues: MEPSymbolKind.allCases.map(\.rawValue)),
        CommandParameter("position", .point2, "Plan position."),
        CommandParameter("rotation", .angle, required: false, "Counterclockwise rotation; omit for none."),
        CommandParameter("mountingHeight", .length, required: false, "Height above the floor; omit for zero."),
        CommandParameter("layerID", .id, required: false, "User layer to put it on; omit for none."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(symbolID, in: document.mepSymbols.map(\.id))
        _ = try document.storeyIndex(storeyID)
        if let mountingHeight { try CommandCheck.nonNegative(mountingHeight, "mountingHeight") }
        try ElementCheck.layer(layerID, in: document)
        try CommandCheck.insertionIndex(index, count: document.mepSymbols.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        document.mepSymbols.insert(MEPSymbol(
            id: symbolID, storeyID: storeyID, kind: kind, position: position,
            rotation: rotation ?? Angle(microDegrees: 0), mountingHeight: mountingHeight ?? Length(ticks: 0),
            layerID: layerID
        ), atOptional: index)
        return RemoveMEPSymbolCommand(symbolID: symbolID).erased
    }
}

/// Moves and rotates a symbol and sets its mounting height.
public struct MoveMEPSymbolCommand: Command {
    public var symbolID: MEPSymbolID
    public var position: Point2
    public var rotation: Angle
    public var mountingHeight: Length

    public init(symbolID: MEPSymbolID, position: Point2, rotation: Angle, mountingHeight: Length) {
        self.symbolID = symbolID
        self.position = position
        self.rotation = rotation
        self.mountingHeight = mountingHeight
    }

    public static let commandName = "move_mep_symbol"
    public static let toolDescription = "Move an MEP symbol to a new plan position, rotation, and mounting height."
    public static let parameters = [
        CommandParameter("symbolID", .id, "ID of the symbol."),
        CommandParameter("position", .point2, "New plan position."),
        CommandParameter("rotation", .angle, "New counterclockwise rotation."),
        CommandParameter("mountingHeight", .length, "New height above the floor; zero or greater."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.mepSymbols.index(.mepSymbolNotFound(symbolID)) { $0.id == symbolID }
        try CommandCheck.nonNegative(mountingHeight, "mountingHeight")
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let i = try document.mepSymbols.index(.mepSymbolNotFound(symbolID)) { $0.id == symbolID }
        let old = document.mepSymbols[i]
        document.mepSymbols[i].position = position
        document.mepSymbols[i].rotation = rotation
        document.mepSymbols[i].mountingHeight = mountingHeight
        return MoveMEPSymbolCommand(symbolID: symbolID, position: old.position, rotation: old.rotation,
                                    mountingHeight: old.mountingHeight).erased
    }
}

/// Removes a symbol.
public struct RemoveMEPSymbolCommand: Command {
    public var symbolID: MEPSymbolID

    public init(symbolID: MEPSymbolID) {
        self.symbolID = symbolID
    }

    public static let commandName = "remove_mep_symbol"
    public static let toolDescription = "Remove an electrical or plumbing symbol."
    public static let parameters = [CommandParameter("symbolID", .id, "ID of the symbol to remove.")]

    public func validate(against document: ModelDocument) throws {
        _ = try document.mepSymbols.index(.mepSymbolNotFound(symbolID)) { $0.id == symbolID }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let i = try document.mepSymbols.index(.mepSymbolNotFound(symbolID)) { $0.id == symbolID }
        let s = document.mepSymbols.remove(at: i)
        return AddMEPSymbolCommand(symbolID: s.id, storeyID: s.storeyID, kind: s.kind, position: s.position,
                                   rotation: s.rotation, mountingHeight: s.mountingHeight, layerID: s.layerID,
                                   index: i).erased
    }
}

// MARK: - Terrain

/// Adds a patch of site terrain.
public struct AddTerrainPatchCommand: Command {
    public var terrainPatchID: TerrainPatchID
    public var name: String
    public var boundary: [Point2]
    public var surveyPoints: [Point3]
    public var index: Int?

    public init(
        terrainPatchID: TerrainPatchID, name: String, boundary: [Point2], surveyPoints: [Point3], index: Int? = nil
    ) {
        self.terrainPatchID = terrainPatchID
        self.name = name
        self.boundary = boundary
        self.surveyPoints = surveyPoints
        self.index = index
    }

    public static let commandName = "add_terrain_patch"
    public static let toolDescription =
        "Add a patch of site terrain from a counterclockwise boundary and survey points with absolute elevations."
    public static let parameters = [
        CommandParameter("terrainPatchID", .id, "New unique ID for the patch."),
        CommandParameter("name", .string, "Patch name, such as Lot."),
        CommandParameter("boundary", .point2List, "Plan boundary, at least three points, counterclockwise."),
        CommandParameter("surveyPoints", .point3List, "Survey points; z is absolute elevation."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(terrainPatchID, in: document.terrainPatches.map(\.id))
        _ = try CommandCheck.name(name)
        try CommandCheck.polygon(boundary)
        try CommandCheck.insertionIndex(index, count: document.terrainPatches.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        document.terrainPatches.insert(TerrainPatch(id: terrainPatchID, name: try CommandCheck.name(name),
                                                    boundary: boundary, surveyPoints: surveyPoints), atOptional: index)
        return RemoveTerrainPatchCommand(terrainPatchID: terrainPatchID).erased
    }
}

/// Replaces a terrain patch's survey points.
public struct SetTerrainPointsCommand: Command {
    public var terrainPatchID: TerrainPatchID
    public var surveyPoints: [Point3]

    public init(terrainPatchID: TerrainPatchID, surveyPoints: [Point3]) {
        self.terrainPatchID = terrainPatchID
        self.surveyPoints = surveyPoints
    }

    public static let commandName = "set_terrain_points"
    public static let toolDescription = "Replace the survey points that shape a terrain patch."
    public static let parameters = [
        CommandParameter("terrainPatchID", .id, "ID of the terrain patch."),
        CommandParameter("surveyPoints", .point3List, "New survey points; z is absolute elevation."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.terrainPatches.index(.terrainPatchNotFound(terrainPatchID)) { $0.id == terrainPatchID }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let i = try document.terrainPatches.index(.terrainPatchNotFound(terrainPatchID)) { $0.id == terrainPatchID }
        let old = document.terrainPatches[i].surveyPoints
        document.terrainPatches[i].surveyPoints = surveyPoints
        return SetTerrainPointsCommand(terrainPatchID: terrainPatchID, surveyPoints: old).erased
    }
}

/// Removes a terrain patch.
public struct RemoveTerrainPatchCommand: Command {
    public var terrainPatchID: TerrainPatchID

    public init(terrainPatchID: TerrainPatchID) {
        self.terrainPatchID = terrainPatchID
    }

    public static let commandName = "remove_terrain_patch"
    public static let toolDescription = "Remove a patch of site terrain."
    public static let parameters = [CommandParameter("terrainPatchID", .id, "ID of the terrain patch to remove.")]

    public func validate(against document: ModelDocument) throws {
        _ = try document.terrainPatches.index(.terrainPatchNotFound(terrainPatchID)) { $0.id == terrainPatchID }
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let i = try document.terrainPatches.index(.terrainPatchNotFound(terrainPatchID)) { $0.id == terrainPatchID }
        let t = document.terrainPatches.remove(at: i)
        return AddTerrainPatchCommand(terrainPatchID: t.id, name: t.name, boundary: t.boundary,
                                      surveyPoints: t.surveyPoints, index: i).erased
    }
}
