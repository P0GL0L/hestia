import ATContracts
import Foundation

/// What is wrong with a model document read from a file, as plain sentences. The commands keep a model sound
/// while it is edited; a file written by hand, merged, or damaged can break what they guarantee, and the
/// drawing and geometry code assumes it holds.
enum ModelIntegrity {
    /// Every problem found, in a stable order. Empty means the document can be opened.
    static func problems(in document: ModelDocument) -> [String] {
        var problems: [String] = []
        problems += duplicateIDs(in: document)
        problems += missingReferences(in: document)
        problems += badSizes(in: document)
        return problems
    }

    /// IDs must be unique across every element, not only within their own kind, so a click or an override
    /// names one thing.
    private static func duplicateIDs(in document: ModelDocument) -> [String] {
        let tagged: [(kind: String, id: UUID)] =
            document.buildings.map { ("building", $0.id.rawValue) }
            + document.storeys.map { ("storey", $0.id.rawValue) }
            + document.walls.map { ("wall", $0.id.rawValue) }
            + document.openings.map { ("opening", $0.id.rawValue) }
            + document.rooms.map { ("room", $0.id.rawValue) }
            + document.stairs.map { ("stair", $0.id.rawValue) }
            + document.roofs.map { ("roof", $0.id.rawValue) }
            + document.slabs.map { ("slab", $0.id.rawValue) }
            + document.sheets.map { ("sheet", $0.id.rawValue) }
            + document.layers.map { ("layer", $0.id.rawValue) }
            + document.columns.map { ("column", $0.id.rawValue) }
            + document.beams.map { ("beam", $0.id.rawValue) }
            + document.placements.map { ("placement", $0.id.rawValue) }
            + document.terrainPatches.map { ("terrain patch", $0.id.rawValue) }
            + document.mepSymbols.map { ("electrical symbol", $0.id.rawValue) }
        var firstKind: [UUID: String] = [:]
        var problems: [String] = []
        for (kind, id) in tagged {
            if let earlier = firstKind[id] {
                problems.append("A \(kind) has the same ID as a \(earlier): \(id.uuidString).")
            } else {
                firstKind[id] = kind
            }
        }
        return problems
    }

    /// Every storey, wall, and layer an element names must be in the file.
    private static func missingReferences(in document: ModelDocument) -> [String] {
        let storeys = Set(document.storeys.map(\.id))
        let walls = Set(document.walls.map(\.id))
        let layers = Set(document.layers.map(\.id))
        var problems: [String] = []
        func onStorey(_ kind: String, _ storeyIDs: [StoreyID]) {
            let missing = storeyIDs.filter { !storeys.contains($0) }.count
            if missing > 0 { problems.append("\(missing) \(kind) name a storey that is not in the file.") }
        }
        onStorey("wall(s)", document.walls.map(\.storeyID))
        onStorey("room(s)", document.rooms.map(\.storeyID))
        onStorey("stair(s)", document.stairs.map(\.storeyID))
        onStorey("roof(s)", document.roofs.map(\.storeyID))
        onStorey("slab(s)", document.slabs.map(\.storeyID))
        onStorey("column(s)", document.columns.map(\.storeyID))
        onStorey("beam(s)", document.beams.map(\.storeyID))
        onStorey("placement(s)", document.placements.map(\.storeyID))
        onStorey("electrical symbol(s)", document.mepSymbols.map(\.storeyID))
        let openingsOffWalls = document.openings.filter { !walls.contains($0.wallID) }.count
        if openingsOffWalls > 0 {
            problems.append("\(openingsOffWalls) opening(s) sit in a wall that is not in the file.")
        }
        for room in document.rooms where room.boundaryWallIDs.contains(where: { !walls.contains($0) }) {
            problems.append("Room \(room.name) is bounded by a wall that is not in the file.")
        }
        let layerIDs = document.columns.compactMap(\.layerID) + document.beams.compactMap(\.layerID)
            + document.placements.compactMap(\.layerID) + document.mepSymbols.compactMap(\.layerID)
        let missingLayers = layerIDs.filter { !layers.contains($0) }.count
        if missingLayers > 0 { problems.append("\(missingLayers) element(s) name a layer that is not in the file.") }
        return problems
    }

    /// Walls and openings need a real size, or the geometry has nothing to build.
    private static func badSizes(in document: ModelDocument) -> [String] {
        var problems: [String] = []
        let flatWalls = document.walls.filter {
            $0.start == $0.end || $0.thickness.ticks <= 0 || $0.height.ticks <= 0
        }.count
        if flatWalls > 0 { problems.append("\(flatWalls) wall(s) have no length, thickness, or height.") }
        let flatOpenings = document.openings.filter { $0.width.ticks <= 0 || $0.height.ticks <= 0 }.count
        if flatOpenings > 0 { problems.append("\(flatOpenings) opening(s) have no width or height.") }
        return problems
    }
}
