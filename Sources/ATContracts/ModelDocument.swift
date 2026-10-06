import Foundation

public struct ModelDocument: Hashable, Codable, Sendable {
    public var schemaVersion: Int
    public var project: Project
    public var buildings: [Building]
    public var storeys: [Storey]
    public var walls: [Wall]
    public var openings: [Opening]
    public var rooms: [Room]

    public init(
        schemaVersion: Int,
        project: Project,
        buildings: [Building],
        storeys: [Storey],
        walls: [Wall],
        openings: [Opening],
        rooms: [Room]
    ) {
        self.schemaVersion = schemaVersion
        self.project = project
        self.buildings = buildings
        self.storeys = storeys
        self.walls = walls
        self.openings = openings
        self.rooms = rooms
    }

    public static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    public static func makeJSONDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    public func encodeToJSONData() throws -> Data {
        try Self.makeJSONEncoder().encode(self)
    }

    public static func decode(from jsonData: Data) throws -> ModelDocument {
        try makeJSONDecoder().decode(ModelDocument.self, from: jsonData)
    }
}
