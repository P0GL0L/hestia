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

@Test func aSlopeTheElevationShowsCarriesItsPitch() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/rect-cottage.json")
    let cottage = try ModelDocument.decode(from: Data(contentsOf: url))
    let sheets = try SchematicDrawingSet().sheets(for: cottage, geometry: HestiaGeometryEngine())
    let elevations = try #require(sheets.first { $0.number == "A-201" })
    let marks = elevations.content.items.filter { $0.style == ElevationView.pitchStyle }
    let figures: [String] = marks.compactMap { item in
        guard case let .text(_, string, _, _, _) = item.primitive else { return nil }
        return string
    }
    // The cottage's hip is 6 in 12: each elevation that shows a slope marks it once.
    #expect(figures.contains("12") && figures.contains("6"))
    #expect(figures.allSatisfy { $0 == "12" || $0 == "6" })
    // The triangle's long side runs at the roof's slope.
    for item in marks {
        guard case let .polyline(points, true) = item.primitive, points.count == 3 else { continue }
        let (low, high) = (points[0], points[1])
        let rise: Double = Double(high.y.ticks - low.y.ticks), run: Double = abs(Double(high.x.ticks - low.x.ticks))
        #expect(abs(rise / run - 0.5) < 0.01)
    }
    #expect(DrawingAudit.findings(elevations).isEmpty)
}

@Test func pitchFiguresStayInTheirViewsRoom() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/rect-cottage.json")
    let cottage = try ModelDocument.decode(from: Data(contentsOf: url))
    let meshes = try HestiaGeometryEngine().meshes(of: cottage)
    let roofIDs = Set(cottage.roofs.map(\.id.rawValue))
    let roofMeshes = meshes.filter { mesh in mesh.elementID.map { roofIDs.contains($0) } ?? false }
    let extent = try #require(ElevationView.meshExtent(cottage, .south, meshes: meshes))
    let area = PaperRect(minX: 0, minY: 0, width: mmTicks(400), height: mmTicks(200))
    let view = SchematicDrawingSet.place(extent: extent, in: area, sheetScale: nil, imperial: true).transform
    func figures(_ room: PaperRect?) -> [Point2] {
        ElevationView.meshItems(cottage, .south, view: view, meshes: meshes, roofMeshes: roofMeshes, room: room)
            .filter { $0.style == ElevationView.pitchStyle }
            .compactMap { item in
                guard case let .text(position, _, _, _, _) = item.primitive else { return nil }
                return position
            }
    }
    let free = figures(nil)
    let lowest = try #require(free.map(\.y.ticks).min())
    // A room that stops below the figures: the mark that would cross into the view above is left out.
    let room = PaperRect(minX: 0, minY: 0, width: mmTicks(400), height: lowest - mmTicks(1))
    let kept = figures(room)
    #expect(kept.count < free.count)
    #expect(kept.allSatisfy { $0.y.ticks < room.maxY })
}

private let pitchProbeScale = DrawingScale(label: "1:1", modelUnitsPerPaperUnit: 1)

private func pitchProbe(_ rises: [Length]) -> (document: ModelDocument, roofID: UUID) {
    var document = house(storeys: [0], corners: [(0, 0), (30, 0), (30, 20), (0, 20)])
    let roof = Roof(id: RoofID(UUID()), storeyID: document.storeys[0].id,
                    footprint: [(0, 0), (30, 0), (30, 20), (0, 20)].map { Point2(x: feet($0.0), y: feet($0.1)) },
                    eaveHeight: .feet(8),
                    planes: rises.map { RoofPlane(pitchRisePer12: $0, overhang: .feet(1)) })
    document.roofs = [roof]
    return (document, roof.id.rawValue)
}

private func pitchSegment(_ roofID: UUID, paperLength: Double, rise: Length) -> HiddenLines.Segment {
    let slope = Double(rise.ticks) / Double(Length.inches(12).ticks)
    let run = paperLength * Double(Length.ticksPerMillimeter) / hypot(1, slope)
    return HiddenLines.Segment(start: (h: 0, v: 0), end: (h: run, v: run * slope),
                               kind: .outline, elementID: roofID)
}

private func pitchItems(_ document: ModelDocument, _ segments: [HiddenLines.Segment], drawn: [DisplayItem] = [],
                        within: [Point2]? = nil) -> [DisplayItem] {
    let view = ViewTransform(scale: pitchProbeScale, modelOrigin: paperPoint(0, 0), paperOrigin: paperPoint(0, 0))
    return ElevationView.pitchMarks(document, segments: segments, view: view, drawn: drawn, within: within)
}

@Test func aVisibleSlopeMatchesOnlyItsExactStoredPitch() {
    let six = Length.inches(6)
    let sixAndAnEighth = Length(ticks: six.ticks + Length.inches(1).ticks / 8)
    let probe = pitchProbe([six, sixAndAnEighth])
    let items = pitchItems(probe.document, [pitchSegment(probe.roofID, paperLength: 40, rise: sixAndAnEighth)])
    let figures = items.compactMap { item -> String? in
        guard case let .text(_, string, _, _, _) = item.primitive else { return nil }
        return string
    }
    #expect(items.filter { if case .polyline = $0.primitive { return true } else { return false } }.count == 1)
    #expect(Set(figures) == ["12", "6.1"])
}

@Test func aPitchIsMarkedOnceAcrossSeveralVisibleEdges() {
    let rise = Length.inches(6)
    let probe = pitchProbe([rise])
    let first = pitchSegment(probe.roofID, paperLength: 40, rise: rise)
    var second = pitchSegment(probe.roofID, paperLength: 40, rise: rise)
    second.start.h += Double(mmTicks(80))
    second.end.h += Double(mmTicks(80))
    let items = pitchItems(probe.document, [first, second])
    #expect(items.filter { if case .polyline = $0.primitive { return true } else { return false } }.count == 1)
}

@Test func onlyVisibleSlopeEdgesAtLeastFifteenMillimetresCarryAPitch() {
    let rise = Length.inches(6)
    let probe = pitchProbe([rise])
    func count(_ length: Double) -> Int {
        pitchItems(probe.document, [pitchSegment(probe.roofID, paperLength: length, rise: rise)])
            .filter { if case .polyline = $0.primitive { return true } else { return false } }.count
    }
    #expect(count(14.9) == 0)
    #expect(count(15.0) == 1)
    #expect(count(15.1) == 1)
    var hidden = pitchSegment(probe.roofID, paperLength: 40, rise: rise)
    hidden.elementID = UUID()
    #expect(pitchItems(probe.document, [hidden]).isEmpty)
}

@Test func aPitchMarkWhoseStrokeLeavesTheViewIsOmitted() {
    let rise = Length.inches(6)
    let probe = pitchProbe([rise])
    let segment = HiddenLines.Segment(start: (h: 0, v: 0),
                                      end: (h: Double(mmTicks(60)), v: Double(mmTicks(30))),
                                      kind: .outline, elementID: probe.roofID)
    // The first candidate's text fits from x 15.5–26.5 mm, but its triangle reaches x 27 mm. The other
    // candidates' figures fall outside this narrow slot, so the complete mark must be omitted.
    let room = PaperRect(minX: mmTicks(15) + mmTicks(1) / 2, minY: 0,
                         width: mmTicks(11), height: mmTicks(50))
    #expect(pitchItems(probe.document, [segment], within: room.corners()).isEmpty)
}

@Test func aPitchMarkWhoseLegCrossesTheDrawingIsOmitted() {
    let rise = Length.inches(6)
    let probe = pitchProbe([rise])
    let segment = HiddenLines.Segment(start: (h: 0, v: 0),
                                      end: (h: Double(mmTicks(60)), v: Double(mmTicks(30))),
                                      kind: .outline, elementID: probe.roofID)
    let style = DisplayStyle(layer: "A-ROOF", pen: .thin)
    let blockers = [1.0 / 3, 0.25, 0.5].map { share -> DisplayItem in
        let lowX = Double(mmTicks(60)) * share
        let lowY = Double(mmTicks(30)) * share + Double(mmTicks(2))
        let topY = lowY + Double(mmTicks(7)) * 0.5
        return DisplayItem(.line(start: paperPoint(Int64(lowX + Double(mmTicks(3))), Int64(topY - 1)),
                                 end: paperPoint(Int64(lowX + Double(mmTicks(3))), Int64(topY + 1))), style: style)
    }
    #expect(pitchItems(probe.document, [segment], drawn: blockers).isEmpty)
}
