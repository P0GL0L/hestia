import ATContracts
import Foundation
import Testing

@Test func rectCottageFixtureRoundTrip() throws {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures/rect-cottage.json")

    let original = try Data(contentsOf: fixtureURL)
    let document = try ModelDocument.decode(from: original)
    #expect(document.schemaVersion == 1)

    let reencoded = try document.encodeToJSONData()
    #expect(reencoded == original)
}
