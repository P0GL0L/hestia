@testable import ATDrawings
import ATContracts
import Foundation
import Testing

private func cottage() throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/rect-cottage.json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

@Test func electricalPlanPlacesSymbolsOnTheirLayersWithALegend() throws {
    var document = try cottage()
    let storey = document.storeys[0].id
    let kinds: [MEPSymbolKind] = [.duplexOutlet, .duplexOutlet, .switchSingle, .ceilingLight, .toilet]
    for (index, kind) in kinds.enumerated() {
        _ = try document.perform(AddMEPSymbolCommand(
            symbolID: MEPSymbolID(UUID()), storeyID: storey, kind: kind,
            position: Point2(x: .feet(Int64(2 + index * 3)), y: .feet(2))).erased)
    }
    document.sheets = [Sheet(id: SheetID(UUID()), number: "E-101", title: "Electrical Plan", paper: .archD,
                             scale: .quarterInch, views: [.electricalPlan(storeyID: storey)])]
    let sheet = try SchematicDrawingSet().sheets(for: document, geometry: MockGeometryEngine())[0]
    let symbols = sheet.content.items.filter { if case .symbol = $0.primitive { return true }; return false }
    #expect(symbols.count == 5)
    #expect(symbols.map(\.style.layer) == ["E-POWR", "E-POWR", "E-LITE", "E-LITE", "P-FIXT"])
    let text = sheet.content.items.compactMap { item -> String? in
        if case let .text(_, s, _, _, _) = item.primitive { return s }; return nil
    }
    #expect(text.contains("LEGEND"))
    #expect(text.contains("Duplex outlet"))
    #expect(text.contains("2"))
}

@Test func storeyWithoutSymbolsKeepsTheNote() throws {
    var document = try cottage()
    #expect(document.mepSymbols.isEmpty)
    document.sheets = [Sheet(id: SheetID(UUID()), number: "E-101", title: "Electrical Plan", paper: .archD,
                             scale: .quarterInch, views: [.electricalPlan(storeyID: document.storeys[0].id)])]
    let sheet = try SchematicDrawingSet().sheets(for: document, geometry: MockGeometryEngine())[0]
    let text = sheet.content.items.compactMap { item -> String? in
        if case let .text(_, s, _, _, _) = item.primitive { return s }; return nil
    }
    #expect(text.contains("Electrical plan: not generated in this version"))
    #expect(text.contains("NOT FOR CONSTRUCTION"))
    #expect(!sheet.content.items.contains { if case .symbol = $0.primitive { return true }; return false })
}
