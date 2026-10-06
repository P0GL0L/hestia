@testable import ATDrawings
import ATContracts
import Foundation
import Testing

private func fixture(_ name: String) throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/\(name).json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

@Test func cottageRoomsGetClearInteriorDimensions() throws {
    let document = try fixture("rect-cottage")
    let walls = { (room: Room) in room.boundaryWallIDs.compactMap { id in document.walls.first { $0.id == id } } }
    let expected: [String: (Int64, Int64)] = [
        "Living": (14, 12), "Kitchen": (10, 12), "Utility": (12, 12),
        "Bedroom": (14, 10), "Bath": (10, 10), "Bedroom 2": (12, 10),
    ]
    for room in document.rooms {
        let box = try #require(DimensionChains.clearBox(walls(room)))
        let size = try #require(expected[room.name])
        #expect(box.1 - box.0 == Length.feet(size.0).ticks, "\(room.name) width")
        #expect(box.3 - box.2 == Length.feet(size.1).ticks, "\(room.name) depth")
    }
}

@Test func interiorDimensionsPrintTheClearSizes() throws {
    let document = try fixture("rect-cottage")
    let view = ViewTransform(scale: .quarterInch, modelOrigin: Point2(x: .feet(-1), y: .feet(-1)),
                             paperOrigin: Point2(x: .millimeters(100), y: .millimeters(100)))
    let items = DimensionChains.interiorItems(document: document, storey: document.storeys[0].id, view: view)
    #expect(items.count == 12)
    let living = items.filter { $0.elementID == document.rooms[0].id.rawValue }
    let labels = try living.map { item -> String in
        guard case let .dimension(from, to, _, _) = item.primitive else { throw CocoaErrorStub() }
        let paper = abs(to.x.ticks - from.x.ticks) + abs(to.y.ticks - from.y.ticks)
        return SheetPDF.measuredLabel(paperTicks: paper, scale: .quarterInch)
    }
    #expect(labels == ["14'-0\"", "12'-0\""])
}

@Test func nonBoxRoomsAreSkipped() throws {
    let document = try fixture("l-house")
    let view = ViewTransform(scale: .oneTo50, modelOrigin: Point2(x: .millimeters(0), y: .millimeters(0)),
                             paperOrigin: Point2(x: .millimeters(0), y: .millimeters(0)))
    let items = DimensionChains.interiorItems(document: document, storey: document.storeys[0].id, view: view)
    // All three ground-floor rooms of l-house are boxes.
    #expect(items.count == 6)
    let tri = [document.walls[0], document.walls[1], document.walls[2]]
    #expect(DimensionChains.clearBox(Array(tri.prefix(2))) == nil)
}

private struct CocoaErrorStub: Error {}
