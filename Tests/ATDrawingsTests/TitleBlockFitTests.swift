@testable import ATDrawings
import ATContracts
import Foundation
import Testing

private let room: Int64 = SheetFrame.titleBlockWidth - mmTicks(8)

/// A line's printed width at cap height `cap`, in ticks.
private func width(_ line: String, _ cap: Int64) -> Double {
    HelveticaMetrics.width(of: line) * Double(cap) / 0.718
}

@Test func aShortNameStaysOnOneLineAtFullSize() {
    let fitted = SheetFrame.fit("Rect Cottage", height: mmTicks(4), width: room)
    #expect(fitted.lines == ["Rect Cottage"])
    #expect(fitted.height == mmTicks(4))
}

@Test func aLongNameWrapsToTwoLinesThatFit() {
    let fitted = SheetFrame.fit("Kings Well Primary Suite - as drawn", height: mmTicks(4), width: room)
    #expect(fitted.lines.count == 2)
    #expect(fitted.lines.joined(separator: " ") == "Kings Well Primary Suite - as drawn")
    for line in fitted.lines {
        let printed: Double = width(line, fitted.height)
        #expect(printed <= Double(room), "\(line)")
    }
    #expect(fitted.height <= mmTicks(3))
    #expect(fitted.height >= mmTicks(2))
}

@Test func aNameTooLongEvenSmallIsCutShort() {
    let name = String(repeating: "Wonderful Retirement Home ", count: 6)
    let fitted = SheetFrame.fit(name, height: mmTicks(4), width: room)
    #expect(fitted.height == mmTicks(2))
    #expect(fitted.lines.count == 2)
    #expect(fitted.lines[1].hasSuffix("..."))
    for line in fitted.lines {
        let printed: Double = width(line, fitted.height)
        #expect(printed <= Double(room), "\(line)")
    }
}

@Test func titleBlockTextNeverCrossesTheBlockEdge() {
    let items = SheetFrame.items(number: "SK-1", title: "Primary Suite - Alcove Entry With Pocket Door",
                                 scale: .quarterInch, paper: .archD,
                                 projectName: "Kings Well Primary Suite - alcove entry", issueDate: "2026-10-08")
    let blockRight: Int64 = PaperSize.archD.width.ticks - SheetFrame.margin
    for item in items {
        guard case let .text(position, string, height, _, alignment) = item.primitive, alignment == .left else {
            continue
        }
        let right: Double = Double(position.x.ticks) + width(string, height.ticks)
        #expect(right <= Double(blockRight - mmTicks(4)), "\(string)")
    }
}
