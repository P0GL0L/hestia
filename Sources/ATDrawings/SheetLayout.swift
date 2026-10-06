import ATContracts
import Foundation

/// Maps model-space plan or elevation points onto a sheet at a drawing scale.
struct ViewTransform: Sendable {
    var scale: DrawingScale
    /// Model point that lands on `paperOrigin`.
    var modelOrigin: Point2
    var paperOrigin: Point2

    func paper(_ point: Point2) -> Point2 {
        Point2(x: Length(ticks: paperOrigin.x.ticks + scale.paper(Length(ticks: point.x.ticks - modelOrigin.x.ticks)).ticks),
               y: Length(ticks: paperOrigin.y.ticks + scale.paper(Length(ticks: point.y.ticks - modelOrigin.y.ticks)).ticks))
    }

    func paper(_ length: Length) -> Length { scale.paper(length) }

    /// Centers a model box of `size` in `area`, and reports whether it fits.
    static func centering(
        modelMin: Point2, modelMax: Point2, in area: PaperRect, scale: DrawingScale
    ) -> (transform: ViewTransform, fits: Bool) {
        let width = scale.paper(Length(ticks: modelMax.x.ticks - modelMin.x.ticks)).ticks
        let height = scale.paper(Length(ticks: modelMax.y.ticks - modelMin.y.ticks)).ticks
        let origin = Point2(x: Length(ticks: area.minX + (area.width - width) / 2),
                            y: Length(ticks: area.minY + (area.height - height) / 2))
        return (ViewTransform(scale: scale, modelOrigin: modelMin, paperOrigin: origin),
                width <= area.width && height <= area.height)
    }
}

/// A paper-space rectangle in ticks.
struct PaperRect: Hashable, Sendable {
    var minX: Int64
    var minY: Int64
    var width: Int64
    var height: Int64

    var maxX: Int64 { minX + width }
    var maxY: Int64 { minY + height }
    var center: Point2 { Point2(x: Length(ticks: minX + width / 2), y: Length(ticks: minY + height / 2)) }

    func corners() -> [Point2] {
        [paperPoint(minX, minY), paperPoint(maxX, minY), paperPoint(maxX, maxY), paperPoint(minX, maxY)]
    }

    /// Splits off `size` ticks from the top; returns (top part, remainder).
    func splitTop(_ size: Int64) -> (PaperRect, PaperRect) {
        (PaperRect(minX: minX, minY: maxY - size, width: width, height: size),
         PaperRect(minX: minX, minY: minY, width: width, height: height - size))
    }
}

func paperPoint(_ x: Int64, _ y: Int64) -> Point2 {
    Point2(x: Length(ticks: x), y: Length(ticks: y))
}

func mmTicks(_ value: Int64) -> Int64 { value * Length.ticksPerMillimeter }

/// Sheet border, title block, and the schematic stamp.
enum SheetFrame {
    static let margin = mmTicks(12)
    static let titleBlockWidth = mmTicks(80)

    /// The area left for views, inside the border and left of the title block.
    static func drawingArea(for paper: PaperSize) -> PaperRect {
        PaperRect(minX: margin + mmTicks(6), minY: margin + mmTicks(6),
                  width: paper.width.ticks - 2 * margin - titleBlockWidth - mmTicks(12),
                  height: paper.height.ticks - 2 * margin - mmTicks(12))
    }

    static func items(
        number: String, title: String, scale: DrawingScale?, paper: PaperSize, projectName: String,
        issueDate: String?
    ) -> [DisplayItem] {
        let border = DisplayStyle(layer: "A-ANNO-TTLB", pen: .heavy)
        let rule = DisplayStyle(layer: "A-ANNO-TTLB", pen: .thin)
        let words = DisplayStyle(layer: "A-ANNO-TTLB", pen: .fine)
        let outer = PaperRect(minX: margin, minY: margin, width: paper.width.ticks - 2 * margin,
                              height: paper.height.ticks - 2 * margin)
        let block = PaperRect(minX: outer.maxX - titleBlockWidth, minY: outer.minY, width: titleBlockWidth,
                              height: outer.height)
        let left = block.minX + mmTicks(4)
        func label(_ text: String, _ y: Int64, _ height: Int64, x: Int64? = nil) -> DisplayItem {
            DisplayItem(.text(position: paperPoint(x ?? left, y), string: text, height: Length(ticks: height),
                              rotation: .degrees(0), alignment: .left), style: words)
        }
        func ruleAt(_ y: Int64) -> DisplayItem {
            DisplayItem(.line(start: paperPoint(block.minX, y), end: paperPoint(block.maxX, y)), style: rule)
        }
        let bottom = block.minY
        var items = [
            DisplayItem(.polyline(points: outer.corners(), closed: true), style: border),
            DisplayItem(.line(start: paperPoint(block.minX, block.minY), end: paperPoint(block.minX, block.maxY)), style: border),
            // Sheet number band.
            label("SHEET", bottom + mmTicks(30), mmTicks(2)),
            label(number, bottom + mmTicks(14), mmTicks(10)),
            ruleAt(bottom + mmTicks(36)),
            label("SCALE", bottom + mmTicks(52), mmTicks(2)),
            label(scale?.label ?? "AS NOTED", bottom + mmTicks(44), mmTicks(3)),
            label("DATE", bottom + mmTicks(52), mmTicks(2), x: left + mmTicks(40)),
            label(issueDate ?? "-", bottom + mmTicks(44), mmTicks(3), x: left + mmTicks(40)),
            ruleAt(bottom + mmTicks(58)),
            label("SHEET TITLE", bottom + mmTicks(76), mmTicks(2)),
            label(title, bottom + mmTicks(66), mmTicks(4)),
            ruleAt(bottom + mmTicks(82)),
            label("PROJECT", bottom + mmTicks(100), mmTicks(2)),
            label(projectName, bottom + mmTicks(90), mmTicks(4)),
            ruleAt(bottom + mmTicks(106)),
            label("REVISIONS", bottom + mmTicks(124), mmTicks(2)),
            label("No.   Date   Description", bottom + mmTicks(116), mmTicks(2)),
            ruleAt(bottom + mmTicks(160)),
            label("Drawn with Hestia", block.maxY - mmTicks(10), mmTicks(2)),
        ]
        // The stamp: boxed, above the revisions, never optional.
        let stampBox = PaperRect(minX: block.minX + mmTicks(3), minY: bottom + mmTicks(164), width: titleBlockWidth - mmTicks(6),
                                 height: mmTicks(16))
        items.append(DisplayItem(.polyline(points: stampBox.corners(), closed: true), style: border))
        items.append(DisplayItem(
            .text(position: paperPoint(stampBox.center.x.ticks, stampBox.minY + mmTicks(9)), string: "SCHEMATIC",
                  height: Length(ticks: mmTicks(4)), rotation: .degrees(0), alignment: .center), style: border))
        items.append(DisplayItem(
            .text(position: paperPoint(stampBox.center.x.ticks, stampBox.minY + mmTicks(3)), string: "NOT FOR CONSTRUCTION",
                  height: Length(ticks: mmTicks(3)), rotation: .degrees(0), alignment: .center), style: border))
        return items
    }

    /// A view title under a view: name, then scale.
    static func viewTitle(_ name: String, scale: DrawingScale?, at position: Point2) -> [DisplayItem] {
        let style = DisplayStyle(layer: "A-ANNO-TEXT", pen: .medium)
        var items = [DisplayItem(.text(position: position, string: name.uppercased(), height: .millimeters(4),
                                       rotation: .degrees(0), alignment: .left), style: style)]
        if let scale {
            items.append(DisplayItem(
                .text(position: Point2(x: position.x, y: Length(ticks: position.y.ticks - mmTicks(6))),
                      string: "SCALE: \(scale.label)", height: .millimeters(2), rotation: .degrees(0),
                      alignment: .left),
                style: DisplayStyle(layer: "A-ANNO-TEXT", pen: .fine)))
        }
        return items
    }

    /// An honest placeholder for views this version does not generate.
    static func notGenerated(_ name: String, in area: PaperRect) -> [DisplayItem] {
        [DisplayItem(.text(position: area.center, string: "\(name): not generated in this version",
                           height: .millimeters(3), rotation: .degrees(0), alignment: .center),
                     style: DisplayStyle(layer: "A-ANNO-TEXT", pen: .thin))]
    }
}
