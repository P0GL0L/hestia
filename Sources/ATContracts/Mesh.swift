import Foundation

/// Names a material shared by meshes, the 3D view, and exporters.
public struct MaterialID: Hashable, Codable, Sendable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A unit direction. Floats are fine here: normals are render data, not model lengths.
public struct Vector3f: Hashable, Codable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Texture coordinate with `v` up.
public struct TextureCoordinate: Hashable, Codable, Sendable {
    public var u: Float
    public var v: Float

    public init(u: Float, v: Float) {
        self.u = u
        self.v = v
    }
}

/// A PBR material. Color is sRGB with alpha; roughness and metallic are 0...1000 per mille.
public struct Material: Hashable, Codable, Sendable {
    public var id: MaterialID
    public var name: String
    public var baseColorRGBA: [UInt8]
    public var roughnessPermille: Int
    public var metallicPermille: Int
    /// File name of a base-color texture in the project package, if any.
    public var textureName: String?

    public init(
        id: MaterialID, name: String, baseColorRGBA: [UInt8],
        roughnessPermille: Int = 800, metallicPermille: Int = 0, textureName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.baseColorRGBA = baseColorRGBA
        self.roughnessPermille = roughnessPermille
        self.metallicPermille = metallicPermille
        self.textureName = textureName
    }
}

public enum MeshError: Error, Sendable, Equatable {
    case attributeCountMismatch
    case indicesNotTriangles
    case indexOutOfRange(UInt32)
}

/// An indexed triangle mesh with one material. Z is up; front faces wind counterclockwise.
///
/// Positions stay in exact ticks; the 3D view and exporters convert them at the edge.
public struct Mesh: Hashable, Codable, Sendable {
    /// The model element this mesh draws, for click-to-select.
    public var elementID: UUID?
    public var materialID: MaterialID
    public var positions: [Point3]
    public var normals: [Vector3f]
    public var uvs: [TextureCoordinate]
    public var indices: [UInt32]

    public init(
        elementID: UUID? = nil, materialID: MaterialID, positions: [Point3],
        normals: [Vector3f], uvs: [TextureCoordinate], indices: [UInt32]
    ) {
        self.elementID = elementID
        self.materialID = materialID
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.indices = indices
    }

    public var triangleCount: Int { indices.count / 3 }

    /// Checks that every vertex has a normal and UV, indices form whole triangles, and all indices are in range.
    public func validate() throws {
        guard normals.count == positions.count, uvs.count == positions.count else {
            throw MeshError.attributeCountMismatch
        }
        guard indices.count % 3 == 0 else { throw MeshError.indicesNotTriangles }
        if let bad = indices.first(where: { Int($0) >= positions.count }) {
            throw MeshError.indexOutOfRange(bad)
        }
    }
}
