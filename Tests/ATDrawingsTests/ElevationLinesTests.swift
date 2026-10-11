@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

private func z(_ feet: Int64, _ inches: Int64 = 0) -> Int64 { Length.feet(feet, inchCount: inches).ticks }

@Test func levelMarksThatWouldCrowdKeepTheFloorsAndTheHighestRidge() {
    let view = ViewTransform(scale: .eighthInch, modelOrigin: paperPoint(0, 0), paperOrigin: paperPoint(0, 0))
    let levels: [(name: String, z: Int64)] = [
        ("FIRST FLOOR", 0), ("SECOND FLOOR", z(11)), ("EAVE", z(10, 6)), ("RIDGE", z(30, 10)), ("RIDGE", z(31, 6)),
        ("EAVE", z(19)),
    ]
    let kept = ElevationView.spaced(levels, view: view).map(\.name)
    let heights = ElevationView.spaced(levels, view: view).map(\.z)
    // At 1/8" a foot is 3.2 mm of paper: the eave 6" under the second floor and the ridge 8" under the top one
    // would print over them.
    #expect(heights == [0, z(11), z(19), z(31, 6)])
    #expect(kept == ["FIRST FLOOR", "SECOND FLOOR", "EAVE", "RIDGE"])
}

@Test func roofMarksPrintToTheHalfInch() {
    let ridge = (name: "RIDGE", z: z(15, 1) + Length.inches(1).ticks * 19 / 32)
    #expect(ElevationView.markHeight(ridge, units: .feetInchesFractions).ticks == z(15, 1) + Length.inches(1).ticks / 2)
    let floor = (name: "SECOND FLOOR", z: z(11) + 3)
    #expect(ElevationView.markHeight(floor, units: .feetInchesFractions).ticks == z(11) + 3)
}

private func feet(_ value: Double) -> Length { Length(ticks: Int64((value * Double(Length.feet(1).ticks)).rounded())) }

/// A house of one building: storeys at the given elevations in feet, and 8' walls around `corners` on the
/// storey at `wallsOn`.
private func house(storeys elevations: [Int64], corners: [(Double, Double)], wallsOn: Int = 0) -> ModelDocument {
    var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(UUID()), name: "Probe"),
                                 buildings: [], storeys: [], walls: [], openings: [], rooms: [])
    let building = BuildingID(UUID())
    document.buildings.append(Building(id: building, projectID: document.project.id, name: "House"))
    for elevation in elevations {
        document.storeys.append(Storey(id: StoreyID(UUID()), buildingID: building, name: "L\(elevation)",
                                       elevation: .feet(elevation)))
    }
    let points = corners.map { Point2(x: feet($0.0), y: feet($0.1)) }
    for index in points.indices {
        document.walls.append(Wall(id: WallID(UUID()), storeyID: document.storeys[wallsOn].id, start: points[index],
                                   end: points[(index + 1) % points.count], thickness: .inches(6), height: .feet(8)))
    }
    return document
}

@Test func aHouseSetAtAnAngleStillHasElevations() throws {
    // A 30' by 20' box turned 30°: no wall is square to any elevation.
    let (c, s) = (cos(Double.pi / 6), sin(Double.pi / 6))
    let box: [(Double, Double)] = [(0, 0), (30, 0), (30, 20), (0, 20)]
    let corners = box.map { ($0.0 * c - $0.1 * s, $0.0 * s + $0.1 * c) }
    var document = house(storeys: [0], corners: corners)
    document.sheets = [Sheet(id: SheetID(UUID()), number: "A-201", title: "Elevations", paper: .archD,
                             scale: .quarterInch, views: [.elevation(direction: .south)])]
    let meshes = try HestiaGeometryEngine().meshes(of: document)
    #expect(ElevationView.meshExtent(document, .south, meshes: meshes) != nil)
    let sheet = try #require(try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine()).first)
    #expect(sheet.content.items.contains { $0.style == ElevationView.profileStyle })
    #expect(sheet.content.items.contains { $0.style == ElevationView.groundStyle })
}

@Test func aBasementIsBelowTheGroundLineNotUnderIt() throws {
    // Walls on the ground floor, a basement 8' down: the ground is at the ground floor.
    let document = house(storeys: [-8, 0], corners: [(0, 0), (30, 0), (30, 20), (0, 20)], wallsOn: 1)
    #expect(ElevationView.grade(document) == 0)
    let meshes = try HestiaGeometryEngine().meshes(of: document)
    let view = ViewTransform(scale: .quarterInch, modelOrigin: paperPoint(0, 0), paperOrigin: paperPoint(0, 0))
    let items = ElevationView.items(document, .south, view: view, meshes: meshes)
    let ground: [Int64] = items.compactMap { item -> Int64? in
        guard item.style == ElevationView.groundStyle, case let .line(start, _) = item.primitive else { return nil }
        return start.y.ticks
    }
    #expect(ground == [view.paper(paperPoint(0, 0)).y.ticks])
    #expect(!ElevationView.levels(document, .south).isEmpty)
}

@Test func theDefaultSectionCutsThroughTheLargestRoof() throws {
    var document = house(storeys: [0], corners: [(0, 0), (100, 0), (100, 40), (0, 40)])
    let storey = document.storeys[0].id
    let plane = RoofPlane(pitchRisePer12: .inches(6), overhang: .feet(1))
    func roof(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Roof {
        Roof(id: RoofID(UUID()), storeyID: storey,
             footprint: [(x0, y0), (x1, y0), (x1, y1), (x0, y1)].map { Point2(x: feet($0.0), y: feet($0.1)) },
             eaveHeight: .feet(8), planes: Array(repeating: plane, count: 4))
    }
    // The large roof runs east to west over x 70'–100', its ridge at y 10'; a small one sits at the west end.
    document.roofs = [roof(0, 0, 10, 10), roof(70, 0, 100, 20)]
    let line = try #require(SchematicDrawingSet.defaultSectionLine(document))
    #expect(line.start.x == feet(85) && line.end.x == feet(85), "cut at \(line.start.x)")
}
