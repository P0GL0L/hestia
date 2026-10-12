import SwiftUI

/// How each plan tool shows in the palette: a short name, an SF Symbol, and the group it sits in.
extension ContentView.Tool {
    var title: String {
        switch self {
        case .select: return "Select"
        case .wall: return "Wall"
        case .room, .roomFromWalls: return "Room"
        case .door: return "Door"
        case .window: return "Window"
        case .opening: return "Opening"
        case .stair: return "Stair"
        case .furniture: return "Furnish"
        case .site: return "Site"
        case .delete: return "Delete"
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .wall: return "line.diagonal"
        case .room, .roomFromWalls: return "square.dashed"
        case .door: return "door.left.hand.open"
        case .window: return "window.casement"
        case .opening: return "rectangle.portrait"
        case .stair: return "stairs"
        case .furniture: return "sofa"
        case .site: return "tree"
        case .delete: return "trash"
        }
    }

    /// The palette, top to bottom, in groups: pick, build, open up, furnish and landscape, remove.
    static let palette: [[ContentView.Tool]] = [
        [.select],
        [.wall, .room, .stair],
        [.door, .window, .opening],
        [.furniture, .site],
        [.delete],
    ]
}

/// The tools down the left edge of the window, as an architecture app lays them out: an icon over a short name,
/// grouped, the chosen one filled with the accent color. The roof button sits at the foot, since it acts at once.
struct ToolPalette: View {
    var selected: ContentView.Tool
    var hasRoof: Bool
    var toolsEnabled: Bool
    var choose: (ContentView.Tool) -> Void
    var toggleRoof: () -> Void

    static func roofActionTitle(hasRoof: Bool) -> String {
        hasRoof ? "Remove Roof" : "Add Roof"
    }

    static func roofDisplayTitle(hasRoof: Bool) -> String {
        hasRoof ? "Remove\nRoof" : "Add\nRoof"
    }

    static func isToolChosen(selected: ContentView.Tool, candidate: ContentView.Tool,
                             toolsEnabled: Bool) -> Bool {
        toolsEnabled && (selected == candidate || (candidate == .room && selected == .roomFromWalls))
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(ContentView.Tool.palette.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Divider()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                }
                ForEach(group, id: \.self) { tool in
                    PaletteButton(title: tool.title, symbol: tool.symbol, isOn: isChosen(tool),
                                  help: tool.hint) {
                        choose(tool)
                    }
                }
            }
            Spacer(minLength: 8)
            PaletteButton(title: Self.roofActionTitle(hasRoof: hasRoof),
                          displayTitle: Self.roofDisplayTitle(hasRoof: hasRoof),
                          symbol: hasRoof ? "house.fill" : "house",
                          isOn: false,
                          help: hasRoof ? "Remove the roof. Undo puts it back."
                              : "Put a hip roof over the ground-floor walls when they close one rectangle.") {
                toggleRoof()
            }
        }
        .padding(.vertical, 10)
        .frame(width: 72)
        .disabled(!toolsEnabled)
        .opacity(toolsEnabled ? 1 : 0.55)
    }

    private func isChosen(_ tool: ContentView.Tool) -> Bool {
        Self.isToolChosen(selected: selected, candidate: tool, toolsEnabled: toolsEnabled)
    }
}

/// One palette button: an SF Symbol over its name, filled when on.
struct PaletteButton: View {
    var title: String
    var displayTitle: String?
    var symbol: String
    var isOn: Bool
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 24, height: 18)
                Text(displayTitle ?? title)
                    .font(.system(size: 9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 58, height: 48)
            .foregroundColor(isOn ? .white : .primary)
            .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
    }
}
