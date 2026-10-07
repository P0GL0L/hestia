@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

private func mm(_ x: Int64, _ y: Int64) -> Point2 { Point2(x: .millimeters(x), y: .millimeters(y)) }

/// How far the nearer edge of a dimension's text (its baseline or its cap line) sits from the dimension line,
/// measured toward the offset side; negative means the text is on the wrong side or the line strikes it.
private func clearance(from: Point2, to: Point2, offset: Length) -> Double {
    let height = Length.millimeters(2)
    let place = SheetPDF.labelPlacement(from: from, to: to, offset: offset, height: height)
    let (x0, y0) = (Double(from.x.ticks), Double(from.y.ticks))
    let (x1, y1) = (Double(to.x.ticks), Double(to.y.ticks))
    let length: Double = hypot(x1 - x0, y1 - y0)
    let ux: Double = (x1 - x0) / length, uy: Double = (y1 - y0) / length
    let off = Double(offset.ticks)
    let sign: Double = off >= 0 ? 1 : -1
    let ax: Double = -uy * sign, ay: Double = ux * sign
    // A point on the dimension line, and the text's up direction.
    let lx: Double = (x0 + x1) / 2 - uy * off, ly: Double = (y0 + y1) / 2 + ux * off
    let radians: Double = Double(place.rotation.microDegrees) / 1_000_000 * .pi / 180
    let upX: Double = -sin(radians), upY: Double = cos(radians)
    let bx = Double(place.position.x.ticks), by = Double(place.position.y.ticks)
    let h = Double(height.ticks)
    let baseline: Double = (bx - lx) * ax + (by - ly) * ay
    let capLine: Double = (bx + upX * h - lx) * ax + (by + upY * h - ly) * ay
    return min(baseline, capLine)
}

private let oneMillimeter = Double(Length.ticksPerMillimeter)

@Test func negativeOffsetLabelClearsItsLine() {
    // A south chain: left to right, drawn below.
    let south = clearance(from: mm(0, 0), to: mm(100, 0), offset: .millimeters(-10))
    #expect(south >= oneMillimeter)
    // Its text now sits entirely below: baseline 1.5 mm plus the 2 mm text height under the line.
    let place = SheetPDF.labelPlacement(from: mm(0, 0), to: mm(100, 0), offset: .millimeters(-10),
                                        height: .millimeters(2))
    #expect(place.position == mm(50, 0).offset(y: -Length.millimeters(10).ticks - mmTicks(3) - mmTicks(1) / 2))
}

@Test func positiveOffsetAndInteriorLabelsStayClear() {
    // A west chain: bottom to top, drawn to the left; its text was already clear and does not move.
    let west = clearance(from: mm(0, 0), to: mm(0, 100), offset: .millimeters(10))
    #expect(west >= oneMillimeter)
    let place = SheetPDF.labelPlacement(from: mm(0, 0), to: mm(0, 100), offset: .millimeters(10),
                                        height: .millimeters(2))
    #expect(place.position == mm(0, 50).offset(x: -Length.millimeters(10).ticks - mmTicks(1) - mmTicks(1) / 2))
    // Interior strings at zero offset, both ways.
    #expect(clearance(from: mm(0, 0), to: mm(100, 0), offset: .millimeters(0)) >= oneMillimeter)
    #expect(clearance(from: mm(0, 0), to: mm(0, 100), offset: .millimeters(0)) >= oneMillimeter)
    // A chain drawn right to left reads flipped, so its text also moves out by its height.
    #expect(clearance(from: mm(100, 0), to: mm(0, 0), offset: .millimeters(10)) >= oneMillimeter)
    #expect(clearance(from: mm(0, 100), to: mm(0, 0), offset: .millimeters(-10)) >= oneMillimeter)
}

@Test func everyPlanDimensionClearsItsLine() throws {
    for name in ["rect-cottage", "l-house"] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("fixtures/\(name).json")
        let document = try ModelDocument.decode(from: Data(contentsOf: url))
        let sheets = try SchematicDrawingSet().sheets(for: document, geometry: HestiaGeometryEngine())
        var negative = 0, positive = 0
        for sheet in sheets {
            for item in sheet.content.items {
                guard case let .dimension(from, to, offset, _) = item.primitive else { continue }
                if offset.ticks < 0 { negative += 1 } else { positive += 1 }
                #expect(clearance(from: from, to: to, offset: offset) >= oneMillimeter, "\(name) \(sheet.number)")
            }
        }
        #expect(negative > 0, "\(name) has a south chain")
        #expect(positive > 0, "\(name) has west chains and interior strings")
    }
}

private extension Point2 {
    func offset(x: Int64 = 0, y: Int64 = 0) -> Point2 {
        Point2(x: Length(ticks: self.x.ticks + x), y: Length(ticks: self.y.ticks + y))
    }
}
