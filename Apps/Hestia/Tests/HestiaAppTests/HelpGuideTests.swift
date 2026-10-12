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
