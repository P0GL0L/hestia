import Foundation

public struct Point2: Hashable, Codable, Sendable {
    public var x: Length
    public var y: Length

    public init(x: Length, y: Length) {
        self.x = x
        self.y = y
    }
}

public struct Point3: Hashable, Codable, Sendable {
    public var x: Length
    public var y: Length
    public var z: Length

    public init(x: Length, y: Length, z: Length) {
        self.x = x
        self.y = y
        self.z = z
    }
}
