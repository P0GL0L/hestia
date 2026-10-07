import ATContracts
import ATGeometry
import Foundation

public enum SchematicWallOutlineDXF {
    public static let schematicStamp = "SCHEMATIC / NOT FOR CONSTRUCTION"
    public static let wallLayer = "A-WALL"
    public static let annotationTextLayer = "A-ANNO-TEXT"

    /// ASCII DXF R2013 (AC1027) schematic export of straight wall outlines.
    public static func export(
        walls: [Wall],
        units: DXFDrawingUnits = .inches
    ) throws -> String {
        let outlines = try StraightWallOutlines().outlines(for: walls)
        return try export(outlines: outlines, walls: walls, units: units)
    }

    public static func export(
        outlines: [WallID: ClosedPolygon2],
        walls: [Wall],
        units: DXFDrawingUnits
    ) throws -> String {
        var writer = DXFDocumentWriter(units: units)
        try writer.writeHeader()
        try writer.writeLayerTable(layers: [Self.wallLayer, Self.annotationTextLayer])
        try writer.beginEntities()

        for wall in walls {
            guard let polygon = outlines[wall.id] else { continue }
            let coords = polygon.vertices.map { vertex in
                (
                    x: units.coordinate(from: vertex.x),
                    y: units.coordinate(from: vertex.y)
                )
            }
            try writer.writeClosedPolyline(layer: Self.wallLayer, vertices: coords)
        }

        let bounds = boundingBox(of: outlines, units: units)
        let stampHeight = units.coordinate(from: Length.feet(1)) / 4
        let stampX = bounds.minX
        let stampY = bounds.minY - stampHeight * 2
        try writer.writeText(
            layer: Self.annotationTextLayer,
            x: stampX,
            y: stampY,
            height: stampHeight,
            value: Self.schematicStamp
        )

        try writer.endEntities()
        return writer.asciiDXF
    }

    private static func boundingBox(
        of outlines: [WallID: ClosedPolygon2],
        units: DXFDrawingUnits
    ) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for polygon in outlines.values {
            for vertex in polygon.vertices {
                let x = units.coordinate(from: vertex.x)
                let y = units.coordinate(from: vertex.y)
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        if minX == Double.greatestFiniteMagnitude {
            return (0, 0, 0, 0)
        }
        return (minX, minY, maxX, maxY)
    }
}

/// Writes an ASCII DXF R2013 document section by section. Shared by the wall-outline and display-list exports.
struct DXFDocumentWriter {
    var units: DXFDrawingUnits
    private(set) var asciiDXF = ""
    private var handleCounter: UInt64 = 0x10

    init(units: DXFDrawingUnits) {
        self.units = units
    }

    mutating func writeHeader() throws {
        appendSection("HEADER")
        appendVariable("ACADVER", string: "AC1027")
        appendVariable("INSUNITS", integer: units.insunitsCode)
        appendEndSec()
    }

    mutating func writeLayerTable(layers: [String]) throws {
        appendSection("TABLES")
        appendLine(code: 0, value: "TABLE")
        appendLine(code: 2, value: "LAYER")
        appendLine(code: 5, value: nextHandle())
        appendLine(code: 100, value: "AcDbSymbolTable")
        appendLine(code: 70, value: "\(layers.count)")
        for name in layers {
            appendLine(code: 0, value: "LAYER")
            appendLine(code: 5, value: nextHandle())
            appendLine(code: 100, value: "AcDbSymbolTableRecord")
            appendLine(code: 100, value: "AcDbLayerTableRecord")
            appendLine(code: 2, value: name)
            appendLine(code: 70, value: "0")
            appendLine(code: 62, value: "7")
            appendLine(code: 6, value: "Continuous")
        }
        appendLine(code: 0, value: "ENDTAB")
        appendEndSec()
    }

    mutating func beginEntities() throws {
        appendSection("ENTITIES")
    }

    mutating func endEntities() throws {
        appendEndSec()
        appendLine(code: 0, value: "EOF")
    }

    mutating func writeClosedPolyline(
        layer: String,
        vertices: [(x: Double, y: Double)]
    ) throws {
        guard vertices.count >= 3 else { return }
        appendLine(code: 0, value: "LWPOLYLINE")
        appendLine(code: 5, value: nextHandle())
        appendLine(code: 100, value: "AcDbEntity")
        appendLine(code: 8, value: layer)
        appendLine(code: 100, value: "AcDbPolyline")
        appendLine(code: 90, value: "\(vertices.count)")
        appendLine(code: 70, value: "1")
        for vertex in vertices {
            appendLine(code: 10, value: format(vertex.x))
            appendLine(code: 20, value: format(vertex.y))
        }
    }

    mutating func writeLine(layer: String, from a: (x: Double, y: Double), to b: (x: Double, y: Double),
                            lineweight: Int) {
        appendLine(code: 0, value: "LINE")
        appendLine(code: 5, value: nextHandle())
        appendLine(code: 100, value: "AcDbEntity")
        appendLine(code: 8, value: layer)
        appendLine(code: 370, value: "\(lineweight)")
        appendLine(code: 100, value: "AcDbLine")
        appendLine(code: 10, value: format(a.x))
        appendLine(code: 20, value: format(a.y))
        appendLine(code: 30, value: "0")
        appendLine(code: 11, value: format(b.x))
        appendLine(code: 21, value: format(b.y))
        appendLine(code: 31, value: "0")
    }

    mutating func writePolyline(layer: String, vertices: [(x: Double, y: Double)], closed: Bool, lineweight: Int) {
        guard vertices.count >= 2 else { return }
        appendLine(code: 0, value: "LWPOLYLINE")
        appendLine(code: 5, value: nextHandle())
        appendLine(code: 100, value: "AcDbEntity")
        appendLine(code: 8, value: layer)
        appendLine(code: 370, value: "\(lineweight)")
        appendLine(code: 100, value: "AcDbPolyline")
        appendLine(code: 90, value: "\(vertices.count)")
        appendLine(code: 70, value: closed ? "1" : "0")
        for vertex in vertices {
            appendLine(code: 10, value: format(vertex.x))
            appendLine(code: 20, value: format(vertex.y))
        }
    }

    /// An arc running counterclockwise from `startDegrees` to `endDegrees`, as DXF requires.
    mutating func writeArc(layer: String, center: (x: Double, y: Double), radius: Double, startDegrees: Double,
                           endDegrees: Double, lineweight: Int) {
        appendLine(code: 0, value: "ARC")
        appendLine(code: 5, value: nextHandle())
        appendLine(code: 100, value: "AcDbEntity")
        appendLine(code: 8, value: layer)
        appendLine(code: 370, value: "\(lineweight)")
        appendLine(code: 100, value: "AcDbCircle")
        appendLine(code: 10, value: format(center.x))
        appendLine(code: 20, value: format(center.y))
        appendLine(code: 30, value: "0")
        appendLine(code: 40, value: format(radius))
        appendLine(code: 100, value: "AcDbArc")
        appendLine(code: 50, value: format(startDegrees))
        appendLine(code: 51, value: format(endDegrees))
    }

    /// Text set at its insertion point, rotated, and justified left (0), center (1), or right (2).
    mutating func writeText(layer: String, at point: (x: Double, y: Double), height: Double, rotationDegrees: Double,
                            justification: Int, value: String) {
        appendLine(code: 0, value: "TEXT")
        appendLine(code: 5, value: nextHandle())
        appendLine(code: 100, value: "AcDbEntity")
        appendLine(code: 8, value: layer)
        appendLine(code: 100, value: "AcDbText")
        appendLine(code: 10, value: format(point.x))
        appendLine(code: 20, value: format(point.y))
        appendLine(code: 30, value: "0")
        appendLine(code: 40, value: format(height))
        appendLine(code: 1, value: value)
        appendLine(code: 50, value: format(rotationDegrees))
        if justification != 0 {
            appendLine(code: 72, value: "\(justification)")
            appendLine(code: 11, value: format(point.x))
            appendLine(code: 21, value: format(point.y))
            appendLine(code: 31, value: "0")
        }
        appendLine(code: 100, value: "AcDbText")
    }

    mutating func writeText(
        layer: String,
        x: Double,
        y: Double,
        height: Double,
        value: String
    ) throws {
        appendLine(code: 0, value: "TEXT")
        appendLine(code: 5, value: nextHandle())
        appendLine(code: 100, value: "AcDbEntity")
        appendLine(code: 8, value: layer)
        appendLine(code: 100, value: "AcDbText")
        appendLine(code: 10, value: format(x))
        appendLine(code: 20, value: format(y))
        appendLine(code: 40, value: format(height))
        appendLine(code: 1, value: value)
    }

    private mutating func appendSection(_ name: String) {
        appendLine(code: 0, value: "SECTION")
        appendLine(code: 2, value: name)
    }

    private mutating func appendEndSec() {
        appendLine(code: 0, value: "ENDSEC")
    }

    private mutating func appendVariable(_ name: String, string: String) {
        appendLine(code: 9, value: "$\(name)")
        appendLine(code: 1, value: string)
    }

    private mutating func appendVariable(_ name: String, integer: Int) {
        appendLine(code: 9, value: "$\(name)")
        appendLine(code: 70, value: "\(integer)")
    }

    private mutating func appendLine(code: Int, value: String) {
        asciiDXF += "\(code)\n\(value)\n"
    }

    private mutating func nextHandle() -> String {
        handleCounter += 1
        return String(format: "%X", handleCounter)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.12g", value)
    }
}
