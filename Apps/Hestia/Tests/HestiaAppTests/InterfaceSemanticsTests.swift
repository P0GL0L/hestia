import ATContracts
import Foundation
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

    #if canImport(SwiftUI)
    @Test("A selected ANSI B export writes the named full drawing set")
    @MainActor
    func selectedPaperExportDelivery() throws {
        var document = try HestiaModel.blank().document
        let unique = "Export \(UUID().uuidString)"
        document.project.name = unique
        let model = try HestiaModel(document: document, issueDate: "2026-10-12")
        let slug = unique.lowercased().replacingOccurrences(of: " ", with: "-")
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Hestia-exports", isDirectory: true)
        let output = directory.appendingPathComponent("\(slug)-schematic-set-ansi-b.pdf")
        try? FileManager.default.removeItem(at: output)
        defer { try? FileManager.default.removeItem(at: output) }

        var view = ContentView()
        view.exportPDF(model, on: .ansiB)

        let data = try Data(contentsOf: output)
        let text = try #require(String(bytes: data, encoding: .utf8))
        let mediaBoxes = text.components(separatedBy: "/MediaBox [0 0 1224.000 792.000]").count - 1
        #expect(mediaBoxes > 0)
        #expect(!text.contains("/MediaBox [0 0 2592.000 1728.000]"))
    }
    #endif

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
