import ATContracts
import Foundation

/// The cottage the app opens with, furnished and on a lot: a lawn, a driveway with a car, front and side walks,
/// a back patio, a flower bed, and trees. The model file it starts from is unchanged; this only adds placements
/// and terrain patches, so the sample shows what the app draws.
enum SampleSite {
    /// A placement: catalog item, middle of its footprint in feet, and turn in degrees.
    private static let furniture: [(String, Double, Double, Int64)] = [
        // Living
        ("hestia.loveseat", 10.5, 10.4, 0), ("hestia.coffee-table", 10.5, 6.8, 0), ("hestia.rug", 10, 6.6, 0),
        ("hestia.armchair", 3, 6.5, 90), ("hestia.tv-stand", 11.5, 1.3, 180), ("hestia.floor-lamp", 1.4, 10.8, 0),
        // Kitchen
        ("hestia.sink-cabinet", 20.5, 1.5, 180), ("hestia.counter-6", 23.5, 3.5, 270),
        ("hestia.range", 23.4, 7.75, 270), ("hestia.refrigerator", 23.1, 10.4, 270), ("hestia.island", 18.5, 7, 0),
        ("hestia.bar-stool", 17, 4.7, 0), ("hestia.bar-stool", 18.5, 4.7, 0), ("hestia.bar-stool", 20, 4.7, 0),
        // Utility
        ("hestia.washer", 31.5, 10.8, 180), ("hestia.dryer", 34, 10.8, 180), ("hestia.bookcase", 35.5, 9, 270),
        // Bedroom
        ("hestia.bed-queen", 7, 18.8, 0), ("hestia.nightstand", 3.3, 21.6, 0), ("hestia.nightstand", 10.7, 21.6, 0),
        ("hestia.dresser", 11.5, 13.4, 180),
        // Bath
        ("hestia.bathtub", 19.5, 21.2, 0), ("hestia.toilet", 23.3, 18, 270), ("hestia.vanity", 15.4, 16.5, 90),
        // Bedroom 2
        ("hestia.bed-twin", 34, 19, 0), ("hestia.desk", 27.5, 21.2, 0), ("hestia.office-chair", 27.5, 19.4, 0),
        ("hestia.wardrobe", 35.9, 14.7, 270),
        // Outside
        ("hestia.car", 47, -16, 0), ("hestia.tree-shade", -14, 36, 0), ("hestia.tree-shade", 58, 34, 0),
        ("hestia.tree-pine", -18, -22, 0), ("hestia.tree-pine", -22, 8, 0), ("hestia.tree-ornamental", 24, -24, 0),
        ("hestia.shrub", 1.5, -4, 0), ("hestia.shrub", 11, -4, 0), ("hestia.shrub", 33, -4, 0),
        ("hestia.patio-table", 9, 28, 0), ("hestia.hedge", 30, 30, 0),
    ]

    /// Terrain: name and the rectangle's corners in feet.
    private static let site: [(String, Double, Double, Double, Double)] = [
        ("Lot", -32, -42, 72, 48),
        ("Driveway", 42, -42, 52, 6),
        ("Path", 4.5, -42, 8, -0.5),
        ("Path 2", 37.5, 2, 42, 6.5),
        ("Patio", 2, 23, 17, 33),
        ("Garden bed", 14, -6.5, 30, -2),
    ]

    /// The cottage document with the sample's furniture and site added. A document that already has
    /// placements or terrain is returned unchanged.
    static func decorate(_ document: ModelDocument) -> ModelDocument {
        guard document.placements.isEmpty, document.terrainPatches.isEmpty,
              let storey = document.storeys.min(by: { $0.elevation.ticks < $1.elevation.ticks })?.id else {
            return document
        }
        var commands: [AnyCommand] = site.map { entry in
            AddTerrainPatchCommand(terrainPatchID: TerrainPatchID(UUID()), name: entry.0,
                                   boundary: PlanGeometry.rectangle(PlanOverlay.point(entry.1, entry.2),
                                                                    PlanOverlay.point(entry.3, entry.4)),
                                   surveyPoints: []).erased
        }
        commands += furniture.map { entry in
            AddPlacementCommand(placementID: PlacementID(UUID()), storeyID: storey,
                                catalogItemID: CatalogItemID(rawValue: entry.0),
                                position: PlanOverlay.point(entry.1, entry.2), rotation: .degrees(entry.3)).erased
        }
        var decorated = document
        guard (try? decorated.perform(batch: commands)) != nil else { return document }
        return decorated
    }
}
