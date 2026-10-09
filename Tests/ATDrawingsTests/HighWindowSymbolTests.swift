@testable import ATDrawings
import ATContracts
import Foundation
import Testing

private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
private func ft(_ f: Int64) -> Length { .feet(f) }
private let view = ViewTransform(scale: .quarterInch, modelOrigin: Point2(x: ft(0), y: ft(0)),
                                 paperOrigin: Point2(x: ft(0), y: ft(0)))
private let wall = Wall(id: WallID(uuid(10)), storeyID: StoreyID(uuid(3)), start: Point2(x: ft(0), y: ft(0)),
                        end: Point2(x: ft(20), y: ft(0)), thickness: .inches(6), height: ft(8))

/// The symbol's line patterns for an opening at 8' along the wall, 4' wide, with the given sill and height.
private func patterns(sill: Length, height: Length, _ kind: OpeningKind = .window) -> [LinePattern] {
    let swing: DoorSwing? = kind.isDoor ? DoorSwing(hinge: .nearStart, opensToward: .left) : nil
    let opening = Opening(id: OpeningID(uuid(20)), wallID: wall.id, offsetAlongWall: ft(8), width: ft(4),
                          height: height, sillHeight: sill, kind: kind, swing: swing)
    return FloorPlanView.symbol(for: opening, in: wall, view: view).map(\.style.pattern)
}

@Test func aWindowAboveThePlanCutIsDashed() {
    // Sill 5', head 7': jambs and glazing all dashed, still on the glazing layer.
    let high = patterns(sill: ft(5), height: ft(2))
    #expect(high.count == 4)
    #expect(high.allSatisfy { $0 == .dashed })
    // A sill exactly at the 4' cut counts as above it.
    #expect(patterns(sill: ft(4), height: ft(3)).allSatisfy { $0 == .dashed })
}

@Test func aWindowTheCutCrossesStaysSolid() {
    // Sill 3', head 7'.
    let crossing = patterns(sill: ft(3), height: ft(4))
    #expect(crossing.count == 4)
    #expect(crossing.allSatisfy { $0 == .solid })
    // Head exactly at the cut: below it, solid.
    #expect(patterns(sill: ft(1), height: ft(3)).allSatisfy { $0 == .solid })
}

@Test func aDoorIsNotDashed() {
    #expect(patterns(sill: ft(0), height: .feet(6, inchCount: 8), .singleDoor).allSatisfy { $0 == .solid })
    #expect(patterns(sill: ft(5), height: ft(2), .slidingDoor).allSatisfy { $0 == .solid })
    #expect(patterns(sill: ft(5), height: ft(2), .casedOpening).allSatisfy { $0 == .solid })
}
