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

    /// The table with its top-left corner at `origin`, title above.
    static func items(_ table: Table, at origin: Point2) -> [DisplayItem] {
        let x0 = origin.x.ticks, y0 = origin.y.ticks
        let width = table.columns.reduce(0) { $0 + $1.width }
        let rows = table.rows.count + 1
        var items = [DisplayItem(.text(position: paperPoint(x0, y0 + mmTicks(3)), string: table.title.uppercased(),
                                       height: .millimeters(4), rotation: .degrees(0), alignment: .left),
                                 style: headStyle)]
        for row in 0...rows {
            let y = y0 - Int64(row) * rowHeight
            items.append(DisplayItem(.line(start: paperPoint(x0, y), end: paperPoint(x0 + width, y)),
                                     style: row <= 1 ? headStyle : ruleStyle))
        }
        var x = x0
        let bottom = y0 - Int64(rows) * rowHeight
        for column in table.columns {
            items.append(DisplayItem(.line(start: paperPoint(x, y0), end: paperPoint(x, bottom)), style: ruleStyle))
            x += column.width
        }
        items.append(DisplayItem(.line(start: paperPoint(x, y0), end: paperPoint(x, bottom)), style: ruleStyle))
        for (index, cells) in ([table.columns.map(\.name)] + table.rows).enumerated() {
            var cx = x0 + mmTicks(2)
            let y = y0 - Int64(index + 1) * rowHeight + mmTicks(2)
            for (cell, column) in zip(cells, table.columns) {
                items.append(DisplayItem(.text(position: paperPoint(cx, y), string: cell,
                                               height: .millimeters(2), rotation: .degrees(0),
                                               alignment: .left), style: index == 0 ? headStyle : ruleStyle))
                cx += column.width
            }
        }
        return items
    }

    static func height(of table: Table) -> Int64 {
        Int64(table.rows.count + 1) * rowHeight + mmTicks(10)
    }
}
