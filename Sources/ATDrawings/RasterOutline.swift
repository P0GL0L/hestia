import ATContracts
import Foundation

/// The outline of a union of polygons, such as a building's footprint from its walls, rooms, and posts, traced on
/// a fine grid: every cell whose middle lies inside any polygon is filled, the boundaries between filled and empty
/// cells are chained into loops, and each loop is simplified back to its corners. Square buildings come back
/// exact to the cell; walls at an angle come back within a cell and a half.
enum RasterOutline {
    /// The loops bounding the union, each closed and counterclockwise for an outer boundary (clockwise for a
    /// hole), in model space. `cell` is the grid size in model ticks.
    static func union(_ polygons: [[Point2]], cell: Int64) -> [[Point2]] {
        let shapes = polygons.filter { $0.count >= 3 }
        let xs = shapes.flatMap { $0.map(\.x.ticks) }, ys = shapes.flatMap { $0.map(\.y.ticks) }
        guard cell > 0, let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return []
        }
        // One empty cell all round, so every boundary closes inside the grid.
        let x0 = minX - cell, y0 = minY - cell
        let columns = Int((maxX - x0) / cell) + 2, rows = Int((maxY - y0) / cell) + 2
        guard columns > 0, rows > 0, columns * rows <= 16_000_000 else { return [] }
        var filled = [Bool](repeating: false, count: columns * rows)
        for shape in shapes {
            let px = shape.map { Double($0.x.ticks) }, py = shape.map { Double($0.y.ticks) }
            guard let sx0 = px.min(), let sx1 = px.max(), let sy0 = py.min(), let sy1 = py.max() else { continue }
            let c0 = max(Int((sx0 - Double(x0)) / Double(cell)) - 1, 0)
            let c1 = min(Int((sx1 - Double(x0)) / Double(cell)) + 1, columns - 1)
            let r0 = max(Int((sy0 - Double(y0)) / Double(cell)) - 1, 0)
            let r1 = min(Int((sy1 - Double(y0)) / Double(cell)) + 1, rows - 1)
            guard c0 <= c1, r0 <= r1 else { continue }
            for row in r0...r1 {
                let y = Double(y0) + (Double(row) + 0.5) * Double(cell)
                for column in c0...c1 where !filled[row * columns + column] {
                    let x = Double(x0) + (Double(column) + 0.5) * Double(cell)
                    if inside(x, y, px, py) { filled[row * columns + column] = true }
                }
            }
        }
        return loops(filled, columns: columns, rows: rows).map { loop in
            simplify(loop, tolerance: 1.5).map { corner in
                paperPoint(x0 + Int64(corner.0) * cell, y0 + Int64(corner.1) * cell)
            }
        }
    }

    /// Even-odd point in polygon.
    static func inside(_ x: Double, _ y: Double, _ px: [Double], _ py: [Double]) -> Bool {
        var result = false
        var j = px.count - 1
        for i in px.indices {
            if (py[i] > y) != (py[j] > y), x < (px[j] - px[i]) * (y - py[i]) / (py[j] - py[i]) + px[i] {
                result.toggle()
            }
            j = i
        }
        return result
    }

    /// The boundaries between filled and empty cells as loops of grid corners, filled cells on the left, each
    /// starting at its lowest, leftmost corner.
    static func loops(_ filled: [Bool], columns: Int, rows: Int) -> [[(Int, Int)]] {
        func at(_ column: Int, _ row: Int) -> Bool {
            column >= 0 && row >= 0 && column < columns && row < rows && filled[row * columns + column]
        }
        // Directed edges, each from one grid corner to the next, keyed by where they start.
        var next: [Int: [(Int, Int)]] = [:]
        func key(_ corner: (Int, Int)) -> Int { corner.1 * (columns + 1) + corner.0 }
        func add(_ from: (Int, Int), _ to: (Int, Int)) { next[key(from), default: []].append(to) }
        for row in 0..<rows {
            for column in 0..<columns where at(column, row) {
                if !at(column, row - 1) { add((column, row), (column + 1, row)) }
                if !at(column + 1, row) { add((column + 1, row), (column + 1, row + 1)) }
                if !at(column, row + 1) { add((column + 1, row + 1), (column, row + 1)) }
                if !at(column - 1, row) { add((column, row + 1), (column, row)) }
            }
        }
        var result: [[(Int, Int)]] = []
        // Each loop starts at its lowest corner, leftmost among equals, so the same shapes always come back as the
        // same loops: a dictionary's order changes from run to run, and the simplified outline with it.
        let starts = next.keys.sorted { a, b in
            (a / (columns + 1), a % (columns + 1)) < (b / (columns + 1), b % (columns + 1))
        }
        var cursor = 0
        while cursor < starts.count {
            let startKey = starts[cursor]
            guard let first = next[startKey]?.first else {
                cursor += 1
                continue
            }
            let start = (startKey % (columns + 1), startKey / (columns + 1))
            var loop = [start]
            var current = first
            next[startKey]?.removeFirst()
            var guardCount = 0
            while !(current == start), guardCount < filled.count * 4 {
                guardCount += 1
                loop.append(current)
                guard var choices = next[key(current)], !choices.isEmpty else { break }
                // Where two loops touch at a corner, keep to this loop by turning left first.
                let previous = loop[loop.count - 2]
                let heading = (current.0 - previous.0, current.1 - previous.1)
                let left = (-heading.1, heading.0)
                let pick = choices.firstIndex { ($0.0 - current.0, $0.1 - current.1) == left } ?? 0
                let chosen = choices.remove(at: pick)
                next[key(current)] = choices
                current = chosen
            }
            if loop.count >= 4 { result.append(loop) }
        }
        return result
    }

    /// A closed loop reduced to its corners: points in line dropped, then Douglas-Peucker within `tolerance`
    /// cells, so a staircase along an angled wall becomes its line.
    static func simplify(_ loop: [(Int, Int)], tolerance: Double) -> [(Int, Int)] {
        guard loop.count > 3 else { return loop }
        var corners: [(Int, Int)] = []
        for index in loop.indices {
            let a = loop[(index + loop.count - 1) % loop.count], b = loop[index], c = loop[(index + 1) % loop.count]
            if (b.0 - a.0) * (c.1 - b.1) - (b.1 - a.1) * (c.0 - b.0) != 0 { corners.append(b) }
        }
        guard corners.count > 4 else { return corners }
        // A closed loop's first and last points coincide, which gives Douglas-Peucker no line to measure from;
        // split it at the corner farthest from the first, and simplify each half.
        let origin = corners[0]
        let far = corners.indices.max { a, b in
            let (da, db) = (corners[a], corners[b])
            return (da.0 - origin.0) * (da.0 - origin.0) + (da.1 - origin.1) * (da.1 - origin.1)
                < (db.0 - origin.0) * (db.0 - origin.0) + (db.1 - origin.1) * (db.1 - origin.1)
        } ?? 0
        let chain = corners + [corners[0]]
        var keep = [Bool](repeating: false, count: chain.count)
        keep[0] = true
        keep[far] = true
        keep[chain.count - 1] = true
        var stack = [(0, far), (far, chain.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last > first + 1 else { continue }
            let (ax, ay) = (Double(chain[first].0), Double(chain[first].1))
            let (bx, by) = (Double(chain[last].0), Double(chain[last].1))
            let length = max(((bx - ax) * (bx - ax) + (by - ay) * (by - ay)).squareRoot(), 1e-9)
            var worst = (index: first, distance: -1.0)
            for index in (first + 1)..<last {
                let (px, py) = (Double(chain[index].0), Double(chain[index].1))
                let distance = abs((bx - ax) * (ay - py) - (ax - px) * (by - ay)) / length
                if distance > worst.distance { worst = (index, distance) }
            }
            if worst.distance > tolerance {
                keep[worst.index] = true
                stack += [(first, worst.index), (worst.index, last)]
            }
        }
        let kept = chain.indices.filter { keep[$0] && $0 < chain.count - 1 }.map { chain[$0] }
        return kept.count >= 3 ? kept : corners
    }
}
