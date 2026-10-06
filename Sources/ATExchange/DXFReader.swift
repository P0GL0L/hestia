import ATContracts
import Foundation

/// Minimal ASCII DXF reader for schematic wall outline round-trip checks.
public enum SchematicWallOutlineDXFReader {
    public struct ParsedDrawing: Sendable {
        public var insunits: Int?
        public var layers: [String]
        public var closedPolylinesByLayer: [String: [[(x: Double, y: Double)]]]
        public var textByLayer: [String: [String]]
    }

    public static func parse(_ asciiDXF: String) -> ParsedDrawing {
        let pairs = groupCodePairs(in: asciiDXF)
        var insunits: Int?
        var layers: [String] = []
        var closedPolylinesByLayer: [String: [[(x: Double, y: Double)]]] = [:]
        var textByLayer: [String: [String]] = [:]

        var index = 0
        while index < pairs.count {
            let pair = pairs[index]
            if pair.code == 0, pair.value == "SECTION", index + 1 < pairs.count, pairs[index + 1].code == 2 {
                let sectionName = pairs[index + 1].value
                index += 2
                if sectionName == "HEADER" {
                    insunits = parseHeaderINSUNITS(pairs: pairs, start: &index)
                } else if sectionName == "TABLES" {
                    layers = parseLayers(pairs: pairs, start: &index)
                } else if sectionName == "ENTITIES" {
                    parseEntities(
                        pairs: pairs,
                        start: &index,
                        closedPolylinesByLayer: &closedPolylinesByLayer,
                        textByLayer: &textByLayer
                    )
                } else {
                    skipToEndSec(pairs: pairs, index: &index)
                }
            } else {
                index += 1
            }
        }

        return ParsedDrawing(
            insunits: insunits,
            layers: layers,
            closedPolylinesByLayer: closedPolylinesByLayer,
            textByLayer: textByLayer
        )
    }

    /// Recover axis-aligned rectangular wall centerline corners from exported wall outlines.
    public static func recoveredRectangleEndpoints(
        from drawing: ParsedDrawing,
        units: DXFDrawingUnits,
        halfWallThickness: Length
    ) -> [Point2] {
        let polylines = drawing.closedPolylinesByLayer[SchematicWallOutlineDXF.wallLayer] ?? []
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for polyline in polylines {
            for vertex in polyline {
                minX = min(minX, vertex.x)
                minY = min(minY, vertex.y)
                maxX = max(maxX, vertex.x)
                maxY = max(maxY, vertex.y)
            }
        }
        guard minX != Double.greatestFiniteMagnitude else { return [] }

        let half = units.coordinate(from: halfWallThickness)
        let corners = [
            Point2(x: units.length(from: minX + half), y: units.length(from: minY + half)),
            Point2(x: units.length(from: maxX - half), y: units.length(from: minY + half)),
            Point2(x: units.length(from: maxX - half), y: units.length(from: maxY - half)),
            Point2(x: units.length(from: minX + half), y: units.length(from: maxY - half)),
        ]
        return corners
    }
}

private struct GroupCodePair {
    var code: Int
    var value: String
}

private func groupCodePairs(in asciiDXF: String) -> [GroupCodePair] {
    let lines = asciiDXF.split(whereSeparator: \.isNewline).map(String.init)
    var pairs: [GroupCodePair] = []
    pairs.reserveCapacity(lines.count / 2)
    var index = 0
    while index + 1 < lines.count {
        guard let code = Int(lines[index].trimmingCharacters(in: .whitespaces)) else {
            index += 1
            continue
        }
        let value = lines[index + 1]
        pairs.append(GroupCodePair(code: code, value: value))
        index += 2
    }
    return pairs
}

private func skipToEndSec(pairs: [GroupCodePair], index: inout Int) {
    while index < pairs.count {
        if pairs[index].code == 0, pairs[index].value == "ENDSEC" {
            index += 1
            return
        }
        index += 1
    }
}

private func parseHeaderINSUNITS(pairs: [GroupCodePair], start: inout Int) -> Int? {
    var insunits: Int?
    while start < pairs.count {
        let pair = pairs[start]
        if pair.code == 0, pair.value == "ENDSEC" {
            start += 1
            return insunits
        }
        if pair.code == 9, pair.value == "$INSUNITS", start + 1 < pairs.count, pairs[start + 1].code == 70 {
            insunits = Int(pairs[start + 1].value)
            start += 2
            continue
        }
        start += 1
    }
    return insunits
}

private func parseLayers(pairs: [GroupCodePair], start: inout Int) -> [String] {
    var layers: [String] = []
    while start < pairs.count {
        let pair = pairs[start]
        if pair.code == 0, pair.value == "ENDSEC" {
            start += 1
            return layers
        }
        if pair.code == 0, pair.value == "LAYER", start + 1 < pairs.count {
            start += 1
            while start < pairs.count {
                let layerPair = pairs[start]
                if layerPair.code == 0 { break }
                if layerPair.code == 2 {
                    layers.append(layerPair.value)
                }
                start += 1
            }
            continue
        }
        start += 1
    }
    return layers
}

private func parseEntities(
    pairs: [GroupCodePair],
    start: inout Int,
    closedPolylinesByLayer: inout [String: [[(x: Double, y: Double)]]],
    textByLayer: inout [String: [String]]
) {
    while start < pairs.count {
        let pair = pairs[start]
        if pair.code == 0, pair.value == "ENDSEC" {
            start += 1
            return
        }
        if pair.code == 0, pair.value == "LWPOLYLINE" {
            if let parsed = parseLWPolyline(pairs: pairs, start: &start) {
                closedPolylinesByLayer[parsed.layer, default: []].append(parsed.vertices)
            }
            continue
        }
        if pair.code == 0, pair.value == "TEXT" {
            if let parsed = parseText(pairs: pairs, start: &start) {
                textByLayer[parsed.layer, default: []].append(parsed.text)
            }
            continue
        }
        start += 1
    }
}

private func parseLWPolyline(
    pairs: [GroupCodePair],
    start: inout Int
) -> (layer: String, vertices: [(x: Double, y: Double)])? {
    start += 1
    var layer = SchematicWallOutlineDXF.wallLayer
    var closed = false
    var vertices: [(x: Double, y: Double)] = []
    var pendingX: Double?
    while start < pairs.count {
        let pair = pairs[start]
        if pair.code == 0 { break }
        switch pair.code {
        case 8:
            layer = pair.value
        case 70:
            closed = pair.value == "1"
        case 10:
            pendingX = Double(pair.value)
        case 20:
            if let x = pendingX, let y = Double(pair.value) {
                vertices.append((x: x, y: y))
                pendingX = nil
            }
        default:
            break
        }
        start += 1
    }
    guard closed, vertices.count >= 3 else { return nil }
    return (layer, vertices)
}

private func parseText(
    pairs: [GroupCodePair],
    start: inout Int
) -> (layer: String, text: String)? {
    start += 1
    var layer = SchematicWallOutlineDXF.annotationTextLayer
    var text: String?
    while start < pairs.count {
        let pair = pairs[start]
        if pair.code == 0 { break }
        switch pair.code {
        case 8:
            layer = pair.value
        case 1:
            text = pair.value
        default:
            break
        }
        start += 1
    }
    guard let text else { return nil }
    return (layer, text)
}
