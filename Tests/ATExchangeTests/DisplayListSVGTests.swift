import ATContracts
import ATExchange
import Foundation
import Testing

private let oneToOne = DrawingScale(label: "1:1", modelUnitsPerPaperUnit: 1)

@Test func svgLineMatchesPaperLengthWithinATenthOfAMillimeter() {
    let style = DisplayStyle(layer: "A-WALL", pen: .wide, pattern: .solid)
    let fullScale = lineList(length: .millimeters(100), style: style)
    let fullSVG = SVGWriter(scale: oneToOne).document(fullScale)
    let fullLength = firstLineLengthMillimeters(fullSVG)
    let fullExpected = paperMillimeters(.millimeters(100), scale: oneToOne)

    #expect(fullLength != nil)
    if let fullLength {
        #expect(abs(fullExpected - 100) <= 0.1)
        #expect(abs(fullLength - fullExpected) <= 0.1)
    }
    #expect(fullSVG.contains("<g id=\"A-WALL\">"))
    #expect(fullSVG.components(separatedBy: "<g id=\"A-WALL\">").count == 2)
    // PenWeight.wide is 500 micrometers, which is 0.5 mm on paper.
    #expect(firstTag("line", in: fullSVG)?.contains("stroke-width=\"0.5\"") == true)
    #expect(firstTag("line", in: fullSVG)?.contains("stroke-dasharray") == false)
    #expect(!fullSVG.contains("SCHEMATIC"))

    let scaledSVG = SVGWriter(scale: .oneTo50).document(lineList(length: .millimeters(100), style: style))
    let scaledLength = firstLineLengthMillimeters(scaledSVG)
    let scaledExpected = paperMillimeters(.millimeters(100), scale: .oneTo50)
    #expect(scaledLength != nil)
    if let scaledLength {
        #expect(abs(scaledExpected - 2) <= 0.1)
        #expect(abs(scaledLength - scaledExpected) <= 0.1)
    }
}

@Test func svgDashedHiddenAndCenterUseDashArrays() {
    let length = Length.millimeters(200)
    let dashed = DisplayStyle(layer: "A-WALL", pen: .thin, pattern: .dashed)
    let items = [
        DisplayItem(line(length), style: dashed),
        DisplayItem(line(length), style: dashed),
        DisplayItem(line(length), style: DisplayStyle(layer: "A-GLAZ", pen: .thin, pattern: .hidden)),
        DisplayItem(line(length), style: DisplayStyle(layer: "A-ANNO-DIMS", pen: .thin, pattern: .center)),
    ]
    let svg = SVGWriter(scale: oneToOne).document(DisplayList(items: items))
    let wall = group("A-WALL", in: svg)

    #expect(tags("line", in: wall ?? "").count == 2)
    #expect(wall?.contains("stroke-dasharray=\"3 1.5\"") == true)
    #expect(group("A-GLAZ", in: svg)?.contains("stroke-dasharray=\"1.5 0.75\"") == true)
    #expect(group("A-ANNO-DIMS", in: svg)?.contains("stroke-dasharray=\"6 1 1 1\"") == true)
    #expect(svg.contains("<g id=\"A-WALL\">"))
    #expect(svg.contains("<g id=\"A-GLAZ\">"))
    #expect(svg.contains("<g id=\"A-ANNO-DIMS\">"))

    let measured = firstLineLengthMillimeters(svg)
    let expected = paperMillimeters(length, scale: oneToOne)
    #expect(measured != nil)
    if let measured {
        #expect(abs(measured - expected) <= 0.1)
    }
}

@Test func svgTextEscapesMarkupAndKeepsPaperHeight() {
    let scale = DrawingScale.oneTo50
    let text = DisplayItem(
        .text(
            position: Point2(x: .millimeters(5_000), y: .millimeters(0)),
            string: "Room & <hall>",
            height: .millimeters(4),
            rotation: .degrees(0),
            alignment: .left
        ),
        style: DisplayStyle(layer: "A-ANNO-TEXT", pen: .thin, pattern: .solid)
    )
    let symbol = DisplayItem(
        .symbol(name: "outlet", position: .init(x: .millimeters(0), y: .millimeters(0)), rotation: .degrees(0), size: .millimeters(10)),
        style: DisplayStyle(layer: "E-LITE", pen: .thin, pattern: .solid)
    )
    let svg = SVGWriter(scale: scale).document(DisplayList(items: [text, symbol]))
    let textTag = firstTag("text", in: svg)

    #expect(svg.contains("Room &amp; &lt;hall&gt;"))
    #expect(!svg.contains("Room & <hall>"))
    #expect(!svg.contains("<hall>"))
    // 5000 mm model at 1:50 is 100 mm on paper. The 4 mm height and 10 mm symbol stay paper size.
    #expect(textTag?.contains("x=\"100\"") == true)
    #expect(textTag?.contains("font-size=\"4\"") == true)
    #expect(firstTag("circle", in: svg)?.contains("r=\"5\"") == true)
    #expect(svg.contains("<g id=\"A-ANNO-TEXT\">"))
    #expect(svg.contains("<g id=\"E-LITE\">"))
    #expect(!svg.contains("SCHEMATIC"))
}

@Test func svgEmptyListWritesNoStamp() {
    let svg = SVGWriter(scale: oneToOne).document(DisplayList())

    #expect(svg.contains("<svg"))
    #expect(svg.contains("xmlns=\"http://www.w3.org/2000/svg\""))
    #expect(!svg.contains("<g"))
    #expect(!svg.contains("<text"))
    #expect(!svg.contains("<line"))
    #expect(!svg.contains("SCHEMATIC"))

    let stamped = DisplayItem(
        .text(
            position: Point2(x: .millimeters(0), y: .millimeters(0)),
            string: "SCHEMATIC / NOT FOR CONSTRUCTION",
            height: .millimeters(3),
            rotation: .degrees(0),
            alignment: .left
        ),
        style: DisplayStyle(layer: "A-ANNO-TEXT")
    )
    let withStamp = SVGWriter(scale: oneToOne).document(DisplayList(items: [stamped]))
    #expect(withStamp.contains("SCHEMATIC / NOT FOR CONSTRUCTION"))
}

private func lineList(length: Length, style: DisplayStyle) -> DisplayList {
    DisplayList(items: [DisplayItem(line(length), style: style)])
}

private func line(_ length: Length) -> DisplayPrimitive {
    .line(
        start: Point2(x: .millimeters(0), y: .millimeters(0)),
        end: Point2(x: length, y: .millimeters(0))
    )
}

private func paperMillimeters(_ length: Length, scale: DrawingScale) -> Double {
    Double(scale.paper(length).ticks) / Double(Length.ticksPerMillimeter)
}

private func firstLineLengthMillimeters(_ svg: String) -> Double? {
    guard let tag = firstTag("line", in: svg) else { return nil }
    func value(_ name: String) -> Double? {
        guard let key = tag.range(of: "\(name)=\"") else { return nil }
        let rest = tag[key.upperBound...]
        guard let quote = rest.firstIndex(of: "\"") else { return nil }
        return Double(rest[..<quote])
    }
    guard let x1 = value("x1"), let y1 = value("y1"), let x2 = value("x2"), let y2 = value("y2") else {
        return nil
    }
    let dx = x2 - x1
    let dy = y2 - y1
    return (dx * dx + dy * dy).squareRoot()
}

private func group(_ id: String, in svg: String) -> String? {
    guard let start = svg.range(of: "<g id=\"\(id)\">") else { return nil }
    guard let end = svg[start.upperBound...].range(of: "</g>") else { return nil }
    return String(svg[start.upperBound..<end.lowerBound])
}

private func firstTag(_ name: String, in svg: String) -> String? {
    tags(name, in: svg).first
}

private func tags(_ name: String, in svg: String) -> [String] {
    var found: [String] = []
    var rest = svg[...]
    let opener = "<\(name) "
    while let start = rest.range(of: opener) {
        let tail = rest[start.lowerBound...]
        let end = tail.range(of: "/>") ?? tail.range(of: ">")
        guard let end else { break }
        found.append(String(rest[start.lowerBound..<end.upperBound]))
        rest = rest[end.upperBound...]
    }
    return found
}
