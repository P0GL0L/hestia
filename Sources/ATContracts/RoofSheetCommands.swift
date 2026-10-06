import Foundation

/// Adds a roof over a footprint. Every edge gets the same pitch and overhang (a hip roof) unless `planes` is given.
public struct AddRoofCommand: Command {
    public var roofID: RoofID
    public var storeyID: StoreyID
    public var footprint: [Point2]
    public var eaveHeight: Length
    public var pitchRisePer12: Length?
    public var overhang: Length?
    public var planes: [RoofPlane]?
    public var index: Int?

    public init(
        roofID: RoofID, storeyID: StoreyID, footprint: [Point2], eaveHeight: Length,
        pitchRisePer12: Length? = nil, overhang: Length? = nil, planes: [RoofPlane]? = nil, index: Int? = nil
    ) {
        self.roofID = roofID
        self.storeyID = storeyID
        self.footprint = footprint
        self.eaveHeight = eaveHeight
        self.pitchRisePer12 = pitchRisePer12
        self.overhang = overhang
        self.planes = planes
        self.index = index
    }

    var resolvedPlanes: [RoofPlane] {
        planes ?? Array(
            repeating: RoofPlane(pitchRisePer12: pitchRisePer12, overhang: overhang ?? Length(ticks: 0)),
            count: footprint.count
        )
    }

    public static let commandName = "add_roof"
    public static let toolDescription =
        "Add a roof over a counterclockwise footprint; one pitch for every edge makes a hip roof."
    public static let parameters = [
        CommandParameter("roofID", .id, "New unique ID for the roof."),
        CommandParameter("storeyID", .id, "ID of the storey the roof sits on."),
        CommandParameter("footprint", .point2List, "Roof outline at the wall line, at least three points, counterclockwise."),
        CommandParameter("eaveHeight", .length, "Eave height above the storey floor; greater than zero."),
        CommandParameter("pitchRisePer12", .length, required: false,
                         "Rise per 12 of run for every edge, such as 6 inches for 6:12; omit for gable ends."),
        CommandParameter("overhang", .length, required: false, "Eave overhang for every edge; omit for none."),
        CommandParameter("planes", .objectList, required: false,
                         "Per-edge override, one {\"pitchRisePer12\": Length or omitted, \"overhang\": Length} per footprint edge."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(roofID, in: document.roofs.map(\.id))
        _ = try document.storeyIndex(storeyID)
        try CommandCheck.polygon(footprint)
        try CommandCheck.positive(eaveHeight, "eaveHeight")
        if let planes, planes.count != footprint.count {
            throw CommandValidationError.invalidValue(parameter: "planes")
        }
        try resolvedPlanes.forEach(RoofCheck.plane)
        try CommandCheck.insertionIndex(index, count: document.roofs.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let roof = Roof(id: roofID, storeyID: storeyID, footprint: footprint, eaveHeight: eaveHeight,
                        planes: resolvedPlanes)
        document.roofs.insert(roof, atOptional: index)
        return RemoveRoofCommand(roofID: roofID).erased
    }
}

/// Edits the plane over one footprint edge: its pitch (or a gable end) and its overhang.
public struct SetRoofEdgeCommand: Command {
    public var roofID: RoofID
    public var edgeIndex: Int
    public var pitchRisePer12: Length?
    public var overhang: Length

    public init(roofID: RoofID, edgeIndex: Int, pitchRisePer12: Length?, overhang: Length) {
        self.roofID = roofID
        self.edgeIndex = edgeIndex
        self.pitchRisePer12 = pitchRisePer12
        self.overhang = overhang
    }

    public static let commandName = "set_roof_edge"
    public static let toolDescription =
        "Set the pitch and overhang of the roof plane over one footprint edge; omit the pitch for a gable end."
    public static let parameters = [
        CommandParameter("roofID", .id, "ID of the roof."),
        CommandParameter("edgeIndex", .integer, "Edge from footprint point edgeIndex to the next point, counting from 0."),
        CommandParameter("pitchRisePer12", .length, required: false, "Rise per 12 of run; omit for a gable end."),
        CommandParameter("overhang", .length, "Eave overhang; zero or greater."),
    ]

    public func validate(against document: ModelDocument) throws {
        let roof = document.roofs[try document.roofIndex(roofID)]
        guard roof.planes.indices.contains(edgeIndex) else {
            throw CommandValidationError.indexOutOfRange(edgeIndex)
        }
        try RoofCheck.plane(RoofPlane(pitchRisePer12: pitchRisePer12, overhang: overhang))
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.roofIndex(roofID)
        let previous = document.roofs[index].planes[edgeIndex]
        document.roofs[index].planes[edgeIndex] = RoofPlane(pitchRisePer12: pitchRisePer12, overhang: overhang)
        return SetRoofEdgeCommand(roofID: roofID, edgeIndex: edgeIndex,
                                  pitchRisePer12: previous.pitchRisePer12, overhang: previous.overhang).erased
    }
}

/// Removes a roof.
public struct RemoveRoofCommand: Command {
    public var roofID: RoofID

    public init(roofID: RoofID) {
        self.roofID = roofID
    }

    public static let commandName = "remove_roof"
    public static let toolDescription = "Remove a roof."
    public static let parameters = [CommandParameter("roofID", .id, "ID of the roof to remove.")]

    public func validate(against document: ModelDocument) throws {
        _ = try document.roofIndex(roofID)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let index = try document.roofIndex(roofID)
        let removed = document.roofs.remove(at: index)
        return AddRoofCommand(roofID: removed.id, storeyID: removed.storeyID, footprint: removed.footprint,
                              eaveHeight: removed.eaveHeight, planes: removed.planes, index: index).erased
    }
}

enum RoofCheck {
    static func plane(_ plane: RoofPlane) throws {
        if let pitch = plane.pitchRisePer12 { try CommandCheck.nonNegative(pitch, "pitchRisePer12") }
        try CommandCheck.nonNegative(plane.overhang, "overhang")
    }
}

/// Adds a sheet to the drawing set.
public struct AddSheetCommand: Command {
    public var sheetID: SheetID
    public var number: String
    public var title: String
    public var paper: PaperSize
    public var scale: DrawingScale?
    public var views: [SheetView]
    public var index: Int?

    public init(
        sheetID: SheetID, number: String, title: String, paper: PaperSize, scale: DrawingScale?,
        views: [SheetView], index: Int? = nil
    ) {
        self.sheetID = sheetID
        self.number = number
        self.title = title
        self.paper = paper
        self.scale = scale
        self.views = views
        self.index = index
    }

    public static let commandName = "add_sheet"
    public static let toolDescription =
        "Add a sheet to the drawing set with a sheet number such as A-101, a title, a paper size, and its views."
    public static let parameters = [
        CommandParameter("sheetID", .id, "New unique ID for the sheet."),
        CommandParameter("number", .string, "Sheet number, unique in the set, such as A-101."),
        CommandParameter("title", .string, "Sheet title, such as Ground Floor Plan."),
        CommandParameter("paper", .object, "Paper size {\"name\", \"width\": Length, \"height\": Length}, landscape."),
        CommandParameter("scale", .object, required: false,
                         "Main view scale {\"label\", \"modelUnitsPerPaperUnit\": Int}, such as 48 for 1/4\" = 1'-0\"."),
        CommandParameter("views", .objectList,
                         "What the sheet shows, such as {\"floorPlan\": {\"storeyID\": ID}} or {\"schedule\": {\"kind\": \"doors\"}}."),
        insertIndexParameter,
    ]

    public func validate(against document: ModelDocument) throws {
        try CommandCheck.unique(sheetID, in: document.sheets.map(\.id))
        try SheetCheck.numberAndTitle(number, title, excluding: nil, in: document)
        try CommandCheck.positive(paper.width, "paper")
        try CommandCheck.positive(paper.height, "paper")
        if let scale, scale.modelUnitsPerPaperUnit <= 0 { throw CommandValidationError.invalidValue(parameter: "scale") }
        for storey in views.compactMap(\.storeyID) { _ = try document.storeyIndex(storey) }
        try CommandCheck.insertionIndex(index, count: document.sheets.count)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let sheet = Sheet(id: sheetID, number: try CommandCheck.name(number), title: try CommandCheck.name(title),
                          paper: paper, scale: scale, views: views)
        document.sheets.insert(sheet, atOptional: index)
        return RemoveSheetCommand(sheetID: sheetID).erased
    }
}

/// Renumbers and retitles a sheet.
public struct SetSheetTitleCommand: Command {
    public var sheetID: SheetID
    public var number: String
    public var title: String

    public init(sheetID: SheetID, number: String, title: String) {
        self.sheetID = sheetID
        self.number = number
        self.title = title
    }

    public static let commandName = "set_sheet_title"
    public static let toolDescription = "Change a sheet's number and title."
    public static let parameters = [
        CommandParameter("sheetID", .id, "ID of the sheet."),
        CommandParameter("number", .string, "Sheet number, unique in the set."),
        CommandParameter("title", .string, "Sheet title."),
    ]

    public func validate(against document: ModelDocument) throws {
        _ = try document.sheetIndex(sheetID)
        try SheetCheck.numberAndTitle(number, title, excluding: sheetID, in: document)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let index = try document.sheetIndex(sheetID)
        let previous = document.sheets[index]
        document.sheets[index].number = try CommandCheck.name(number)
        document.sheets[index].title = try CommandCheck.name(title)
        return SetSheetTitleCommand(sheetID: sheetID, number: previous.number, title: previous.title).erased
    }
}

/// Removes a sheet from the drawing set.
public struct RemoveSheetCommand: Command {
    public var sheetID: SheetID

    public init(sheetID: SheetID) {
        self.sheetID = sheetID
    }

    public static let commandName = "remove_sheet"
    public static let toolDescription = "Remove a sheet from the drawing set."
    public static let parameters = [CommandParameter("sheetID", .id, "ID of the sheet to remove.")]

    public func validate(against document: ModelDocument) throws {
        _ = try document.sheetIndex(sheetID)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        let index = try document.sheetIndex(sheetID)
        let removed = document.sheets.remove(at: index)
        return AddSheetCommand(sheetID: removed.id, number: removed.number, title: removed.title,
                               paper: removed.paper, scale: removed.scale, views: removed.views, index: index).erased
    }
}

enum SheetCheck {
    static func numberAndTitle(_ number: String, _ title: String, excluding: SheetID?, in document: ModelDocument) throws {
        let trimmed = try CommandCheck.name(number)
        _ = try CommandCheck.name(title)
        if document.sheets.contains(where: { $0.number == trimmed && $0.id != excluding }) {
            throw CommandValidationError.duplicateSheetNumber(trimmed)
        }
    }
}
