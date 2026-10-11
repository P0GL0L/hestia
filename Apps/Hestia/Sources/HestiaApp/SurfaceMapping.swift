import Foundation

/// Texture coordinates for Hestia's solids, so a photographed material lies on every surface at its real size.
///
/// Each vertex is projected onto its own face's plane: on a floor or ceiling, u runs east and v south; on a
/// wall or a roof slope, u runs level along the face and v runs up it. So roof courses run along the eaves on
/// every slope, boards and tiles stay level on walls, and one texture tile covers `tile` meters each way.
enum SurfaceMapping {
    static let metersPerFoot = 0.3048

    /// The texture coordinate of a view-space point (feet, y up) on a face with the given normal.
    static func coordinate(_ point: ScenePoint, normal: ScenePoint, tile: Double) -> (u: Float, v: Float) {
        let scale = metersPerFoot / max(tile, 1e-6)
        let (x, y, z) = (Double(point.x), Double(point.y), Double(point.z))
        let (nx, ny, nz) = (Double(normal.x), Double(normal.y), Double(normal.z))
        let level = (nx * nx + nz * nz).squareRoot()
        guard level > 1e-3 else {
            // Facing straight up or down: lay the tile flat, east and south.
            return (Float(x * scale), Float(z * scale))
        }
        // Along the face, level: up × normal, normalized.
        let (ax, az) = (nz / level, -nx / level)
        // Up the face: normal × along (along has no y).
        let (ux, uy, uz) = (ny * az, nz * ax - nx * az, -ny * ax)
        let u = x * ax + z * az
        let v = x * ux + y * uy + z * uz
        // Image rows run down, so up the face is toward smaller v.
        return (Float(u * scale), Float(-v * scale))
    }

    /// The direction texture u runs along a face with this normal, in view space: level along a wall or slope,
    /// east on a floor or ceiling.
    static func tangent(normal: ScenePoint) -> ScenePoint {
        let (nx, nz) = (Double(normal.x), Double(normal.z))
        let level = (nx * nx + nz * nz).squareRoot()
        guard level > 1e-3 else { return ScenePoint(1, 0, 0) }
        return ScenePoint(Float(nz / level), 0, Float(-nx / level))
    }

    /// Texture coordinates for every vertex of a solid.
    static func coordinates(_ solid: Solid, tile: Double) -> [(u: Float, v: Float)] {
        zip(solid.positions, solid.normals).map { coordinate($0, normal: $1, tile: tile) }
    }
}
