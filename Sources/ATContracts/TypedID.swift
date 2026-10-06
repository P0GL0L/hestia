import Foundation

public struct ProjectID: Hashable, Codable, Sendable, RawRepresentable {
    public var rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct BuildingID: Hashable, Codable, Sendable, RawRepresentable {
    public var rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct StoreyID: Hashable, Codable, Sendable, RawRepresentable {
    public var rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct WallID: Hashable, Codable, Sendable, RawRepresentable {
    public var rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct OpeningID: Hashable, Codable, Sendable, RawRepresentable {
    public var rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct RoomID: Hashable, Codable, Sendable, RawRepresentable {
    public var rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}
