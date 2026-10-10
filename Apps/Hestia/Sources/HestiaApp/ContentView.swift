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
        /// One click on a drawn wall.
        case opening
        /// Two clicks: the bottom of the stair, then the way it climbs.
        case stair
        /// One click on a drawn opening, stair, or wall, or inside a room.
        case delete
        /// Clicks on drawn walls pick a room's boundary; Add Room makes it.
        case room

        var hint: String {
            switch self {
            case .wall: return "Click two points on the plan to add a wall."
            case .door: return "Click a wall to add a door."
            case .window: return "Click a wall to add a window."
            case .opening: return "Click a wall to add a cased opening."
            case .stair: return "Click the bottom of the stair, then click the way it climbs."
            case .delete: return "Click a door, window, opening, stair, or wall, or inside a room, to remove it."
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
    /// This window's place in the list Quit asks.
    @State private var windowID = UUID()
    /// The model area the plan view shows. It grows when the drawing outgrows it and otherwise holds still;
    /// New and Open start it afresh.
    @State private var fit = HeldFit()

    /// What the held fit follows: the session and its document.
    private struct FitKey: Equatable {
        var session: UUID?
        var document: ModelDocument?
    }

    init() {
        do {
            _session = State(initialValue: EditSession(model: try HestiaModel.cottage()))
        } catch {
            _loadError = State(initialValue: HestiaModel.describe(error))
        }
    }

    var body: some View {
        Group {
            if let session {
                editor(session.model, sessionID: session.id)
            } else {
                Text(loadError ?? "No model loaded.")
                    .padding()
            }
        }
        .background(WindowCloseGuard { confirmDiscard() })
        .onAppear { UnsavedChanges.shared.register(windowID) { confirmDiscard() } }
        // One path: hold the fit on screen whenever the session or its document changes (`HeldFit`).
        .task(id: FitKey(session: session?.id, document: session?.model.document)) {
            if let session { fit.hold(for: session.model, session: session.id) }
        }
        .onDisappear { UnsavedChanges.shared.remove(windowID) }
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
            // File and Undo on the left, export on the right; the tools on their own row below. Each group keeps
            // its ideal width, so no label is cut short at the narrowest window.
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Button("New") { newModel() }
                    Button("Open…") { openModel() }
                    Button("Save…") { saveModel() }
                        .background {
                            // Command-S writes the remembered file. It is unseen, so it adds no button and no menu.
                            Button("Save to the Current File") { saveToCurrentFile() }
                                .keyboardShortcut("s", modifiers: .command)
                                .opacity(0)
                                .frame(width: 0, height: 0)
                                .accessibilityHidden(true)
                        }
                    Button("Undo") { undo() }
                        .keyboardShortcut("z", modifiers: .command)
                        .disabled(!(session?.canUndo ?? false))
                    Button("Redo") { redo() }
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .disabled(!(session?.canRedo ?? false))
                }
                .fixedSize()
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    Button("Export PDF") { exportPDF(model) }
                    Button("Export DXF") { exportDXF(model) }
                }
                .fixedSize()
            }
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    toolButton("Wall", .wall)
                    toolButton("Door", .door)
                    toolButton("Window", .window)
                    toolButton("Opening", .opening)
                    toolButton("Stair", .stair)
                    toolButton("Delete", .delete)
                    toolButton("Room", .room)
                    Button(model.groundRoof == nil ? "Roof" : "Remove Roof") { toggleRoof() }
                }
                .fixedSize()
                if tool == .room {
                    TextField("Room name", text: $roomName)
                        .frame(width: 140)
                    Button("Add Room") { addRoom() }
                        .disabled(roomWalls.isEmpty)
                        .fixedSize()
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                PlanCanvas(items: model.modelPlan(), bounds: fit.current(for: model, session: sessionID),
                           pendingStart: pendingStart.flatMap { model.planTransform?.model($0) },
                           selected: Set(roomWalls.map(\.rawValue)),
                           penScale: Double(model.planTransform?.scale.modelUnitsPerPaperUnit ?? 1),
                           onClick: { point in
                               // The tools work in the plan sheet's paper; take the model point there.
                               if let paper = model.planTransform?.paper(point) { click(paper) }
                           })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                OrbitScene(meshes: model.meshes, sessionID: sessionID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // The status on its own line; where the last export went, at the right of it.
            HStack(spacing: 12) {
                Text(status)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 12)
                Text(exportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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

    /// With the Door tool, or an Option-click, a click on a wall adds a door; with the Window tool, a window; with
    /// the Opening tool, a cased opening. With the Stair tool the first click sets a stair's bottom and the
    /// second the way it climbs. With the Delete tool a click removes the door or wall under it. With the Wall tool the first click starts
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
        if tool == .opening {
            addCasedOpening(paper)
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
        if tool == .stair {
            stairClick(paper)
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
            status = HestiaModel.describe(error)
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
            status = HestiaModel.describe(error)
        }
    }

    /// Removes the ground storey's roof when it has one; otherwise puts a hip roof over the ground walls, when
    /// they close one rectangle.
    private func toggleRoof() {
        guard var current = session else { return }
        pendingStart = nil
        do {
            if current.model.groundRoof != nil {
                try current.removeRoof()
                session = current
                status = "Removed the roof. Undo puts it back."
            } else {
                try current.addRoof()
                session = current
                status = "Added a hip roof. Undo removes it."
            }
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

    /// The first click sets the stair's bottom; the second, the way it climbs, and adds it.
    private func stairClick(_ paper: Point2) {
        guard var current = session else { return }
        guard let start = pendingStart else {
            pendingStart = paper
            status = "Click the way the stair climbs."
            return
        }
        pendingStart = nil
        do {
            let stair = try current.addStair(fromPaper: start, towardPaper: paper)
            session = current
            let model = current.model
            let dx = Double(stair.runEnd.x.ticks - stair.runStart.x.ticks)
            let dy = Double(stair.runEnd.y.ticks - stair.runStart.y.ticks)
            let run = Length(ticks: Int64((dx * dx + dy * dy).squareRoot().rounded()))
            status = "Added a stair: \(stair.riserCount) risers of \(model.written(stair.riserHeight)), "
                + "\(model.written(run)) run. Undo removes it."
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    private func addCasedOpening(_ paper: Point2) {
        guard var current = session else { return }
        pendingStart = nil
        do {
            if try current.addCasedOpening(atPaper: paper) {
                session = current
                status = "Added a cased opening. Undo removes it."
            } else {
                status = "That missed every wall. " + Tool.opening.hint
            }
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    private func delete(_ paper: Point2) {
        guard var current = session else { return }
        pendingStart = nil
        do {
            if let removed = try current.delete(atPaper: paper) {
                session = current
                // A removed wall or room leaves the Room tool's picked boundary too.
                let walls = Set(current.model.document.walls.map(\.id))
                roomWalls = roomWalls.filter { walls.contains($0) }
                status = "Removed \(removed.phrase). Undo puts it back."
            } else {
                status = "That missed everything that can be removed. " + Tool.delete.hint
            }
        } catch {
            status = HestiaModel.describe(error)
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
    /// be undone. The new session has no file, so the file from the last Open or Save is forgotten. A cancelled
    /// discard leaves that file in place.
    private func newModel() {
        guard confirmDiscard() else { return }
        pendingStart = nil
        do {
            session = EditSession(model: try HestiaModel.blank())
            roomWalls = []
            tool = .wall
            status = "New model. " + Tool.wall.hint
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    /// Replaces the model with one read from a saved file, and remembers that file. Nothing before it can be
    /// undone. A cancelled panel, or a file that cannot be read, leaves the remembered file as it was.
    private func openModel() {
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingStart = nil
        do {
            session = EditSession(model: try HestiaModel.open(Data(contentsOf: url)), fileURL: url)
            roomWalls = []
            status = "Opened \(url.lastPathComponent)."
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    /// Writes the model's JSON where the person chooses. The undo history is not saved. Returns whether it was
    /// written. The Save… button always opens this panel. A cancelled panel leaves the remembered file as it was.
    @discardableResult
    private func saveModel() -> Bool {
        guard let model = session?.model else { return false }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        panel.nameFieldStringValue = fileName(model, ".json")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return save(to: url)
    }

    /// Command-S. Writes the document to the file remembered from a successful Open or Save, and does not open a
    /// panel. With no remembered file, opens the save panel.
    private func saveToCurrentFile() {
        guard let url = session?.fileURL else {
            saveModel()
            return
        }
        save(to: url)
    }

    /// Writes the document to `url` and remembers that file. A failed write leaves the document unsaved and the
    /// remembered file as it was.
    @discardableResult
    private func save(to url: URL) -> Bool {
        guard var current = session else { return false }
        do {
            try current.save(to: url)
            session = current
            status = "Saved \(url.lastPathComponent)."
            return true
        } catch {
            status = HestiaModel.describe(error)
            return false
        }
    }

    /// Asks before the document is replaced or its window closes, when it differs from the last New, Open, or
    /// successful Save. Save writes it through the save panel, and a cancelled panel stays; Don't Save goes
    /// ahead; Cancel stays. A document with no changes does not ask. Returns whether to go ahead.
    private func confirmDiscard() -> Bool {
        guard let current = session, current.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to \u{201C}\(current.model.document.project.name)\u{201D}?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveModel()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
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
            status = HestiaModel.describe(error)
        }
    }

    private func redo() {
        guard var current = session else { return }
        pendingStart = nil
        do {
            try current.redo()
            session = current
            // A redone removal takes a wall out of the room's boundary too.
            let walls = Set(current.model.document.walls.map(\.id))
            roomWalls = roomWalls.filter { walls.contains($0) }
            status = "Redone."
        } catch {
            status = HestiaModel.describe(error)
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

    /// `name` in `directory`, or, when a file of that name is already there, the name with the lowest free
    /// number before its extension ("rect-cottage-schematic-set 2.pdf", then 3), so an export never replaces
    /// an earlier one.
    static func unusedURL(for name: String, in directory: URL) -> URL {
        let first = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: first.path) else { return first }
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var number = 2
        while true {
            let candidate = directory.appendingPathComponent("\(stem) \(number)" + (ext.isEmpty ? "" : ".\(ext)"))
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    private func writeExport(name: String, body: () throws -> Data) {
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Hestia-exports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = Self.unusedURL(for: name, in: directory)
            try body().write(to: url, options: .atomic)
            exportMessage = url.path
        } catch {
            exportMessage = HestiaModel.describe(error)
        }
    }
}
