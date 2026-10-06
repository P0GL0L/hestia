import ATContracts
import Foundation
import Testing

extension Sample {
    static let wallsAndOpenings: [AnyCommand] = [
        AddWallCommand(wallID: newWall, storeyID: storey, start: point(0, 3000), end: point(4000, 3000),
                       thickness: .millimeters(100), height: .millimeters(2400), index: 1).erased,
        MoveWallCommand(wallID: wallSouth, start: point(0, 0), end: point(5000, 0)).erased,
        SetWallThicknessCommand(wallID: wallSouth, thickness: .millimeters(300)).erased,
        SetWallHeightCommand(wallID: wallSouth, height: .millimeters(3000)).erased,
        RemoveWallCommand(wallID: wallSpare).erased,
        SetWallLayersCommand(wallID: wallSouth, layers: [
            WallLayer(material: "Plaster", function: .finish, thickness: .millimeters(20)),
            WallLayer(material: "Brick", function: .structure, thickness: .millimeters(220)),
        ]).erased,
        SetWallPhaseCommand(wallID: wallSouth, phase: .existing).erased,
        AddOpeningCommand(openingID: newWindow, wallID: wallSouth, offsetAlongWall: .millimeters(2000),
                          width: .millimeters(1000), height: .millimeters(1200),
                          sillHeight: .millimeters(900), index: 0).erased,
        MoveOpeningCommand(openingID: door, offsetAlongWall: .millimeters(100)).erased,
        ResizeOpeningCommand(openingID: door, width: .millimeters(800), height: .millimeters(2000),
                             sillHeight: .millimeters(0)).erased,
        RemoveOpeningCommand(openingID: door).erased,
    ]
}

@Test func openingPastWallEndIsRefused() {
    expectRefused(.openingOutsideWall(Sample.newWindow), AddOpeningCommand(
        openingID: Sample.newWindow, wallID: Sample.wallSouth, offsetAlongWall: .millimeters(3500),
        width: .millimeters(600), height: .millimeters(1000), sillHeight: .millimeters(900)
    ))
}

@Test func openingAboveWallTopIsRefused() {
    expectRefused(.openingAboveWall(Sample.newWindow), AddOpeningCommand(
        openingID: Sample.newWindow, wallID: Sample.wallSouth, offsetAlongWall: .millimeters(2000),
        width: .millimeters(600), height: .millimeters(1600), sillHeight: .millimeters(900)
    ))
}

@Test func overlappingOpeningsAreRefused() {
    expectRefused(.openingsOverlap(Sample.door, Sample.newWindow), AddOpeningCommand(
        openingID: Sample.newWindow, wallID: Sample.wallSouth, offsetAlongWall: .millimeters(1000),
        width: .millimeters(600), height: .millimeters(1000), sillHeight: .millimeters(900)
    ))
}

@Test func openingsMayTouchEdgeToEdge() throws {
    var document = Sample.document()
    _ = try AddOpeningCommand(
        openingID: Sample.newWindow, wallID: Sample.wallSouth, offsetAlongWall: .millimeters(1400),
        width: .millimeters(2600), height: .millimeters(1000), sillHeight: .millimeters(900)
    ).apply(to: &document)
    #expect(document.openings.count == 2)
}

@Test func negativeOffsetIsRefused() {
    expectRefused(.negative(parameter: "offsetAlongWall"),
                  MoveOpeningCommand(openingID: Sample.door, offsetAlongWall: .millimeters(-1)))
}

@Test func shrinkingWallUnderAnOpeningIsRefused() {
    expectRefused(.openingOutsideWall(Sample.door),
                  MoveWallCommand(wallID: Sample.wallSouth, start: Sample.point(0, 0), end: Sample.point(1000, 0)))
}

@Test func loweringWallBelowAnOpeningIsRefused() {
    expectRefused(.openingAboveWall(Sample.door),
                  SetWallHeightCommand(wallID: Sample.wallSouth, height: .millimeters(2000)))
}

@Test func zeroLengthAndThinWallsAreRefused() {
    expectRefused(.zeroLengthWall, AddWallCommand(
        wallID: Sample.newWall, storeyID: Sample.storey, start: Sample.point(1, 1), end: Sample.point(1, 1),
        thickness: .millimeters(100), height: .millimeters(2400)
    ))
    expectRefused(.notPositive(parameter: "thickness"),
                  SetWallThicknessCommand(wallID: Sample.wallSouth, thickness: .millimeters(0)))
}

@Test func wallIDsAndStoreysAreChecked() {
    expectRefused(.duplicateID(Sample.wallSouth.rawValue), AddWallCommand(
        wallID: Sample.wallSouth, storeyID: Sample.storey, start: Sample.point(0, 0), end: Sample.point(1, 0),
        thickness: .millimeters(100), height: .millimeters(2400)
    ))
    expectRefused(.storeyNotFound(Sample.newStorey), AddWallCommand(
        wallID: Sample.newWall, storeyID: Sample.newStorey, start: Sample.point(0, 0), end: Sample.point(1, 0),
        thickness: .millimeters(100), height: .millimeters(2400)
    ))
    expectRefused(.wallNotFound(Sample.newWall), RemoveWallCommand(wallID: Sample.newWall))
}

@Test func wallHostingAnOpeningCannotBeRemoved() {
    expectRefused(.hasDependents(Sample.wallSouth.rawValue), RemoveWallCommand(wallID: Sample.wallSouth))
}

@Test func rectCottageFixtureAcceptsCommands() throws {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/rect-cottage.json")
    let original = try ModelDocument.decode(from: Data(contentsOf: fixtureURL))
    var document = original
    let opening = try #require(document.openings.first)
    let inverse = try document.perform(
        MoveOpeningCommand(openingID: opening.id, offsetAlongWall: .millimeters(100)).erased
    )
    _ = try document.perform(inverse)
    #expect(try document.encodeToJSONData() == original.encodeToJSONData())
}

@Test func wallLayersSetTheThickness() throws {
    var document = Sample.document()
    let layers = [WallLayer(material: "Gypsum", function: .finish, thickness: .millimeters(13)),
                  WallLayer(material: "Studs", function: .structure, thickness: .millimeters(90))]
    _ = try document.perform(SetWallLayersCommand(wallID: Sample.wallSouth, layers: layers).erased)
    #expect(document.walls[0].thickness == .millimeters(103))
    expectRefusedOn(document, .invalidValue(parameter: "thickness"),
                    SetWallThicknessCommand(wallID: Sample.wallSouth, thickness: .millimeters(200)))
    expectRefused(.invalidValue(parameter: "layers"), AddWallCommand(
        wallID: Sample.newWall, storeyID: Sample.storey, start: Sample.point(0, 0), end: Sample.point(1, 0),
        thickness: .millimeters(200), height: .millimeters(2400), layers: layers
    ))
}

@Test func wallsWithoutLayersOrPhaseStillDecode() throws {
    let json = Data(#"{"id": "00000000-0000-4000-8000-000000000020", "storeyID": "00000000-0000-4000-8000-000000000010", "start": {"x": {"ticks": 0}, "y": {"ticks": 0}}, "end": {"x": {"ticks": 1}, "y": {"ticks": 0}}, "thickness": {"ticks": 5}, "height": {"ticks": 9}}"#.utf8)
    let wall = try JSONDecoder().decode(Wall.self, from: json)
    #expect(wall.layers.isEmpty)
    #expect(wall.phase == .new)
}
