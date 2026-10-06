import ATContracts
import Foundation
import Testing

extension Sample {
    static let buildingsAndStoreys: [AnyCommand] = [
        AddBuildingCommand(buildingID: newBuilding, name: "Garage", index: 0).erased,
        RenameBuildingCommand(buildingID: building, newName: "Main House").erased,
        RemoveBuildingCommand(buildingID: emptyBuilding).erased,
        AddStoreyCommand(storeyID: newStorey, buildingID: building, name: "Basement",
                         elevation: .millimeters(-2500), index: 0).erased,
        RenameStoreyCommand(storeyID: storey, newName: "Ground Floor").erased,
        SetStoreyElevationCommand(storeyID: storey, elevation: .millimeters(150)).erased,
        RemoveStoreyCommand(storeyID: emptyStorey).erased,
    ]
}

@Test func buildingsAndStoreysWithContentsCannotBeRemoved() {
    expectRefused(.hasDependents(Sample.storey.rawValue), RemoveStoreyCommand(storeyID: Sample.storey))
    expectRefused(.hasDependents(Sample.building.rawValue), RemoveBuildingCommand(buildingID: Sample.building))
}

@Test func storeyNeedsAnExistingBuilding() {
    expectRefused(.buildingNotFound(Sample.newBuilding), AddStoreyCommand(
        storeyID: Sample.newStorey, buildingID: Sample.newBuilding, name: "Upper", elevation: .millimeters(2700)
    ))
}

@Test func duplicateBuildingIDAndBadIndexAreRefused() {
    expectRefused(.duplicateID(Sample.building.rawValue), AddBuildingCommand(buildingID: Sample.building, name: "Barn"))
    expectRefused(.indexOutOfRange(5), AddBuildingCommand(buildingID: Sample.newBuilding, name: "Barn", index: 5))
    expectRefused(.nameEmpty, RenameStoreyCommand(storeyID: Sample.storey, newName: ""))
}

@Test func removedStoreyReturnsToItsPosition() throws {
    var document = Sample.document()
    let inverse = try document.perform(RemoveStoreyCommand(storeyID: Sample.emptyStorey).erased)
    #expect(document.storeys.map(\.id) == [Sample.storey])
    _ = try document.perform(inverse)
    #expect(document.storeys.map(\.id) == [Sample.storey, Sample.emptyStorey])
}
