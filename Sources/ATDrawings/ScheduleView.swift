import ATContracts
import Foundation

/// Door, window, room finish, and area schedules drawn as ruled tables in paper space.
enum ScheduleView {
    static let ruleStyle = DisplayStyle(layer: "A-ANNO-SCHD", pen: .thin)
    static let headStyle = DisplayStyle(layer: "A-ANNO-SCHD", pen: .medium)
    static let rowHeight = mmTicks(7)

    struct Table {
        var title: String
        var columns: [(name: String, width: Int64)]
        var rows: [[String]]
    }

    /// Door marks D1, D2, … and window marks W1, W2, … in model order. Cased openings get no mark.
    static func marks(_ document: ModelDocument) -> [OpeningID: String] {
        var marks: [OpeningID: String] = [:]
        var doors = 0, windows = 0
        for opening in document.openings {
            if opening.kind.isDoor {
                doors += 1
                marks[opening.id] = "D\(doors)"
            } else if opening.kind.isWindow {
                windows += 1
                marks[opening.id] = "W\(windows)"
            }
        }
        return marks
    }

    static func table(_ kind: ScheduleKind, document: ModelDocument, style: LengthFormatStyle,
                      areas: [RoomID: Area]) -> Table? {
        func f(_ length: Length) -> String { LengthFormatting.format(length, style: style) }
        /// An opening's width cell: its width override when it has one, else the measured width.
        func width(_ opening: Opening) -> String {
            document.dimensionOverride(for: opening.id.rawValue, face: .width) ?? f(opening.width)
        }
        let marks = marks(document)
        switch kind {
        case .doors:
            return Table(
                title: "Door Schedule",
                columns: [("MARK", mmTicks(16)), ("TYPE", mmTicks(32)), ("WIDTH", mmTicks(26)),
                          ("HEIGHT", mmTicks(26)), ("SWING", mmTicks(40))],
                rows: document.openings.filter(\.kind.isDoor).map { door in
                    [marks[door.id] ?? "", words(door.kind.rawValue), width(door), f(door.height),
                     door.swing.map { "\($0.hinge == .nearStart ? "Start" : "End") hinge, \($0.opensToward.rawValue)" } ?? "-"]
                })
        case .windows:
            return Table(
                title: "Window Schedule",
                columns: [("MARK", mmTicks(16)), ("TYPE", mmTicks(40)), ("WIDTH", mmTicks(26)),
                          ("HEIGHT", mmTicks(26)), ("SILL", mmTicks(26))],
                rows: document.openings.filter(\.kind.isWindow).map { window in
                    [marks[window.id] ?? "", words(window.kind.rawValue), width(window), f(window.height),
                     f(window.sillHeight)]
                })
        case .areas:
            let imperial = style == .feetInchesFractions
            return Table(
                title: "Area Schedule",
                columns: [("ROOM", mmTicks(50)), ("STOREY", mmTicks(40)), ("AREA", mmTicks(30))],
                rows: document.rooms.map { room in
                    [room.name, document.storeys.first { $0.id == room.storeyID }?.name ?? "-",
                     areas[room.id].map { FloorPlanView.areaLabel($0, imperial: imperial) } ?? "-"]
                })
        case .roomFinishes:
            return Table(
                title: "Room Finish Schedule",
                columns: [("ROOM", mmTicks(36)), ("STOREY", mmTicks(30)), ("FLOOR", mmTicks(50)),
                          ("WALLS", mmTicks(50)), ("CEILING", mmTicks(50))],
                rows: document.rooms.map { room in
                    [room.name, document.storeys.first { $0.id == room.storeyID }?.name ?? "-",
                     room.floorFinish ?? "-", room.wallFinish ?? "-", room.ceilingFinish ?? "-"]
                })
        }
    }

    /// "slidingDoor" → "Sliding door".
    static func words(_ camel: String) -> String {
        var out = ""
        for character in camel {
            if character.isUppercase { out += " " + character.lowercased() } else { out.append(character) }
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    /// The table with its top left at `origin`. Given the `height` it may fill, a table too long for it
    /// continues in further columns to the right, each with the header row again, so no row runs off the sheet.
    /// Given the `width` too, a table wider than it is set smaller to fit, down to 60 % (below that it is
    /// refused with a note); then only the columns that fit are drawn, and a note under the first says how many
    /// rows were left out, rather than running off the sheet's side. A cell too long for its column is cut short
    /// with "...".
    static func items(_ table: Table, at origin: Point2, height: Int64? = nil, width: Int64? = nil) -> [DisplayItem] {
        let fullWidth = table.columns.reduce(0) { $0 + $1.width }
        var k = 1.0
        if let width, fullWidth > width {
            k = Double(width) / Double(fullWidth)
            guard k >= 0.6 else {
                return [DisplayItem(.text(position: paperPoint(origin.x.ticks, origin.y.ticks - mmTicks(4)),
                                          string: table.title.uppercased() + " IS TOO WIDE FOR THIS SHEET",
                                          height: .millimeters(3), rotation: .degrees(0), alignment: .left),
                                    style: headStyle)]
            }
        }
        let row = Int64((Double(rowHeight) * k).rounded(.down))
        let fits = height.map { max(Int(($0 - mmTicks(10)) / row) - 1, 1) } ?? max(table.rows.count, 1)
        guard table.rows.count > fits else { return block(table, at: origin, titled: true, scale: k) }
        let blockWidth = table.columns.reduce(0) { $0 + Int64((Double($1.width) * k).rounded(.down)) }
        let gap = mmTicks(10)
        let columns = width.map { max(Int(($0 + gap) / (blockWidth + gap)), 1) } ?? Int.max
        var items: [DisplayItem] = []
        for (index, start) in stride(from: 0, to: table.rows.count, by: fits).enumerated() {
            guard index < columns else {
                let note = "\(table.rows.count - start) MORE ROWS DO NOT FIT THIS SHEET"
                let y = origin.y.ticks - Int64(fits + 1) * row - mmTicks(5)
                items.append(DisplayItem(.text(position: paperPoint(origin.x.ticks, y), string: note,
                                               height: .millimeters(3), rotation: .degrees(0), alignment: .left),
                                         style: headStyle))
                break
            }
            var part = table
            part.rows = Array(table.rows[start..<min(start + fits, table.rows.count)])
            let at = paperPoint(origin.x.ticks + Int64(index) * (blockWidth + gap), origin.y.ticks)
            items += block(part, at: at, titled: index == 0, scale: k)
        }
        return items
    }

    /// One block of a table: its title when `titled`, the header row, and its rows, all set `scale` times
    /// their full size.
    private static func block(_ table: Table, at origin: Point2, titled: Bool, scale k: Double) -> [DisplayItem] {
        func sized(_ ticks: Int64) -> Int64 { Int64((Double(ticks) * k).rounded(.down)) }
        let x0 = origin.x.ticks, y0 = origin.y.ticks
        let widths = table.columns.map { sized($0.width) }
        let width = widths.reduce(0, +)
        let rows = table.rows.count + 1, row = sized(rowHeight)
        var items = titled ? [DisplayItem(.text(position: paperPoint(x0, y0 + mmTicks(3)),
                                                string: table.title.uppercased(), height: .millimeters(4),
                                                rotation: .degrees(0), alignment: .left), style: headStyle)] : []
        for line in 0...rows {
            let y = y0 - Int64(line) * row
            items.append(DisplayItem(.line(start: paperPoint(x0, y), end: paperPoint(x0 + width, y)),
                                     style: line <= 1 ? headStyle : ruleStyle))
        }
        var x = x0
        let bottom = y0 - Int64(rows) * row
        for columnWidth in widths {
            items.append(DisplayItem(.line(start: paperPoint(x, y0), end: paperPoint(x, bottom)), style: ruleStyle))
            x += columnWidth
        }
        items.append(DisplayItem(.line(start: paperPoint(x, y0), end: paperPoint(x, bottom)), style: ruleStyle))
        let textHeight = Length(ticks: sized(mmTicks(2))), pad = sized(mmTicks(2))
        for (index, cells) in ([table.columns.map(\.name)] + table.rows).enumerated() {
            var cx = x0 + pad
            let y = y0 - Int64(index + 1) * row + pad
            for (cell, columnWidth) in zip(cells, widths) {
                items.append(DisplayItem(.text(position: paperPoint(cx, y),
                                               string: shortened(cell, to: columnWidth - pad * 2, height: textHeight),
                                               height: textHeight, rotation: .degrees(0), alignment: .left),
                                         style: index == 0 ? headStyle : ruleStyle))
                cx += columnWidth
            }
        }
        return items
    }

    /// `cell` as it fits `room` ticks of paper at `height`, cut short with "..." when it does not.
    static func shortened(_ cell: String, to room: Int64, height: Length) -> String {
        let size = Double(height.ticks) / 0.718
        func fits(_ text: String) -> Bool { HelveticaMetrics.width(of: text) * size <= Double(room) }
        guard !fits(cell) else { return cell }
        var kept = cell
        while !kept.isEmpty, !fits(kept + "...") { kept.removeLast() }
        return kept.isEmpty ? "" : kept + "..."
    }

    /// How `items` lays a table out in `height` by `width`: the rows each column of blocks holds, how many
    /// blocks fit side by side, and the scale they are set at. Nil when the table is too wide to set at all.
    static func layout(_ table: Table, height: Int64, width: Int64) -> (perColumn: Int, columns: Int, scale: Double)? {
        let fullWidth = table.columns.reduce(0) { $0 + $1.width }
        let k = fullWidth > width ? Double(width) / Double(fullWidth) : 1.0
        guard k >= 0.6 else { return nil }
        let row = Int64((Double(rowHeight) * k).rounded(.down))
        let perColumn = max(Int((height - mmTicks(10)) / row) - 1, 1)
        let blockWidth = table.columns.reduce(0) { $0 + Int64((Double($1.width) * k).rounded(.down)) }
        let gap = mmTicks(10)
        let columns = max(Int((width + gap) / (blockWidth + gap)), 1)
        return (perColumn, columns, k)
    }

    /// How many of a table's rows `items` draws in `height` by `width` without leaving any out.
    static func capacity(_ table: Table, height: Int64, width: Int64) -> Int {
        guard let layout = layout(table, height: height, width: width) else { return 0 }
        return layout.perColumn * layout.columns
    }

    static func height(of table: Table) -> Int64 {
        Int64(table.rows.count + 1) * rowHeight + mmTicks(10)
    }
}
