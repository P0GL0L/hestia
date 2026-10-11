import ATContracts
import Foundation
import Testing
@testable import HestiaApp

/// A length in feet, to the nearest tick.
private func length(_ feet: Double) -> Length {
    Length(ticks: Int64((feet / HouseScene.feetPerTick).rounded()))
}

/// The parts of one opening of `kind`, `width` by `height` feet, in a 30-foot wall.
private func pieces(_ kind: OpeningKind, width: Double, height: Double,
                    sill: Double = 0, swing: DoorSwing? = nil) throws -> [OpeningDetail.Piece] {
    var session = EditSession(model: try HestiaModel.blank())
    try session.addWall(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(30, 0))
    var document = session.model.document
    let wall = try #require(document.walls.first)
    document.openings = [Opening(id: OpeningID(UUID()), wallID: wall.id, offsetAlongWall: length(10),
                                 width: length(width), height: length(height), sillHeight: length(sill),
                                 kind: kind, swing: swing)]
    let details = OpeningDetail.details(document)
    #expect(details.count == 1)
    return details.first?.pieces ?? []
}

/// How far two pieces overlap along one axis; zero or less when they only touch or stand apart.
private func overlap(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
    min(a.1, b.1) - max(a.0, b.0)
}

/// Whether two pieces share any volume in the opening's frame.
private func intersect(_ a: OpeningDetail.Piece, _ b: OpeningDetail.Piece) -> Bool {
    let tolerance = 1e-9
    func along(_ p: OpeningDetail.Piece) -> (Double, Double) { (p.along - p.length / 2, p.along + p.length / 2) }
    func across(_ p: OpeningDetail.Piece) -> (Double, Double) { (p.across - p.depth / 2, p.across + p.depth / 2) }
    func up(_ p: OpeningDetail.Piece) -> (Double, Double) { (p.z0, p.z0 + p.tall) }
    return overlap(along(a), along(b)) > tolerance && overlap(across(a), across(b)) > tolerance
        && overlap(up(a), up(b)) > tolerance
}

@Suite("Door and window detail")
struct OpeningDetailTests {
    static let sizes = [0.03, 0.05, 0.21, 0.32, 0.33, 0.47, 0.48, 3, 7]
    static let kinds: [OpeningKind] = [.window, .singleDoor, .doubleDoor, .slidingDoor, .foldingDoor, .pocketDoor,
                                       .garageDoor, .casedOpening]
    static let doors: [OpeningKind] = [.singleDoor, .doubleDoor, .slidingDoor, .foldingDoor, .pocketDoor, .garageDoor]

    @Test("Every part of any valid opening has a positive size, and no two parts overlap",
          arguments: kinds)
    func partsFitAtEverySize(kind: OpeningKind) throws {
        for width in Self.sizes {
            for height in Self.sizes {
                let parts = try pieces(kind, width: width, height: height, sill: kind.isWindow ? 3 : 0)
                #expect(parts.contains { $0.part == .casing }, "\(kind) \(width) x \(height) keeps its casing")
                for part in parts {
                    #expect(part.length > 0 && part.depth > 0 && part.tall > 0,
                            "\(kind) \(width) x \(height): \(part)")
                }
                for (index, part) in parts.enumerated() {
                    for other in parts[(index + 1)...] {
                        #expect(!intersect(part, other), "\(kind) \(width) x \(height): \(part) and \(other)")
                    }
                }
            }
        }
    }

    @Test("Openings too small for sash bars keep their casing and drop the detail that does not fit")
    func smallWindowsSimplify() throws {
        for size in [0.21, 0.32, 0.33, 0.47] {
            let parts = try pieces(.window, width: size, height: size, sill: 3)
            #expect(!parts.contains { $0.part == .sash }, "a \(size) ft window has no room for sash bars")
            #expect(parts.filter { $0.part == .glass }.count == 1, "a \(size) ft window is one pane")
        }
        let tiny = try pieces(.window, width: 0.03, height: 0.03, sill: 3)
        #expect(!tiny.contains { $0.part == .liner || $0.part == .glass })
        // At half a foot the sash fits, but two panes and a meeting rail do not.
        let narrow = try pieces(.window, width: 0.5, height: 0.5, sill: 3)
        #expect(narrow.filter { $0.part == .sash }.count == 4)
        #expect(narrow.filter { $0.part == .glass }.count == 1)
        let door = try pieces(.singleDoor, width: 0.33, height: 0.33)
        #expect(door.filter { $0.part == .leaf }.count == 1)
        #expect(!door.contains { $0.part == .handle })
    }

    @Test("A normal window has a full sash with a meeting rail; a normal door has a leaf and two handles")
    func normalOpenings() throws {
        let window = try pieces(.window, width: 3, height: 4, sill: 3)
        #expect(window.filter { $0.part == .sash }.count == 5)
        #expect(window.filter { $0.part == .glass }.count == 2)
        #expect(window.filter { $0.part == .liner }.count == 3)
        #expect(window.filter { $0.part == .sill }.count == 1)
        let door = try pieces(.singleDoor, width: 3, height: 6.67)
        #expect(door.filter { $0.part == .leaf }.count == 1)
        #expect(door.filter { $0.part == .handle }.count == 2)
        let double = try pieces(.doubleDoor, width: 5, height: 6.67)
        #expect(double.filter { $0.part == .leaf }.count == 2)
        for kind in [OpeningKind.slidingDoor, .foldingDoor] {
            let operable = try pieces(kind, width: 5, height: 6.67)
            #expect(operable.contains { $0.part == .handle }, "\(kind) keeps a usable handle while open")
        }
        let garage = try pieces(.garageDoor, width: 9, height: 7)
        #expect(!garage.contains { $0.part == .handle })
    }

    @Test("Every door stands open: nothing of it is in the way of a walk through its open width",
          arguments: doors)
    func doorsStandOpen(kind: OpeningKind) throws {
        let (width, height) = kind == .garageDoor ? (9.0, 7.0) : (3.0, 6.67)
        let swings = DoorSwing.Hinge.allCases.flatMap { hinge in
            DoorSwing.Side.allCases.map { DoorSwing(hinge: hinge, opensToward: $0) }
        }
        for swing in swings {
            let parts = try pieces(kind, width: width, height: height, swing: swing)
            // A foot-wide path through the wall and two feet past each face, up to six feet: through the middle,
            // or for a sliding door the middle of the half its panels leave open.
            let clear = OpeningDetail.liner + OpeningDetail.gap
            let open = kind == .slidingDoor ? 10 + width - clear - (width - 2 * clear - OpeningDetail.gap) / 4
                : 10 + width / 2
            let path = OpeningDetail.Piece(part: .leaf, look: .door, along: open, across: 0, z0: 0, length: 1,
                                           depth: 4.5, tall: 6)
            for part in parts where part.part == .leaf || part.part == .handle {
                #expect(!intersect(part, path), "\(kind) \(swing): \(part) is in the way")
            }
            let leaves = parts.filter { $0.part == .leaf }
            #expect(leaves.count == (kind == .pocketDoor ? 0 : [.doubleDoor, .slidingDoor, .foldingDoor]
                .contains(kind) ? 2 : 1), "\(kind)")
        }
    }

    @Test("A hinged leaf stands square to the wall against its hinge jamb, out on the side it swings to")
    func hingedLeafFollowsItsSwing() throws {
        let thickness = 0.5 // The wall a blank model draws, six inches.
        for hinge in DoorSwing.Hinge.allCases {
            for side in DoorSwing.Side.allCases {
                let parts = try pieces(.singleDoor, width: 3, height: 6.67,
                                       swing: DoorSwing(hinge: hinge, opensToward: side))
                let leaf = try #require(parts.first { $0.part == .leaf })
                let jamb = hinge == .nearStart ? 10 + OpeningDetail.liner + OpeningDetail.gap
                    : 13 - OpeningDetail.liner - OpeningDetail.gap
                let toward: Double = hinge == .nearStart ? 1 : -1
                #expect(abs(leaf.along - (jamb + toward * OpeningDetail.leafThickness / 2)) < 1e-9)
                #expect(abs(leaf.length - OpeningDetail.leafThickness) < 1e-9)
                let out: Double = side == .left ? 1 : -1
                // From the wall's face out the leaf's own width.
                #expect(abs(leaf.across - out * (thickness / 2 + leaf.depth / 2)) < 0.01, "\(hinge) \(side)")
                #expect(abs(leaf.depth - (3 - 2 * (OpeningDetail.liner + OpeningDetail.gap))) < 1e-9)
                let handles = parts.filter { $0.part == .handle }
                #expect(handles.count == 2)
                #expect(handles.allSatisfy { $0.across * out > thickness / 2 })
            }
        }
    }

    @Test("A door with no recorded swing opens into the building")
    func unrecordedSwingOpensInward() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addRectangleRoom(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(16, 12), named: "Room")
        var document = session.model.document
        for wall in document.walls {
            document.openings.append(Opening(id: OpeningID(UUID()), wallID: wall.id, offsetAlongWall: length(4),
                                             width: length(3), height: length(6.67), sillHeight: length(0),
                                             kind: .singleDoor))
        }
        let details = OpeningDetail.details(document)
        #expect(details.count == 4)
        for (frame, parts) in details {
            let leaf = try #require(parts.first { $0.part == .leaf })
            let middle = frame.point(leaf.along, leaf.across)
            #expect(middle.x > 0 && middle.x < 16 && middle.y > 0 && middle.y < 12, "\(middle) is outside")
        }
    }

    @Test("A walk goes through an open door both ways but not through its leaf")
    func walkRoundTheLeaf() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addWall(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(30, 0))
        var document = session.model.document
        let wall = try #require(document.walls.first)
        document.openings = [Opening(id: OpeningID(UUID()), wallID: wall.id, offsetAlongWall: length(10),
                                     width: length(3), height: length(6.67), sillHeight: length(0),
                                     kind: .singleDoor, swing: DoorSwing(hinge: .nearStart, opensToward: .left))]
        let barriers = WalkBarriers(document: document, storey: wall.storeyID)
        func walk(from start: (Double, Double), heading: Double) -> Walker {
            var walker = Walker(x: start.0, y: start.1, floor: 0)
            walker.heading = heading
            for _ in 0..<60 { walker.step(WalkInput(forward: 1), seconds: 0.05, barriers: barriers) }
            return walker
        }
        // Straight through the middle, in and out.
        #expect(walk(from: (11.5, -4), heading: 0).y > 2)
        #expect(walk(from: (11.5, 4), heading: .pi).y < -2)
        // Along the wall on the swing side, a foot and a half out: the leaf stands there.
        #expect(walk(from: (6, 1.5), heading: .pi / 2).x < 10)
        #expect(walk(from: (15, 1.5), heading: -.pi / 2).x > 11)
        // The same walk on the other side has nothing in the way.
        #expect(walk(from: (6, -1.5), heading: .pi / 2).x > 14)
    }

    @Test("A walk collides only with door leaves on its own storey")
    func walkLeafBarriersStayOnStorey() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addWall(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(30, 0))
        var document = session.model.document
        let groundWall = try #require(document.walls.first)
        document.openings = [Opening(id: OpeningID(UUID()), wallID: groundWall.id, offsetAlongWall: length(10),
                                     width: length(3), height: length(6.67), sillHeight: length(0),
                                     kind: .singleDoor,
                                     swing: DoorSwing(hinge: .nearStart, opensToward: .left))]

        let ground = try #require(document.storeys.first { $0.id == groundWall.storeyID })
        let upperID = StoreyID(UUID())
        document.storeys.append(Storey(id: upperID, buildingID: ground.buildingID, name: "Upper",
                                       elevation: length(10)))
        var upperWall = groundWall
        upperWall.id = WallID(UUID())
        upperWall.storeyID = upperID
        document.walls.append(upperWall)
        document.openings.append(Opening(id: OpeningID(UUID()), wallID: upperWall.id,
                                         offsetAlongWall: length(10), width: length(3), height: length(6.67),
                                         sillHeight: length(0), kind: .singleDoor,
                                         swing: DoorSwing(hinge: .nearStart, opensToward: .right)))

        let barriers = WalkBarriers(document: document, storey: groundWall.storeyID)
        func walk(from start: (Double, Double), heading: Double) -> Walker {
            var walker = Walker(x: start.0, y: start.1, floor: 0)
            walker.heading = heading
            for _ in 0..<60 { walker.step(WalkInput(forward: 1), seconds: 0.05, barriers: barriers) }
            return walker
        }
        #expect(walk(from: (6, 1.5), heading: .pi / 2).x < 10, "the ground-floor leaf blocks its swing side")
        #expect(walk(from: (6, -1.5), heading: .pi / 2).x > 14, "the upper-storey leaf does not leak downstairs")
    }
}

@Suite("Moldings and baseboards")
struct MoldingTests {
    @Test("A molding fills exactly the box it is cut to, and every face winds toward its normal")
    func extrusion() throws {
        var solid = Solid(look: .trim)
        let casing = Molding.casing(width: 0.29, proud: 0.06)
        casing.extrude(&solid, start: Vector(1, 2, 3), run: Vector(0, 0, 1), length: 6.5, across: Vector(1, 0, 0),
                       out: Vector(0, -1, 0))
        let xs = solid.positions.map { Double($0.x) }, heights = solid.positions.map { Double($0.y) }
        let depths = solid.positions.map { Double(-$0.z) }
        #expect(abs((xs.min() ?? 0) - 1) < 1e-5 && abs((xs.max() ?? 0) - 1.29) < 1e-5)
        #expect(abs((heights.min() ?? 0) - 3) < 1e-5 && abs((heights.max() ?? 0) - 9.5) < 1e-5)
        #expect(abs((depths.max() ?? 0) - 2) < 1e-5 && abs((depths.min() ?? 0) - 1.94) < 1e-5)
        // Every triangle winds counterclockwise seen from its normal's side.
        for start in stride(from: 0, to: solid.indices.count, by: 3) {
            let (a, b, c) = (solid.positions[Int(solid.indices[start])], solid.positions[Int(solid.indices[start + 1])],
                             solid.positions[Int(solid.indices[start + 2])])
            let (u, v) = ((b.x - a.x, b.y - a.y, b.z - a.z), (c.x - a.x, c.y - a.y, c.z - a.z))
            let cross = (u.1 * v.2 - u.2 * v.1, u.2 * v.0 - u.0 * v.2, u.0 * v.1 - u.1 * v.0)
            let normal = solid.normals[Int(solid.indices[start])]
            #expect(cross.0 * normal.x + cross.1 * normal.y + cross.2 * normal.z > -1e-6)
        }
    }

    @Test("A room gets a baseboard along each inside face, broken at its door by the door and its casing")
    func baseboards() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addRectangleRoom(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(20, 15), named: "Living")
        let plain = Baseboards.runs(session.model.document)
        let thickness = HouseScene.feet(try #require(session.model.document.walls.first).thickness)
        #expect(plain.count == 4)
        let lengths = plain.map(\.length).sorted()
        #expect(abs(lengths[0] - (15 - thickness)) < 0.01 && abs(lengths[3] - (20 - thickness)) < 0.01)
        for run in plain {
            // Each board's face looks into the room.
            let middle = (x: run.start.x + run.run.x * run.length / 2, y: run.start.y + run.run.y * run.length / 2)
            let ahead = (x: middle.x + run.into.x, y: middle.y + run.into.y)
            #expect(ahead.x > 0 && ahead.x < 20 && ahead.y > 0 && ahead.y < 15)
        }
        let south = try #require(session.model.document.walls.first {
            abs(HouseScene.feet($0.start.y)) < 0.01 && abs(HouseScene.feet($0.end.y)) < 0.01
        })
        try session.perform(session.model.doorCommand(on: south.id, at: PlanOverlay.point(10, 0)).erased)
        let door = try #require(session.model.document.openings.first)
        let runs = Baseboards.runs(session.model.document)
        #expect(runs.count == 5)
        let southRuns = runs.filter { abs($0.run.y) < 1e-6 && $0.start.y < 1 }
        #expect(southRuns.count == 2)
        let covered = southRuns.map(\.length).reduce(0, +)
        let gap = HouseScene.feet(door.width) + 2 * OpeningDetail.casing
        #expect(abs(covered - (20 - thickness - gap)) < 0.01)
    }

    @Test("A split collinear wall stops its board at an opening on a later segment")
    func splitWallOpeningGap() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addRectangleRoom(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(20, 15), named: "Living")
        var document = session.model.document
        let southIndex = try #require(document.walls.firstIndex {
            abs(HouseScene.feet($0.start.y)) < 0.01 && abs(HouseScene.feet($0.end.y)) < 0.01
        })
        let original = document.walls.remove(at: southIndex)
        var first = original
        first.id = WallID(UUID())
        first.start = PlanOverlay.point(0, 0)
        first.end = PlanOverlay.point(10, 0)
        var second = original
        second.id = WallID(UUID())
        second.start = PlanOverlay.point(20, 0)
        second.end = PlanOverlay.point(10, 0)
        document.walls += [first, second]
        let roomIndex = try #require(document.rooms.firstIndex { $0.boundaryWallIDs.contains(original.id) })
        let boundaryIndex = try #require(document.rooms[roomIndex].boundaryWallIDs.firstIndex(of: original.id))
        document.rooms[roomIndex].boundaryWallIDs.replaceSubrange(boundaryIndex...boundaryIndex,
                                                                  with: [first.id, second.id])
        document.openings = [
            Opening(id: OpeningID(UUID()), wallID: second.id, offsetAlongWall: length(5), width: length(3),
                    height: length(7), sillHeight: length(0), kind: .casedOpening),
        ]

        let runs = Baseboards.runs(document).filter { abs($0.run.y) < 1e-6 && $0.start.y < 1 }
            .sorted { $0.start.x < $1.start.x }
        #expect(runs.count == 2)
        let gapStart = 12 - OpeningDetail.casing
        let gapEnd = 15 + OpeningDetail.casing
        if runs.count == 2 {
            #expect(abs(runs[0].start.x + runs[0].run.x * runs[0].length - gapStart) < 0.01)
            #expect(abs(runs[1].start.x - gapEnd) < 0.01)
        }
    }

    @Test("Window casing interrupts a board exactly while their heights overlap")
    func windowCasingGap() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addRectangleRoom(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(20, 15), named: "Living")
        var document = session.model.document
        let south = try #require(document.walls.first {
            abs(HouseScene.feet($0.start.y)) < 0.01 && abs(HouseScene.feet($0.end.y)) < 0.01
        })
        let firstClearSill = Baseboards.floorLift + Baseboards.height + OpeningDetail.casing
        document.openings = [
            Opening(id: OpeningID(UUID()), wallID: south.id, offsetAlongWall: length(8), width: length(4),
                    height: length(4), sillHeight: length(firstClearSill - 0.02), kind: .window),
        ]
        let colliding = Baseboards.runs(document).filter { abs($0.run.y) < 1e-6 && $0.start.y < 1 }
        #expect(colliding.count == 2)

        document.openings[0].sillHeight = length(firstClearSill + 0.02)
        let clear = Baseboards.runs(document).filter { abs($0.run.y) < 1e-6 && $0.start.y < 1 }
        #expect(clear.count == 1)
    }

    @Test("Gaps come out of a run, leaving no slivers")
    func gaps() {
        let pieces = Baseboards.pieces(length: 10, minus: [(2, 4), (3.98, 6), (9.97, 11)])
        #expect(pieces.count == 2)
        #expect(pieces[0] == (0, 2))
        #expect(pieces[1].0 == 6 && pieces[1].1 == 9.97)
    }
}
