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
                    sill: Double = 0) throws -> [OpeningDetail.Piece] {
    var session = EditSession(model: try HestiaModel.blank())
    try session.addWall(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(30, 0))
    var document = session.model.document
    let wall = try #require(document.walls.first)
    document.openings = [Opening(id: OpeningID(UUID()), wallID: wall.id, offsetAlongWall: length(10),
                                 width: length(width), height: length(height), sillHeight: length(sill),
                                 kind: kind)]
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
    static let kinds: [OpeningKind] = [.window, .singleDoor, .doubleDoor, .slidingDoor, .garageDoor, .casedOpening]

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
        let garage = try pieces(.garageDoor, width: 9, height: 7)
        #expect(!garage.contains { $0.part == .handle })
    }
}
