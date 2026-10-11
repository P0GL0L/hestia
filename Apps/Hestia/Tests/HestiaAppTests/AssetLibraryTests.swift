import ATContracts
import Foundation
import Testing
@testable import HestiaApp

/// A library folder with the given `library.json` and empty files at `files`.
private func library(_ json: String, files: [String] = []) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("hestia-library-\(UUID())")
    for file in files {
        let url = root.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(json.utf8).write(to: root.appendingPathComponent("library.json"))
    return root
}

private let goodLibrary = """
{
  "version": 1,
  "surfaces": {
    "wall": {"asset": "painted_plaster_wall", "tile": 3.0, "paint": [0.82, 0.78, 0.71],
             "maps": {"diffuse": "surfaces/plaster/diffuse.jpg", "normal": "surfaces/plaster/normal.jpg"}},
    "lawn": {"asset": "leafy_grass", "tile": 0, "maps": {}}
  },
  "models": {
    "hestia.sofa": {"asset": "Sofa_01", "file": "models/Sofa_01.usdz", "fit": "footprint", "turn": 0,
                    "size": [1.57, 0.8, 0.66]},
    "hestia.bad": {"asset": "Bad", "file": "models/Bad.usdz", "fit": "height", "turn": 0, "size": [1, 0]}
  },
  "sky": {"file": "sky/sky.png", "sunAzimuth": 150, "sunElevation": 47.9}
}
"""

@Suite("Asset library")
struct AssetLibraryTests {
    @Test("A library loads its surfaces, models, and sky, and skips entries that cannot be used")
    func loads() throws {
        let root = try library(goodLibrary, files: ["surfaces/plaster/diffuse.jpg", "surfaces/plaster/normal.jpg",
                                                    "models/Sofa_01.usdz", "sky/sky.png"])
        let loaded = try AssetLibrary.load(root)
        let wall = try #require(loaded.surface(.wall))
        #expect(wall.tile == 3)
        #expect(wall.paint == [0.82, 0.78, 0.71])
        #expect(wall.diffuse?.lastPathComponent == "diffuse.jpg")
        #expect(wall.rough == nil)
        #expect(loaded.surface(.lawn) == nil, "a zero tile is skipped")
        let sofa = try #require(loaded.model("hestia.sofa"))
        #expect(sofa.fit == .footprint)
        #expect(sofa.file.path.hasSuffix("models/Sofa_01.usdz"))
        #expect(loaded.model("hestia.bad") == nil, "a size without three dimensions is skipped")
        #expect(loaded.sky?.sunAzimuth == 150)
    }

    @Test("A library cannot name a file outside its own folder")
    func refusesEscapes() throws {
        let root = try library("{\"version\": 1}")
        for path in ["../outside.jpg", "/etc/passwd", "models/../../outside", "", "models//x", "./x", "a\\b"] {
            #expect(throws: AssetLibrary.LoadError.self, "\(path)") { try AssetLibrary.inside(root, path) }
        }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("hestia-outside-\(UUID())")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        #expect(throws: AssetLibrary.LoadError.self) { try AssetLibrary.inside(root, "link/file.jpg") }
        let escaping = goodLibrary.replacingOccurrences(of: "sky/sky.png", with: "../sky.png")
        #expect(throws: AssetLibrary.LoadError.self) { try AssetLibrary.load(try library(escaping)) }
    }

    @Test("A library of another version or not JSON is refused")
    func refusesOtherVersions() throws {
        #expect(throws: AssetLibrary.LoadError.unsupportedVersion(2)) {
            try AssetLibrary.load(try library("{\"version\": 2}"))
        }
        #expect(throws: AssetLibrary.LoadError.unreadable) { try AssetLibrary.load(try library("not json")) }
    }

    @Test("Models fit by footprint or height")
    func modelFit() {
        let sofa = (x: 1.5, y: 0.8, z: 0.75)
        // A 6 by 3 foot sofa: width allows 4, depth allows 4.
        #expect(abs(ModelFit.scale(fit: .footprint, model: sofa, width: 6, depth: 3, height: 3) - 4) < 1e-9)
        // A narrower item: depth limits.
        #expect(abs(ModelFit.scale(fit: .footprint, model: sofa, width: 6, depth: 1.5, height: 3) - 2) < 1e-9)
        #expect(abs(ModelFit.scale(fit: .height, model: (x: 4, y: 5, z: 4), width: 1, depth: 1, height: 20) - 4)
                < 1e-9)
    }
}

@Suite("Surface mapping")
struct SurfaceMappingTests {
    @Test("A tile covers its size in meters, level along walls and up their face")
    func walls() {
        let tile = 3.0, foot = SurfaceMapping.metersPerFoot
        let east = ScenePoint(1, 0, 0)
        let base = SurfaceMapping.coordinate(ScenePoint(0, 0, 0), normal: east, tile: tile)
        let up = SurfaceMapping.coordinate(ScenePoint(0, 10, 0), normal: east, tile: tile)
        let along = SurfaceMapping.coordinate(ScenePoint(0, 0, -10), normal: east, tile: tile)
        #expect(abs(Double(up.u - base.u)) < 1e-6, "going up a wall keeps u")
        #expect(abs(Double(base.v - up.v) - 10 * foot / tile) < 1e-5, "going up a wall moves v by its height")
        #expect(abs(Double(along.v - base.v)) < 1e-6, "going along a wall keeps v")
        #expect(abs(abs(Double(along.u - base.u)) - 10 * foot / tile) < 1e-5)
        let tangent = SurfaceMapping.tangent(normal: east)
        #expect(tangent == ScenePoint(0, 0, -1))
    }

    @Test("Roof courses run level on every slope, and floors lie east and south")
    func roofsAndFloors() {
        // A slope facing north-east and up.
        let normal = ScenePoint(0.5, 0.7071, -0.5)
        let start = SurfaceMapping.coordinate(ScenePoint(0, 0, 0), normal: normal, tile: 2)
        // Level along this slope: perpendicular to the normal's horizontal part, at the same height.
        let level = SurfaceMapping.coordinate(ScenePoint(5, 0, 5), normal: normal, tile: 2)
        #expect(abs(Double(level.v - start.v)) < 1e-5)
        let floor = SurfaceMapping.coordinate(ScenePoint(10, 0, 20), normal: ScenePoint(0, 1, 0), tile: 1)
        #expect(abs(Double(floor.u) - 10 * SurfaceMapping.metersPerFoot) < 1e-5)
        #expect(abs(Double(floor.v) - 20 * SurfaceMapping.metersPerFoot) < 1e-5)
        #expect(SurfaceMapping.tangent(normal: ScenePoint(0, 1, 0)) == ScenePoint(1, 0, 0))
    }
}

@Suite("Placed models")
struct PlacedModelTests {
    @Test("Items left for library models are placed as models and not drawn as shapes")
    func leaving() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addRectangleRoom(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(20, 15), named: "Living")
        let item = try #require(Furniture.item(CatalogItemID(rawValue: "hestia.sofa")))
        _ = try session.place(item, at: PlanOverlay.point(10, 5), degrees: 0)
        let document = session.model.document
        let drawn = HouseScene(document: document, meshes: session.model.meshes)
        let left = HouseScene(document: document, meshes: session.model.meshes, leaving: ["hestia.sofa"])
        #expect(drawn.models.isEmpty)
        let sofa = try #require(left.models.first)
        #expect(left.models.count == 1)
        #expect(sofa.catalogID == "hestia.sofa")
        #expect(abs(Double(sofa.position.x) - 10) < 0.01 && abs(Double(sofa.position.z) + 5) < 0.01)
        #expect(sofa.width == item.width && sofa.depth == item.depth && sofa.height == item.height)
        let fabric = { (scene: HouseScene) in
            scene.solids.filter { $0.look == .fabric }.map(\.indices.count).reduce(0, +)
        }
        #expect(fabric(left) < fabric(drawn), "the sofa's stand-in shapes are left out")
    }

    @Test("Each room has a ceiling light point at its middle, with its area")
    func roomCeilings() throws {
        var session = EditSession(model: try HestiaModel.blank())
        try session.addRectangleRoom(from: PlanOverlay.point(0, 0), to: PlanOverlay.point(20, 15), named: "Living")
        let ceilings = HouseScene.roomCeilings(session.model.document)
        let room = try #require(ceilings.first)
        #expect(ceilings.count == 1)
        #expect(abs(room.area - 300) < 1)
        #expect(abs(room.reach - 20) < 0.01)
        #expect(abs(Double(room.middle.x) - 10) < 0.01 && abs(Double(room.middle.y) - 8) < 0.01)
        #expect(abs(Double(room.middle.z) + 7.5) < 0.01)
    }
}
