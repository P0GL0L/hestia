import ATContracts
import ATGeometry
import SwiftUI

struct PlanCanvas: View {
    var cottage: SixRoomCottage

    var body: some View {
        Canvas { context, size in
            let outlines = (try? StraightWallOutlines().outlines(for: cottage.walls)) ?? [:]
            let bounds = planBounds(outlines: outlines)
            let scale = fitScale(bounds: bounds, size: size)
            var wallPath = Path()
            for polygon in outlines.values {
                append(polygon.vertices, to: &wallPath, bounds: bounds, scale: scale, size: size)
            }
            context.stroke(wallPath, with: .color(.black), lineWidth: 1.5)

            var stairPath = Path()
            let cut = cottage.slabCut
            append(
                [
                    Point2(x: cut.minX, y: cut.minY),
                    Point2(x: cut.maxX, y: cut.minY),
                    Point2(x: cut.maxX, y: cut.maxY),
                    Point2(x: cut.minX, y: cut.maxY),
                ],
                to: &stairPath,
                bounds: bounds,
                scale: scale,
                size: size
            )
            context.stroke(stairPath, with: .color(.orange), lineWidth: 1)

            for room in cottage.rooms {
                let center = Point2(
                    x: Length(ticks: room.interiorMin.x.ticks + room.interiorWidth.ticks / 2),
                    y: Length(ticks: room.interiorMin.y.ticks + room.interiorHeight.ticks / 2)
                )
                let point = map(center, bounds: bounds, scale: scale, size: size)
                context.draw(Text(room.name).font(.caption), at: point)
            }
        }
    }

    private func planBounds(outlines: [WallID: ClosedPolygon2]) -> (minX: Int64, minY: Int64, maxX: Int64, maxY: Int64) {
        var minX = Int64.max
        var minY = Int64.max
        var maxX = Int64.min
        var maxY = Int64.min
        for polygon in outlines.values {
            for vertex in polygon.vertices {
                minX = min(minX, vertex.x.ticks)
                minY = min(minY, vertex.y.ticks)
                maxX = max(maxX, vertex.x.ticks)
                maxY = max(maxY, vertex.y.ticks)
            }
        }
        if minX == Int64.max {
            return (0, 0, 1, 1)
        }
        return (minX, minY, maxX, maxY)
    }

    private func fitScale(
        bounds: (minX: Int64, minY: Int64, maxX: Int64, maxY: Int64),
        size: CGSize
    ) -> CGFloat {
        let width = CGFloat(max(bounds.maxX - bounds.minX, 1))
        let height = CGFloat(max(bounds.maxY - bounds.minY, 1))
        return min(size.width / width, size.height / height) * 0.86
    }

    private func map(
        _ point: Point2,
        bounds: (minX: Int64, minY: Int64, maxX: Int64, maxY: Int64),
        scale: CGFloat,
        size: CGSize
    ) -> CGPoint {
        let modelWidth = CGFloat(bounds.maxX - bounds.minX) * scale
        let modelHeight = CGFloat(bounds.maxY - bounds.minY) * scale
        let originX = (size.width - modelWidth) / 2
        let originY = (size.height - modelHeight) / 2
        let x = originX + CGFloat(point.x.ticks - bounds.minX) * scale
        let y = size.height - (originY + CGFloat(point.y.ticks - bounds.minY) * scale)
        return CGPoint(x: x, y: y)
    }

    private func append(
        _ vertices: [Point2],
        to path: inout Path,
        bounds: (minX: Int64, minY: Int64, maxX: Int64, maxY: Int64),
        scale: CGFloat,
        size: CGSize
    ) {
        guard let first = vertices.first else { return }
        path.move(to: map(first, bounds: bounds, scale: scale, size: size))
        for vertex in vertices.dropFirst() {
            path.addLine(to: map(vertex, bounds: bounds, scale: scale, size: size))
        }
        path.closeSubpath()
    }
}
