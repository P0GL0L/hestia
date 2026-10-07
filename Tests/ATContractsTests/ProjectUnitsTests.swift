import ATContracts
import Foundation
import Testing

@Test func setProjectUnitsAppliesAndUndoRestoresNil() throws {
    var document = Sample.document()
    #expect(document.project.displayUnits == nil)
    let inverse = try SetProjectUnitsCommand(projectID: Sample.project, units: .feetInchesFractions).apply(to: &document)
    #expect(document.project.displayUnits == .feetInchesFractions)
    _ = try inverse.apply(to: &document)
    #expect(document.project.displayUnits == nil)
    #expect(document == Sample.document())
}

@Test func setProjectUnitsRefusesUnknownValueAndWrongProject() {
    expectRefused(.invalidValue(parameter: "units"), SetProjectUnitsCommand(projectID: Sample.project, unitsValue: "cubits"))
    let missing = ProjectID(Sample.uuid(99))
    expectRefused(.projectNotFound(missing), SetProjectUnitsCommand(projectID: missing, units: .metric))
}

@Test func unknownUnitsFromJSONDecodeAndAreRefused() throws {
    let json = """
    {"name": "set_project_units", "parameters": {"projectID": "\(Sample.project.rawValue.uuidString)", "units": "cubits"}}
    """
    let command = try JSONDecoder().decode(AnyCommand.self, from: Data(json.utf8))
    #expect(throws: CommandValidationError.invalidValue(parameter: "units")) {
        try command.validate(against: Sample.document())
    }
}

@Test func unsetDisplayUnitsStayOutOfJSON() throws {
    let plain = Project(id: Sample.project, name: "Plain")
    let text = String(decoding: try Sample.json(plain), as: UTF8.self)
    #expect(!text.contains("displayUnits"))
    let metric = Project(id: Sample.project, name: "Metric", displayUnits: .metric)
    let decoded = try JSONDecoder().decode(Project.self, from: try Sample.json(metric))
    #expect(decoded.displayUnits == .metric)
    // Clearing encodes without a units key, and decodes back to clearing.
    let clear = SetProjectUnitsCommand(projectID: Sample.project, units: nil).erased
    let clearText = String(decoding: try Sample.json(clear), as: UTF8.self)
    #expect(!clearText.contains("\"units\""))
    let roundTrip = try JSONDecoder().decode(AnyCommand.self, from: try Sample.json(clear))
    #expect(roundTrip == clear)
}
