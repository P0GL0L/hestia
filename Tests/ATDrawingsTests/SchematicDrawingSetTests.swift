@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

/// Plan outlines from ATGeometry's straight-wall outliner; room areas from each room's interior box.
/// Test scaffolding only: the real GeometryEngine conformance belongs to Stream A.
private struct OutlinerGeometry: GeometryEngine {
    func planView(of document: ModelDocument, storey: StoreyID) throws -> [ClassifiedOutline] {
        let walls = document.walls.filter { $0.storeyID == storey }
        let outlines = try StraightWallOutlines().outlines(for: walls)
        return walls.compactMap { wall in
            outlines[wall.id].map {
                ClassifiedOutline(elementID: wall.id.rawValue, kind: .wall, classification: .cut, polygon: $0.vertices)
            }
        }
    }

    func roomAreas(of document: ModelDocument, storey: StoreyID) throws -> [RoomID: Area] {
        var areas: [RoomID: Area] = [:]
        for room in document.rooms where room.storeyID == storey {
            let walls = room.boundaryWallIDs.compactMap { id in document.walls.first { $0.id == id } }
            let corners = FloorPlanView.roomPolygon(walls) ?? []
            let xs = corners.map(\.x.ticks), ys = corners.map(\.y.ticks)
            let inset = walls.map(\.thickness.ticks).max()!
            areas[room.id] = Area(tickSquares: (xs.max()! - xs.min()! - inset) * (ys.max()! - ys.min()! - inset))
        }
        return areas
    }

    func meshes(of document: ModelDocument) throws -> [Mesh] { [] }

    func section(of document: ModelDocument, along line: SectionLine) throws -> [ClassifiedOutline] { [] }
}

private func cottage() throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/rect-cottage.json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

private func strings(_ sheet: SheetDrawing) -> [String] {
    sheet.content.items.compactMap {
        if case let .text(_, string, _, _, _) = $0.primitive { return string }
        return nil
    }
}

@Test func cottageSheetSetFollowsTheModelSheets() throws {
    let sheets = try SchematicDrawingSet(issueDate: "2026-10-06").sheets(for: cottage(), geometry: OutlinerGeometry())
    #expect(sheets.map(\.number) == ["A-101", "A-201", "A-601"])
    for sheet in sheets {
        let text = strings(sheet)
        #expect(text.contains("SCHEMATIC"))
        #expect(text.contains("NOT FOR CONSTRUCTION"))
        #expect(text.contains(sheet.number))
        #expect(text.contains("Rect Cottage"))
        #expect(text.contains("2026-10-06"))
        let bounds = try #require(sheet.content.bounds)
        #expect(bounds.min.x.ticks >= 0 && bounds.min.y.ticks >= 0)
        #expect(bounds.max.x <= sheet.paper.width && bounds.max.y <= sheet.paper.height)
    }
    #expect(strings(sheets[1]).contains("SOUTH ELEVATION"))
    #expect(strings(sheets[2]).contains("DOOR SCHEDULE"))
}

@Test func cottagePlanDrawsWallsOpeningsAndRoomTags() throws {
    let document = try cottage()
    let plan = try SchematicDrawingSet().sheets(for: document, geometry: OutlinerGeometry())[0]
    let items = plan.content.items
    let wallIDs = Set(document.walls.map(\.id.rawValue))
    let walls = items.filter { $0.style.layer == "A-WALL" && wallIDs.contains($0.elementID ?? UUID()) }
    #expect(walls.count == 7)
    #expect(items.filter { $0.style.layer == "A-WALL-PATT" }.count == 7)
    let openingIDs = Set(items.filter { ["A-DOOR", "A-GLAZ"].contains($0.style.layer) }.compactMap(\.elementID))
    #expect(openingIDs == Set(document.openings.map(\.id.rawValue)))
    let text = strings(plan)
    for name in ["LIVING", "KITCHEN", "UTILITY", "BEDROOM", "BATH", "BEDROOM 2"] { #expect(text.contains(name)) }
    #expect(text.contains("168 SF"))
    #expect(text.contains("GROUND FLOOR PLAN"))
    #expect(text.contains("SCALE: 1/4\" = 1'-0\""))
}

@Test func planPrintsTrueToScale() throws {
    let document = try cottage()
    let plan = try SchematicDrawingSet().sheets(for: document, geometry: OutlinerGeometry())[0]
    // The south wall is 38'-0" long outside to outside: 9 1/2" on paper at 1/4" = 1'-0".
    let south = try #require(plan.content.items.first { $0.elementID == document.walls[0].id.rawValue
        && $0.style.layer == "A-WALL" })
    guard case let .polyline(points, true) = south.primitive else { Issue.record("not a closed polyline"); return }
    let width = points.map(\.x.ticks).max()! - points.map(\.x.ticks).min()!
    let expected = DrawingScale.quarterInch.paper(.feet(38)).ticks
    #expect(abs(width - expected) <= Length.millimeters(1).ticks / 10)
}

@Test func hingedDoorSwingsIntoTheRequestedSide() {
    let wall = Wall(id: WallID(UUID()), storeyID: StoreyID(UUID()), start: Point2(x: .millimeters(0), y: .millimeters(0)),
                    end: Point2(x: .millimeters(4000), y: .millimeters(0)), thickness: .millimeters(200),
                    height: .millimeters(2400))
    let door = Opening(id: OpeningID(UUID()), wallID: wall.id, offsetAlongWall: .millimeters(1000),
                       width: .millimeters(900), height: .millimeters(2100), sillHeight: .millimeters(0),
                       kind: .singleDoor, swing: DoorSwing(hinge: .nearStart, opensToward: .left))
    let view = ViewTransform(scale: .oneTo50, modelOrigin: Point2(x: .millimeters(0), y: .millimeters(0)),
                             paperOrigin: Point2(x: .millimeters(0), y: .millimeters(0)))
    let items = FloorPlanView.symbol(for: door, in: wall, view: view)
    #expect(items.count == 4)
    guard case let .line(hinge, leafEnd) = items[2].primitive,
          case let .arc(center, radius, start, sweep) = items[3].primitive else {
        Issue.record("expected jambs, leaf, and arc"); return
    }
    // Hinge at the wall's left face (+y), leaf straight up into the room, arc back down to the far jamb.
    #expect(hinge == Point2(x: .millimeters(20), y: .millimeters(2)))
    #expect(leafEnd == Point2(x: .millimeters(20), y: .millimeters(20)))
    #expect(center == hinge && radius == .millimeters(18))
    #expect(start == .degrees(90) && sweep == .degrees(-90))
}

@Test func windowsAndSlidingDoorsHaveNoSwing() {
    let wall = Wall(id: WallID(UUID()), storeyID: StoreyID(UUID()), start: Point2(x: .millimeters(0), y: .millimeters(0)),
                    end: Point2(x: .millimeters(0), y: .millimeters(4000)), thickness: .millimeters(200),
                    height: .millimeters(2400))
    let view = ViewTransform(scale: .oneTo50, modelOrigin: wall.start, paperOrigin: wall.start)
    let window = Opening(id: OpeningID(UUID()), wallID: wall.id, offsetAlongWall: .millimeters(500),
                         width: .millimeters(1200), height: .millimeters(1200), sillHeight: .millimeters(900))
    #expect(FloorPlanView.symbol(for: window, in: wall, view: view).map(\.style.layer) == Array(repeating: "A-GLAZ", count: 4))
    let slider = Opening(id: OpeningID(UUID()), wallID: wall.id, offsetAlongWall: .millimeters(2000),
                         width: .millimeters(1800), height: .millimeters(2100), sillHeight: .millimeters(0), kind: .slidingDoor)
    let items = FloorPlanView.symbol(for: slider, in: wall, view: view)
    #expect(items.count == 3)
    #expect(!items.contains { if case .arc = $0.primitive { return true }; return false })
}

@Test func modelsWithoutSheetsGetOnePlanPerStorey() throws {
    var document = try cottage()
    document.sheets = []
    let sheets = try SchematicDrawingSet().sheets(for: document, geometry: OutlinerGeometry())
    #expect(sheets.map(\.number) == ["A-101"])
    #expect(sheets[0].paper == .archD && sheets[0].scale == .quarterInch)
}

@Test func pdfExporterWritesOnePagePerSheet() throws {
    let sheets = try SchematicDrawingSet().sheets(for: cottage(), geometry: OutlinerGeometry())
    let pdf = try SheetPDFExporter().export(.sheets(sheets))
    let text = String(decoding: pdf, as: UTF8.self)
    #expect(text.contains("/Count 3"))
    #expect(text.contains("(NOT FOR CONSTRUCTION) Tj"))
    #expect(throws: ExchangeError.unsupportedPayload(format: "pdf")) {
        try SheetPDFExporter().export(.meshes([], materials: []))
    }
}

@Test func roomTagsSitInsideTheirRooms() throws {
    let document = try cottage()
    let walls = { (room: Room) in room.boundaryWallIDs.compactMap { id in document.walls.first { $0.id == id } } }
    let living = try #require(document.rooms.first { $0.name == "Living" })
    let bath = try #require(document.rooms.first { $0.name == "Bath" })
    let livingCenter = FloorPlanView.centroid(try #require(FloorPlanView.roomPolygon(walls(living))))
    let bathCenter = FloorPlanView.centroid(try #require(FloorPlanView.roomPolygon(walls(bath))))
    // Living spans x -3" to 14'-3", y -3" to 12'-3"; Bath x 14'-3" to 24'-9", y 12'-3" to 22'-9".
    #expect(livingCenter == Point2(x: .inches(84), y: .inches(72)))
    #expect(bathCenter == Point2(x: .inches(234), y: .inches(210)))
}
