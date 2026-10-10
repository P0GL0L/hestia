import ATContracts
import AppKit
import SwiftUI

struct ContentView: View {
    /// What the plan view's clicks and drags do.
    enum Tool: Equatable {
        /// Click to pick a wall, a placed item, or a terrain patch; drag to move it.
        case select
        /// Click point after point to draw connected walls, or drag one wall.
        case wall
        /// Drag, or click two corners, for a rectangular room: four walls and the room inside them.
        case room
        /// Clicks on drawn walls pick a room's boundary; Add Room makes it.
        case roomFromWalls
        /// One click on a drawn wall.
        case door
        /// One click on a drawn wall.
        case window
        /// One click on a drawn wall.
        case opening
        /// Two clicks: the bottom of the stair, then the way it climbs.
        case stair
        /// One click places the chosen item.
        case furniture
        /// Drag, or click two corners, for a rectangle of lot, lawn, driveway, path, patio, deck, or pond.
        case site
        /// One click on a drawn opening, stair, wall, item, or patch, or inside a room.
        case delete

        var hint: String {
            switch self {
            case .select: return "Click a wall, an item, or a patch to select it. Drag to move it; Delete removes it."
            case .wall: return "Click to start a wall, then click each corner. Type a length and press Return for an "
                + "exact wall. Esc or right-click stops."
            case .room: return "Drag out a room, or click two corners. Type a size such as 12 x 10 and press Return."
            case .roomFromWalls:
                return "Click walls to add them to the room's boundary or take them out, then Add Room."
            case .door: return "Click a wall to add a door."
            case .window: return "Click a wall to add a window."
            case .opening: return "Click a wall to add a cased opening."
            case .stair: return "Click the bottom of the stair, then click the way it climbs."
            case .furniture: return "Click to place the item. R turns it a quarter turn before you place it."
            case .site: return "Drag out the area, or click two corners."
            case .delete: return "Click a door, window, opening, stair, wall, item, or patch, or inside a room."
            }
        }
    }

    /// What the window shows.
    enum Layout: String, CaseIterable {
        case plan = "Plan"
        case split = "Plan + 3D"
        case house = "3D"
    }

    /// A press on the plan, until it is released.
    struct Press: Equatable {
        var model: Point2
        var view: CGPoint
    }

    @State var tool = Tool.wall
    @State var session: EditSession?
    @State var loadError: String?
    /// The first point of a two-point tool, in the model, until the second point is placed. For walls, the end
    /// of the last wall, so the next one continues from it.
    @State var anchor: Point2?
    /// Where the current chain of walls began, so clicking it again closes the outline.
    @State var chainStart: Point2?
    /// The model point under the pointer, as the current tool would use it.
    @State var hover: Point2?
    @State var press: Press?
    @State var dragging = false
    /// A length or size typed while drawing.
    @State var typed = ""
    /// The Room from Walls tool's boundary so far, in click order.
    @State var roomWalls: [WallID] = []
    @State var roomName = "Room"
    @State var furnitureID = "hestia.sofa"
    @State var furnitureTurn = 0
    @State var siteKind = SiteKind.lot
    @State var selection: PlanSelection?
    @State var zoom = 1.0
    @State var pan = CGSize.zero
    @State var layout = Layout.split
    @State var houseMode = HouseViewMode.orbit
    @State var showRoof = true
    /// Whether Blender is rendering a photo.
    @State var rendering = false
    @State var status = Tool.wall.hint
    @State var exportMessage = "Schematic exports land in ~/Hestia-exports"
    /// This window's place in the list Quit asks.
    @State var windowID = UUID()
    /// The model area the plan view shows. It grows when the drawing outgrows it and otherwise holds still;
    /// New and Open start it afresh.
    @State var fit = HeldFit()

    /// What the held fit follows: the session and its document.
    private struct FitKey: Equatable {
        var session: UUID?
        var document: ModelDocument?
    }

    init() {
        do {
            // The cottage, furnished and on its lot (`SampleSite`), so the first look shows the whole house.
            let cottage = try HestiaModel.cottage()
            let sample = try HestiaModel(document: SampleSite.decorate(cottage.document), issueDate: cottage.issueDate)
            _session = State(initialValue: EditSession(model: sample))
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(model.document.project.name)
                    .font(.title2.weight(.semibold))
                Text(OutputHonesty.schematicStamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer(minLength: 12)
                Picker("", selection: $layout) {
                    ForEach(Layout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(SegmentedPickerStyle())
                .labelsHidden()
                .fixedSize()
            }
            fileRow(model)
            toolRow(model)
            HStack(spacing: 12) {
                if layout != .house {
                    plan(model)
                }
                if layout != .plan {
                    house(model, sessionID: sessionID)
                }
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
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(16)
        .frame(minWidth: 1100, minHeight: 720)
    }

    /// File and Undo on the left, export on the right. Each group keeps its ideal width, so no label is cut
    /// short at the narrowest window.
    private func fileRow(_ model: HestiaModel) -> some View {
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
                Button("Export USD") { exportUSD(model) }
                Menu(rendering ? "Rendering…" : "Render Photo") {
                    Button("Outside, from the street") { renderPhoto(model, view: .exterior) }
                    Button("Inside, the living room") { renderPhoto(model, view: .interior) }
                }
                .disabled(rendering)
                .fixedSize()
            }
            .fixedSize()
        }
    }

    /// The tools; under them, what the chosen tool needs: a room's name, the item to place, or the kind of site
    /// area.
    private func toolRow(_ model: HestiaModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                toolButton("Select", .select)
                toolButton("Wall", .wall)
                toolButton("Room", .room)
                toolButton("Door", .door)
                toolButton("Window", .window)
                toolButton("Opening", .opening)
                toolButton("Stair", .stair)
                toolButton("Furniture", .furniture)
                toolButton("Site", .site)
                toolButton("Delete", .delete)
                Button(model.groundRoof == nil ? "Add Roof" : "Remove Roof") { toggleRoof() }
            }
            .fixedSize()
            if [.room, .roomFromWalls, .furniture, .site].contains(tool) {
                HStack(spacing: 6) {
                    toolOptions
                }
            }
        }
    }

    @ViewBuilder private var toolOptions: some View {
        switch tool {
        case .room, .roomFromWalls:
            TextField("Room name", text: $roomName)
                .frame(width: 130)
            Button(tool == .room ? "Pick Walls…" : "Draw Room") {
                select(tool == .room ? .roomFromWalls : .room)
            }
            .fixedSize()
            if tool == .roomFromWalls {
                Button("Add Room") { addRoom() }
                    .disabled(roomWalls.isEmpty)
                    .fixedSize()
            }
        case .furniture:
            Menu(Furniture.item(CatalogItemID(rawValue: furnitureID))?.name ?? "Choose") {
                ForEach(FurnitureItem.Category.allCases, id: \.self) { category in
                    Menu(category.rawValue) {
                        ForEach(Furniture.items(in: category), id: \.id) { item in
                            Button(item.name) { furnitureID = item.id }
                        }
                    }
                }
            }
            .frame(width: 170)
            Button("Turn") { furnitureTurn = (furnitureTurn + 90) % 360 }
                .fixedSize()
        case .site:
            Picker("", selection: $siteKind) {
                ForEach(SiteKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)
        default:
            EmptyView()
        }
    }

    private func plan(_ model: HestiaModel) -> some View {
        PlanCanvas(items: model.modelPlan(), bounds: fit.current(for: model, session: session?.id ?? UUID()),
                   pendingStart: anchor,
                   selected: selectedWalls,
                   penScale: Double(model.planTransform?.scale.modelUnitsPerPaperUnit ?? 1),
                   overlay: PlanOverlay(document: model.document, storey: model.groundStorey,
                                        selected: selectedPlacement),
                   preview: preview(model).shapes, labels: preview(model).labels,
                   zoom: zoom, pan: pan,
                   onInput: { input, fit in planInput(input, fit: fit) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
    }

    private func house(_ model: HestiaModel, sessionID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(houseMode == .walk ? "Stop Walking" : "Walk Inside") {
                    houseMode = houseMode == .walk ? .orbit : .walk
                    status = houseMode == .walk
                        ? "Walking. W A S D or the arrows move, drag to look, Shift runs, Esc stops."
                        : "Orbiting. Drag to turn the house, scroll to zoom."
                }
                .fixedSize()
                Toggle("Roof", isOn: $showRoof)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            ZStack(alignment: .bottom) {
                HouseView(scene: model.house, sessionID: sessionID, mode: houseMode, showRoof: showRoof,
                          walkStart: Walker.start(in: model.document, storey: model.groundStorey),
                          barriers: WalkBarriers(document: model.document, storey: model.groundStorey),
                          onLeaveWalk: {
                              houseMode = .orbit
                              status = "Orbiting. Drag to turn the house, scroll to zoom."
                          })
                if houseMode == .walk {
                    Text("W A S D or arrows to walk · drag to look · Shift to run · Esc to stop")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.55))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .padding(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedWalls: Set<UUID> {
        var walls = Set(roomWalls.map(\.rawValue))
        if case let .wall(id) = selection { walls.insert(id.rawValue) }
        return walls
    }

    private var selectedPlacement: PlacementID? {
        if case let .placement(id) = selection { return id }
        return nil
    }

    /// A tool button, marked while its tool is the one clicks use.
    private func toolButton(_ title: String, _ choice: Tool) -> some View {
        let selected = tool == choice || (choice == .room && tool == .roomFromWalls)
        return Button(action: { select(choice) }) {
            Text(title)
                .fontWeight(selected ? .bold : .regular)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(selected ? Color.accentColor.opacity(0.3) : Color.clear))
        }
    }

    func select(_ choice: Tool) {
        tool = choice
        clearDrawing()
        roomWalls = []
        selection = nil
        status = choice.hint
    }

    /// Forgets a half-drawn wall chain, room, or area, and anything typed for it.
    func clearDrawing() {
        anchor = nil
        chainStart = nil
        press = nil
        dragging = false
        typed = ""
    }
}
