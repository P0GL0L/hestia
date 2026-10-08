import ATContracts
import Foundation

/// Schematic exterior elevation: the visible faces of walls parallel to the picture plane, their doors and
/// windows, the roof silhouette, a ground line, and level marks for each floor and each roof's eave and ridge.
/// Model space here is (h, z): h runs left to right as the viewer sees it, z is elevation.
enum ElevationView {
    static let wallStyle = DisplayStyle(layer: "A-ELEV-OTLN", pen: .medium)
    static let openingStyle = DisplayStyle(layer: "A-ELEV-OPNG", pen: .thin)
    static let roofStyle = DisplayStyle(layer: "A-ELEV-ROOF", pen: .medium)
    static let foldStyle = DisplayStyle(layer: "A-ELEV-ROOF", pen: .thin)
    static let groundStyle = DisplayStyle(layer: "A-ELEV-GRND", pen: .extraHeavy)
    static let slabStyle = DisplayStyle(layer: "A-ELEV-SLAB", pen: .medium)
    static let slabPatternStyle = DisplayStyle(layer: "A-ELEV-SLAB", pen: .extraFine)
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
    static func extent(_ document: ModelDocument, _ direction: ElevationDirection, roofMeshes: [Mesh] = [])
        -> (min: Point2, max: Point2)? {
        let faces = faces(document, direction)
        guard !faces.isEmpty else { return nil }
        var minH = faces.map(\.h0).min()!, maxH = faces.map(\.h1).max()!
        var maxZ = faces.map { $0.base + $0.wall.height.ticks }.max()!
        for outline in roofOutlines(document, direction, roofMeshes: roofMeshes) {
            minH = min(minH, outline.map(\.x.ticks).min()!)
            maxH = max(maxH, outline.map(\.x.ticks).max()!)
            maxZ = max(maxZ, outline.map(\.y.ticks).max()!)
        }
        let minZ = faces.map(\.base).min()!
        return (paperPoint(minH, minZ), paperPoint(maxH, maxZ))
    }

    static func items(_ document: ModelDocument, _ direction: ElevationDirection, view: ViewTransform,
                      roofMeshes: [Mesh] = [], slabMeshes: [Mesh] = []) -> [DisplayItem] {
        let faces = faces(document, direction)
        guard !faces.isEmpty else { return [] }
        func at(_ h: Int64, _ z: Int64) -> Point2 { view.paper(paperPoint(h, z)) }
        var items: [DisplayItem] = []
        let grade = faces.map(\.base).min()!
        let bands = slabBands(document, direction, slabMeshes: slabMeshes, above: grade)
        for band in bands {
            let outline = [at(band.h0, band.z0), at(band.h1, band.z0), at(band.h1, band.z1), at(band.h0, band.z1)]
            items.append(DisplayItem(.hatch(boundary: outline, pattern: .concrete, spacing: .millimeters(1),
                                            angle: .degrees(45)), style: slabPatternStyle, elementID: band.id))
            items.append(DisplayItem(.polyline(points: outline, closed: true), style: slabStyle, elementID: band.id))
        }
        for face in faces {
            let top = face.base + face.wall.height.ticks
            for (h0, h1) in face.visible {
                for (a, b) in wallEdges(h0: h0, h1: h1, base: face.base, top: top, bands: bands) {
                    items.append(DisplayItem(.line(start: at(a.0, a.1), end: at(b.0, b.1)), style: wallStyle,
                                             elementID: face.wall.id.rawValue))
                }
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
                // Windows get a mullion down the middle; doors and cased openings are the rectangle alone.
                if opening.kind.isWindow {
                    let mid = (o0 + o1) / 2
                    items.append(DisplayItem(.line(start: at(mid, z0), end: at(mid, z1)), style: openingStyle,
                                             elementID: opening.id.rawValue))
                }
            }
        }
        let roofs = roofOutlines(document, direction, roofMeshes: roofMeshes)
        for outline in roofs {
            items.append(DisplayItem(.polyline(points: outline.map { view.paper($0) }, closed: true), style: roofStyle))
        }
        for roof in document.roofs {
            for (a, b) in folds(of: roof, direction, roofMeshes: roofMeshes, outlines: roofs) {
                items.append(DisplayItem(.line(start: view.paper(a), end: view.paper(b)), style: foldStyle,
                                         elementID: roof.id.rawValue))
            }
        }
        let minH = faces.map(\.h0).min()!, maxH = faces.map(\.h1).max()!
        let reach = Length.millimeters(1500).ticks
        items.append(DisplayItem(.line(start: at(minH - reach, grade), end: at(maxH + reach, grade)), style: groundStyle))
        // Marks start past the roof's overhang so their lines never cross it.
        let roofEdge = roofs.flatMap { $0.map(\.x.ticks) }.max() ?? maxH
        let markH = max(maxH, roofEdge)
        let units = DrawingUnits.style(document, scale: view.scale)
        for level in levels(document, direction, roofMeshes: roofMeshes) {
            items.append(DisplayItem(.line(start: at(markH + reach / 3, level.z), end: at(markH + reach, level.z)),
                                     style: levelStyle))
            let label = level.name + " " + LengthFormatting.format(Length(ticks: level.z), style: units)
            let mark = at(markH + reach / 3, level.z)
            items.append(DisplayItem(.text(position: Point2(x: mark.x, y: Length(ticks: mark.y.ticks + mmTicks(1))),
                                           string: label, height: .millimeters(2), rotation: .degrees(0),
                                           alignment: .left), style: levelStyle))
        }
        return items
    }

    /// A floor slab's edge seen in elevation: its projected extent, a rectangle since slabs are prisms.
    struct Band {
        var id: UUID
        var h0: Int64
        var h1: Int64
        var z0: Int64
        var z1: Int64
    }

    /// Slab edges from the engine's slab meshes, projected the same way as the roofs. Slabs at or below grade
    /// are left out; the ground line already stands for them.
    static func slabBands(_ document: ModelDocument, _ direction: ElevationDirection, slabMeshes: [Mesh],
                          above grade: Int64) -> [Band] {
        var bands: [Band] = []
        for slab in document.slabs {
            let meshes = slabMeshes.filter { $0.elementID == slab.id.rawValue }
            guard !meshes.isEmpty else { continue }
            let outlines = MeshSilhouette.outlines(of: meshes) { point in
                let (h, _) = project(Point2(x: point.x, y: point.y), direction)
                return (Double(h), Double(point.z.ticks))
            }
            for outline in outlines {
                let hs = outline.map(\.x.ticks), zs = outline.map(\.y.ticks)
                guard let z1 = zs.max(), z1 > grade else { continue }
                bands.append(Band(id: slab.id.rawValue, h0: hs.min()!, h1: hs.max()!, z0: zs.min()!, z1: z1))
            }
        }
        return bands
    }

    /// The edges of a wall face from h0 to h1 and base to top, leaving out what a slab edge covers or already
    /// draws, so no line runs through a slab band and none is drawn twice along its edge.
    static func wallEdges(h0: Int64, h1: Int64, base: Int64, top: Int64, bands: [Band])
        -> [((Int64, Int64), (Int64, Int64))] {
        var stations: Set<Int64> = [h0, h1]
        for band in bands where band.h1 > h0 && band.h0 < h1 {
            stations.insert(max(band.h0, h0))
            stations.insert(min(band.h1, h1))
        }
        let hs = stations.sorted()
        // The wall's visible z stretches over each column, and the band edges that bound them there.
        func cover(_ a: Int64, _ b: Int64) -> [(Int64, Int64)] {
            let over = bands.filter { $0.h0 <= a && $0.h1 >= b }.map { ($0.z0, $0.z1) }
            return subtract([(base, top)], over)
        }
        func onBand(_ z: Int64, _ a: Int64, _ b: Int64) -> Bool {
            bands.contains { $0.h0 <= a && $0.h1 >= b && ($0.z0 == z || $0.z1 == z) }
        }
        var edges: [((Int64, Int64), (Int64, Int64))] = []
        var columns: [[(Int64, Int64)]] = []
        // Horizontal pieces by height, joined where one column's piece runs straight on into the next.
        var runs: [Int64: [(Int64, Int64)]] = [:]
        for (a, b) in zip(hs, hs.dropFirst()) {
            let stretches = cover(a, b)
            columns.append(stretches)
            for (z0, z1) in stretches {
                for z in [z0, z1] where !onBand(z, a, b) {
                    if let last = runs[z]?.last, last.1 == a {
                        runs[z]![runs[z]!.count - 1].1 = b
                    } else {
                        runs[z, default: []].append((a, b))
                    }
                }
            }
        }
        for z in runs.keys.sorted() {
            for (a, b) in runs[z]! { edges.append(((a, z), (b, z))) }
        }
        // Vertical edges where the covered stretches change from one column to the next.
        for (index, h) in hs.enumerated() {
            let left = index > 0 ? columns[index - 1] : []
            let right = index < columns.count ? columns[index] : []
            let rightOnly = left.reduce(right) { remaining, cut in subtract(remaining, [cut]) }
            let leftOnly = right.reduce(left) { remaining, cut in subtract(remaining, [cut]) }
            for (z0, z1) in rightOnly + leftOnly {
                // A band's own side already draws this edge.
                let onSide = bands.contains { ($0.h0 == h || $0.h1 == h) && $0.z0 <= z0 && $0.z1 >= z1 }
                if !onSide { edges.append(((h, z0), (h, z1))) }
            }
        }
        return edges
    }

    /// The heights an elevation marks: every floor, then each roof's eave and, when it is pitched, its ridge,
    /// both read from the silhouette drawn. A height already marked is not marked again, so an eave at the top
    /// of the wall, or two roofs at one height, print one mark.
    static func levels(_ document: ModelDocument, _ direction: ElevationDirection, roofMeshes: [Mesh] = [])
        -> [(name: String, z: Int64)] {
        var levels = document.storeys.map { (name: $0.name.uppercased(), z: $0.elevation.ticks) }
        func add(_ name: String, _ z: Int64) {
            let tolerance = Length.ticksPerMillimeter
            guard !levels.contains(where: { abs($0.z - z) < tolerance }) else { return }
            levels.append((name, z))
        }
        let elevations = Dictionary(uniqueKeysWithValues: document.storeys.map { ($0.id, $0.elevation.ticks) })
        for roof in document.roofs {
            let outlines = silhouettes(of: roof, base: elevations[roof.storeyID] ?? 0, direction, roofMeshes: roofMeshes)
            let zs = outlines.flatMap { $0.map(\.y.ticks) }
            guard !zs.isEmpty else { continue }
            add("EAVE", zs.min()!)
            let pitched = roof.planes.contains { ($0.pitchRisePer12?.ticks ?? 0) > 0 }
            if pitched { add("RIDGE", zs.max()!) }
        }
        return levels
    }

    /// Roof silhouettes in (h, z). Each roof is drawn from the engine's mesh for it when `roofMeshes` holds one,
    /// so the elevation shows the same roof as the 3D view and the section; otherwise from its footprint box.
    static func roofOutlines(_ document: ModelDocument, _ direction: ElevationDirection, roofMeshes: [Mesh] = [])
        -> [[Point2]] {
        let elevations = Dictionary(uniqueKeysWithValues: document.storeys.map { ($0.id, $0.elevation.ticks) })
        return document.roofs.flatMap {
            silhouettes(of: $0, base: elevations[$0.storeyID] ?? 0, direction, roofMeshes: roofMeshes)
        }
    }

    /// A roof's ridges, hips, and valleys that show inside the silhouette, in (h, z), from its mesh; none
    /// without one. See `RoofFolds`.
    static func folds(of roof: Roof, _ direction: ElevationDirection, roofMeshes: [Mesh], outlines: [[Point2]])
        -> [(Point2, Point2)] {
        let meshes = roofMeshes.filter { $0.elementID == roof.id.rawValue }
        guard !meshes.isEmpty else { return [] }
        let toward: RoofFolds.Vec2
        switch direction {
        case .south: toward = RoofFolds.Vec2(x: 0, y: -1)
        case .north: toward = RoofFolds.Vec2(x: 0, y: 1)
        case .east: toward = RoofFolds.Vec2(x: 1, y: 0)
        case .west: toward = RoofFolds.Vec2(x: -1, y: 0)
        }
        return RoofFolds.lines(meshes: meshes, toward: toward, outlines: outlines) { x, y in
            switch direction {
            case .south: return x
            case .north: return -x
            case .east: return y
            case .west: return -y
            }
        }
    }

    /// One roof's outlines in (h, z): its mesh projected when there is one, else the box outline.
    static func silhouettes(of roof: Roof, base: Int64, _ direction: ElevationDirection, roofMeshes: [Mesh])
        -> [[Point2]] {
        let meshes = roofMeshes.filter { $0.elementID == roof.id.rawValue }
        if !meshes.isEmpty {
            let outlines = MeshSilhouette.outlines(of: meshes) { point in
                let (h, _) = project(Point2(x: point.x, y: point.y), direction)
                return (Double(h), Double(point.z.ticks))
            }
            if !outlines.isEmpty { return outlines }
        }
        return [roofOutline(roof, base: base, direction)].compactMap { $0 }
    }

    /// One roof's outline from its footprint box and edge pitches, for engines that give no roof mesh.
    ///
    /// Equal pitches on every edge read as a hip; pitched long sides with gable short ends read as a gable;
    /// no pitch reads as flat. Other combinations fall back to the hip outline. Schematic only.
    static func roofOutline(_ roof: Roof, base: Int64, _ direction: ElevationDirection) -> [Point2]? {
        guard roof.footprint.count >= 3 else { return nil }
        let projected = roof.footprint.map { project($0, direction) }
        let overhang = roof.planes.map(\.overhang.ticks).max() ?? 0
        let h0 = projected.map(\.h).min()! - overhang, h1 = projected.map(\.h).max()! + overhang
        let d0 = projected.map(\.depth).min()! - overhang, d1 = projected.map(\.depth).max()! + overhang
        let eave = base + roof.eaveHeight.ticks
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
