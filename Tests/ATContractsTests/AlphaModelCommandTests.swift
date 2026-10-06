import ATContracts
import Foundation
import Testing

extension Sample {
    static let alphaElements: [AnyCommand] = [
        SetOpeningKindCommand(openingID: door, kind: .singleDoor,
                              swing: DoorSwing(hinge: .nearStart, opensToward: .left)).erased,
        AddStairCommand(stairID: newStair, storeyID: storey, kind: .straight, runStart: point(3000, 500),
                        runEnd: point(3000, 2900), width: .millimeters(850), riserCount: 14,
                        riserHeight: .millimeters(190), index: 0).erased,
        MoveStairCommand(stairID: stair, runStart: point(1200, 2000), runEnd: point(1200, 4500)).erased,
        SetStairRisersCommand(stairID: stair, riserCount: 16, riserHeight: .millimeters(170),
                              width: .millimeters(1000)).erased,
        RemoveStairCommand(stairID: stair).erased,
        AddRoofCommand(roofID: newRoof, storeyID: emptyStorey, footprint: footprint, eaveHeight: .millimeters(2400),
                       pitchRisePer12: .inches(8), overhang: .millimeters(300), index: 0).erased,
        SetRoofEdgeCommand(roofID: roof, edgeIndex: 1, pitchRisePer12: nil, overhang: .millimeters(0)).erased,
        RemoveRoofCommand(roofID: roof).erased,
        AddSlabCommand(slabID: newSlab, storeyID: emptyStorey, kind: .ceiling, outline: footprint,
                       thickness: .millimeters(200), topOffset: .millimeters(-50), index: 0).erased,
        SetSlabOutlineCommand(slabID: slab, outline: [point(0, 0), point(5000, 0), point(5000, 3000)]).erased,
        RemoveSlabCommand(slabID: slab).erased,
        AddSheetCommand(sheetID: newSheet, number: "A-601", title: "Door Schedule", paper: .ansiB, scale: nil,
                        views: [.schedule(kind: .doors), .elevation(direction: .north)], index: 0).erased,
        SetSheetTitleCommand(sheetID: sheet, number: "A-102", title: "Main Floor Plan").erased,
        RemoveSheetCommand(sheetID: sheet).erased,
    ]
}

@Test func swingIsOnlyForHingedDoors() {
    expectRefused(.swingNotAllowed(Sample.door), SetOpeningKindCommand(
        openingID: Sample.door, kind: .slidingDoor, swing: DoorSwing(hinge: .nearEnd, opensToward: .right)
    ))
}

@Test func stairsNeedARunAndRisers() {
    expectRefused(.invalidValue(parameter: "riserCount"),
                  SetStairRisersCommand(stairID: Sample.stair, riserCount: 1, riserHeight: .millimeters(180),
                                        width: .millimeters(900)))
    expectRefused(.invalidValue(parameter: "runEnd"),
                  MoveStairCommand(stairID: Sample.stair, runStart: Sample.point(1, 1), runEnd: Sample.point(1, 1)))
    expectRefused(.stairNotFound(Sample.newStair), RemoveStairCommand(stairID: Sample.newStair))
}

@Test func outlinesMustBeCounterclockwise() {
    expectRefused(.polygonInvalid, SetSlabOutlineCommand(slabID: Sample.slab, outline: Sample.footprint.reversed()))
    expectRefused(.polygonInvalid, AddRoofCommand(
        roofID: Sample.newRoof, storeyID: Sample.storey, footprint: Array(Sample.footprint.prefix(2)),
        eaveHeight: .millimeters(2400), pitchRisePer12: .inches(6)
    ))
}

@Test func roofEdgesAreCheckedAgainstTheFootprint() {
    expectRefused(.indexOutOfRange(4), SetRoofEdgeCommand(roofID: Sample.roof, edgeIndex: 4,
                                                          pitchRisePer12: .inches(6), overhang: .millimeters(0)))
    expectRefused(.invalidValue(parameter: "planes"), AddRoofCommand(
        roofID: Sample.newRoof, storeyID: Sample.storey, footprint: Sample.footprint, eaveHeight: .millimeters(2400),
        planes: [RoofPlane(pitchRisePer12: nil, overhang: .millimeters(0))]
    ))
    expectRefused(.negative(parameter: "overhang"), SetRoofEdgeCommand(
        roofID: Sample.roof, edgeIndex: 0, pitchRisePer12: .inches(6), overhang: .millimeters(-1)
    ))
}

@Test func sheetNumbersAreUniqueAndViewsNeedRealStoreys() {
    expectRefused(.duplicateSheetNumber("A-101"), AddSheetCommand(
        sheetID: Sample.newSheet, number: " A-101 ", title: "Copy", paper: .archD, scale: nil, views: []
    ))
    expectRefused(.storeyNotFound(Sample.newStorey), AddSheetCommand(
        sheetID: Sample.newSheet, number: "A-102", title: "Upper", paper: .archD, scale: .quarterInch,
        views: [.floorPlan(storeyID: Sample.newStorey)]
    ))
}

@Test func storeyWithAStairOrSheetCannotBeRemoved() throws {
    var document = Sample.document()
    _ = try document.perform(AddSheetCommand(
        sheetID: Sample.newSheet, number: "A-102", title: "Loft", paper: .archD, scale: .quarterInch,
        views: [.floorPlan(storeyID: Sample.emptyStorey)]
    ).erased)
    #expect(throws: CommandValidationError.hasDependents(Sample.emptyStorey.rawValue)) {
        try RemoveStoreyCommand(storeyID: Sample.emptyStorey).validate(against: document)
    }
}

@Test func choiceParametersListTheirValues() {
    for descriptor in CommandCatalog.descriptors {
        for parameter in descriptor.parameters where parameter.kind == .choice {
            #expect(!(parameter.allowedValues ?? []).isEmpty, "\(descriptor.name).\(parameter.name)")
        }
    }
}
