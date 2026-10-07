import ATContracts
import AppKit
import SwiftUI

struct ContentView: View {
    /// What a click on the plan does.
    enum Tool {
        /// Two clicks: the wall's start, then its end.
        case wall
        /// One click on a drawn wall.
        case door
        /// One click on a drawn wall.
        case window
        /// One click on a drawn door or wall.
        case delete
        /// Clicks on drawn walls pick a room's boundary; Add Room makes it.
        case room

        var hint: String {
            switch self {
            case .wall: return "Click two points on the plan to add a wall."
            case .door: return "Click a wall to add a door."
            case .window: return "Click a wall to add a window."
            case .delete: return "Click a door or a wall to remove it."
            case .room: return "Click walls to add them to the room's boundary or take them out, then Add Room."
            }
        }
    }

    @State private var tool = Tool.wall
    @State private var session: EditSession?
    @State private var loadError: String?
    /// The first click of a wall, on the plan sheet's paper, until the second click places its end.
    @State private var pendingStart: Point2?
    /// The Room tool's boundary so far, in click order.
    @State private var roomWalls: [WallID] = []
    @State private var roomName = "Room"
    @State private var status = Tool.wall.hint
    @State private var exportMessage = "Schematic exports land in ~/Hestia-exports"

    init() {
        do {
            _session = State(initialValue: EditSession(model: try HestiaModel.cottage()))
        } catch {
            _loadError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some View {
        if let session {
            editor(session.model, sessionID: session.id)
        } else {
            Text(loadError ?? "No model loaded.")
                .padding()
        }
    }

    private func editor(_ model: HestiaModel, sessionID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.document.project.name)
                    .font(.title2.weight(.semibold))
                Text(OutputHonesty.schematicStamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                PlanCanvas(items: model.plan, bounds: model.planBounds, pendingStart: pendingStart,
                           selected: Set(roomWalls.map(\.rawValue)), onClick: { paper in click(paper) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                OrbitScene(meshes: model.meshes, sessionID: sessionID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Button("New") { newModel() }
                Button("Open…") { openModel() }
                Button("Save…") { saveModel(model) }
                toolButton("Wall", .wall)
                toolButton("Door", .door)
                toolButton("Window", .window)
                toolButton("Delete", .delete)
                toolButton("Room", .room)
                Button("Roof") { addRoof() }
                if tool == .room {
                    TextField("Room name", text: $roomName)
                        .frame(width: 140)
                    Button("Add Room") { addRoom() }
                        .disabled(roomWalls.isEmpty)
                }
                Button("Undo") { undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!(session?.canUndo ?? false))
                Text(status)
                    .font(.caption)
                Spacer()
                Button("Export PDF") { exportPDF(model) }
                Button("Export DXF") { exportDXF(model) }
                Text(exportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(minWidth: 1100, minHeight: 720)
    }

    /// A tool button, marked while its tool is the one clicks use.
    private func toolButton(_ title: String, _ choice: Tool) -> some View {
        let selected = tool == choice
        return Button(action: { select(choice) }) {
            Text(title)
                .fontWeight(selected ? .bold : .regular)
                .padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(selected ? Color.accentColor.opacity(0.3) : Color.clear))
        }
    }

    private func select(_ choice: Tool) {
        tool = choice
        pendingStart = nil
        roomWalls = []
        status = choice.hint
    }

    /// With the Door tool, or an Option-click, a click on a wall adds a door; with the Window tool, a window.
    /// With the Delete tool a click removes the door or wall under it. With the Wall tool the first click starts
    /// a wall; the second ends it and adds it to the ground storey.
    private func click(_ paper: Point2) {
        guard var current = session else { return }
        if tool == .door || NSEvent.modifierFlags.contains(.option) {
            addDoor(paper)
            return
        }
        if tool == .window {
            addWindow(paper)
            return
        }
        if tool == .delete {
            delete(paper)
            return
        }
        if tool == .room {
            toggleRoomWall(paper)
            return
        }
        guard let start = pendingStart else {
            pendingStart = paper
            status = "Click the wall's end point."
            return
        }
        pendingStart = nil
        do {
            try current.addWall(fromPaper: start, toPaper: paper)
            session = current
            status = "Added a wall. Undo removes it."
        } catch {
            status = error.localizedDescription
        }
    }

    private func addDoor(_ paper: Point2) {
        guard var current = session else { return }
        pendingStart = nil
        do {
            if try current.addDoor(atPaper: paper) {
                session = current
                status = "Added a door. Undo removes it."
            } else {
                status = "That missed every wall. " + Tool.door.hint
            }
        } catch {
            status = error.localizedDescription
        }
    }

    /// Puts a hip roof over the ground walls, when they close one rectangle.
    private func addRoof() {
        guard var current = session else { return }
        pendingStart = nil
        do {
            try current.addRoof()
            session = current
            status = "Added a hip roof. Undo removes it."
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    private func addWindow(_ paper: Point2) {
        guard var current = session else { return }
        pendingStart = nil
        do {
            if try current.addWindow(atPaper: paper) {
                session = current
                status = "Added a window. Undo removes it."
            } else {
                status = "That missed every wall. " + Tool.window.hint
            }
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    private func delete(_ paper: Point2) {
        guard var current = session else { return }
        pendingStart = nil
        do {
            if try current.delete(atPaper: paper) {
                session = current
                status = "Removed. Undo puts it back."
            } else {
                status = "That missed every door and wall. " + Tool.delete.hint
            }
        } catch {
            status = error.localizedDescription
        }
    }

    /// Puts the clicked wall in the room's boundary, or takes it out if it is there.
    private func toggleRoomWall(_ paper: Point2) {
        guard let model = session?.model else { return }
        switch model.wallHit(paper: paper) {
        case .none:
            status = "That missed every wall. " + Tool.room.hint
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
    private func addRoom() {
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

    /// Replaces the model with an empty one: one building, one ground storey, no walls. Nothing before it can
    /// be undone.
    private func newModel() {
        pendingStart = nil
        do {
            session = EditSession(model: try HestiaModel.blank())
            roomWalls = []
            tool = .wall
            status = "New model. " + Tool.wall.hint
        } catch {
            status = error.localizedDescription
        }
    }

    /// Replaces the model with one read from a saved file. Nothing before it can be undone.
    private func openModel() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingStart = nil
        do {
            session = EditSession(model: try HestiaModel.open(Data(contentsOf: url)))
            roomWalls = []
            status = "Opened \(url.lastPathComponent)."
        } catch {
            status = error.localizedDescription
        }
    }

    /// Writes the model's JSON where the person chooses. The undo history is not saved.
    private func saveModel(_ model: HestiaModel) {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        panel.nameFieldStringValue = fileName(model, ".json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.saveData().write(to: url, options: .atomic)
            status = "Saved \(url.lastPathComponent)."
        } catch {
            status = error.localizedDescription
        }
    }

    private func undo() {
        guard var current = session else { return }
        pendingStart = nil
        do {
            try current.undo()
            session = current
            // An undone wall leaves the room's boundary too.
            let walls = Set(current.model.document.walls.map(\.id))
            roomWalls = roomWalls.filter { walls.contains($0) }
            status = "Undone."
        } catch {
            status = error.localizedDescription
        }
    }

    private func fileName(_ model: HestiaModel, _ suffix: String) -> String {
        let name = model.document.project.name.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
        return (name.isEmpty ? "hestia" : name) + suffix
    }

    private func exportPDF(_ model: HestiaModel) {
        writeExport(name: fileName(model, "-schematic-set.pdf")) {
            try model.pdf()
        }
    }

    private func exportDXF(_ model: HestiaModel) {
        writeExport(name: fileName(model, "-ground-plan.dxf")) {
            try model.dxf()
        }
    }

    private func writeExport(name: String, body: () throws -> Data) {
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Hestia-exports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try body().write(to: url)
            exportMessage = url.path
        } catch {
            exportMessage = error.localizedDescription
        }
    }
}
