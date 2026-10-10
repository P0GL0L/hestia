import ATContracts
import Foundation
import Testing
@testable import HestiaApp

@Suite("OpenUSD export")
struct HouseUSDTests {
    @Test("Strings are escaped so no name can break out of its literal",
          arguments: [
              ("plain", "\"plain\""),
              ("", "\"\""),
              ("say \"hi\"", "\"say \\\"hi\\\"\""),
              ("back\\slash", "\"back\\\\slash\""),
              ("line\nbreak\ttab\rreturn", "\"line\\nbreak\\ttab\\rreturn\""),
              ("bell\u{07}delete\u{7F}nul\u{00}", "\"bell\\x07delete\\x7fnul\\x00\""),
              ("Küche 厨房 🏠", "\"Küche 厨房 🏠\""),
          ])
    func quoted(text: String, literal: String) {
        #expect(HouseUSD.quoted(text) == literal)
    }

    @Test("Prim names are ASCII identifiers whatever the text",
          arguments: ["", "2nd bedroom", "Küche", "a/b\"c\nd", "厨房"])
    func primName(text: String) {
        let name = HouseUSD.name(text)
        #expect(!name.isEmpty)
        #expect(name.unicodeScalars.allSatisfy { $0.isASCII && ($0 == "_" || CharacterSet.alphanumerics.contains($0)) })
        let startsWithDigit = name.first.map(\.isNumber) ?? false
        #expect(!startsWithDigit)
    }

    @Test("A model with hostile room names and catalog IDs exports a stage with every string escaped")
    func hostileExport() throws {
        var session = EditSession(model: try HestiaModel.blank())
        let hostile = "Den\"\n}\ndef Xform \"Evil\" {\t\\\u{01}"
        try session.addRectangleRoom(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(12, 10), named: hostile)
        let storey = try #require(session.model.groundStorey)
        for id in ["hestia.sofa", "unknown \"item\"\nwith\\breaks", ""] {
            let command = AddPlacementCommand(placementID: PlacementID(UUID()), storeyID: storey,
                                              catalogItemID: CatalogItemID(rawValue: id.isEmpty ? " x" : id),
                                              position: PlanOverlay.point(4, 4))
            try session.perform(command.erased)
        }
        let text = HouseUSD.export(document: session.model.document, meshes: session.model.meshes)
        #expect(text.contains("custom string hestia:room = \(HouseUSD.quoted(hostile))"))
        #expect(text.contains("custom string hestia:catalogItem = \(HouseUSD.quoted("unknown \"item\"\nwith\\breaks"))"))
        #expect(!text.contains("def Xform \"Evil\""))
        // Every line that sets a string holds exactly one literal: an opening quote, escaped content, a closing quote.
        for line in text.split(separator: "\n") where line.contains("custom string") {
            let literal = line[line.index(after: line.firstIndex(of: "=")!)...].trimmingCharacters(in: .whitespaces)
            #expect(literal.hasPrefix("\"") && literal.hasSuffix("\""))
            var escaped = false, quotes = 0
            for character in literal {
                if escaped { escaped = false; continue }
                if character == "\\" { escaped = true } else if character == "\"" { quotes += 1 }
            }
            #expect(quotes == 2)
        }
    }
}
