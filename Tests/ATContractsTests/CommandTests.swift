import ATContracts
import Foundation
import Testing

@Test func renameProjectCommandValidateApplyInverse() throws {
    let projectID = ProjectID(UUID(uuidString: "00000000-0000-4000-8000-000000000001")!)
    var document = ModelDocument(
        schemaVersion: 1,
        project: Project(id: projectID, name: "Rect Cottage"),
        buildings: [],
        storeys: [],
        walls: [],
        openings: [],
        rooms: []
    )

    let command = RenameProjectCommand(projectID: projectID, newName: "Cottage Renovation")
    try command.validate(against: document)
    let inverse = try command.apply(to: &document)
    #expect(document.project.name == "Cottage Renovation")

    try inverse.validate(against: document)
    _ = try inverse.apply(to: &document)
    #expect(document.project.name == "Rect Cottage")
}
