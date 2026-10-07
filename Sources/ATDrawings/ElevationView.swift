import ATContracts
import Foundation

/// Schematic exterior elevation: the visible faces of walls parallel to the picture plane, their doors and
/// windows, the roof silhouette, a ground line, and level marks. Model space here is (h, z): h runs left to
/// right as the viewer sees it, z is elevation.
enum ElevationView {
    static let wallStyle = DisplayStyle(layer: "A-ELEV-OTLN", pen: .medium)
    static let openingStyle = DisplayStyle(layer: "A-ELEV-OPNG", pen: .thin)
    static let roofStyle = DisplayStyle(layer: "A-ELEV-ROOF", pen: .medium)
    static let groundStyle = DisplayStyle(layer: "A-ELEV-GRND", pen: .extraHeavy)
    static let levelStyle = DisplayStyle(layer: "A-ANNO-TEXT", pen: .fine)

    /// Plan point → (h, depth), where smaller depth is nearer the viewer.
    static func project(_ p: Point2, _ direction: ElevationDirection) -> (h: Int64, depth: Int64) {
        switch direction {
        case .south: return (p.x.ticks, p.y.ticks)
        case .north: return (-p.x.ticks, -p.y.ticks)
        case .east: return (p.y.ticks, -p.x.ticks)
        case .west: return (-p.y.ticks, p.x.ticks)
        }
    }

    struct Face {
        var wall: Wall
        var base: Int64
        var h0: Int64
        var h1: Int64
        var visible: [(Int64, Int64)]
    }

    /// Walls parallel to the picture plane, nearest first, each with the parts no nearer wall hides.
    static func faces(_ document: ModelDocument, _ direction: ElevationDirection) -> [Face] {
        let elevations = Dictionary(uniqueKeysWithValues: document.storeys.map { ($0.id, $0.elevation.ticks) })
        var candidates: [(Face, Int64)] = []
        for wall in document.walls {
            let a = project(wall.start, direction), b = project(wall.end, direction)
            guard a.depth == b.depth, a.h != b.h else { continue }
            let base = elevations[wall.storeyID] ?? 0
            let half = wall.thickness.ticks / 2
            let face = Face(wall: wall, base: base, h0: min(a.h, b.h) - half, h1: max(a.h, b.h) + half, visible: [])
            candidates.append((face, a.depth - half))
        }
        candidates.sort { $0.1 < $1.1 }
        var covered: [Int64: [(Int64, Int64)]] = [:]
        var result: [Face] = []
        for (candidate, _) in candidates {
            var face = candidate
            let band = face.base
            face.visible = subtract([(face.h0, face.h1)], covered[band] ?? [])
            guard !face.visible.isEmpty else { continue }
            covered[band, default: []].append((face.h0, face.h1))
            result.append(face)
        }
        return result
    }

    /// Intervals minus the covered ones.
    static func subtract(_ intervals: [(Int64, Int64)], _ covered: [(Int64, Int64)]) -> [(Int64, Int64)] {
        var remaining = intervals
        for (c0, c1) in covered {
            remaining = remaining.flatMap { r0, r1 -> [(Int64, Int64)] in
                if c1 <= r0 || c0 >= r1 { return [(r0, r1)] }
                return [(r0, max(r0, c0)), (min(r1, c1), r1)].filter { $0.0 < $0.1 }
            }
        }
        return remaining
    }

    /// Model-space (h, z) extent of the elevation, or nil when no wall faces this way.
    static func extent(_ document: ModelDocument, _ direction: ElevationDirection) -> (min: Point2, max: Point2)? {
        let faces = faces(document, direction)
        guard !faces.isEmpty else { return nil }
        var minH = faces.map(\.h0).min()!, maxH = faces.map(\.h1).max()!
        var maxZ = faces.map { $0.base + $0.wall.height.ticks }.max()!
        for outline in roofOutlines(document, direction) {
            minH = min(minH, outline.map(\.x.ticks).min()!)
            maxH = max(maxH, outline.map(\.x.ticks).max()!)
            maxZ = max(maxZ, outline.map(\.y.ticks).max()!)
        }
        let minZ = faces.map(\.base).min()!
        return (paperPoint(minH, minZ), paperPoint(maxH, maxZ))
    }

    static func items(_ document: ModelDocument, _ direction: ElevationDirection, view: ViewTransform) -> [DisplayItem] {
        let faces = faces(document, direction)
        guard !faces.isEmpty else { return [] }
        func at(_ h: Int64, _ z: Int64) -> Point2 { view.paper(paperPoint(h, z)) }
        var items: [DisplayItem] = []
        for face in faces {
            let top = face.base + face.wall.height.ticks
            for (h0, h1) in face.visible {
                items.append(DisplayItem(.polyline(points: [at(h0, face.base), at(h1, face.base), at(h1, top),
                                                            at(h0, top)], closed: true),
                                         style: wallStyle, elementID: face.wall.id.rawValue))
            }
            let a = project(face.wall.start, direction).h
            let sign: Int64 = project(face.wall.end, direction).h >= a ? 1 : -1
            for opening in document.openings where opening.wallID == face.wall.id {
                let e0 = a + sign * opening.offsetAlongWall.ticks
                let e1 = e0 + sign * opening.width.ticks
                let (o0, o1) = (min(e0, e1), max(e0, e1))
                guard face.visible.contains(where: { $0.0 <= o0 && o1 <= $0.1 }) else { continue }
                let z0 = face.base + opening.sillHeight.ticks
                let z1 = z0 + opening.height.ticks
                items.append(DisplayItem(.polyline(points: [at(o0, z0), at(o1, z0), at(o1, z1), at(o0, z1)],
                                                   closed: true), style: openingStyle, elementID: opening.id.rawValue))
                if !opening.kind.isDoor {
                    let mid = (o0 + o1) / 2
                    items.append(DisplayItem(.line(start: at(mid, z0), end: at(mid, z1)), style: openingStyle,
                                             elementID: opening.id.rawValue))
                }
            }
        }
        for outline in roofOutlines(document, direction) {
            items.append(DisplayItem(.polyline(points: outline.map { view.paper($0) }, closed: true), style: roofStyle))
        }
        let minH = faces.map(\.h0).min()!, maxH = faces.map(\.h1).max()!
        let grade = faces.map(\.base).min()!
        let reach = Length.millimeters(1500).ticks
        items.append(DisplayItem(.line(start: at(minH - reach, grade), end: at(maxH + reach, grade)), style: groundStyle))
        let units = DrawingUnits.style(document, scale: view.scale)
        for storey in document.storeys {
            let z = storey.elevation.ticks
            items.append(DisplayItem(.line(start: at(maxH + reach / 3, z), end: at(maxH + reach, z)), style: levelStyle))
            let label = "\(storey.name.uppercased()) "
                + LengthFormatting.format(storey.elevation, style: units)
            let mark = at(maxH + reach / 3, z)
            items.append(DisplayItem(.text(position: Point2(x: mark.x, y: Length(ticks: mark.y.ticks + mmTicks(1))),
                                           string: label, height: .millimeters(2), rotation: .degrees(0),
                                           alignment: .left), style: levelStyle))
        }
        return items
    }

    /// Roof silhouettes in (h, z), from each roof's footprint box and edge pitches.
    ///
    /// Equal pitches on every edge read as a hip; pitched long sides with gable short ends read as a gable;
    /// no pitch reads as flat. Other combinations fall back to the hip outline. Schematic only.
    static func roofOutlines(_ document: ModelDocument, _ direction: ElevationDirection) -> [[Point2]] {
        let elevations = Dictionary(uniqueKeysWithValues: document.storeys.map { ($0.id, $0.elevation.ticks) })
        return document.roofs.compactMap { roof in
            guard roof.footprint.count >= 3 else { return nil }
            let projected = roof.footprint.map { project($0, direction) }
            let overhang = roof.planes.map(\.overhang.ticks).max() ?? 0
            let h0 = projected.map(\.h).min()! - overhang, h1 = projected.map(\.h).max()! + overhang
            let d0 = projected.map(\.depth).min()! - overhang, d1 = projected.map(\.depth).max()! + overhang
            let eave = (elevations[roof.storeyID] ?? 0) + roof.eaveHeight.ticks
            let pitches = roof.planes.compactMap(\.pitchRisePer12?.ticks).filter { $0 > 0 }
            guard let pitch = pitches.max() else {
                let fascia = Length.millimeters(250).ticks
                return [paperPoint(h0, eave), paperPoint(h1, eave), paperPoint(h1, eave + fascia),
                        paperPoint(h0, eave + fascia)]
            }
            let twelve = Length.inches(12).ticks
            let width = h1 - h0, depth = d1 - d0
            let gableEnds = roof.planes.contains { $0.pitchRisePer12 == nil }
            if gableEnds {
                // Ridge along the longer plan direction; gable ends face along it.
                if width >= depth {
                    let ridge = eave + pitch * (depth / 2) / twelve
                    return [paperPoint(h0, eave), paperPoint(h1, eave), paperPoint(h1, ridge), paperPoint(h0, ridge)]
                }
                let ridge = eave + pitch * (width / 2) / twelve
                return [paperPoint(h0, eave), paperPoint(h1, eave), paperPoint((h0 + h1) / 2, ridge)]
            }
            let half = min(width, depth) / 2
            let ridge = eave + pitch * half / twelve
            if width > depth {
                return [paperPoint(h0, eave), paperPoint(h1, eave), paperPoint(h1 - half, ridge),
                        paperPoint(h0 + half, ridge)]
            }
            return [paperPoint(h0, eave), paperPoint(h1, eave), paperPoint((h0 + h1) / 2, ridge)]
        }
    }
}
