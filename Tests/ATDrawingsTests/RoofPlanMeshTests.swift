@testable import ATDrawings
import ATContracts
import ATGeometry
import Foundation
import Testing

private func lHouse() throws -> ModelDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/l-house.json")
    return try ModelDocument.decode(from: Data(contentsOf: url))
}

private func mm(_ x: Int64, _ y: Int64) -> Point2 { Point2(x: .millimeters(x), y: .millimeters(y)) }

private func texts(_ sheet: SheetDrawing) -> [String] {
    sheet.content.items.compactMap { item -> String? in
        if case let .text(_, string, _, _, _) = item.primitive { return string }
        return nil
    }
}

@Test func lRoofPlanComesFromItsMesh() throws {
    let house = try lHouse()
    let meshes = try HestiaGeometryEngine().meshes(of: house).filter { $0.elementID == house.roofs[0].id.rawValue }
    let plan = try #require(RoofPlanView.meshPlan(meshes))
    // The outer eave: the L pushed out by its 450 mm overhang, outside the wall centerlines.
    #expect(plan.eaves.count == 1)
    let eave: Set<Point2> = Set(try #require(plan.eaves.first))
    let expected: Set<Point2> = [mm(-450, -450), mm(10450, -450), mm(10450, 6450), mm(5450, 6450),
                                 mm(5450, 10450), mm(-450, 10450)]
    #expect(eave == expected)
    // The valley where the wings meet, from the inner eave corner up to the hall wing's ridge.
    let valley = plan.folds.contains { fold in
        let ends: Set<Point2> = [fold.0, fold.1]
        return ends == [mm(5450, 6450), mm(2500, 3500)]
    }
    #expect(valley)
    // Five hips, two ridges, the valley, and the short fold where the ridges meet.
    #expect(plan.folds.count == 9)
    let ratios: [String] = plan.pitches.map(\.1)
    #expect(ratios.count == 6)
    #expect(ratios.allSatisfy { $0 == "6:12" })
}

@Test func lRoofPlanSheetDrawsTheMeshNotTheFootprint() throws {
    let house = try lHouse()
    let sheets = try SchematicDrawingSet().sheets(for: house, geometry: HestiaGeometryEngine())
    let roofPlan = try #require(sheets.first { $0.number == "A-401" })
    let roofID = house.roofs[0].id.rawValue
    let outlines = roofPlan.content.items.filter { item in
        guard item.style == RoofPlanView.roofStyle, item.elementID == roofID, case .polyline = item.primitive else {
            return false
        }
        return true
    }
    #expect(outlines.count == 1)
    let folds = roofPlan.content.items.filter { $0.style == RoofPlanView.lineStyle && $0.elementID == roofID }
    #expect(folds.count == 9)
    let lines = texts(roofPlan)
    let pitchLabels: [String] = lines.filter { $0 == "6:12" }
    #expect(pitchLabels.count == 6)
    #expect(!lines.contains(RoofPlanView.unresolved))
}

@Test func withoutAMeshTheRoofPlanSaysSo() throws {
    let house = try lHouse()
    let sheets = try SchematicDrawingSet().sheets(for: house, geometry: MockGeometryEngine())
    let roofPlan = try #require(sheets.first { $0.number == "A-401" })
    #expect(texts(roofPlan).contains(RoofPlanView.unresolved))
}
