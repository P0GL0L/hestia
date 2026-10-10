import ATContracts
import SwiftUI

/// The tools that work on drawn walls: doors, windows, openings, stairs, and rooms from picked walls.
extension ContentView {
    /// Adds a door, window, or cased opening where a point of the plan sheet's paper falls on a wall.
    func addOnWall(_ paper: Point2, tool: Tool) {
        guard var current = session else { return }
        do {
            let added: Bool
            let name: String
            switch tool {
            case .door:
                added = try current.addDoor(atPaper: paper)
                name = "door"
            case .window:
                added = try current.addWindow(atPaper: paper)
                name = "window"
            default:
                added = try current.addCasedOpening(atPaper: paper)
                name = "cased opening"
            }
            if added {
                session = current
                status = "Added a \(name). Undo removes it."
            } else {
                status = "That missed every wall. " + tool.hint
            }
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    /// The first click sets the stair's bottom; the second, the way it climbs, and adds it.
    func stairClick(_ point: Point2) {
        guard var current = session, let transform = current.model.planTransform else { return }
        guard let start = anchor else {
            anchor = point
            status = "Click the way the stair climbs."
            return
        }
        anchor = nil
        do {
            let stair = try current.addStair(fromPaper: transform.paper(start), towardPaper: transform.paper(point))
            session = current
            let model = current.model
            let run = PlanGeometry.distance(stair.runStart, stair.runEnd)
            status = "Added a stair: \(stair.riserCount) risers of \(model.written(stair.riserHeight)), "
                + "\(model.written(run)) run. Undo removes it."
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    /// Puts the clicked wall in the room's boundary, or takes it out if it is there.
    func toggleRoomWall(_ paper: Point2) {
        guard let model = session?.model else { return }
        switch model.wallHit(paper: paper) {
        case .none:
            status = "That missed every wall. " + Tool.roomFromWalls.hint
        case .ambiguous:
            status = "More than one wall is there. Click where only one wall is drawn."
        case let .wall(id):
            if let index = roomWalls.firstIndex(of: id) {
                roomWalls.remove(at: index)
            } else {
                roomWalls.append(id)
            }
            status = roomWalls.count == 1 ? "1 wall in the boundary." : "\(roomWalls.count) walls in the boundary."
        }
    }

    /// Makes the room from the picked walls and the name, as the model's command checks them.
    func addRoom() {
        guard var current = session else { return }
        do {
            try current.addRoom(named: roomName, walls: roomWalls)
            session = current
            status = "Added \(roomName). Undo removes it."
            roomWalls = []
            roomName = "Room"
        } catch {
            status = HestiaModel.describe(error)
        }
    }
}
