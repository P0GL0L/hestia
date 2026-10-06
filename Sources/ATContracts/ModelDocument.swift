import Foundation

public enum ModelDocumentError: Error, Sendable, Equatable {
    /// The file was written by a newer Hestia; opening it could lose data.
    case unsupportedSchemaVersion(found: Int, supported: Int)
}

/// The whole model as stored in `model.json`.
///
/// Collections added after the first files were written decode as empty when absent, so older files still open.
/// Encoding always writes every key, with sorted keys, so a decode and re-encode is byte-stable.
public struct ModelDocument: Hashable, Codable, Sendable {
    /// The newest `schemaVersion` this build reads and writes.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var project: Project
    public var buildings: [Building]
    public var storeys: [Storey]
    public var walls: [Wall]
    public var openings: [Opening]
    public var rooms: [Room]
    public var stairs: [Stair]
    public var roofs: [Roof]
    public var slabs: [Slab]
    public var sheets: [Sheet]
    public var layers: [Layer]
    public var columns: [Column]
    public var beams: [Beam]
    public var placements: [Placement]
    public var terrainPatches: [TerrainPatch]
    public var mepSymbols: [MEPSymbol]
    /// Display text replacing measured dimension values. The measured value stays the source of truth.
    public var dimensionOverrides: [DimensionOverride]

    public init(
        schemaVersion: Int,
        project: Project,
        buildings: [Building],
        storeys: [Storey],
        walls: [Wall],
        openings: [Opening],
        rooms: [Room],
        stairs: [Stair] = [],
        roofs: [Roof] = [],
        slabs: [Slab] = [],
        sheets: [Sheet] = [],
        layers: [Layer] = [],
        columns: [Column] = [],
        beams: [Beam] = [],
        placements: [Placement] = [],
        terrainPatches: [TerrainPatch] = [],
        mepSymbols: [MEPSymbol] = [],
        dimensionOverrides: [DimensionOverride] = []
    ) {
        self.schemaVersion = schemaVersion
        self.project = project
        self.buildings = buildings
        self.storeys = storeys
        self.walls = walls
        self.openings = openings
        self.rooms = rooms
        self.stairs = stairs
        self.roofs = roofs
        self.slabs = slabs
        self.sheets = sheets
        self.layers = layers
        self.columns = columns
        self.beams = beams
        self.placements = placements
        self.terrainPatches = terrainPatches
        self.mepSymbols = mepSymbols
        self.dimensionOverrides = dimensionOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, project, buildings, storeys, walls, openings, rooms, stairs, roofs, slabs, sheets
        case layers, columns, beams, placements, terrainPatches, mepSymbols, dimensionOverrides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version <= Self.currentSchemaVersion else {
            throw ModelDocumentError.unsupportedSchemaVersion(found: version, supported: Self.currentSchemaVersion)
        }
        self.init(
            schemaVersion: version,
            project: try c.decode(Project.self, forKey: .project),
            buildings: try c.decodeIfPresent([Building].self, forKey: .buildings) ?? [],
            storeys: try c.decodeIfPresent([Storey].self, forKey: .storeys) ?? [],
            walls: try c.decodeIfPresent([Wall].self, forKey: .walls) ?? [],
            openings: try c.decodeIfPresent([Opening].self, forKey: .openings) ?? [],
            rooms: try c.decodeIfPresent([Room].self, forKey: .rooms) ?? [],
            stairs: try c.decodeIfPresent([Stair].self, forKey: .stairs) ?? [],
            roofs: try c.decodeIfPresent([Roof].self, forKey: .roofs) ?? [],
            slabs: try c.decodeIfPresent([Slab].self, forKey: .slabs) ?? [],
            sheets: try c.decodeIfPresent([Sheet].self, forKey: .sheets) ?? [],
            layers: try c.decodeIfPresent([Layer].self, forKey: .layers) ?? [],
            columns: try c.decodeIfPresent([Column].self, forKey: .columns) ?? [],
            beams: try c.decodeIfPresent([Beam].self, forKey: .beams) ?? [],
            placements: try c.decodeIfPresent([Placement].self, forKey: .placements) ?? [],
            terrainPatches: try c.decodeIfPresent([TerrainPatch].self, forKey: .terrainPatches) ?? [],
            mepSymbols: try c.decodeIfPresent([MEPSymbol].self, forKey: .mepSymbols) ?? [],
            dimensionOverrides: try c.decodeIfPresent([DimensionOverride].self, forKey: .dimensionOverrides) ?? []
        )
    }

    public static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    public static func makeJSONDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    public func encodeToJSONData() throws -> Data {
        try Self.makeJSONEncoder().encode(self)
    }

    public static func decode(from jsonData: Data) throws -> ModelDocument {
        try makeJSONDecoder().decode(ModelDocument.self, from: jsonData)
    }
}
