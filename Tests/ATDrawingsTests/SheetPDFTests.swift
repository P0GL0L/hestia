@testable import ATDrawings
import ATContracts
import Foundation
import Testing

private func mm(_ x: Int64, _ y: Int64) -> Point2 {
    Point2(x: .millimeters(x), y: .millimeters(y))
}

private let everyPrimitive = SheetDrawing(
    number: "A-101", title: "Floor Plan", paper: .archD, scale: .quarterInch,
    content: DisplayList(items: [
        DisplayItem(.line(start: mm(10, 10), end: mm(110, 10)), style: DisplayStyle(layer: "A-WALL", pen: .heavy)),
        DisplayItem(.polyline(points: [mm(20, 20), mm(60, 20), mm(60, 50)], closed: true),
                    style: DisplayStyle(layer: "A-WALL", pattern: .dashed)),
        DisplayItem(.arc(center: mm(100, 100), radius: .millimeters(20), start: .degrees(0), sweep: .degrees(90)),
                    style: DisplayStyle(layer: "A-DOOR", pattern: .hidden)),
        DisplayItem(.text(position: mm(200, 200), string: "Living (14'-0\")", height: .millimeters(3),
                          rotation: .degrees(90), alignment: .center), style: DisplayStyle(layer: "A-ANNO-TEXT")),
        DisplayItem(.hatch(boundary: [mm(300, 300), mm(400, 300), mm(400, 350)], pattern: .crosshatch,
                           spacing: .millimeters(3), angle: .degrees(45)), style: DisplayStyle(layer: "A-WALL")),
        DisplayItem(.hatch(boundary: [mm(300, 400), mm(400, 400), mm(400, 450)], pattern: .solid,
                           spacing: .millimeters(1), angle: .degrees(0)), style: DisplayStyle(layer: "A-WALL")),
        DisplayItem(.dimension(from: mm(10, 500), to: mm(35, 500), offset: .millimeters(8), override: nil),
                    style: DisplayStyle(layer: "A-ANNO-DIMS", pen: .extraFine, pattern: .center)),
        DisplayItem(.symbol(name: "north-arrow", position: mm(800, 500), rotation: .degrees(0), size: .millimeters(12)),
                    style: DisplayStyle(layer: "A-ANNO-SYMB")),
        DisplayItem(.symbol(name: "outlet-duplex", position: mm(820, 500), rotation: .degrees(0), size: .millimeters(4)),
                    style: DisplayStyle(layer: "E-POWR")),
    ])
)

private func numbers(_ string: Substring) -> [Double] {
    string.split(separator: " ").compactMap { Double($0) }
}

@Test func sheetPDFIsWellFormedWithOnePagePerSheet() throws {
    let second = SheetDrawing(number: "A-601", title: "Schedules", paper: .ansiB, scale: nil, content: DisplayList())
    let data = SheetPDF.render([everyPrimitive, second])
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.hasPrefix("%PDF-1.4\n"))
    #expect(text.hasSuffix("%%EOF\n"))
    #expect(text.contains("/Count 2"))
    #expect(text.contains("/MediaBox [0 0 2592.000 1728.000]"))
    #expect(text.contains("/MediaBox [0 0 1224.000 792.000]"))

    // Every xref entry points at its object header.
    let xref = try #require(text.range(of: "xref\n0 "))
    let rows = text[xref.upperBound...].split(separator: "\n").dropFirst(2).prefix(7)
    for (index, row) in rows.enumerated() {
        let offset = try #require(Int(row.prefix(10)))
        let header = "\(index + 1) 0 obj"
        #expect(String(decoding: data[offset..<(offset + header.utf8.count)], as: UTF8.self) == header)
    }
}

@Test func lineLengthsPrintTrueToScale() throws {
    let stream = SheetPDF.contentStream(for: everyPrimitive)
    let line = try #require(stream.split(separator: "\n").first { $0.hasSuffix(" l S") })
    let values = numbers(line)
    let printedMillimeters = (values[2] - values[0]) * 25.4 / 72
    #expect(abs(printedMillimeters - 100) < 0.1)
    #expect(stream.contains("1.984 w"))
}

@Test func dimensionsReadModelLengthAtTheSheetScale() {
    // 25 mm on paper at 1/4" = 1'-0" is 1200 mm of model, 3'-11 1/4" to the nearest 1/16".
    let label = SheetPDF.measuredLabel(paperTicks: Length.millimeters(25).ticks, scale: .quarterInch)
    #expect(label == LengthFormatting.format(.sixtyFourthInches(3024), style: .feetInchesFractions))
    #expect(SheetPDF.measuredLabel(paperTicks: Length.millimeters(25).ticks, scale: .oneTo50)
            == LengthFormatting.format(.millimeters(1250), style: .metric))
    let stream = SheetPDF.contentStream(for: everyPrimitive)
    #expect(stream.contains("(\(SheetPDF.literal(label))) Tj"))
}

@Test func textIsEscapedAndCentered() {
    #expect(SheetPDF.literal("Bath (2) \\ é") == "Bath \\(2\\) \\\\ ?")
    #expect(abs(HelveticaMetrics.width(of: "A") - 0.667) < 1e-9)
    let centered = SheetPDF.text("AA", at: mm(100, 0), height: .millimeters(3), rotation: .degrees(0),
                                 alignment: .center)
    let size = 3 * 72 / 25.4 / 0.718
    let expectedX = 100 * 72 / 25.4 - 0.667 * size
    let values = numbers(centered.split(separator: "Tm")[0][...])
    #expect(abs(values[values.count - 2] - expectedX) < 0.01)
}
