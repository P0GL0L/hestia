import ATContracts
import ATGeometry
import Foundation

public enum SchematicFloorPlanPDF {
    public static let schematicStamp = "SCHEMATIC / NOT FOR CONSTRUCTION"

    private static let pageWidth: Double = 612
    private static let pageHeight: Double = 792
    private static let margin: Double = 36
    private static let strokeWidth: Double = 0.75
    private static let stampFontSize: Double = 10

    /// PDF 1.4 schematic floor plan of straight wall outlines (US Letter).
    public static func export(walls: [Wall]) throws -> Data {
        let outlines = try StraightWallOutlines().outlines(for: walls)
        return export(outlines: outlines, walls: walls)
    }

    public static func export(
        outlines: [WallID: ClosedPolygon2],
        walls: [Wall]
    ) -> Data {
        let bounds = modelBounds(of: outlines)
        let transform = fitTransform(for: bounds)
        var content = ""

        content += "q\n"
        content += formatStrokeWidth(strokeWidth) + " w\n"

        for wall in walls {
            guard let polygon = outlines[wall.id], polygon.vertices.count >= 3 else { continue }
            content += polygonPath(polygon.vertices, transform: transform)
            content += " S\n"
        }

        content += "Q\n"

        let stampModelX = bounds.minX
        let stampModelY = bounds.minY - stampFontSize * 2
        let stampPage = transformPoint(x: stampModelX, y: stampModelY, transform: transform)
        content += "BT\n"
        content += "/F1 \(format(stampFontSize)) Tf\n"
        content += "\(format(stampPage.x)) \(format(stampPage.y)) Td\n"
        content += "(\(pdfLiteral(schematicStamp))) Tj\n"
        content += "ET\n"

        let streamData = Data(content.utf8)
        var writer = PDF14Writer()

        writer.addObject(number: 1, body: "<< /Type /Catalog /Pages 2 0 R >>")
        writer.addObject(number: 2, body: "<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
        writer.addObject(
            number: 3,
            body: """
            << /Type /Page /Parent 2 0 R /MediaBox [0 0 \(format(pageWidth)) \(format(pageHeight))] \
            /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
            """
        )
        writer.addObject(
            number: 4,
            body: "<< /Length \(streamData.count) >>\nstream\n\(content)endstream"
        )
        writer.addObject(
            number: 5,
            body: "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
        )

        writer.finish(rootObjectNumber: 1, objectCount: 5)
        return writer.data
    }

    private struct ModelBounds {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double
    }

    private struct FitTransform {
        var scale: Double
        var translateX: Double
        var translateY: Double
    }

    private static func modelBounds(of outlines: [WallID: ClosedPolygon2]) -> ModelBounds {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for polygon in outlines.values {
            for vertex in polygon.vertices {
                let x = inches(from: vertex.x)
                let y = inches(from: vertex.y)
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        if minX == Double.greatestFiniteMagnitude {
            return ModelBounds(minX: 0, minY: 0, maxX: 0, maxY: 0)
        }
        return ModelBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    private static func fitTransform(for bounds: ModelBounds) -> FitTransform {
        let drawableWidth = pageWidth - 2 * margin
        let drawableHeight = pageHeight - 2 * margin
        let modelWidth = max(bounds.maxX - bounds.minX, 1e-6)
        let modelHeight = max(bounds.maxY - bounds.minY, 1e-6)
        let scale = min(drawableWidth / modelWidth, drawableHeight / modelHeight)
        let scaledWidth = modelWidth * scale
        let scaledHeight = modelHeight * scale
        let translateX = margin + (drawableWidth - scaledWidth) / 2 - bounds.minX * scale
        let translateY = margin + (drawableHeight - scaledHeight) / 2 - bounds.minY * scale
        return FitTransform(scale: scale, translateX: translateX, translateY: translateY)
    }

    private static func transformPoint(x: Double, y: Double, transform: FitTransform) -> (x: Double, y: Double) {
        (
            transform.translateX + x * transform.scale,
            transform.translateY + y * transform.scale
        )
    }

    private static func polygonPath(_ vertices: [Point2], transform: FitTransform) -> String {
        var path = ""
        for (index, vertex) in vertices.enumerated() {
            let x = inches(from: vertex.x)
            let y = inches(from: vertex.y)
            let page = transformPoint(x: x, y: y, transform: transform)
            if index == 0 {
                path += "\(format(page.x)) \(format(page.y)) m\n"
            } else {
                path += "\(format(page.x)) \(format(page.y)) l\n"
            }
        }
        path += "h\n"
        return path
    }

    private static func inches(from length: Length) -> Double {
        let ticksPerInch = Length.ticksPerSixtyFourthInch * 64
        return Double(length.ticks) / Double(ticksPerInch)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func formatStrokeWidth(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func pdfLiteral(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }
}
