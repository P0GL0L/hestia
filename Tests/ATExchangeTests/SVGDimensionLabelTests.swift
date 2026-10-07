import ATContracts
import ATExchange
import Foundation
import Testing

private let fullSize = DrawingScale(label: "1:1", modelUnitsPerPaperUnit: 1)
private let dims = DisplayStyle(layer: "A-ANNO-DIMS", pen: .thin)

private func mm(_ x: Int64, _ y: Int64) -> Point2 { Point2(x: .millimeters(x), y: .millimeters(y)) }

/// The one dimension's label: its text, and its baseline in paper millimetres with y up.
private func label(from: Point2, to: Point2, offset: Int64) -> (text: String, x: Double, y: Double)? {
    let item = DisplayItem(.dimension(from: from, to: to, offset: .millimeters(offset), override: nil), style: dims)
    let svg: String = SVGWriter(scale: fullSize).document(DisplayList(items: [item]))
    guard let open = svg.range(of: "<text "), let close = svg.range(of: "</text>", range: open.upperBound..<svg.endIndex),
          let end = svg.range(of: ">", range: open.upperBound..<close.lowerBound) else { return nil }
    let tag = String(svg[open.upperBound..<end.lowerBound])
    let text = String(svg[end.upperBound..<close.lowerBound])
    func attribute(_ name: String) -> Double? {
        guard let start = tag.range(of: name + "=\"") else { return nil }
        let rest = tag[start.upperBound...]
        return rest.firstIndex(of: "\"").flatMap { Double(rest[..<$0]) }
    }
    guard let x = attribute("x"), let y = attribute("y") else { return nil }
    // SVG stores y down.
    return (text, x, -y)
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

@Test func aSouthChainLabelClearsItsLine() throws {
    // Drawn 10 mm below the measured points; the text is 2 mm tall and reads left to right, so its up points
    // back at the line and the baseline sits a gap and a text height beyond it.
    let south = try #require(label(from: mm(0, 0), to: mm(1000, 0), offset: -10))
    #expect(near(south.y, -13.5))
    let top: Double = south.y + 2
    #expect(top < -10)
    #expect(near(south.x, 500))
}

@Test func aNorthChainLabelKeepsItsPlace() throws {
    let north = try #require(label(from: mm(0, 0), to: mm(1000, 0), offset: 10))
    #expect(near(north.y, 11.5))
}

@Test func aWestChainLabelKeepsItsPlace() throws {
    // Read bottom to top, so the text's up points west, away from the line drawn 10 mm west.
    let west = try #require(label(from: mm(0, 0), to: mm(0, 1000), offset: 10))
    #expect(near(west.x, -11.5))
    let reversed = try #require(label(from: mm(0, 1000), to: mm(0, 0), offset: -10))
    #expect(near(reversed.x, -11.5))
}

@Test func anEastChainLabelClearsItsLine() throws {
    let east = try #require(label(from: mm(0, 0), to: mm(0, 1000), offset: -10))
    #expect(near(east.x, 13.5))
}

@Test func movingTheLabelKeepsTheMeasuredValue() throws {
    let south = try #require(label(from: mm(0, 0), to: mm(1000, 0), offset: -10))
    let north = try #require(label(from: mm(0, 0), to: mm(1000, 0), offset: 10))
    #expect(south.text == "1000 mm")
    #expect(north.text == "1000 mm")
}
