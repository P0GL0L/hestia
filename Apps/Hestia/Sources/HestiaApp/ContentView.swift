import ATContracts
import AppKit
import SwiftUI

struct ContentView: View {
    static let minimumWindowWidth: CGFloat = 1280

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

        var toolbarLabel: String { rawValue }
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
    /// Zoom steps asked of the 3D view by its + and − buttons; the view moves by the change.
    @State var houseZoom = 0
    @State var showHelp = false
    @State var showInspector = true
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

    /// The window as an architecture app lays it out: the tools down the left, the plan and the house in the
    /// middle, the inspector down the right, and a status bar along the foot. File, edit, view, and output
    /// commands sit in the window's toolbar.
    private func editor(_ model: HestiaModel, sessionID: UUID) -> some View {
        HStack(spacing: 0) {
            ToolPalette(selected: tool, hasRoof: model.groundRoof != nil, toolsEnabled: houseMode != .walk,
                        choose: { select($0) },
                        toggleRoof: { toggleRoof() })
            Divider()
            VStack(spacing: 0) {
                workspace(model, sessionID: sessionID)
                Divider()
                statusBar
            }
            if showInspector {
                Divider()
                inspector(model)
            }
        }
        .frame(minWidth: Self.minimumWindowWidth, minHeight: 720)
        .navigationTitle(model.document.project.name)
        .navigationSubtitle(OutputHonesty.schematicStamp)
        .toolbar { toolbar(model) }
        .background {
            // Command-S writes the remembered file. It is unseen, so it adds no button and no menu.
            Button("Save to the Current File") { saveToCurrentFile() }
                .keyboardShortcut("s", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .sheet(isPresented: $showHelp) {
            HelpView { showHelp = false }
        }
    }

    /// The plan, the house, or both side by side, each on a card in a soft gray well.
    private func workspace(_ model: HestiaModel, sessionID: UUID) -> some View {
        HStack(spacing: 10) {
            if layout != .house {
                card { plan(model) }
            }
            if layout != .plan {
                card { house(model, sessionID: sessionID) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.12), lineWidth: 1))
    }

    /// What the chosen tool does or what just happened, on the left; where the last export went, on the right.
    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: tool.symbol)
                .foregroundColor(.secondary)
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
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    /// File and history on the leading side, the layout in the middle, walking, output, help, and the inspector
    /// on the trailing side.
    static let renderPhotoLabel = "Render Photo"
    static let exportLabel = "Export"

    @ToolbarContentBuilder
    private func toolbar(_ model: HestiaModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("New", systemImage: "doc.badge.plus") { newModel() }
                .help("Start an empty model")
            Button("Open", systemImage: "folder") { openModel() }
                .help("Open a saved model")
            Button("Save", systemImage: "square.and.arrow.down") { saveModel() }
                .help("Save the model as… (Command-S saves to the current file)")
            Button("Undo", systemImage: "arrow.uturn.backward") { undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!(session?.canUndo ?? false))
                .help("Undo (Command-Z)")
            Button("Redo", systemImage: "arrow.uturn.forward") { redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(session?.canRedo ?? false))
                .help("Redo (Shift-Command-Z)")
        }
        ToolbarItem(placement: .principal) {
            Picker("Layout", selection: $layout) {
                ForEach(Layout.allCases, id: \.self) { choice in
                    Text(choice.toolbarLabel)
                        .accessibilityLabel(choice.toolbarLabel)
                        .tag(choice)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
            .help("Show the plan, the house in 3D, or both")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(houseMode == .walk ? "Stop Walking" : "Walk Inside",
                   systemImage: houseMode == .walk ? "figure.stand" : "figure.walk") { toggleWalk() }
            .disabled(layout == .plan)
            .help("Walk through the house at eye height")
            Menu {
                Button("Outside, from the street") { renderPhoto(model, view: .exterior) }
                Button("Inside the house") { renderPhoto(model, view: .interior) }
                Divider()
                Text("Materials, models, and sky: Poly Haven, CC0")
            } label: {
                Label(Self.renderPhotoLabel, systemImage: rendering ? "hourglass" : "camera.aperture")
                    .accessibilityLabel(Self.renderPhotoLabel)
            }
            .disabled(rendering)
            .accessibilityLabel(Self.renderPhotoLabel)
            .help(rendering ? "Rendering..." : "Render a photoreal still with Blender")
            Menu {
                Button("Drawing Set (PDF)") { exportPDF(model) }
                Button("Ground Plan (DXF)") { exportDXF(model) }
                Button("3D Model (USD)") { exportUSD(model) }
            } label: {
                Label(Self.exportLabel, systemImage: "square.and.arrow.up")
                    .accessibilityLabel(Self.exportLabel)
            }
            .accessibilityLabel(Self.exportLabel)
            .help("Export the drawings or the model to ~/Hestia-exports")
            Button("Help", systemImage: "questionmark.circle") { showHelp = true }
                .keyboardShortcut("?", modifiers: .command)
                .help("How to use Hestia (Command-?)")
            Button("Inspector", systemImage: "sidebar.right") { showInspector.toggle() }
                .help("Show or hide the inspector")
        }
    }

    /// Starts or stops walking, and says how.
    func toggleWalk() {
        houseMode = houseMode == .walk ? .orbit : .walk
        status = houseMode == .walk ? Self.walkingStatus : Self.orbitingStatus
    }

    static let walkingStatus = "Walking. W A S D or the arrows move, drag to look, Shift runs, Esc stops."
    static let orbitingStatus = "Orbiting. Drag to turn the house; scroll, pinch, or + and \u{2212} to zoom."

    @ViewBuilder var toolOptions: some View {
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

    /// The house in 3D, with its controls floating over the bottom right corner and, while walking, the keys
    /// to use along the bottom.
    private func house(_ model: HestiaModel, sessionID: UUID) -> some View {
        ZStack(alignment: .bottomTrailing) {
            HouseView(scene: model.house, document: model.document, meshes: model.meshes, sessionID: sessionID,
                      mode: houseMode, showRoof: showRoof, zoom: houseZoom,
                      walkStart: Walker.start(in: model.document, storey: model.groundStorey),
                      barriers: WalkBarriers(document: model.document, storey: model.groundStorey),
                      onLeaveWalk: {
                          houseMode = .orbit
                          status = Self.orbitingStatus
                      })
            if houseMode == .walk {
                Text("W A S D or arrows to walk · drag to look · Shift to run · Esc to stop")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 52)
            }
            HStack(spacing: 2) {
                floating(houseMode == .walk ? "figure.stand" : "figure.walk",
                         houseMode == .walk ? "Stop walking (Esc)" : "Walk inside") { toggleWalk() }
                floating(showRoof ? "house.fill" : "house", showRoof ? "Hide the roof" : "Show the roof") {
                    showRoof.toggle()
                }
                // Zoom for the orbiting view; the scroll wheel and a trackpad pinch zoom too.
                floating("minus.magnifyingglass", "Zoom out (Command-minus)") {
                    houseZoom = HouseZoom.pressed(houseZoom, by: -1)
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(houseMode == .walk)
                floating("plus.magnifyingglass", "Zoom in (Command-=)") {
                    houseZoom = HouseZoom.pressed(houseZoom, by: 1)
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(houseMode == .walk)
            }
            .padding(4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One control floating over the 3D view.
    private func floating(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
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
