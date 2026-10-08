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
    /// How that plan was placed on its sheet, to take paper points back into the model. A ground storey with no
    /// walls has no drawn plan to place, so it gets the blank placement instead, and the first wall can be drawn.
    let planTransform: ViewTransform?
    /// The paper the plan view shows: the drawn plan's extent, or the blank area when the storey has no walls.
    let planBounds: (min: Point2, max: Point2)?

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
        let placed = ground.flatMap { drawingSet.planTransform(for: document, storey: $0.id) }
        let empty = ground.map { storey in !document.walls.contains { $0.storeyID == storey.id } } ?? false
        planTransform = placed ?? (empty ? Self.blankTransform : nil)
        // The ground plan's sheet: the model's own sheet for it, or the drawing set's default first plan sheet.
        let number = ground.flatMap { storey in
            document.sheets.first { $0.views.contains(.floorPlan(storeyID: storey.id)) }?.number
        } ?? "A-101"
        let planSheet = sheets.first { $0.number == number }
        plan = planSheet?.content.items.filter { Self.planLayers.contains($0.style.layer) } ?? []
        if let drawn = DisplayList(items: plan).bounds {
            planBounds = drawn
        } else if placed == nil && empty {
            planBounds = Self.blankArea
        } else {
            planBounds = nil
        }
    }

    /// A new model: one building with one ground storey at elevation zero, no walls, and no display units, so
    /// lengths read in feet and inches.
    static func blank() throws -> HestiaModel {
        var document = ModelDocument(schemaVersion: 1, project: Project(id: ProjectID(UUID()), name: "Untitled"),
                                     buildings: [], storeys: [], walls: [], openings: [], rooms: [])
        let building = BuildingID(UUID())
        let commands: [AnyCommand] = [
            AddBuildingCommand(buildingID: building, name: "Building").erased,
            AddStoreyCommand(storeyID: StoreyID(UUID()), buildingID: building, name: "Ground Floor",
                             elevation: .millimeters(0)).erased,
        ]
        _ = try document.perform(batch: commands)
        return try HestiaModel(document: document)
    }

    /// Where an empty ground storey is drawn on: model zero at paper zero, at 1/4" = 1'-0".
    static let blankTransform = ViewTransform(scale: .quarterInch, modelOrigin: Point2(x: .feet(0), y: .feet(0)),
                                              paperOrigin: Point2(x: .feet(0), y: .feet(0)))

    /// The paper an empty plan shows: 60' by 40' of the model through the blank placement, from model zero.
    static let blankArea: (min: Point2, max: Point2) = (
        min: blankTransform.paper(Point2(x: .feet(0), y: .feet(0))),
        max: blankTransform.paper(Point2(x: .feet(60), y: .feet(40)))
    )

    /// An exterior wall's size when the storey has none to copy: the cottage's, 6" thick and 8'-0" high.
    static let defaultWallThickness: Length = .inches(6)
    static let defaultWallHeight: Length = .feet(8)

    /// The cottage roof's pitch and overhang.
    static let defaultRoofPitch: Length = .inches(6)
    static let defaultRoofOverhang: Length = .feet(1)

    /// A window's size when the storey has none to copy: the cottage's common window.
    static let defaultWindowWidth: Length = .feet(4)
    static let defaultWindowHeight: Length = .feet(4)
    static let defaultWindowSill: Length = .feet(3)

    /// A cased opening's size when the storey has none to copy.
    static let defaultCasedWidth: Length = .feet(3)
    static let defaultCasedHeight: Length = .feet(6, inchCount: 8)
    static let defaultCasedSill: Length = .feet(0)

    /// A door's size when the storey has none to copy: the cottage's single door.
    static let defaultDoorWidth: Length = .feet(3)
    static let defaultDoorHeight: Length = .feet(6, inchCount: 8)
    static let defaultDoorSill: Length = .feet(0)

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

    /// The grid a clicked wall end lands on: 10 mm on a metric project, else 1 inch.
    var snapStep: Length {
        document.project.displayUnits == .metric ? .millimeters(10) : .inches(1)
    }

    /// A model point moved to the nearest point of the snap grid, halves rounding away from zero.
    func snapped(_ point: Point2) -> Point2 {
        Point2(x: Self.snap(point.x, to: snapStep), y: Self.snap(point.y, to: snapStep))
    }

    static func snap(_ length: Length, to step: Length) -> Length {
        let half: Int64 = step.ticks / 2
        let shifted: Int64 = length.ticks >= 0 ? length.ticks + half : length.ticks - half
        return Length(ticks: shifted / step.ticks * step.ticks)
    }

    /// A straight wall on the ground storey from one model point to another, with a new ID, as thick and as
    /// tall as an exterior wall on that storey (one with layers, else the thickest). On a storey with no walls
    /// it takes the default exterior size.
    func wallCommand(from start: Point2, to end: Point2, id: WallID = WallID(UUID())) throws -> AddWallCommand {
        guard let storey = groundStorey else { throw LoadError(message: "The model has no storey to draw on.") }
        let walls = document.walls.filter { $0.storeyID == storey }
        let exterior = walls.first { !$0.layers.isEmpty } ?? walls.max { $0.thickness.ticks < $1.thickness.ticks }
        return AddWallCommand(wallID: id, storeyID: storey, start: start, end: end,
                              thickness: exterior?.thickness ?? Self.defaultWallThickness,
                              height: exterior?.height ?? Self.defaultWallHeight)
    }

    /// What a point of the plan sheet's paper lands on: the drawn wall outlines that contain it.
    enum WallHit: Equatable {
        case none
        case wall(WallID)
        /// Inside more than one wall's outline, as where walls cross: which one is meant cannot be told.
        case ambiguous([WallID])
    }

    func wallHit(paper: Point2) -> WallHit {
        var hits: [WallID] = []
        for item in plan where item.style.layer == "A-WALL" {
            guard case let .polyline(points, true) = item.primitive, let id = item.elementID,
                  Self.contains(points, paper) else { continue }
            let wall = WallID(id)
            if !hits.contains(wall) { hits.append(wall) }
        }
        switch hits.count {
        case 0: return .none
        case 1: return .wall(hits[0])
        default: return .ambiguous(hits)
        }
    }

    /// A room on the ground storey with a new ID, the given name and boundary walls, and no finishes.
    func roomCommand(named name: String, walls: [WallID], id: RoomID = RoomID(UUID())) throws -> AddRoomCommand {
        guard let storey = groundStorey else { throw LoadError(message: "The model has no storey to put a room on.") }
        return AddRoomCommand(roomID: id, storeyID: storey, name: name, boundaryWallIDs: walls)
    }

    /// An error as a status line: its own description when it has one, else the refusal it names.
    static func describe(_ error: Error) -> String {
        if let described = (error as? LocalizedError)?.errorDescription { return described }
        return "Refused: \(error)"
    }

    /// A hip roof over the ground storey's wall line, as on the cottage: 6" in 12 on every edge, a 1'-0"
    /// overhang, and its eave at the walls' height. Only when the ground walls close one rectangle, square to
    /// the axes: the walls lying on the four sides of the box around all the ground walls must cover those sides
    /// end to end (walls inside it are fine, so an L, whose box has open sides, is refused). The footprint is the
    /// rectangle's corners at the wall centerlines, counterclockwise. Refused when the storey has a roof already,
    /// or when the walls on the sides are not all one height.
    func roofCommand(id: RoofID = RoofID(UUID())) throws -> AddRoofCommand {
        guard let storey = groundStorey else { throw LoadError(message: "The model has no storey to roof.") }
        if document.roofs.contains(where: { $0.storeyID == storey }) {
            throw LoadError(message: "The ground storey already has a roof, so no other is added.")
        }
        let walls = document.walls.filter { $0.storeyID == storey }
        let refusal = LoadError(message: "The ground walls do not close one rectangle, so there is no roof to add.")
        let xs: [Int64] = walls.flatMap { [$0.start.x.ticks, $0.end.x.ticks] }
        let ys: [Int64] = walls.flatMap { [$0.start.y.ticks, $0.end.y.ticks] }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max(), x1 > x0, y1 > y0 else {
            throw refusal
        }
        var sides: [Wall] = []
        // Each side as the walls on its line, their spans along it, and the span it must cover.
        let lines: [(onLine: (Wall) -> Bool, span: (Wall) -> (Int64, Int64), from: Int64, to: Int64)] = [
            ({ $0.start.y.ticks == y0 && $0.end.y.ticks == y0 }, { ($0.start.x.ticks, $0.end.x.ticks) }, x0, x1),
            ({ $0.start.x.ticks == x1 && $0.end.x.ticks == x1 }, { ($0.start.y.ticks, $0.end.y.ticks) }, y0, y1),
            ({ $0.start.y.ticks == y1 && $0.end.y.ticks == y1 }, { ($0.start.x.ticks, $0.end.x.ticks) }, x0, x1),
            ({ $0.start.x.ticks == x0 && $0.end.x.ticks == x0 }, { ($0.start.y.ticks, $0.end.y.ticks) }, y0, y1),
        ]
        for line in lines {
            let on = walls.filter(line.onLine)
            let spans = on.map(line.span).map { (min($0.0, $0.1), max($0.0, $0.1)) }.sorted { $0.0 < $1.0 }
            var reached: Int64 = line.from
            for span in spans where span.0 <= reached {
                reached = max(reached, span.1)
            }
            guard reached >= line.to else { throw refusal }
            sides += on
        }
        let heights = Set(sides.map(\.height))
        guard heights.count == 1, let height = heights.first else {
            throw LoadError(message: "The walls around the rectangle are not all one height, so the eave is not set.")
        }
        let footprint: [Point2] = [
            Point2(x: Length(ticks: x0), y: Length(ticks: y0)), Point2(x: Length(ticks: x1), y: Length(ticks: y0)),
            Point2(x: Length(ticks: x1), y: Length(ticks: y1)), Point2(x: Length(ticks: x0), y: Length(ticks: y1)),
        ]
        return AddRoofCommand(roofID: id, storeyID: storey, footprint: footprint, eaveHeight: height,
                              pitchRisePer12: Self.defaultRoofPitch, overhang: Self.defaultRoofOverhang)
    }

    /// A window in a wall, centered on a model point projected onto the wall's centerline, with a new ID. Its
    /// width, height, and sill come from a window already on that storey, or, with none to copy, the cottage's
    /// common window: 4'-0" by 4'-0" with a 3'-0" sill. It has no swing. The offset is rounded to a whole inch,
    /// or 10 mm on a metric project, and kept within the wall.
    func windowCommand(on wallID: WallID, at point: Point2, id: OpeningID = OpeningID(UUID())) throws -> AddOpeningCommand {
        try unswungCommand(on: wallID, at: point, id: id, kind: .window, copies: { $0.isWindow }, name: "window",
                           defaults: (Self.defaultWindowWidth, Self.defaultWindowHeight, Self.defaultWindowSill))
    }

    /// A cased opening (no door, no glass) in a wall, centered on a model point projected onto the wall's
    /// centerline, with a new ID. Its width, height, and sill come from a cased opening already on that storey,
    /// or, with none to copy, 3'-0" by 6'-8" on the floor. It has no swing. The offset is rounded as a window's.
    func casedOpeningCommand(on wallID: WallID, at point: Point2, id: OpeningID = OpeningID(UUID())) throws
        -> AddOpeningCommand {
        try unswungCommand(on: wallID, at: point, id: id, kind: .casedOpening, copies: { $0 == .casedOpening },
                           name: "cased opening",
                           defaults: (Self.defaultCasedWidth, Self.defaultCasedHeight, Self.defaultCasedSill))
    }

    /// An opening with no swing, centered on the click: sized from the first opening on the storey whose kind
    /// `copies` accepts, else from `defaults`; its offset is rounded to the snap step and kept within the wall.
    private func unswungCommand(
        on wallID: WallID, at point: Point2, id: OpeningID, kind: OpeningKind, copies: (OpeningKind) -> Bool,
        name: String, defaults: (width: Length, height: Length, sill: Length)
    ) throws -> AddOpeningCommand {
        guard let wall = document.walls.first(where: { $0.id == wallID }) else {
            throw LoadError(message: "That wall is not in the model.")
        }
        let storeyWalls = Set(document.walls.filter { $0.storeyID == wall.storeyID }.map(\.id))
        let copied = document.openings.first { copies($0.kind) && storeyWalls.contains($0.wallID) }
        let width: Length = copied?.width ?? defaults.width
        let height: Length = copied?.height ?? defaults.height
        let sill: Length = copied?.sillHeight ?? defaults.sill
        let sx = Double(wall.start.x.ticks), sy = Double(wall.start.y.ticks)
        let dx = Double(wall.end.x.ticks) - sx, dy = Double(wall.end.y.ticks) - sy
        let length: Double = (dx * dx + dy * dy).squareRoot()
        let span = Double(width.ticks)
        guard length > span else { throw LoadError(message: "That wall is shorter than a \(name).") }
        let along: Double = ((Double(point.x.ticks) - sx) * dx + (Double(point.y.ticks) - sy) * dy) / length
        let step = Double(snapStep.ticks)
        let offset: Double = min(max(((along - span / 2) / step).rounded() * step, 0), length - span)
        return AddOpeningCommand(openingID: id, wallID: wallID, offsetAlongWall: Length(ticks: Int64(offset)),
                                 width: width, height: height, sillHeight: sill, kind: kind, swing: nil)
    }

    /// A single door in a wall, centered on a model point projected onto the wall's centerline, with a new ID.
    /// Its width, height, and sill come from a door already on that storey, or, with none to copy, the cottage's
    /// single door: 3'-0" by 6'-8" on the floor. It hinges at the start-side jamb
    /// and swings to whichever side of the wall its open leaf lands on the floor. A storey with no floor to
    /// test against (no slab, and walls that enclose no area, as with a first lone wall) swings it left. The
    /// offset is rounded to a whole inch, or 10 mm on a metric project.
    func doorCommand(on wallID: WallID, at point: Point2, id: OpeningID = OpeningID(UUID())) throws -> AddOpeningCommand {
        guard let wall = document.walls.first(where: { $0.id == wallID }) else {
            throw LoadError(message: "That wall is not in the model.")
        }
        let storeyWalls = Set(document.walls.filter { $0.storeyID == wall.storeyID }.map(\.id))
        let copied = document.openings.first { $0.kind.isDoor && storeyWalls.contains($0.wallID) }
        let doorWidth: Length = copied?.width ?? Self.defaultDoorWidth
        let doorHeight: Length = copied?.height ?? Self.defaultDoorHeight
        let doorSill: Length = copied?.sillHeight ?? Self.defaultDoorSill
        let sx = Double(wall.start.x.ticks), sy = Double(wall.start.y.ticks)
        let dx = Double(wall.end.x.ticks) - sx, dy = Double(wall.end.y.ticks) - sy
        let length: Double = (dx * dx + dy * dy).squareRoot()
        let width = Double(doorWidth.ticks)
        guard length > width else { throw LoadError(message: "That wall is shorter than a door.") }
        let (ux, uy) = (dx / length, dy / length)
        let along: Double = (Double(point.x.ticks) - sx) * ux + (Double(point.y.ticks) - sy) * uy
        let step = Double(document.project.displayUnits == .metric ? Length.millimeters(10).ticks : Length.inches(1).ticks)
        let offset: Double = min(max(((along - width / 2) / step).rounded() * step, 0), length - width)
        // The open leaf's tip, a door's width out from the wall face at the door's middle.
        let middle: Double = offset + width / 2
        let reach: Double = Double(wall.thickness.ticks) / 2 + width
        func tip(_ side: Double) -> Point2 {
            let x: Double = sx + ux * middle - uy * reach * side
            let y: Double = sy + uy * middle + ux * reach * side
            return Point2(x: Length(ticks: Int64(x.rounded())), y: Length(ticks: Int64(y.rounded())))
        }
        let side: DoorSwing.Side
        if onFloor(tip(1), storey: wall.storeyID) {
            side = .left
        } else if onFloor(tip(-1), storey: wall.storeyID) {
            side = .right
        } else if !hasFloor(storey: wall.storeyID) {
            side = .left
        } else {
            throw LoadError(message: "Neither side of that wall is inside the building.")
        }
        return AddOpeningCommand(openingID: id, wallID: wallID, offsetAlongWall: Length(ticks: Int64(offset)),
                                 width: doorWidth, height: doorHeight, sillHeight: doorSill,
                                 kind: .singleDoor, swing: DoorSwing(hinge: .nearStart, opensToward: side))
    }

    /// The door a point of the plan sheet's paper lands on: inside the gap between its jambs, or within 2 mm
    /// on paper of its drawn symbol (jambs, leaf, and swing). Nil when it lands on no door.
    func doorHit(paper: Point2) -> OpeningID? {
        guard let transform = planTransform, let storey = groundStorey else { return nil }
        let walls = Dictionary(uniqueKeysWithValues: document.walls.filter { $0.storeyID == storey }.map { ($0.id, $0) })
        let reach = Double(Length.millimeters(2).ticks)
        for opening in document.openings where opening.kind.isDoor {
            guard let wall = walls[opening.wallID] else { continue }
            if Self.contains(gap(opening, in: wall).map(transform.paper), paper) { return opening.id }
            let symbol = plan.filter { $0.style.layer == "A-DOOR" && $0.elementID == opening.id.rawValue }
            if symbol.contains(where: { Self.distance(from: paper, to: $0.primitive) <= reach }) { return opening.id }
        }
        return nil
    }

    /// The opening's gap through its wall in model space: its width along the wall, the wall's thickness across.
    func gap(_ opening: Opening, in wall: Wall) -> [Point2] {
        let sx = Double(wall.start.x.ticks), sy = Double(wall.start.y.ticks)
        let dx = Double(wall.end.x.ticks) - sx, dy = Double(wall.end.y.ticks) - sy
        let length: Double = max((dx * dx + dy * dy).squareRoot(), 1)
        let (ux, uy) = (dx / length, dy / length)
        let half = Double(wall.thickness.ticks) / 2
        let a = Double(opening.offsetAlongWall.ticks), b = a + Double(opening.width.ticks)
        func at(_ along: Double, _ across: Double) -> Point2 {
            let x: Double = sx + ux * along - uy * across
            let y: Double = sy + uy * along + ux * across
            return Point2(x: Length(ticks: Int64(x.rounded())), y: Length(ticks: Int64(y.rounded())))
        }
        return [at(a, -half), at(b, -half), at(b, half), at(a, half)]
    }

    /// Distance on paper from a point to a drawn line, polyline, or arc; infinite for anything else.
    static func distance(from point: Point2, to primitive: DisplayPrimitive) -> Double {
        let px = Double(point.x.ticks), py = Double(point.y.ticks)
        func segment(_ a: Point2, _ b: Point2) -> Double {
            let ax = Double(a.x.ticks), ay = Double(a.y.ticks)
            let dx = Double(b.x.ticks) - ax, dy = Double(b.y.ticks) - ay
            let lengthSquared: Double = dx * dx + dy * dy
            let t: Double = lengthSquared > 0 ? max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSquared)) : 0
            return hypot(px - (ax + dx * t), py - (ay + dy * t))
        }
        switch primitive {
        case let .line(start, end):
            return segment(start, end)
        case let .polyline(points, closed):
            var pairs = Array(zip(points, points.dropFirst()))
            if closed, let first = points.first, let last = points.last { pairs.append((last, first)) }
            return pairs.map { segment($0.0, $0.1) }.min() ?? .infinity
        case let .arc(center, radius, start, sweep):
            let cx = Double(center.x.ticks), cy = Double(center.y.ticks), r = Double(radius.ticks)
            let a0 = Double(start.microDegrees) / 1_000_000 * .pi / 180
            let sweepRadians = Double(sweep.microDegrees) / 1_000_000 * .pi / 180
            // Within the swept angle, the distance to the circle; otherwise to the nearer end.
            var angle: Double = atan2(py - cy, px - cx) - (sweepRadians >= 0 ? a0 : a0 + sweepRadians)
            while angle < 0 { angle += 2 * .pi }
            while angle >= 2 * .pi { angle -= 2 * .pi }
            if angle <= abs(sweepRadians) { return abs(hypot(px - cx, py - cy) - r) }
            let ends = [a0, a0 + sweepRadians].map { hypot(px - (cx + r * cos($0)), py - (cy + r * sin($0))) }
            return ends.min()!
        default:
            return .infinity
        }
    }

    /// Why a wall cannot be removed yet: its openings and the rooms it bounds.
    func dependents(of wallID: WallID) -> String {
        let openings = document.openings.filter { $0.wallID == wallID }.count
        let rooms = document.rooms.filter { $0.boundaryWallIDs.contains(wallID) }.map(\.name)
        var reasons: [String] = []
        if openings > 0 { reasons.append(openings == 1 ? "has 1 opening" : "has \(openings) openings") }
        if !rooms.isEmpty { reasons.append("bounds " + rooms.joined(separator: ", ")) }
        return reasons.joined(separator: " and ")
    }

    /// Whether a plan point is over the storey's floor: inside one of its slabs, or, with no slab, inside the box
    /// around its walls.
    func onFloor(_ point: Point2, storey: StoreyID) -> Bool {
        let slabs = document.slabs.filter { $0.storeyID == storey }
        if !slabs.isEmpty {
            return slabs.contains { Self.contains($0.outline, point) }
        }
        guard let box = wallBox(storey: storey) else { return false }
        return point.x.ticks > box.x0 && point.x.ticks < box.x1 && point.y.ticks > box.y0 && point.y.ticks < box.y1
    }

    /// Whether the storey has a floor to test a swing against: a slab, or walls whose box has an area.
    func hasFloor(storey: StoreyID) -> Bool {
        if document.slabs.contains(where: { $0.storeyID == storey }) { return true }
        guard let box = wallBox(storey: storey) else { return false }
        return box.x1 > box.x0 && box.y1 > box.y0
    }

    /// The box around the ends of the storey's walls, or nil with no walls.
    private func wallBox(storey: StoreyID) -> (x0: Int64, x1: Int64, y0: Int64, y1: Int64)? {
        let ends: [Point2] = document.walls.filter { $0.storeyID == storey }.flatMap { [$0.start, $0.end] }
        let xs: [Int64] = ends.map(\.x.ticks)
        let ys: [Int64] = ends.map(\.y.ticks)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
        return (x0, x1, y0, y1)
    }

    /// Whether a point lies inside a polygon, by ray casting.
    static func contains(_ polygon: [Point2], _ point: Point2) -> Bool {
        let px = Double(point.x.ticks), py = Double(point.y.ticks)
        var inside = false
        for (a, b) in zip(polygon, polygon.dropFirst() + polygon.prefix(1)) {
            let ay = Double(a.y.ticks), by = Double(b.y.ticks)
            guard (ay > py) != (by > py) else { continue }
            let ax = Double(a.x.ticks), bx = Double(b.x.ticks)
            let x: Double = ax + (py - ay) / (by - ay) * (bx - ax)
            if px < x { inside.toggle() }
        }
        return inside
    }

    /// The model document as saved: its JSON, nothing more. The undo history is not part of it.
    func saveData() throws -> Data {
        try document.encodeToJSONData()
    }

    /// A model opened from saved JSON, drawn afresh through the geometry engine.
    static func open(_ data: Data) throws -> HestiaModel {
        let document: ModelDocument
        do {
            document = try ModelDocument.decode(from: data)
        } catch {
            throw LoadError(message: "That file is not a Hestia model: \(error.localizedDescription)")
        }
        return try HestiaModel(document: document)
    }

    /// The whole schematic set as one PDF, a page per sheet, at true scale.
    func pdf() throws -> Data {
        try SheetPDFExporter().export(.sheets(sheets))
    }

    /// The ground floor plan as ASCII DXF, with the schematic stamp, in the project's units: the plan's walls,
    /// doors and swings, windows, stairs, and room tags, taken back from the sheet into the model so a length in
    /// the file is the length in the model. Hatches have no DXF entity here and are left out by the writer.
    func dxf() throws -> Data {
        guard groundStorey != nil, planTransform != nil else {
            throw LoadError(message: "The model has no placed ground floor plan to export.")
        }
        guard !plan.isEmpty else {
            throw LoadError(message: "The ground floor has nothing drawn to export. Add a wall first.")
        }
        let units: DXFDrawingUnits = document.project.displayUnits == .metric ? .millimeters : .inches
        let text = try DisplayListDXF.export(DisplayList(items: modelPlan()), units: units)
        return Data(text.utf8)
    }

    /// The ground floor plan in model space: each plan item taken back through the plan's placement on its
    /// sheet. Paper points come back exactly onto the scale's model grid, a fraction of a millimetre at most
    /// from where the model put them. Text heights are scaled with the drawing too, so a room tag in the file
    /// reads at its printed size when the file is plotted at the plan's scale. Without a placement there is no
    /// plan to take back, and the result is empty.
    func modelPlan() -> [DisplayItem] {
        guard let transform = planTransform else { return [] }
        return plan.map { Self.model($0, through: transform) }
    }

    /// One paper-space item in model space. The placement is a uniform scale and a shift with y up on both
    /// sides, so every item inverts: angles are kept and lengths grow by the scale's ratio.
    static func model(_ item: DisplayItem, through transform: ViewTransform) -> DisplayItem {
        let ratio: Int64 = transform.scale.modelUnitsPerPaperUnit
        func grow(_ length: Length) -> Length { Length(ticks: length.ticks * ratio) }
        let primitive: DisplayPrimitive
        switch item.primitive {
        case let .line(start, end):
            primitive = .line(start: transform.model(start), end: transform.model(end))
        case let .polyline(points, closed):
            primitive = .polyline(points: points.map { transform.model($0) }, closed: closed)
        case let .arc(center, radius, start, sweep):
            primitive = .arc(center: transform.model(center), radius: grow(radius), start: start, sweep: sweep)
        case let .text(position, string, height, rotation, alignment):
            primitive = .text(position: transform.model(position), string: string, height: grow(height),
                              rotation: rotation, alignment: alignment)
        case let .hatch(boundary, pattern, spacing, angle):
            primitive = .hatch(boundary: boundary.map { transform.model($0) }, pattern: pattern,
                               spacing: grow(spacing), angle: angle)
        case let .dimension(from, to, offset, override):
            primitive = .dimension(from: transform.model(from), to: transform.model(to), offset: grow(offset),
                                   override: override)
        case let .symbol(name, position, rotation, size):
            primitive = .symbol(name: name, position: transform.model(position), rotation: rotation,
                                size: grow(size))
        }
        return DisplayItem(primitive, style: item.style, elementID: item.elementID)
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
    /// Which session this is. Edits and undo keep it; New and Open start a session with a new one, so a view
    /// can tell a changed model from an edited one.
    let id = UUID()

    init(model: HestiaModel) {
        self.model = model
    }

    var canUndo: Bool { !undoStack.isEmpty }

    /// Adds a wall between two points of the plan sheet's paper, taken back into the model.
    /// Each end is snapped to the project's grid, so a clicked wall measures in whole inches (or 10 mm).
    mutating func addWall(fromPaper start: Point2, toPaper end: Point2) throws {
        guard let a = model.modelPoint(paper: start), let b = model.modelPoint(paper: end) else {
            throw HestiaModel.LoadError(message: "The plan has no placement to draw on.")
        }
        let from = model.snapped(a), to = model.snapped(b)
        guard from != to else {
            throw HestiaModel.LoadError(message: "Both ends snap to the same point. Click farther apart.")
        }
        try perform(model.wallCommand(from: from, to: to).erased)
    }

    /// Adds a single door where a point of the plan sheet's paper falls on a drawn wall. A point off every wall
    /// does nothing and returns false; a point on more than one wall is refused.
    mutating func addDoor(atPaper paper: Point2) throws -> Bool {
        switch model.wallHit(paper: paper) {
        case .none:
            return false
        case .ambiguous:
            throw HestiaModel.LoadError(message: "That point is on more than one wall. Click clear of the crossing.")
        case let .wall(id):
            guard let point = model.modelPoint(paper: paper) else {
                throw HestiaModel.LoadError(message: "The plan has no placement to draw on.")
            }
            try perform(model.doorCommand(on: id, at: point).erased)
            return true
        }
    }

    /// Adds a hip roof over the ground walls when they close one rectangle.
    mutating func addRoof() throws {
        try perform(model.roofCommand().erased)
    }

    /// Adds a single window where a point of the plan sheet's paper falls on a drawn wall. A point off every
    /// wall does nothing and returns false; a point on more than one wall is refused.
    mutating func addWindow(atPaper paper: Point2) throws -> Bool {
        try addOnWall(atPaper: paper) { model, id, point in try model.windowCommand(on: id, at: point) }
    }

    /// Adds a single cased opening where a point of the plan sheet's paper falls on a drawn wall. A point off
    /// every wall does nothing and returns false; a point on more than one wall is refused.
    mutating func addCasedOpening(atPaper paper: Point2) throws -> Bool {
        try addOnWall(atPaper: paper) { model, id, point in try model.casedOpeningCommand(on: id, at: point) }
    }

    private mutating func addOnWall(
        atPaper paper: Point2, _ command: (HestiaModel, WallID, Point2) throws -> AddOpeningCommand
    ) throws -> Bool {
        switch model.wallHit(paper: paper) {
        case .none:
            return false
        case .ambiguous:
            throw HestiaModel.LoadError(message: "That point is on more than one wall. Click clear of the crossing.")
        case let .wall(id):
            guard let point = model.modelPoint(paper: paper) else {
                throw HestiaModel.LoadError(message: "The plan has no placement to draw on.")
            }
            try perform(command(model, id, point).erased)
            return true
        }
    }

    /// Adds a room on the ground storey named `name` and bounded by `walls` in the order given, with a new ID
    /// and no finishes. The command's own checks decide what is refused.
    mutating func addRoom(named name: String, walls: [WallID]) throws {
        try perform(model.roomCommand(named: name, walls: walls).erased)
    }

    /// Removes what a point of the plan sheet's paper lands on: a door before the wall it sits in, else the
    /// wall. A miss does nothing and returns false. A crossing, or a wall with openings or rooms, is refused and
    /// nothing else is removed to make way.
    mutating func delete(atPaper paper: Point2) throws -> Bool {
        if let door = model.doorHit(paper: paper) {
            try perform(RemoveOpeningCommand(openingID: door).erased)
            return true
        }
        switch model.wallHit(paper: paper) {
        case .none:
            return false
        case .ambiguous:
            throw HestiaModel.LoadError(message: "That point is on more than one wall. Click clear of the crossing.")
        case let .wall(id):
            do {
                try perform(RemoveWallCommand(wallID: id).erased)
            } catch CommandValidationError.hasDependents {
                let reasons = model.dependents(of: id)
                throw HestiaModel.LoadError(message: "Refused: that wall \(reasons). Remove those first.")
            }
            return true
        }
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
