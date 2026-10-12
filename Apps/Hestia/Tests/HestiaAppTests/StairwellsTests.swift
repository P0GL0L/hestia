import ATContracts
import Foundation
import Testing
@testable import HestiaApp

/// A flight climbing north from (10, 2) to (10, 14), three feet wide: its well is x 8.5...11.5, y 2...14.
private let flight = WalkHouse.Flight(startX: 10, startY: 2, ux: 0, uy: 1, length: 12, halfWidth: 1.5, bottom: 0,
                                      top: 9, lower: StoreyID(UUID()), upper: StoreyID(UUID()))

private func area(_ pieces: [[(x: Double, y: Double)]]) -> Double {
    pieces.map { abs(Triangulation.twiceArea($0)) / 2 }.reduce(0, +)
}

/// Whether a point is inside any piece.
private func covers(_ pieces: [[(x: Double, y: Double)]], _ x: Double, _ y: Double) -> Bool {
    pieces.contains { ring in
        var inside = false
        for index in ring.indices {
            let a = ring[index], b = ring[(index + 1) % ring.count]
            if (a.y > y) != (b.y > y), x < a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x) { inside.toggle() }
        }
        return inside
    }
}

@Suite("Stairwells")
struct StairwellsTests {
    @Test("A floor around a stair keeps everything but the well")
    func wellInsideTheFloor() {
        let floor: [(x: Double, y: Double)] = [(0, 0), (20, 0), (20, 20), (0, 20)]
        let pieces = Stairwells.outside(floor, wells: [flight])
        #expect(abs(area(pieces) - (400 - 36)) < 1e-6)
        #expect(!covers(pieces, 10, 8), "the well is open")
        #expect(covers(pieces, 10, 1) && covers(pieces, 10, 15) && covers(pieces, 7, 8) && covers(pieces, 13, 8))
        // Every piece can be drawn.
        #expect(pieces.allSatisfy { !Triangulation.ears(Triangulation.counterclockwise($0)).isEmpty })
    }

    @Test("A floor the well only reaches into loses only the overlap, and one it misses stays whole")
    func partialAndMissed() {
        let half: [(x: Double, y: Double)] = [(0, 0), (10, 0), (10, 20), (0, 20)]
        #expect(abs(area(Stairwells.outside(half, wells: [flight])) - (200 - 18)) < 1e-6)
        let away: [(x: Double, y: Double)] = [(30, 0), (40, 0), (40, 10), (30, 10)]
        let kept = Stairwells.outside(away, wells: [flight])
        #expect(kept.count == 1 && abs(area(kept) - 100) < 1e-9)
        #expect(Stairwells.outside(away, wells: []).count == 1)
    }

    @Test("An L-shaped floor keeps its shape around the well")
    func lShape() {
        let floor: [(x: Double, y: Double)] = [(0, 0), (20, 0), (20, 10), (12, 10), (12, 20), (0, 20)]
        let pieces = Stairwells.outside(floor, wells: [flight])
        #expect(abs(area(pieces) - (320 - 36)) < 1e-6)
        #expect(!covers(pieces, 10, 12) && !covers(pieces, 15, 15))
    }

    @Test("Cutting a concave U floor never bridges its disconnected arms")
    func concaveSplit() {
        let floor: [(x: Double, y: Double)] = [
            (0, 0), (20, 0), (20, 20), (14, 20), (14, 6), (6, 6), (6, 20), (0, 20),
        ]
        let pieces = Stairwells.outside(floor, wells: [flight])
        #expect(abs(area(pieces) - 276) < 1e-6)
        #expect(!covers(pieces, 10, 4), "the well is open through the U's connector")
        #expect(!covers(pieces, 10, 18), "the empty middle of the U is not bridged")
        #expect(pieces.allSatisfy {
            let ring = Triangulation.counterclockwise($0)
            return Triangulation.ears(ring).count == ring.count - 2
        })
    }

    @Test("A cut slab's top and underside leave the well open, and it has sides around the well")
    func slabWithWell() {
        var solid = Solid(look: .slab, group: .house)
        Stairwells.slab([(0, 0), (20, 0), (20, 20), (0, 20)], bottom: 8.5, top: 9, wells: [flight], into: &solid)
        // Faces up at the top, by area.
        var up = 0.0, sides = 0
        for t in stride(from: 0, to: solid.indices.count, by: 3) {
            let ps = (0..<3).map { solid.positions[Int(solid.indices[t + $0])] }
            let normal = solid.normals[Int(solid.indices[t])]
            if normal.y > 0.5 {
                // View space: x east, z south.
                let a = (Double(ps[1].x - ps[0].x), Double(ps[1].z - ps[0].z))
                let b = (Double(ps[2].x - ps[0].x), Double(ps[2].z - ps[0].z))
                up += abs(a.0 * b.1 - a.1 * b.0) / 2
            } else if abs(normal.y) < 0.1 {
                sides += 1
            }
        }
        #expect(abs(up - (400 - 36)) < 1e-3)
        // Four outer sides and four well sides, with harmless splits where cut pieces meet the outer boundary.
        #expect(sides >= 16 && sides.isMultiple(of: 2))
    }

    @Test("Partial, missed, and overlapping wells create only exposed slab sides")
    func slabSidesFollowTheCutUnion() {
        func sideCenters(_ outline: [(x: Double, y: Double)], _ wells: [WalkHouse.Flight])
            -> [(x: Double, y: Double)] {
            var solid = Solid(look: .slab, group: .house)
            Stairwells.slab(outline, bottom: 8.5, top: 9, wells: wells, into: &solid)
            var centers: [(x: Double, y: Double)] = []
            for index in stride(from: 0, to: solid.indices.count, by: 3) {
                let normal = solid.normals[Int(solid.indices[index])]
                guard abs(normal.y) < 0.1 else { continue }
                let points = (0..<3).map { solid.positions[Int(solid.indices[index + $0])] }
                centers.append((points.map { Double($0.x) }.reduce(0, +) / 3,
                                -points.map { Double($0.z) }.reduce(0, +) / 3))
            }
            return centers
        }

        let partial: [(x: Double, y: Double)] = [(0, 0), (10, 0), (10, 20), (0, 20)]
        let partialSides = sideCenters(partial, [flight])
        #expect(partialSides.allSatisfy { $0.x <= 10 + 1e-6 })
        #expect(!partialSides.contains { abs($0.x - 10) < 1e-6 && $0.y > 2 && $0.y < 14 })
        #expect(partialSides.contains { abs($0.x - 8.5) < 1e-6 && $0.y > 2 && $0.y < 14 })

        let away: [(x: Double, y: Double)] = [(30, 0), (40, 0), (40, 20), (30, 20)]
        #expect(sideCenters(away, [flight]).allSatisfy { $0.x >= 30 - 1e-6 })

        let overlapping = WalkHouse.Flight(startX: 11, startY: 2, ux: 0, uy: 1, length: 12,
                                           halfWidth: 1.5, bottom: 0, top: 9,
                                           lower: flight.lower, upper: flight.upper)
        let overlapSides = sideCenters([(0, 0), (20, 0), (20, 20), (0, 20)], [flight, overlapping])
        #expect(!overlapSides.contains { abs($0.x - 11.5) < 1e-6 && $0.y > 2 && $0.y < 14 })
    }

    @Test("In the L-house, nothing between the stair's two floors spans its well: no ceiling, floor, or slab")
    func lHouseHasAnOpenStairwell() throws {
        let repo = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repo.appendingPathComponent("fixtures/l-house.json"))
        let model = try HestiaModel(document: try JSONDecoder().decode(ModelDocument.self, from: data))
        let flight = try #require(WalkHouse.flights(model.document).first)
        // Points spread over the well, a little in from its edges.
        var probes: [(x: Double, y: Double)] = []
        for along in stride(from: 0.5, through: flight.length - 0.5, by: (flight.length - 1) / 6) {
            for across in [-0.8, 0, 0.8].map({ $0 * flight.halfWidth }) {
                probes.append(flight.point(along: along, across: across))
            }
        }
        var crossing: [String] = []
        for solid in model.house.solids where [.ceiling, .slab, .woodFloor, .tileFloor, .carpet].contains(solid.look) {
            for t in stride(from: 0, to: solid.indices.count, by: 3) {
                // View space back to plan: x east, y up, z south.
                let ps = (0..<3).map { solid.positions[Int(solid.indices[t + $0])] }
                let height = Double(ps.map(\.y).max() ?? 0)
                guard height > flight.bottom + 1, height <= flight.top + 0.05 else { continue }
                let plan = ps.map { (x: Double($0.x), y: -Double($0.z)) }
                if let probe = probes.first(where: { Self.inside($0, plan) }) {
                    crossing.append("\(solid.look) at \(height) over \(probe)")
                }
            }
        }
        #expect(crossing.isEmpty, "\(crossing.prefix(5))")
    }

    @Test("A wall-box fallback floor also leaves the stairwell open")
    func fallbackFloorHasAnOpenStairwell() throws {
        let repo = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repo.appendingPathComponent("fixtures/l-house.json"))
        var document = try JSONDecoder().decode(ModelDocument.self, from: data)
        document.rooms = []
        document.slabs = []
        let model = try HestiaModel(document: document)
        let flight = try #require(WalkHouse.flights(model.document).first)
        let probes = [0.25, 0.5, 0.75].map { flight.point(along: flight.length * $0, across: 0) }
        var crossing: [(x: Double, y: Double)] = []
        for solid in model.house.solids where solid.look == .woodFloor {
            for index in stride(from: 0, to: solid.indices.count, by: 3) {
                let points = (0..<3).map { solid.positions[Int(solid.indices[index + $0])] }
                let height = Double(points.map(\.y).max() ?? 0)
                guard abs(height - (flight.top + 0.02)) < 0.05 else { continue }
                let plan = points.map { (x: Double($0.x), y: -Double($0.z)) }
                crossing += probes.filter { Self.inside($0, plan) }
            }
        }
        #expect(crossing.isEmpty, "fallback floor still covers the well at \(crossing)")
    }

    /// Whether a plan point lies inside a triangle (either winding).
    static func inside(_ p: (x: Double, y: Double), _ t: [(x: Double, y: Double)]) -> Bool {
        func side(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
            (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
        }
        let (d1, d2, d3) = (side(t[0], t[1]), side(t[1], t[2]), side(t[2], t[0]))
        return (d1 > 0 && d2 > 0 && d3 > 0) || (d1 < 0 && d2 < 0 && d3 < 0)
    }
}
