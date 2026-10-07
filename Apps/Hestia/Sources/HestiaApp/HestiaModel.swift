import ATContracts
import ATDrawings
import ATExchange
import ATGeometry
import Foundation

/// What the window shows: a model document and everything drawn from it through the geometry engine.
struct HestiaModel {
    let document: ModelDocument
    /// The schematic set, as exported to PDF.
    let sheets: [SheetDrawing]
    /// The 3D model, in absolute elevations.
    let meshes: [Mesh]
    /// The ground floor plan's walls, openings, stairs, and room tags, in sheet paper space.
    let plan: [DisplayItem]

    /// Layers of a floor plan sheet that make up the plan itself, without dimensions or the sheet frame.
    static let planLayers: Set<String> = [
        "A-WALL", "A-WALL-PATT", "A-DOOR", "A-GLAZ", "A-FLOR-STRS", "A-FLOR-OPNG", "A-AREA-IDEN",
    ]

    init(document: ModelDocument, issueDate: String? = HestiaModel.today()) throws {
        let engine = HestiaGeometryEngine()
        self.document = document
        sheets = try SchematicDrawingSet(issueDate: issueDate).sheets(for: document, geometry: engine)
        meshes = try engine.meshes(of: document)
        // The first sheet carrying wall outlines is the ground floor plan.
        let planSheet = sheets.first { sheet in sheet.content.items.contains { $0.style.layer == "A-WALL" } }
        plan = planSheet?.content.items.filter { Self.planLayers.contains($0.style.layer) } ?? []
    }

    /// The cottage fixture, from the app bundle or, when run from the repository, its fixtures folder.
    static func cottage() throws -> HestiaModel {
        guard let url = fixtureURL(named: "rect-cottage") else {
            throw LoadError(message: "rect-cottage.json was not found in the app or the repository's fixtures.")
        }
        return try HestiaModel(document: ModelDocument.decode(from: Data(contentsOf: url)))
    }

    static func fixtureURL(named name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "json") { return url }
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        var directory = executable.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("fixtures").appendingPathComponent("\(name).json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    /// The whole schematic set as one PDF, a page per sheet, at true scale.
    func pdf() throws -> Data {
        try SheetPDFExporter().export(.sheets(sheets))
    }

    /// The ground floor's joined wall outlines as ASCII DXF, with the schematic stamp, in the project's units.
    func dxf() throws -> Data {
        guard let ground = document.storeys.min(by: { $0.elevation.ticks < $1.elevation.ticks }) else {
            throw LoadError(message: "The model has no storey to export.")
        }
        let walls = document.walls.filter { $0.storeyID == ground.id }
        let footprints = try WallFootprints().footprints(for: walls)
        let outlines = footprints.mapValues { ClosedPolygon2(vertices: $0) }
        let units: DXFDrawingUnits = document.project.displayUnits == .metric ? .millimeters : .inches
        let text = try SchematicWallOutlineDXF.export(outlines: outlines, walls: walls, units: units)
        return Data(text.utf8)
    }

    static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    struct LoadError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }
}
