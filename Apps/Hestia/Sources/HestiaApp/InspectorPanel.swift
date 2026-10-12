import ATContracts
import SwiftUI

/// The panel down the right edge: what the chosen tool needs, what is selected, how the 3D view is shown, and a
/// summary of the project, each in its own titled section.
extension ContentView {
    struct InspectorContext: Equatable {
        var title: String
        var symbol: String
        var hint: String
    }

    static func inspectorContext(mode: HouseViewMode, tool: Tool) -> InspectorContext {
        if mode == .walk {
            return InspectorContext(
                title: "Walking",
                symbol: "figure.walk",
                hint: "Use W, A, S, D or the arrow keys to walk. Drag to look; hold Shift to run. " +
                    "Press Esc or Stop Walking to return."
            )
        }
        return InspectorContext(title: tool.title, symbol: tool.symbol, hint: tool.hint)
    }

    func inspector(_ model: HestiaModel) -> some View {
        let context = Self.inspectorContext(mode: houseMode, tool: tool)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(context.title, symbol: context.symbol) {
                    Text(context.hint)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if houseMode == .walk {
                        Button("Stop Walking") { toggleWalk() }
                    } else {
                        toolOptions
                    }
                }
                if let selection, let details = model.properties(of: selection) {
                    section(details.title, symbol: "checkmark.circle") {
                        ForEach(details.rows, id: \.label) { row in
                            // Keyed by its value, so the field shows the new figure after a change or Undo.
                            PropertyRow(property: row) { text in setProperty(row, to: text, on: selection) }
                                .id(row.label + row.value)
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicateSelection() }
                            .help("Copy it beside itself (Command-D)")
                        Text("Type a new figure and press Return. Undo puts it back.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                section("3D View", symbol: "cube") {
                    Toggle("Show the roof", isOn: $showRoof)
                    HStack(spacing: 8) {
                        Text("Zoom")
                        Spacer(minLength: 0)
                        Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                            houseZoom = HouseZoom.pressed(houseZoom, by: -1)
                        }
                        .labelStyle(.iconOnly)
                        .help("Zoom out (Command-minus)")
                        Button("Zoom In", systemImage: "plus.magnifyingglass") {
                            houseZoom = HouseZoom.pressed(houseZoom, by: 1)
                        }
                        .labelStyle(.iconOnly)
                        .help("Zoom in (Command-=)")
                    }
                    .disabled(houseMode == .walk || layout == .plan)
                }
                section("Project", symbol: "building.2") {
                    ForEach(Self.summary(model.document), id: \.label) { row in
                        HStack {
                            Text(row.label)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 8)
                            Text(row.value)
                        }
                        .font(.callout)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 250)
    }

    /// A titled group: an SF Symbol and a name over its content.
    func section<Content: View>(_ title: String, symbol: String,
                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
    }

    /// Changes one figure of the selection from the inspector, as one undoable step.
    func setProperty(_ property: ElementProperty, to text: String, on selection: PlanSelection) {
        guard var current = session, let field = property.field, text != property.value else { return }
        do {
            status = try current.set(field, to: text, on: selection)
            session = current
            forgetRemoved()
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    /// Counts that say what the project holds.
    static func summary(_ document: ModelDocument) -> [(label: String, value: String)] {
        [
            ("Storeys", "\(document.storeys.count)"),
            ("Rooms", "\(document.rooms.count)"),
            ("Walls", "\(document.walls.count)"),
            ("Doors", "\(document.openings.filter(\.kind.isDoor).count)"),
            ("Windows", "\(document.openings.filter(\.kind.isWindow).count)"),
            ("Furniture", "\(document.placements.count)"),
        ]
    }
}

/// One line of the inspector: a name and its value, typed over when it can be changed.
struct PropertyRow: View {
    var property: ElementProperty
    var commit: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(property.label)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            if property.field != nil {
                TextField(property.label, text: $text, onCommit: { commit(text) })
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .onAppear { text = property.value }
            } else {
                Text(property.value)
            }
        }
        .font(.callout)
    }
}
