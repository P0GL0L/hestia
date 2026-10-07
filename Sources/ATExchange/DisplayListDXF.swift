import ATContracts
import Foundation

/// ASCII DXF R2013 (AC1027) of a display list, at true size in the units passed in.
///
/// Lines, polylines, arcs, and text are written on DXF layers named after their display layers, each with its
/// pen as the entity's lineweight. Hatch has no entity in this writer and is left out, as are dimensions and
/// symbols; no stand-in is drawn for them. The schematic stamp is written below the drawing.
public enum DisplayListDXF {
    public static let stampLayer = SchematicWallOutlineDXF.annotationTextLayer

    public static func export(_ list: DisplayList, units: DXFDrawingUnits) throws -> String {
        var writer = DXFDocumentWriter(units: units)
        try writer.writeHeader()
        var layers: [String] = []
        for item in list.items where entity(item.primitive) && !layers.contains(item.style.layer) {
            layers.append(item.style.layer)
        }
        if !layers.contains(stampLayer) { layers.append(stampLayer) }
        try writer.writeLayerTable(layers: layers)
        try writer.beginEntities()

        func at(_ point: Point2) -> (x: Double, y: Double) {
            (units.coordinate(from: point.x), units.coordinate(from: point.y))
        }
        for item in list.items {
            let layer = item.style.layer
            // DXF lineweight is in hundredths of a millimetre, as Hestia's pens are.
            let weight = item.style.pen.rawValue
            switch item.primitive {
            case let .line(start, end):
                writer.writeLine(layer: layer, from: at(start), to: at(end), lineweight: weight)
            case let .polyline(points, closed):
                writer.writePolyline(layer: layer, vertices: points.map(at), closed: closed, lineweight: weight)
            case let .arc(center, radius, start, sweep):
                let a = degrees(start), b = a + degrees(sweep)
                writer.writeArc(layer: layer, center: at(center), radius: units.coordinate(from: radius),
                                startDegrees: min(a, b), endDegrees: max(a, b), lineweight: weight)
            case let .text(position, string, height, rotation, alignment):
                let justification: Int
                switch alignment {
                case .left: justification = 0
                case .center: justification = 1
                case .right: justification = 2
                }
                writer.writeText(layer: layer, at: at(position), height: units.coordinate(from: height),
                                 rotationDegrees: degrees(rotation), justification: justification, value: string)
            case .hatch, .dimension, .symbol:
                break
            }
        }

        // The stamp under the drawing, a fiftieth of its larger side high and never under 2.5 mm.
        let box = list.bounds ?? (min: Point2(x: .millimeters(0), y: .millimeters(0)), max: Point2(x: .millimeters(0), y: .millimeters(0)))
        let side = max(box.max.x.ticks - box.min.x.ticks, box.max.y.ticks - box.min.y.ticks)
        let height = Length(ticks: max(side / 50, Length.millimeters(5).ticks / 2))
        let corner = at(box.min)
        let size = units.coordinate(from: height)
        writer.writeText(layer: stampLayer, at: (corner.x, corner.y - size * 2), height: size, rotationDegrees: 0,
                         justification: 0, value: OutputHonesty.schematicStamp)
        try writer.endEntities()
        return writer.asciiDXF
    }

    /// Whether a primitive is written as a DXF entity.
    static func entity(_ primitive: DisplayPrimitive) -> Bool {
        switch primitive {
        case .line, .polyline, .arc, .text: return true
        case .hatch, .dimension, .symbol: return false
        }
    }

    static func degrees(_ angle: Angle) -> Double {
        Double(angle.microDegrees) / 1_000_000
    }
}
