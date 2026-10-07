import ATContracts
import ATExchange
import Foundation
import Testing

private func mm(_ x: Int64, _ y: Int64) -> Point2 { Point2(x: .millimeters(x), y: .millimeters(y)) }

private let thin = DisplayStyle(layer: "A-WALL", pen: .thin)

/// The DXF as (code, value) pairs.
private func pairs(_ dxf: String) -> [(Int, String)] {
    let lines = dxf.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    return stride(from: 0, to: lines.count - 1, by: 2).compactMap { i in
        Int(lines[i].trimmingCharacters(in: .whitespaces)).map { ($0, lines[i + 1]) }
    }
}

/// Every entity of one type, as its codes and values.
private func entities(_ type: String, in dxf: String) -> [[(Int, String)]] {
    var result: [[(Int, String)]] = []
    var current: [(Int, String)]?
    for pair in pairs(dxf) {
        if pair.0 == 0 {
            if let entity = current { result.append(entity) }
            current = pair.1 == type ? [] : nil
        } else {
            current?.append(pair)
        }
    }
    return result
}

private func value(_ code: Int, _ entity: [(Int, String)]) -> Double? {
    entity.first { $0.0 == code }.flatMap { Double($0.1) }
}

@Test func aHundredMillimetreLineMeasuresAHundredMillimetres() throws {
    let list = DisplayList(items: [DisplayItem(.line(start: mm(0, 0), end: mm(100, 0)), style: thin)])
    let metric = try #require(entities("LINE", in: try DisplayListDXF.export(list, units: .millimeters)).first)
    let x0: Double = try #require(value(10, metric)), x1: Double = try #require(value(11, metric))
    #expect(abs(x1 - x0 - 100) < 1e-9)
    let imperial = try #require(entities("LINE", in: try DisplayListDXF.export(list, units: .inches)).first)
    let i0: Double = try #require(value(10, imperial)), i1: Double = try #require(value(11, imperial))
    #expect(abs((i1 - i0) * 25.4 - 100) < 1e-9)
    // The units are declared in the header too.
    let header = try DisplayListDXF.export(list, units: .millimeters)
    #expect(header.contains("$INSUNITS\n70\n4\n"))
}

@Test func linesPolylinesArcsAndTextAreWritten() throws {
    let list = DisplayList(items: [
        DisplayItem(.polyline(points: [mm(0, 0), mm(50, 0), mm(50, 20)], closed: false), style: thin),
        DisplayItem(.polyline(points: [mm(0, 0), mm(10, 0), mm(10, 10), mm(0, 10)], closed: true),
                    style: DisplayStyle(layer: "A-DOOR", pen: .heavy)),
        // A quarter arc swept clockwise, from 90 degrees back to 0.
        DisplayItem(.arc(center: mm(0, 0), radius: .millimeters(900), start: .degrees(90), sweep: .degrees(-90)),
                    style: DisplayStyle(layer: "A-DOOR", pen: .thin)),
        DisplayItem(.text(position: mm(5, 5), string: "LIVING", height: .millimeters(3), rotation: .degrees(90),
                          alignment: .center), style: DisplayStyle(layer: "A-AREA-IDEN", pen: .fine)),
    ])
    let dxf = try DisplayListDXF.export(list, units: .millimeters)
    let polylines = entities("LWPOLYLINE", in: dxf)
    #expect(polylines.count == 2)
    let flags: [Double] = polylines.compactMap { value(70, $0) }
    #expect(flags == [0, 1])
    // The pen is the lineweight, in hundredths of a millimetre.
    #expect(value(370, polylines[1]) == 70)
    let arc = try #require(entities("ARC", in: dxf).first)
    #expect(value(40, arc) == 900)
    // DXF arcs run counterclockwise, so the clockwise sweep is written from 0 to 90 degrees.
    #expect(value(50, arc) == 0)
    #expect(value(51, arc) == 90)
    let texts = entities("TEXT", in: dxf)
    let living = try #require(texts.first { entity in entity.contains { $0.0 == 1 && $0.1 == "LIVING" } })
    #expect(value(40, living) == 3)
    #expect(value(50, living) == 90)
    #expect(value(72, living) == 1)
    // One layer table entry per display layer, and the stamp's.
    let layerNames: [String] = pairs(dxf).filter { $0.0 == 2 }.map(\.1)
    let expected: [String] = ["A-WALL", "A-DOOR", "A-AREA-IDEN", DisplayListDXF.stampLayer]
    for layer in expected {
        let count: Int = layerNames.filter { $0 == layer }.count
        #expect(count == 1, "\(layer)")
    }
}

@Test func hatchIsLeftOutAndNotReplaced() throws {
    let hatch = DisplayItem(.hatch(boundary: [mm(0, 0), mm(10, 0), mm(10, 10)], pattern: .diagonal,
                                   spacing: .millimeters(1), angle: .degrees(45)),
                            style: DisplayStyle(layer: "A-WALL-PATT", pen: .extraFine))
    let list = DisplayList(items: [hatch, DisplayItem(.line(start: mm(0, 0), end: mm(10, 0)), style: thin)])
    let dxf = try DisplayListDXF.export(list, units: .millimeters)
    #expect(!dxf.contains("HATCH"))
    #expect(!dxf.contains("A-WALL-PATT"))
    // Only the line and the stamp were written: no stand-in outline for the hatch.
    #expect(entities("LWPOLYLINE", in: dxf).isEmpty)
    #expect(entities("LINE", in: dxf).count == 1)
}

@Test func everyExportCarriesTheStamp() throws {
    let list = DisplayList(items: [DisplayItem(.line(start: mm(0, 0), end: mm(4000, 0)), style: thin)])
    let dxf = try DisplayListDXF.export(list, units: .millimeters)
    let stamp = try #require(entities("TEXT", in: dxf).first { entity in
        entity.contains { $0.0 == 1 && $0.1 == OutputHonesty.schematicStamp }
    })
    #expect(stamp.contains { $0.0 == 8 && $0.1 == DisplayListDXF.stampLayer })
    // Below the drawing.
    let y: Double = try #require(value(20, stamp))
    #expect(y < 0)
    // The reader in this module finds it on its layer.
    let parsed = SchematicWallOutlineDXFReader.parse(dxf)
    #expect(parsed.textByLayer[DisplayListDXF.stampLayer]?.contains(OutputHonesty.schematicStamp) == true)
    #expect(parsed.insunits == 4)
}
