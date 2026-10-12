@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

private func fixture(_ name: String) throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/\(name).json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

/// Everything a sheet draws, as one box on paper, in ticks.
private func extent(_ sheet: SheetDrawing) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    let parts = DrawingAudit.parts(sheet.content.items, scale: sheet.scale)
    var xs: [Double] = [], ys: [Double] = []
    for stroke in parts.strokes { xs += [stroke.a.x, stroke.b.x]; ys += [stroke.a.y, stroke.b.y] }
    for label in parts.labels { xs += label.box.corners.map(\.x); ys += label.box.corners.map(\.y) }
    for area in parts.areas { xs += area.boundary.map(\.x); ys += area.boundary.map(\.y) }
    return (xs.min() ?? 0, ys.min() ?? 0, xs.max() ?? 0, ys.max() ?? 0)
}

@Test(arguments: SchematicDrawingSet.papers)
func everySheetSizeKeepsTheSetOnThePaperAndClearOfItself(paper: PaperSize) throws {
    for name in ["rect-cottage", "l-house", "rect-cottage, set added"] {
        var document = try fixture(String(name.prefix { $0 != "," }))
        // The model's own sheets, and the set the app adds on its own when there are none.
        if name.hasSuffix("added") { document.sheets = [] }
        let sheets = try SchematicDrawingSet(paper: paper).sheets(for: document, geometry: HestiaGeometryEngine())
        #expect(!sheets.isEmpty)
        for sheet in sheets {
            #expect(sheet.paper == paper, "\(name) \(sheet.number) is on \(sheet.paper.name)")
            let box = extent(sheet)
            #expect(box.minX >= 0 && box.minY >= 0, "\(paper.name) \(name) \(sheet.number) runs off: \(box)")
            #expect(box.maxX <= Double(paper.width.ticks) && box.maxY <= Double(paper.height.ticks),
                    "\(paper.name) \(name) \(sheet.number) runs off: \(box)")
            let found = DrawingAudit.findings(sheet)
            #expect(found.isEmpty, "\(paper.name) \(name) \(sheet.number): \(found)")
        }
    }
}

@Test func withNoPaperChosenStoredSheetsKeepTheirsAndAddedOnesAreArchD() throws {
    var cottage = try fixture("rect-cottage")
    cottage.sheets = []
    let added = try SchematicDrawingSet().sheets(for: cottage, geometry: HestiaGeometryEngine())
    #expect(!added.isEmpty && added.allSatisfy { $0.paper == .archD })
    cottage.sheets = [Sheet(id: SheetID(UUID()), number: "A-101", title: "Plan", paper: .archC, scale: .quarterInch,
                            views: [.floorPlan(storeyID: try #require(cottage.storeys.first).id)])]
    let kept = try SchematicDrawingSet().sheets(for: cottage, geometry: HestiaGeometryEngine())
    #expect(kept.map(\.paper) == [.archC])
    let chosen = try SchematicDrawingSet(paper: .ansiB).sheets(for: cottage, geometry: HestiaGeometryEngine())
    #expect(chosen.map(\.paper) == [.ansiB])
}

/// A wall with `doors` doors and `windows` windows along it, 5' apart.
private func manyOpenings(doors: Int, windows: Int) throws -> ModelDocument {
    var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(UUID()), name: "Long"),
                                 buildings: [], storeys: [], walls: [], openings: [], rooms: [])
    let building = BuildingID(UUID()), storey = StoreyID(UUID()), wall = WallID(UUID())
    var commands: [AnyCommand] = [
        AddBuildingCommand(buildingID: building, name: "House").erased,
        AddStoreyCommand(storeyID: storey, buildingID: building, name: "Ground", elevation: .feet(0)).erased,
        AddWallCommand(wallID: wall, storeyID: storey, start: paperPoint(0, 0),
                       end: Point2(x: .feet(Int64((doors + windows) * 5 + 10)), y: .feet(0)),
                       thickness: .inches(6), height: .feet(8)).erased,
    ]
    for index in 0..<(doors + windows) {
        let door = index < doors
        commands.append(AddOpeningCommand(openingID: OpeningID(UUID()), wallID: wall,
                                          offsetAlongWall: .feet(Int64(1 + index * 5)), width: .feet(3),
                                          height: door ? .inches(80) : .feet(4), sillHeight: door ? .feet(0) : .feet(3),
                                          kind: door ? .singleDoor : .window,
                                          swing: door ? DoorSwing(hinge: .nearStart, opensToward: .left) : nil).erased)
    }
    _ = try document.perform(batch: commands)
    return document
}

@Test func schedulesTooLongForTheirSheetRunOnToContinuationSheetsWithEveryRow() throws {
    let document = try manyOpenings(doors: 30, windows: 45)
    let sheet = Sheet(id: SheetID(UUID()), number: "A-601", title: "Schedules", paper: .ansiB, scale: nil,
                      views: [.schedule(kind: .doors), .schedule(kind: .windows)])
    var used: Set<String> = ["A-601"]
    let pages = try #require(try SchematicDrawingSet().schedulePages(sheet, document: document,
                                                                    geometry: HestiaGeometryEngine(), used: &used))
    #expect(pages.count >= 2)
    let numbers: [String] = (1...pages.count).map { String(format: "A-6%02d", $0) }
    #expect(pages.map(\.number) == numbers)
    #expect(pages.dropFirst().allSatisfy { $0.title == "Schedules (continued)" })
    var strings: Set<String> = []
    var marks: [String] = []
    for page in pages {
        for item in page.content.items {
            if case let .text(_, string, _, _, _) = item.primitive {
                strings.insert(string)
                if let first = string.first, first == "D" || first == "W",
                   !string.dropFirst().isEmpty, string.dropFirst().allSatisfy(\.isNumber) {
                    marks.append(string)
                }
            }
        }
        let box = extent(page)
        #expect(box.minX >= 0 && box.minY >= 0 && box.maxX <= Double(page.paper.width.ticks)
            && box.maxY <= Double(page.paper.height.ticks), "\(page.number) runs off: \(box)")
        #expect(DrawingAudit.findings(page).isEmpty, "\(page.number): \(DrawingAudit.findings(page))")
    }
    #expect(!strings.contains { $0.contains("DO NOT FIT") })
    let expected = (1...30).map({ "D\($0)" }) + (1...45).map({ "W\($0)" })
    #expect(marks == expected, "schedule marks are duplicated or out of order: \(marks)")
    for mark in expected {
        #expect(strings.contains(mark), "\(mark) is missing")
    }
}

@Test func nilAndArchDPaperKeepTheStoredViewScales() throws {
    let document = try fixture("rect-cottage")
    let geometry = HestiaGeometryEngine()
    let unchanged = try SchematicDrawingSet().sheets(for: document, geometry: geometry)
    let chosen = try SchematicDrawingSet(paper: .archD).sheets(for: document, geometry: geometry)
    for source in document.sheets where source.scale != nil {
        let original = try #require(unchanged.first { $0.number == source.number })
        let archD = try #require(chosen.first { $0.number == source.number })
        #expect(original.scale == source.scale, "nil changed \(source.number) from \(String(describing: source.scale))")
        #expect(archD.scale == source.scale, "ARCH D changed \(source.number) from \(String(describing: source.scale))")
    }
}

@Test func schedulesThatFitAreDrawnAsBefore() throws {
    let document = try manyOpenings(doors: 3, windows: 3)
    let sheet = Sheet(id: SheetID(UUID()), number: "A-601", title: "Schedules", paper: .archD, scale: nil,
                      views: [.schedule(kind: .doors), .schedule(kind: .windows)])
    var used: Set<String> = []
    #expect(try SchematicDrawingSet().schedulePages(sheet, document: document, geometry: HestiaGeometryEngine(),
                                                    used: &used) == nil)
}

@Test(arguments: SchematicDrawingSet.papers)
func stackedViewsLeaveRoomForTheScaleOverThem(_ paper: PaperSize) {
    let slots = SchematicDrawingSet.slots(in: SheetFrame.drawingArea(for: paper), count: 4)
    for (upper, lower) in zip(slots, slots.dropFirst()) {
        // The upper view's title and scale fit in the 16 mm under it, and 4 mm more stay clear above the lower.
        #expect(upper.minY - mmTicks(16) - lower.maxY >= mmTicks(4))
        #expect(lower.height > 0)
    }
}

@Test func theCoverListsContinuationSheets() throws {
    let document = try manyOpenings(doors: 30, windows: 45)
    let sheets = try SchematicDrawingSet(paper: .ansiB).sheets(for: document, geometry: HestiaGeometryEngine())
    #expect(sheets.contains { $0.number == "A-602" })
    let cover = try #require(sheets.first { $0.number == "A-000" })
    let strings: [String] = cover.content.items.compactMap { item in
        guard case let .text(_, string, _, _, _) = item.primitive else { return nil }
        return string
    }
    for sheet in sheets {
        #expect(strings.contains(sheet.number), "the cover leaves out \(sheet.number)")
    }
    #expect(strings.contains("Schedules (continued)"))
    #expect(DrawingAudit.findings(cover).isEmpty, "\(DrawingAudit.findings(cover))")
}

@Test func aHundredIndexEntriesRunOnToClearOrderedCoverPages() throws {
    var document = try fixture("rect-cottage")
    let cover = Sheet(id: SheetID(UUID()), number: "A-000", title: "Cover", paper: .ansiB, scale: nil,
                      views: [.cover])
    let schedules = (1...100).map { position in
        Sheet(id: SheetID(UUID()), number: String(format: "A-6%02d", position),
              title: "Schedules (continued)", paper: .ansiB, scale: nil, views: [])
    }
    document.sheets = [cover] + schedules

    let drawings = try SchematicDrawingSet(paper: .ansiB).sheets(for: document, geometry: HestiaGeometryEngine())
    let covers = drawings.filter { $0.title == "Cover" || $0.title == "Cover (continued)" }
    #expect(covers.count > 1)
    let expected = drawings.map(\.number)
    let expectedSet = Set(expected)
    let indexed: [String] = covers.flatMap { page in
        page.content.items.compactMap { item in
            guard item.style.layer == "A-ANNO-TEXT",
                  case let .text(_, string, _, _, _) = item.primitive,
                  expectedSet.contains(string) else { return nil }
            return string
        }
    }
    #expect(indexed == expected, "cover index order differs from drawing order: \(indexed)")
    #expect(Set(indexed).count == indexed.count, "a cover index entry is duplicated")

    let firstStrings: [String] = covers[0].content.items.compactMap { item in
        guard case let .text(_, string, _, _, _) = item.primitive else { return nil }
        return string
    }
    #expect(firstStrings.contains("GENERAL NOTES"))
    #expect(firstStrings.contains("SYMBOLS"), "the first cover drops its legend")
    for page in covers {
        let box = extent(page)
        #expect(box.minX >= 0 && box.minY >= 0 && box.maxX <= Double(page.paper.width.ticks)
            && box.maxY <= Double(page.paper.height.ticks), "\(page.number) runs off: \(box)")
        #expect(DrawingAudit.findings(page).isEmpty, "\(page.number): \(DrawingAudit.findings(page))")
    }
}

@Test func aVeryLargeIndexPaginatesWithoutAContinuationLimit() throws {
    var document = try fixture("rect-cottage")
    let cover = Sheet(id: SheetID(UUID()), number: "A-000", title: "Cover", paper: .ansiB, scale: nil,
                      views: [.cover])
    let schedules = (1...6_000).map { position in
        Sheet(id: SheetID(UUID()), number: String(format: "A-%04d", position + 1_000),
              title: "Schedules (continued)", paper: .ansiB, scale: nil, views: [])
    }
    document.sheets = [cover] + schedules

    let drawings = try SchematicDrawingSet(paper: .ansiB).sheets(for: document, geometry: HestiaGeometryEngine())
    let covers = drawings.filter { $0.title == "Cover" || $0.title == "Cover (continued)" }
    #expect(covers.count > 145)
    let numbers = Set(drawings.map(\.number))
    let indexed: [String] = covers.flatMap { page in
        page.content.items.compactMap { item in
            guard item.style.layer == "A-ANNO-TEXT",
                  case let .text(_, string, _, _, _) = item.primitive,
                  numbers.contains(string) else { return nil }
            return string
        }
    }
    #expect(indexed.count == drawings.count)
    #expect(indexed.last == drawings.last?.number)
}
