import ATContracts
import Foundation
import Testing

@Test func renameProjectCommandValidateApplyInverse() throws {
    var document = Sample.document()
    let command = RenameProjectCommand(projectID: Sample.project, newName: "  Cottage Renovation ")
    try command.validate(against: document)
    let inverse = try command.apply(to: &document)
    #expect(document.project.name == "Cottage Renovation")

    try inverse.validate(against: document)
    _ = try inverse.apply(to: &document)
    #expect(document.project.name == "Command Test")
}

@Test func renameProjectRefusesBlankNameAndWrongProject() {
    expectRefused(.nameEmpty, RenameProjectCommand(projectID: Sample.project, newName: "   "))
    expectRefused(.projectNotFound(ProjectID(Sample.uuid(99))),
                  RenameProjectCommand(projectID: ProjectID(Sample.uuid(99)), newName: "X"))
}

@Test func catalogCoversEveryCommandOnce() {
    let names = CommandCatalog.v1.map { $0.commandName }
    #expect(Set(names).count == names.count)
    #expect(Set(Sample.commands.map(\.name)) == Set(names))
    for name in names {
        #expect(name.allSatisfy { $0.isLowercase || $0 == "_" }, "\(name) is not snake_case")
        #expect(CommandCatalog.commandType(named: name)?.commandName == name)
    }
    #expect(CommandCatalog.commandType(named: "delete_everything") == nil)
}

@Test func toolDescriptionsAreSingleLines() {
    for descriptor in CommandCatalog.descriptors {
        #expect(!descriptor.toolDescription.isEmpty)
        #expect(!descriptor.toolDescription.contains("\n"))
        #expect(!descriptor.parameters.isEmpty)
        #expect(Set(descriptor.parameters.map(\.name)).count == descriptor.parameters.count)
        for parameter in descriptor.parameters {
            #expect(!parameter.description.isEmpty, "\(descriptor.name).\(parameter.name)")
        }
    }
}

/// Parameter metadata must name exactly the JSON keys the command encodes, so generated tool schemas are true.
@Test(arguments: Sample.commands)
func parameterMetadataMatchesEncodedKeys(command: AnyCommand) throws {
    let object = try JSONSerialization.jsonObject(with: Sample.json(command)) as? [String: Any]
    let parameters = try #require(object?["parameters"] as? [String: Any])
    #expect(object?["name"] as? String == command.name)
    let type = try #require(CommandCatalog.commandType(named: command.name))
    let all = Set(type.parameters.map(\.name))
    let required = Set(type.parameters.filter(\.isRequired).map(\.name))
    #expect(Set(parameters.keys).isSubset(of: all))
    #expect(required.isSubset(of: Set(parameters.keys)))
}

@Test(arguments: Sample.commands)
func commandJSONRoundTrips(command: AnyCommand) throws {
    let decoded = try ModelDocument.makeJSONDecoder().decode(AnyCommand.self, from: Sample.json(command))
    #expect(decoded == command)
}

/// Apply then apply the inverse: the document must come back byte-for-byte, including list order.
@Test(arguments: Sample.commands)
func inverseRestoresDocumentExactly(command: AnyCommand) throws {
    let original = Sample.document()
    var document = original
    let inverse = try document.perform(command)
    #expect(document != original, "\(command.name) changed nothing")
    _ = try document.perform(inverse)
    #expect(document == original)
    #expect(try Sample.json(document) == Sample.json(original))
}

@Test func unknownCommandNameIsRejected() throws {
    let json = Data(#"{"name":"delete_everything","parameters":{}}"#.utf8)
    #expect(throws: CommandValidationError.unknownCommand("delete_everything")) {
        try ModelDocument.makeJSONDecoder().decode(AnyCommand.self, from: json)
    }
}

@Test func batchUndoesInReverseOrder() throws {
    let original = Sample.document()
    var document = original
    let inverse = try document.perform(batch: [
        RenameProjectCommand(projectID: Sample.project, newName: "First").erased,
        RenameProjectCommand(projectID: Sample.project, newName: "Second").erased,
    ])
    #expect(document.project.name == "Second")
    _ = try document.perform(batch: inverse)
    #expect(document == original)
}

@Test func refusedBatchLeavesDocumentUnchanged() throws {
    let original = Sample.document()
    var document = original
    #expect(throws: CommandValidationError.nameEmpty) {
        try document.perform(batch: [
            RenameProjectCommand(projectID: Sample.project, newName: "Applied first").erased,
            RenameProjectCommand(projectID: Sample.project, newName: " ").erased,
        ])
    }
    #expect(document == original)
}
