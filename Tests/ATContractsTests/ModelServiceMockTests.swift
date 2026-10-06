import ATContracts
import Foundation
import Testing

private let southOutline = ClassifiedOutline(
    elementID: Sample.wallSouth.rawValue, kind: .wall, classification: .cut,
    polygon: [Sample.point(0, -100), Sample.point(4000, -100), Sample.point(4000, 100), Sample.point(0, 100)]
)

private let floorMesh = Mesh(
    elementID: Sample.room.rawValue, materialID: MaterialID("floor"),
    positions: [Sample.point(0, 0), Sample.point(4000, 0), Sample.point(4000, 3000)]
        .map { Point3(x: $0.x, y: $0.y, z: .millimeters(0)) },
    normals: Array(repeating: Vector3f(x: 0, y: 0, z: 1), count: 3),
    uvs: Array(repeating: TextureCoordinate(u: 0, v: 0), count: 3),
    indices: [0, 1, 2]
)

private let planSheet = SheetDrawing(
    number: "A-101", title: "Floor Plan", paper: .isoA3, scale: .oneTo100,
    content: DisplayList(items: [
        DisplayItem(.polyline(points: southOutline.polygon.map { Point2(
            x: DrawingScale.oneTo100.paper($0.x), y: DrawingScale.oneTo100.paper($0.y)) }, closed: true),
                    style: DisplayStyle(layer: "A-WALL", pen: .heavy), elementID: southOutline.elementID),
        DisplayItem(.text(position: Sample.point(400, 20), string: OutputHonesty.schematicStamp,
                          height: .millimeters(4), rotation: .degrees(0), alignment: .right),
                    style: DisplayStyle(layer: "A-ANNO-TEXT")),
    ])
)

@Test func mockGeometryReturnsConfiguredResultsAndChecksStoreys() throws {
    let engine = MockGeometryEngine(
        planOutlines: [Sample.storey: [southOutline]],
        areas: [Sample.storey: [Sample.room: Area(tickSquares: 12_000_000 * Area.tickSquaresPerSquareMillimeter)]],
        meshes: [floorMesh]
    )
    let document = Sample.document()
    #expect(try engine.planView(of: document, storey: Sample.storey) == [southOutline])
    #expect(try engine.planView(of: document, storey: Sample.emptyStorey).isEmpty)
    #expect(try engine.roomAreas(of: document, storey: Sample.storey)[Sample.room]?.squareMillimeters == 12_000_000)
    #expect(try engine.meshes(of: document) == [floorMesh])
    #expect(try engine.section(of: document, along: SectionLine(start: Sample.point(0, 0),
                                                                end: Sample.point(1, 0))).isEmpty)
    #expect(throws: CommandValidationError.storeyNotFound(Sample.newStorey)) {
        try engine.planView(of: document, storey: Sample.newStorey)
    }
}

@Test func mockDrawingGeneratorReturnsConfiguredSheets() throws {
    let sheets = try MockDrawingGenerator(sheets: [planSheet])
        .sheets(for: Sample.document(), geometry: MockGeometryEngine())
    #expect(sheets == [planSheet])
}

@Test func drawingScalesConvertExactly() {
    #expect(DrawingScale.oneTo100.paper(.millimeters(4000)) == .millimeters(40))
    #expect(DrawingScale.oneTo50.paper(.millimeters(-1000)) == .millimeters(-20))
    #expect(DrawingScale.quarterInch.paper(.feet(4)) == .inches(1))
    #expect(DrawingScale.eighthInch.paper(.feet(8)) == .inches(1))
    #expect(PaperSize.archD.width == .inches(36))
    #expect(PaperSize.isoA1.height == .millimeters(594))
}

@Test func mockExchangeRoundTripsDrawingsAndMeshes() throws {
    let document = Sample.document()
    let material = Material(id: MaterialID("floor"), name: "Floor", baseColorRGBA: [180, 140, 90, 255])

    let drawing = try MockExporter().export(.sheets([planSheet]))
    #expect(try MockImporter().importFile(drawing, into: document).underlay == planSheet.content)

    let model = try MockExporter().export(.meshes([floorMesh], materials: [material]))
    let imported = try MockImporter().importFile(model, into: document)
    #expect(imported.meshes == [floorMesh])
    #expect(imported.materials == [material])
    #expect(imported.commands.isEmpty)

    #expect(throws: ExchangeError.malformedInput("not mock-json export output")) {
        try MockImporter().importFile(Data("nope".utf8), into: document)
    }
}
