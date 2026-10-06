import ATContracts
import Foundation
import Testing

extension Sample {
    static let siteAndFurnishing: [AnyCommand] = [
        AddLayerCommand(layerID: newLayer, name: "Furniture", colorRGB: [40, 120, 200], isVisible: false,
                        index: 0).erased,
        SetLayerCommand(layerID: layer, name: "Frame", colorRGB: [0, 0, 0], isVisible: false, isLocked: true).erased,
        RemoveLayerCommand(layerID: spareLayer).erased,
        SetElementLayerCommand(elementID: placement.rawValue, layerID: layer).erased,
        AddColumnCommand(columnID: newColumn, storeyID: storey, shape: .round, center: point(3000, 1500),
                         width: .millimeters(250), depth: .millimeters(250), height: .millimeters(2400),
                         rotation: .degrees(0), layerID: layer, index: 0).erased,
        MoveColumnCommand(columnID: column, center: point(2100, 1500), rotation: .degrees(45)).erased,
        RemoveColumnCommand(columnID: column).erased,
        AddBeamCommand(beamID: newBeam, storeyID: storey, start: point(2000, 0), end: point(2000, 3000),
                       width: .millimeters(150), depth: .millimeters(250), topOffset: .millimeters(2400),
                       index: 0).erased,
        MoveBeamCommand(beamID: beam, start: point(0, 1600), end: point(4000, 1600)).erased,
        RemoveBeamCommand(beamID: beam).erased,
        AddPlacementCommand(placementID: newPlacement, storeyID: storey,
                            catalogItemID: CatalogItemID(rawValue: "lighting/sconce"), position: point(50, 2000),
                            rotation: .degrees(90), elevation: .millimeters(1800), index: 0).erased,
        MovePlacementCommand(placementID: placement, position: point(1500, 2500), rotation: .degrees(180),
                             elevation: .millimeters(0)).erased,
        RemovePlacementCommand(placementID: placement).erased,
        AddMEPSymbolCommand(symbolID: newSymbol, storeyID: storey, kind: .switchSingle, position: point(400, 100),
                            rotation: .degrees(90), mountingHeight: .millimeters(1200), index: 0).erased,
        MoveMEPSymbolCommand(symbolID: symbol, position: point(100, 1200), rotation: .degrees(0),
                             mountingHeight: .millimeters(450)).erased,
        RemoveMEPSymbolCommand(symbolID: symbol).erased,
        AddTerrainPatchCommand(terrainPatchID: newTerrain, name: "Driveway", boundary: footprint,
                               surveyPoints: [], index: 0).erased,
        SetTerrainPointsCommand(terrainPatchID: terrain, surveyPoints: []).erased,
        RemoveTerrainPatchCommand(terrainPatchID: terrain).erased,
    ]
}

@Test func layersInUseCannotBeRemoved() {
    expectRefused(.hasDependents(Sample.layer.rawValue), RemoveLayerCommand(layerID: Sample.layer))
    expectRefused(.invalidValue(parameter: "colorRGB"),
                  AddLayerCommand(layerID: Sample.newLayer, name: "Bad", colorRGB: [1, 2]))
    expectRefused(.layerNotFound(Sample.newLayer),
                  SetElementLayerCommand(elementID: Sample.column.rawValue, layerID: Sample.newLayer))
    expectRefused(.elementNotFound(Sample.wallSouth.rawValue),
                  SetElementLayerCommand(elementID: Sample.wallSouth.rawValue, layerID: nil))
}

@Test func structureAndSymbolsAreChecked() {
    expectRefused(.invalidValue(parameter: "end"),
                  MoveBeamCommand(beamID: Sample.beam, start: Sample.point(1, 1), end: Sample.point(1, 1)))
    expectRefused(.notPositive(parameter: "depth"), AddColumnCommand(
        columnID: Sample.newColumn, storeyID: Sample.storey, shape: .rectangular, center: Sample.point(0, 0),
        width: .millimeters(100), depth: .millimeters(0), height: .millimeters(2400)
    ))
    expectRefused(.negative(parameter: "mountingHeight"), MoveMEPSymbolCommand(
        symbolID: Sample.symbol, position: Sample.point(0, 0), rotation: .degrees(0), mountingHeight: .millimeters(-1)
    ))
    expectRefused(.invalidValue(parameter: "catalogItemID"), AddPlacementCommand(
        placementID: Sample.newPlacement, storeyID: Sample.storey, catalogItemID: CatalogItemID(rawValue: " "),
        position: Sample.point(0, 0)
    ))
    expectRefused(.polygonInvalid, AddTerrainPatchCommand(
        terrainPatchID: Sample.newTerrain, name: "Lot", boundary: Sample.footprint.reversed(), surveyPoints: []
    ))
}

@Test func symbolKindsMapToNCSLayers() {
    #expect(MEPSymbolKind.duplexOutlet.cadLayer == "E-POWR")
    #expect(MEPSymbolKind.ceilingLight.cadLayer == "E-LITE")
    #expect(MEPSymbolKind.toilet.cadLayer == "P-FIXT")
    #expect(Set(MEPSymbolKind.allCases.map(\.cadLayer)) == ["E-POWR", "E-LITE", "P-FIXT"])
}
