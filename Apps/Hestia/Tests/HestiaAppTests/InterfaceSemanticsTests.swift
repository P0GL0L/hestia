import Testing
@testable import HestiaApp

@Suite("Interface semantics")
struct InterfaceSemanticsTests {
    @Test("Layout choices keep their architecture names")
    func layoutNames() {
        #expect(ContentView.Layout.allCases.map(\.toolbarLabel) == ["Plan", "Plan + 3D", "3D"])
    }

    @Test("Output toolbar controls name their actions")
    func outputNames() {
        #expect(ContentView.renderPhotoLabel == "Render Photo")
        #expect(ContentView.exportLabel == "Export")
    }

    @Test("Roof action names the model mutation")
    func roofActionNames() {
        #expect(ToolPalette.roofActionTitle(hasRoof: false) == "Add Roof")
        #expect(ToolPalette.roofActionTitle(hasRoof: true) == "Remove Roof")
        #expect(ToolPalette.roofDisplayTitle(hasRoof: false) == "Add\nRoof")
        #expect(ToolPalette.roofDisplayTitle(hasRoof: true) == "Remove\nRoof")
    }

    @Test("Minimum window preserves the architecture toolbar")
    func minimumWindowWidth() {
        #expect(ContentView.minimumWindowWidth >= 1280)
    }

    @Test("Walking takes priority in the inspector")
    func walkingInspectorContext() {
        let walking = ContentView.inspectorContext(mode: .walk, tool: .wall)
        #expect(walking.title == "Walking")
        #expect(walking.symbol == "figure.walk")
        #expect(walking.hint.contains("Stop Walking"))

        let editing = ContentView.inspectorContext(mode: .orbit, tool: .wall)
        #expect(editing.title == "Wall")
        #expect(editing.symbol == ContentView.Tool.wall.symbol)
        #expect(editing.hint == ContentView.Tool.wall.hint)
    }

    @Test("Walking deactivates the drawing palette")
    func walkingPaletteState() {
        #expect(ToolPalette.isToolChosen(selected: .wall, candidate: .wall, toolsEnabled: true))
        #expect(!ToolPalette.isToolChosen(selected: .wall, candidate: .wall, toolsEnabled: false))
        #expect(ToolPalette.isToolChosen(selected: .roomFromWalls, candidate: .room, toolsEnabled: true))
    }
}
