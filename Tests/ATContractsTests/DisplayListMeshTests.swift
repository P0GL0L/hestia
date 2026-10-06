import ATContracts
import Foundation
import Testing

private func mm(_ x: Int64, _ y: Int64) -> Point2 {
    Point2(x: .millimeters(x), y: .millimeters(y))
}

private let wallStyle = DisplayStyle(layer: "A-WALL", pen: .heavy)
private let textStyle = DisplayStyle(layer: "A-ANNO-TEXT", pen: .fine)

private let sampleList = DisplayList(items: [
    DisplayItem(.polyline(points: [mm(0, 0), mm(4000, 0), mm(4000, 200), mm(0, 200)], closed: true),
                style: wallStyle, elementID: UUID(uuidString: "00000000-0000-4000-8000-000000000020")),
    DisplayItem(.hatch(boundary: [mm(0, 0), mm(4000, 0), mm(4000, 200)], pattern: .diagonal,
                       spacing: .millimeters(2), angle: .degrees(45)), style: wallStyle),
    DisplayItem(.arc(center: mm(500, 0), radius: .millimeters(900), start: .degrees(0), sweep: .degrees(90)),
                style: DisplayStyle(layer: "A-DOOR", pen: .thin)),
    DisplayItem(.line(start: mm(0, -500), end: mm(4000, -500)), style: DisplayStyle(layer: "A-ANNO-DIMS")),
    DisplayItem(.dimension(from: mm(0, 0), to: mm(4000, 0), offset: .millimeters(600), override: nil),
                style: DisplayStyle(layer: "A-ANNO-DIMS")),
    DisplayItem(.text(position: mm(2000, 1500), string: "Living", height: .millimeters(3),
                      rotation: .degrees(0), alignment: .center), style: textStyle),
    DisplayItem(.symbol(name: "outlet-duplex", position: mm(100, 300), rotation: .degrees(90),
                        size: .millimeters(4)), style: DisplayStyle(layer: "E-POWR")),
])

@Test func displayListRoundTripsThroughJSON() throws {
    let data = try ModelDocument.makeJSONEncoder().encode(sampleList)
    let decoded = try JSONDecoder().decode(DisplayList.self, from: data)
    #expect(decoded == sampleList)
    #expect(try ModelDocument.makeJSONEncoder().encode(decoded) == data)
}

@Test func displayListReportsLayersInFirstUseOrder() {
    #expect(sampleList.layers == ["A-WALL", "A-DOOR", "A-ANNO-DIMS", "A-ANNO-TEXT", "E-POWR"])
}

@Test func displayListBoundsIncludeArcRadius() throws {
    let bounds = try #require(sampleList.bounds)
    #expect(bounds.min == mm(-400, -900))
    #expect(bounds.max == mm(4000, 1500))
    #expect(DisplayList().bounds == nil)
}

@Test func penWeightsFollowISOSeries() {
    #expect(PenWeight.allCases.map(\.micrometers) == [130, 180, 250, 350, 500, 700, 1000])
}

private func quad(indices: [UInt32] = [0, 1, 2, 0, 2, 3]) -> Mesh {
    let up = Vector3f(x: 0, y: 0, z: 1)
    return Mesh(
        elementID: UUID(uuidString: "00000000-0000-4000-8000-000000000050"),
        materialID: MaterialID("floor-oak"),
        positions: [mm(0, 0), mm(1000, 0), mm(1000, 1000), mm(0, 1000)]
            .map { Point3(x: $0.x, y: $0.y, z: .millimeters(0)) },
        normals: Array(repeating: up, count: 4),
        uvs: [TextureCoordinate(u: 0, v: 0), TextureCoordinate(u: 1, v: 0),
              TextureCoordinate(u: 1, v: 1), TextureCoordinate(u: 0, v: 1)],
        indices: indices
    )
}

@Test func meshValidatesAndRoundTrips() throws {
    let mesh = quad()
    try mesh.validate()
    #expect(mesh.triangleCount == 2)
    let data = try ModelDocument.makeJSONEncoder().encode(mesh)
    #expect(try JSONDecoder().decode(Mesh.self, from: data) == mesh)
    #expect(String(decoding: data, as: UTF8.self).contains(#""materialID" : "floor-oak""#))
}

@Test func malformedMeshesAreRejected() {
    #expect(throws: MeshError.indicesNotTriangles) { try quad(indices: [0, 1]).validate() }
    #expect(throws: MeshError.indexOutOfRange(4)) { try quad(indices: [0, 1, 4]).validate() }
    var missingNormal = quad()
    missingNormal.normals.removeLast()
    #expect(throws: MeshError.attributeCountMismatch) { try missingNormal.validate() }
}
