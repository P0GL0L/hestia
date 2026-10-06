import ATContracts
import Foundation
import Testing

extension Sample {
    static let overrides: [AnyCommand] = [
        SetDimensionOverrideCommand(elementID: wallSouth.rawValue, face: .length, text: "13'-1\" VIF", index: 0).erased,
        SetDimensionOverrideCommand(elementID: room.rawValue, face: .width, text: "14'-0\" CLR").erased,
        ClearDimensionOverrideCommand(elementID: room.rawValue, face: .width).erased,
    ]
}

@Test func overridesReplaceTextOnly() throws {
    var document = Sample.document()
    let geometry = (document.walls, document.rooms, document.openings)
    _ = try document.perform(SetDimensionOverrideCommand(elementID: Sample.door.rawValue, face: .width,
                                                         text: "  3'-0\" NOM ").erased)
    #expect(document.dimensionOverride(for: Sample.door.rawValue, face: .width) == "3'-0\" NOM")
    #expect(document.dimensionOverride(for: Sample.door.rawValue, face: .length) == nil)
    #expect(document.walls == geometry.0 && document.rooms == geometry.1 && document.openings == geometry.2)
}

@Test func replacingAnOverrideUndoesToThePreviousText() throws {
    var document = Sample.document()
    let inverse = try document.perform(SetDimensionOverrideCommand(elementID: Sample.room.rawValue, face: .width,
                                                                   text: "CLR").erased)
    #expect(document.dimensionOverride(for: Sample.room.rawValue, face: .width) == "CLR")
    #expect(document.dimensionOverrides.count == 1)
    _ = try document.perform(inverse)
    #expect(document == Sample.document())
}

@Test func overridesAreRefusedWhenBlankUnknownOrMissing() {
    expectRefused(.nameEmpty, SetDimensionOverrideCommand(elementID: Sample.room.rawValue, face: .depth, text: "  "))
    expectRefused(.elementNotFound(Sample.stair.rawValue),
                  SetDimensionOverrideCommand(elementID: Sample.stair.rawValue, face: .length, text: "X"))
    expectRefused(.dimensionOverrideNotFound(Sample.room.rawValue, .depth),
                  ClearDimensionOverrideCommand(elementID: Sample.room.rawValue, face: .depth))
}

@Test func filesWithoutOverridesStillOpen() throws {
    let legacy = Data(#"{"schemaVersion": 1, "project": {"id": "00000000-0000-4000-8000-000000000001", "name": "Old"}}"#.utf8)
    #expect(try ModelDocument.decode(from: legacy).dimensionOverrides.isEmpty)
}
