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
                if let selection {
                    section("Selected", symbol: "checkmark.circle") {
                        Text(describe(selection, in: model))
                            .font(.callout)
                        Text("Drag it on the plan to move it. The Delete tool removes it.")
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

    /// What is selected, in a few words.
    func describe(_ selection: PlanSelection, in model: HestiaModel) -> String {
        switch selection {
        case let .wall(id):
            guard let wall = model.document.walls.first(where: { $0.id == id }) else { return "A wall" }
            let dx = Double(wall.end.x.ticks - wall.start.x.ticks), dy = Double(wall.end.y.ticks - wall.start.y.ticks)
            let length = Length(ticks: Int64((dx * dx + dy * dy).squareRoot().rounded()))
            let units = model.document.project.displayUnits ?? .feetInchesFractions
            return "Wall, " + LengthFormatting.format(length, style: units)
        case let .placement(id):
            guard let placement = model.document.placements.first(where: { $0.id == id }) else { return "An item" }
            return Furniture.item(placement.catalogItemID)?.name ?? "An item"
        case let .patch(id):
            return model.document.terrainPatches.first { $0.id == id }?.name ?? "A site area"
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
