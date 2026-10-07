import ATContracts
import ATDrawings
import ATExchange
import ATGeometry
import Foundation

/// What the window shows: a model document and everything drawn from it through the geometry engine.
struct HestiaModel {
    let document: ModelDocument
    /// Printed in each sheet's title block; kept for the session so exports of one model always match.
    let issueDate: String?
    /// The schematic set, as exported to PDF.
    let sheets: [SheetDrawing]
    /// The 3D model, in absolute elevations.
    let meshes: [Mesh]
    /// The storey the plan shows: the lowest.
    let groundStorey: StoreyID?
    /// The ground floor plan's walls, openings, stairs, and room tags, in sheet paper space.
    let plan: [DisplayItem]
    /// How that plan was placed on its sheet, to take paper points back into the model.
    let planTransform: ViewTransform?

    /// Layers of a floor plan sheet that make up the plan itself, without dimensions or the sheet frame.
    static let planLayers: Set<String> = [
        "A-WALL", "A-WALL-PATT", "A-DOOR", "A-GLAZ", "A-FLOR-STRS", "A-FLOR-OPNG", "A-AREA-IDEN",
    ]

    init(document: ModelDocument, issueDate: String? = HestiaModel.today()) throws {
        let engine = HestiaGeometryEngine()
        let drawingSet = SchematicDrawingSet(issueDate: issueDate)
        self.document = document
        self.issueDate = issueDate
        sheets = try drawingSet.sheets(for: document, geometry: engine)
        meshes = try engine.meshes(of: document)
        let ground = document.storeys.min { $0.elevation.ticks < $1.elevation.ticks }
        groundStorey = ground?.id
        planTransform = ground.flatMap { drawingSet.planTransform(for: document, storey: $0.id) }
        // The ground plan's sheet: the model's own sheet for it, or the drawing set's default first plan sheet.
        let number = ground.flatMap { storey in
            document.sheets.first { $0.views.contains(.floorPlan(storeyID: storey.id)) }?.number
        } ?? "A-101"
        let planSheet = sheets.first { $0.number == number }
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

    /// The model point under a point of the plan sheet's paper, or nil when there is no plan.
    func modelPoint(paper: Point2) -> Point2? {
        planTransform?.model(paper)
    }

    /// A straight wall on the ground storey from one model point to another, with a new ID, as thick and as
    /// tall as an exterior wall on that storey (one with layers, else the thickest).
    func wallCommand(from start: Point2, to end: Point2, id: WallID = WallID(UUID())) throws -> AddWallCommand {
        guard let storey = groundStorey else { throw LoadError(message: "The model has no storey to draw on.") }
        let walls = document.walls.filter { $0.storeyID == storey }
        let exterior = walls.first { !$0.layers.isEmpty } ?? walls.max { $0.thickness.ticks < $1.thickness.ticks }
        guard let template = exterior else {
            throw LoadError(message: "The ground storey has no wall to take a thickness and height from.")
        }
        return AddWallCommand(wallID: id, storeyID: storey, start: start, end: end, thickness: template.thickness,
                              height: template.height)
    }

    /// The whole schematic set as one PDF, a page per sheet, at true scale.
    func pdf() throws -> Data {
        try SheetPDFExporter().export(.sheets(sheets))
    }

    /// The ground floor's joined wall outlines as ASCII DXF, with the schematic stamp, in the project's units.
    func dxf() throws -> Data {
        guard let storey = groundStorey else {
            throw LoadError(message: "The model has no storey to export.")
        }
        let walls = document.walls.filter { $0.storeyID == storey }
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

/// The model being edited, with the inverse of every change so far for undo.
struct EditSession {
    private(set) var model: HestiaModel
    private(set) var undoStack: [AnyCommand] = []

    init(model: HestiaModel) {
        self.model = model
    }

    var canUndo: Bool { !undoStack.isEmpty }

    /// Adds a wall between two points of the plan sheet's paper, taken back into the model.
    mutating func addWall(fromPaper start: Point2, toPaper end: Point2) throws {
        guard let a = model.modelPoint(paper: start), let b = model.modelPoint(paper: end) else {
            throw HestiaModel.LoadError(message: "The plan has no placement to draw on.")
        }
        try perform(model.wallCommand(from: a, to: b).erased)
    }

    /// Applies a command, keeping its inverse.
    mutating func perform(_ command: AnyCommand) throws {
        var document = model.document
        let inverse = try document.perform(command)
        model = try HestiaModel(document: document, issueDate: model.issueDate)
        undoStack.append(inverse)
    }

    /// Applies the inverse of the last change.
    mutating func undo() throws {
        guard let inverse = undoStack.last else { return }
        var document = model.document
        _ = try document.perform(inverse)
        model = try HestiaModel(document: document, issueDate: model.issueDate)
        undoStack.removeLast()
    }
}
