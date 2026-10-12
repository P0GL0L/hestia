import ATContracts
import Testing
@testable import HestiaApp

@Suite("Help guide")
struct HelpGuideTests {
    @Test("Searching finds the topics that mention every word, and an empty search lists them all")
    func search() {
        #expect(HelpGuide.search("").count == HelpGuide.topics.count)
        let zoom = HelpGuide.search("zoom").map(\.title)
        #expect(zoom.contains("Look around in 3D") && zoom.contains("Move around the plan"))
        #expect(HelpGuide.search("WASD walk").map(\.title) == ["Walk inside"])
        #expect(HelpGuide.search("exact wall").contains { $0.title == "Draw walls" })
        #expect(HelpGuide.search("submarine").isEmpty)
    }

    @Test("Every topic has a unique title and says something")
    func topics() {
        let titles = HelpGuide.topics.map(\.title)
        #expect(Set(titles).count == titles.count)
        #expect(HelpGuide.topics.allSatisfy { !$0.lines.isEmpty })
    }
}

@Suite("Export sheet sizes")
struct ExportSheetSizeTests {
    @Test("The export menu offers every sheet size, labelled with its size in its own units")
    func labels() {
        #expect(HestiaModel.sheetSizes.map(HestiaModel.label) == [
            "ARCH D (36 x 24 in)", "ISO A1 (841 x 594 mm)", "ARCH C (24 x 18 in)", "ISO A3 (420 x 297 mm)",
            "ANSI B (17 x 11 in)",
        ])
    }

    @Test("A set exported on another size puts every sheet on it")
    func exportOnAnotherSize() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addRectangleRoom(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(16, 12), named: "Room")
        let data = try session.model.pdf(on: .ansiB)
        let text = String(data.map { Character(UnicodeScalar($0)) })
        #expect(text.hasPrefix("%PDF"))
        // ANSI B is 17 x 11 in, 1224 x 792 points, on every page.
        let boxes = text.components(separatedBy: "/MediaBox [").dropFirst().map { $0.prefix { $0 != "]" } }
        #expect(!boxes.isEmpty)
        #expect(boxes.allSatisfy { $0 == "0 0 1224.000 792.000" }, "\(boxes)")
    }
}
