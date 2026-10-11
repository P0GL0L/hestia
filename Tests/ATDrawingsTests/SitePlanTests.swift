@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

private func ft(_ feet: Int64) -> Length { .feet(feet) }
private func pt(_ x: Int64, _ y: Int64) -> Point2 { Point2(x: ft(x), y: ft(y)) }

/// A document with no buildings yet.
private func empty() -> ModelDocument {
    ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(UUID()), name: "Site"), buildings: [],
                  storeys: [], walls: [], openings: [], rooms: [])
}

/// Four 6" walls around a box, on `storey`.
private func box(_ x0: Int64, _ y0: Int64, _ x1: Int64, _ y1: Int64, on storey: StoreyID) -> [Wall] {
    let corners = [pt(x0, y0), pt(x1, y0), pt(x1, y1), pt(x0, y1)]
    return (0..<4).map { index in
        Wall(id: WallID(UUID()), storeyID: storey, start: corners[index], end: corners[(index + 1) % 4],
             thickness: .inches(6), height: ft(8))
    }
}

/// Adds a building with storeys at the given elevations, in feet; returns their IDs in that order.
private func addBuilding(_ document: inout ModelDocument, elevations: [Int64]) -> [StoreyID] {
    let building = BuildingID(UUID())
    document.buildings.append(Building(id: building, projectID: document.project.id, name: "B"))
    return elevations.map { elevation in
        let id = StoreyID(UUID())
        document.storeys.append(Storey(id: id, buildingID: building, name: "L\(elevation)", elevation: ft(elevation)))
        return id
    }
}

/// Whether a point lies inside a polygon.
private func inside(_ point: Point2, _ polygon: [Point2]) -> Bool {
    RasterOutline.inside(Double(point.x.ticks), Double(point.y.ticks), polygon.map { Double($0.x.ticks) },
                         polygon.map { Double($0.y.ticks) })
}

@Test func aCourtyardStaysOpenInTheHatch() {
    let outer = [pt(0, 0), pt(40, 0), pt(40, 40), pt(0, 40)]
    let hole = [pt(10, 10), pt(10, 30), pt(30, 30), pt(30, 10)]
    let lines = SitePlanView.hatchLines([outer, hole], spacing: ft(1).ticks)
    #expect(!lines.isEmpty)
    for (a, b) in lines {
        let middle = paperPoint((a.x.ticks + b.x.ticks) / 2, (a.y.ticks + b.y.ticks) / 2)
        #expect(inside(middle, outer) && !inside(middle, hole))
    }
}

@Test func everyBuildingIsDrawnWhereItMeetsTheGround() {
    var document = empty()
    // A house with a basement under it, and a detached garage.
    let house = addBuilding(&document, elevations: [-9, 0, 10])
    let garage = addBuilding(&document, elevations: [0])
    document.walls += box(-20, -20, 60, 60, on: house[0])   // the basement runs far beyond the house
    document.walls += box(0, 0, 30, 20, on: house[1])
    document.walls += box(50, 0, 70, 20, on: garage[0])
    let atGrade: Set<StoreyID> = Set(SitePlanView.gradeStoreys(document))
    let expected: Set<StoreyID> = [house[1], garage[0]]
    #expect(atGrade == expected)
    // Walls alone, with no rooms, leave each building's inside open: an outer loop and a hole for each.
    let loops = SitePlanView.footprint(document).filter { SitePlanView.signedTwiceArea($0) > 0 }
    #expect(loops.count == 2)
    #expect(loops.contains { inside(pt(15, 10), $0) })
    #expect(loops.contains { inside(pt(60, 10), $0) })
    #expect(!loops.contains { inside(pt(-10, -10), $0) }, "the basement is not at grade")
}

@Test func theDripLineFollowsAnLShapedRoof() throws {
    // An L, counterclockwise, with a 2' overhang on every edge but 1' on the first.
    let footprint = [pt(0, 0), pt(30, 0), pt(30, 10), pt(10, 10), pt(10, 30), pt(0, 30)]
    var planes = Array(repeating: RoofPlane(pitchRisePer12: .inches(6), overhang: ft(2)), count: 6)
    planes[0].overhang = ft(1)
    let roof = Roof(id: RoofID(UUID()), storeyID: StoreyID(UUID()), footprint: footprint, eaveHeight: ft(8),
                    planes: planes)
    let drip = SitePlanView.roofOutline(roof)
    #expect(drip == [pt(-2, -1), pt(32, -1), pt(32, 12), pt(12, 12), pt(12, 32), pt(-2, 32)])
    // Drawn from the engine's mesh, it is an L too: the inside corner of the L is open.
    var document = empty()
    let storey = addBuilding(&document, elevations: [0])[0]
    document.walls += box(0, 0, 30, 30, on: storey)
    document.roofs = [Roof(id: roof.id, storeyID: storey, footprint: footprint, eaveHeight: ft(8), planes: planes)]
    let meshes = try HestiaGeometryEngine().meshes(of: document).filter { $0.elementID == roof.id.rawValue }
    #expect(!meshes.isEmpty)
    let outlines = SitePlanView.dripLine(document, roofMeshes: meshes)
    #expect(outlines.contains { inside(pt(5, 5), $0) })
    #expect(!outlines.contains { inside(pt(20, 20), $0) })
}

@Test func lotSideLengthsSitOutsideTheLotAndAreAvoided() {
    let lot = [pt(0, 0), pt(100, 0), pt(100, 80), pt(0, 80)]
    let view = ViewTransform(scale: .eighthInch, modelOrigin: paperPoint(0, 0), paperOrigin: paperPoint(0, 0))
    var taken: [PaperRect] = []
    let items = SitePlanView.sideLengths(lot, view: view, units: .feetInchesFractions, taken: &taken)
    #expect(items.count == 4)
    #expect(taken.count == 4)
    let paperLot = lot.map { view.paper($0) }
    for item in items {
        guard case let .text(position, _, _, _, _) = item.primitive else { continue }
        #expect(!inside(position, paperLot))
    }
    // No label box straddles the property line.
    for rect in taken {
        let corners = rect.corners()
        #expect(corners.allSatisfy { !inside($0, paperLot) })
    }
}

@Test func aLongScheduleStaysInsideItsSlotAndSaysWhatIsLeftOut() {
    let rows = (0..<200).map { ["W\($0)", "3'-0\"", "4'-0\""] }
    let table = ScheduleView.Table(title: "Window Schedule",
                                   columns: [("MARK", mmTicks(20)), ("WIDTH", mmTicks(30)), ("HEIGHT", mmTicks(30))],
                                   rows: rows)
    let width = mmTicks(300)
    let items = ScheduleView.items(table, at: paperPoint(0, mmTicks(500)), height: mmTicks(400), width: width)
    let xs: [Int64] = items.flatMap { item -> [Int64] in
        switch item.primitive {
        case let .line(start, end): return [start.x.ticks, end.x.ticks]
        case let .text(position, _, _, _, _): return [position.x.ticks]
        default: return []
        }
    }
    #expect((xs.max() ?? 0) <= width)
    #expect(items.contains { item in
        guard case let .text(_, string, _, _, _) = item.primitive else { return false }
        return string.hasSuffix("MORE ROWS DO NOT FIT THIS SHEET")
    })
}

@Test func fallbackScalesStayInTheirFamilyLargestFirst() {
    let extent = (min: paperPoint(0, 0), max: paperPoint(Length.millimeters(5000).ticks, 0))
    let slot = PaperRect(minX: 0, minY: 0, width: mmTicks(102), height: mmTicks(102))
    #expect(SchematicDrawingSet.fittingScale(extent: extent, in: slot, imperial: false) == .oneTo50)
    #expect(SchematicDrawingSet.fittingScale(extent: extent, in: slot, imperial: true)
        == SchematicDrawingSet.threeSixteenthsInch)
    for family in [SchematicDrawingSet.imperialScales, SchematicDrawingSet.metricScales] {
        let ratios = family.map(\.modelUnitsPerPaperUnit)
        #expect(ratios == ratios.sorted())
    }
}

@Test func aSpaceUnderTheRoofIsHatchedButACourtyardIsNot() {
    // A ring of walls with no rooms: open inside, unless a roof covers it.
    var document = empty()
    let storey = addBuilding(&document, elevations: [0])[0]
    document.walls += box(0, 0, 40, 40, on: storey)
    let view = ViewTransform(scale: .eighthInch, modelOrigin: paperPoint(0, 0), paperOrigin: paperPoint(0, 0))
    let area = PaperRect(minX: 0, minY: 0, width: mmTicks(400), height: mmTicks(400))
    func hatchedAtMiddle(_ document: ModelDocument) -> Bool {
        // Off the middle, where the building's name masks the hatch.
        let middle = view.paper(pt(10, 30))
        return SitePlanView.items(document, view: view, area: area).contains { item in
            guard item.style == SitePlanView.patternStyle, case let .line(start, end) = item.primitive else {
                return false
            }
            // A 45° line through the middle point, to within a millimetre.
            let (dx, dy) = (end.x.ticks - start.x.ticks, end.y.ticks - start.y.ticks)
            let cross = Double(dx) * Double(middle.y.ticks - start.y.ticks)
                - Double(dy) * Double(middle.x.ticks - start.x.ticks)
            let length = (Double(dx) * Double(dx) + Double(dy) * Double(dy)).squareRoot()
            return abs(cross) / length < Double(mmTicks(1)) && min(start.x.ticks, end.x.ticks) <= middle.x.ticks
                && max(start.x.ticks, end.x.ticks) >= middle.x.ticks
        }
    }
    #expect(!hatchedAtMiddle(document), "a courtyard open to the sky")
    let corners = [pt(0, 0), pt(40, 0), pt(40, 40), pt(0, 40)]
    document.roofs = [Roof(id: RoofID(UUID()), storeyID: storey, footprint: corners, eaveHeight: ft(8),
                           planes: Array(repeating: RoofPlane(pitchRisePer12: .inches(6), overhang: ft(1)), count: 4))]
    #expect(hatchedAtMiddle(document), "a room under the roof")
}

@Test func aSheetWithNoScaleInAnImperialSetFallsBackToAnImperialScale() throws {
    // A house with no sheets of its own: its default elevations sheet has no scale, and the plans beside it are
    // at 1/4", so the elevations are drawn and titled at an inch scale, not a ratio.
    var document = empty()
    let storey = addBuilding(&document, elevations: [0])[0]
    document.walls += box(0, 0, 90, 60, on: storey)
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
    let elevations = try #require(sheets.first { $0.number == "A-201" })
    let scale = try #require(elevations.scale)
    #expect(scale.label.contains("\""), "elevations at \(scale.label)")
}

@Test func aShortScheduleWiderThanItsSlotIsSetSmallerToFit() {
    let table = ScheduleView.Table(title: "Door Schedule",
                                   columns: [("MARK", mmTicks(40)), ("WIDTH", mmTicks(50)), ("HEIGHT", mmTicks(50))],
                                   rows: [["D1", "3'-0\"", "6'-8\""], ["D2", "2'-8\"", "6'-8\""]])
    let width = mmTicks(100)
    let items = ScheduleView.items(table, at: paperPoint(0, mmTicks(300)), height: mmTicks(250), width: width)
    let xs: [Int64] = items.flatMap { item -> [Int64] in
        if case let .line(start, end) = item.primitive { return [start.x.ticks, end.x.ticks] }
        return []
    }
    #expect((xs.max() ?? 0) <= width, "the 140 mm table is set within 100 mm")
    // Every cell's text stays inside its column.
    let rights: [Double] = items.compactMap { item -> Double? in
        guard case let .text(position, string, height, _, .left) = item.primitive else { return nil }
        return Double(position.x.ticks) + HelveticaMetrics.width(of: string) * Double(height.ticks) / 0.718
    }
    #expect(rights.allSatisfy { $0 <= Double(width) })
    // One that would have to shrink below 60 % is refused, plainly.
    let narrow = ScheduleView.items(table, at: paperPoint(0, mmTicks(300)), height: mmTicks(250), width: mmTicks(60))
    #expect(narrow.count == 1)
    if case let .text(_, string, _, _, _) = narrow.first?.primitive {
        #expect(string == "DOOR SCHEDULE IS TOO WIDE FOR THIS SHEET")
    }
}

@Test func aCellTooLongForItsColumnIsCutShort() {
    let cell = ScheduleView.shortened("Floor-to-ceiling window", to: mmTicks(20), height: .millimeters(2))
    #expect(cell.hasSuffix("..."))
    #expect(HelveticaMetrics.width(of: cell) * Double(Length.millimeters(2).ticks) / 0.718 <= Double(mmTicks(20)))
    #expect(ScheduleView.shortened("D1", to: mmTicks(20), height: .millimeters(2)) == "D1")
}

@Test func theSiteExtentReachesTheDripLine() {
    var document = empty()
    let storey = addBuilding(&document, elevations: [0])[0]
    document.walls += box(-5, -5, 5, 5, on: storey)
    let corners = [pt(-5, -5), pt(5, -5), pt(5, 5), pt(-5, 5)]
    document.roofs = [Roof(id: RoofID(UUID()), storeyID: storey, footprint: corners, eaveHeight: ft(8),
                           planes: Array(repeating: RoofPlane(pitchRisePer12: .inches(6), overhang: ft(15)), count: 4))]
    let extent = SitePlanView.extent(document)
    // The drip line runs 15' past the 5' walls, to 20' each way.
    #expect((extent?.min.x.ticks ?? 0) <= ft(-20).ticks && (extent?.max.x.ticks ?? 0) >= ft(20).ticks)
    #expect((extent?.min.y.ticks ?? 0) <= ft(-20).ticks && (extent?.max.y.ticks ?? 0) >= ft(20).ticks)
}

@Test func aCourtyardPartlyRoofedStaysOpen() {
    let hole = [pt(10, 10), pt(10, 30), pt(30, 30), pt(30, 10)]
    let half = [pt(0, 0), pt(20, 0), pt(20, 40), pt(0, 40)]
    let whole = [pt(0, 0), pt(40, 0), pt(40, 40), pt(0, 40)]
    #expect(!SitePlanView.covered(hole, by: [half]), "half under a roof is still open to the sky")
    #expect(SitePlanView.covered(hole, by: [whole]))
}

@Test func lotSideLengthsDoNotPrintOverEachOther() {
    // A long thin lot: its 3' ends would set their lengths over the long sides' if nothing checked.
    let lot = [pt(0, 0), pt(3, 0), pt(3, 120), pt(0, 120)]
    let view = ViewTransform(scale: .eighthInch, modelOrigin: paperPoint(0, 0), paperOrigin: paperPoint(0, 0))
    var taken: [PaperRect] = []
    _ = SitePlanView.sideLengths(lot, view: view, units: .feetInchesFractions, taken: &taken)
    for (index, rect) in taken.enumerated() {
        #expect(!taken[(index + 1)...].contains { $0.intersects(rect) })
    }
    #expect(taken.count >= 2, "the long sides keep their lengths")
}
