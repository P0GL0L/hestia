import ATContracts
import Foundation

/// Where a room is on the plan, for an editor that needs to know which room a point is in.
public enum RoomOutline {
    /// The room's centerline polygon in model space: the same corners the floor plan places the room's tag
    /// from, walking its boundary walls around the room. Nil when the walls give no polygon, so the room has no
    /// inside to point at.
    public static func centerline(of room: Room, in document: ModelDocument) -> [Point2]? {
        let walls = Dictionary(document.walls.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return FloorPlanView.roomPolygon(room.boundaryWallIDs.compactMap { walls[$0] })
    }
}
