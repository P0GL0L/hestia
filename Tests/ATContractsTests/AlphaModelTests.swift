import ATContracts
import Foundation
import Testing

@Test func fullModelRoundTripsThroughJSON() throws {
    var document = Sample.document()
    document.openings[0].swing = DoorSwing(hinge: .nearStart, opensToward: .left)
    document.roofs[0].planes[1] = RoofPlane(pitchRisePer12: nil, overhang: .millimeters(0))
    document.sheets.append(Sheet(
        id: Sample.newSheet, number: "A-301", title: "Section", paper: .isoA1, scale: .oneTo50,
        views: [.section(line: SectionLine(start: Sample.point(0, 1500), end: Sample.point(4000, 1500))),
                .roofPlan, .sitePlan, .cover, .electricalPlan(storeyID: Sample.storey),
                .elevation(direction: .south), .schedule(kind: .windows)]
    ))
    let data = try document.encodeToJSONData()
    let decoded = try ModelDocument.decode(from: data)
    #expect(decoded == document)
    #expect(try decoded.encodeToJSONData() == data)
}

@Test func filesWithoutNewCollectionsStillOpen() throws {
    let legacy = Data("""
    {"schemaVersion": 1, "project": {"id": "00000000-0000-4000-8000-000000000001", "name": "Old"},
     "openings": [{"id": "00000000-0000-4000-8000-000000000030", "wallID": "00000000-0000-4000-8000-000000000020",
       "offsetAlongWall": {"ticks": 0}, "width": {"ticks": 1}, "height": {"ticks": 1}, "sillHeight": {"ticks": 9}}]}
    """.utf8)
    let document = try ModelDocument.decode(from: legacy)
    #expect(document.walls.isEmpty && document.stairs.isEmpty && document.sheets.isEmpty)
    #expect(document.openings.first?.kind == .window)
    #expect(document.openings.first?.swing == nil)
}

@Test func newerSchemaVersionIsRefused() {
    let future = Data(#"{"schemaVersion": 2, "project": {"id": "00000000-0000-4000-8000-000000000001", "name": "New"}}"#.utf8)
    #expect(throws: ModelDocumentError.unsupportedSchemaVersion(found: 2, supported: 1)) {
        try ModelDocument.decode(from: future)
    }
}

@Test func openingKindDefaultsFromSill() {
    #expect(Opening.defaultKind(sillHeight: .millimeters(0)) == .singleDoor)
    #expect(Opening.defaultKind(sillHeight: .millimeters(900)) == .window)
    #expect(OpeningKind.allCases.filter(\.isDoor).count == 6)
}
