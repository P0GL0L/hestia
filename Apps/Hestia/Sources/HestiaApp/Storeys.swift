import ATContracts
import Foundation

/// The storeys of the model as the plan sees them: which one it shows, the ones above and below, and a new one
/// on top.
extension HestiaModel {
    /// The storey under `storey` in its building: the highest one lower than it. Nil for the lowest.
    static func storey(below storey: Storey, in document: ModelDocument) -> Storey? {
        document.storeys.filter { $0.buildingID == storey.buildingID && $0.elevation.ticks < storey.elevation.ticks }
            .max { $0.elevation.ticks < $1.elevation.ticks }
    }

    /// The storeys the plan can show, lowest first.
    var storeysUpward: [Storey] {
        document.storeys.sorted { $0.elevation.ticks < $1.elevation.ticks }
    }

    /// The name of the storey the plan shows.
    var planStoreyName: String {
        document.storeys.first { $0.id == planStorey }?.name ?? "Floor"
    }

    /// The end of a DXF export's file name for the shown plan, such as "-second-floor-plan.dxf".
    var planFileSuffix: String {
        let words = planStoreyName.lowercased().split { !$0.isLetter && !$0.isNumber }
        return "-" + (words.isEmpty ? ["floor"] : words).joined(separator: "-") + "-plan.dxf"
    }

    /// The next storey up from the plan's, or down when `up` is false; nil at the top or the bottom.
    func storey(next up: Bool) -> StoreyID? {
        let order = storeysUpward
        guard let index = order.firstIndex(where: { $0.id == planStorey }) else { return nil }
        let next = up ? index + 1 : index - 1
        return order.indices.contains(next) ? order[next].id : nil
    }

    /// A new storey on top of the plan storey's building, with a new ID: as high above the top storey as that
    /// storey's exterior walls are tall (one with layers, else the thickest), else as far as the storey under it
    /// is below, else the default wall height. Named for its place: Second Floor, Third Floor, and so on.
    func storeyAboveCommand(id: StoreyID = StoreyID(UUID())) throws -> AddStoreyCommand {
        guard let shown = document.storeys.first(where: { $0.id == planStorey }) else {
            throw LoadError(message: "The model has no storey to build on.")
        }
        let building = document.storeys.filter { $0.buildingID == shown.buildingID }
            .sorted { $0.elevation.ticks < $1.elevation.ticks }
        let top = building.last ?? shown
        let walls = document.walls.filter { $0.storeyID == top.id }
        let exterior = walls.first { !$0.layers.isEmpty } ?? walls.max { $0.thickness.ticks < $1.thickness.ticks }
        let below = Self.storey(below: top, in: document)
        let rise = exterior?.height.ticks ?? below.map { top.elevation.ticks - $0.elevation.ticks }
            ?? Self.defaultWallHeight.ticks
        let names = ["First", "Second", "Third", "Fourth", "Fifth", "Sixth"]
        let name = building.count < names.count ? "\(names[building.count]) Floor" : "Floor \(building.count + 1)"
        return AddStoreyCommand(storeyID: id, buildingID: top.buildingID, name: name,
                                elevation: Length(ticks: top.elevation.ticks + rise))
    }
}

extension EditSession {
    /// Commands for one history step, plus an explicit storey to restore when that step created or removed the
    /// selected storey. Ordinary edits leave the storey nil and preserve whichever floor the user is viewing.
    struct HistoryStep {
        var commands: [AnyCommand]
        var storeyToShow: StoreyID?
    }

    /// Adds a storey on top of the building and shows it, empty, over the floor below; a document that keeps its
    /// own sheets gets a plan sheet for it too, so the set prints the new floor. One Undo takes both back.
    mutating func addStoreyAbove() throws {
        let command = try model.storeyAboveCommand()
        let sheet = model.planSheetCommand(for: command.storeyID, named: command.name)
        try perform(batch: [command.erased] + (sheet.map { [$0.erased] } ?? []), showing: command.storeyID)
    }
}

extension HestiaModel {
    /// The sheet a storey's plan is drawn on when the document keeps its own sheets and none of them plans it:
    /// on the paper and at the scale of the plan sheet below it, else ARCH D at 1/4" = 1'-0", as the default set
    /// draws a plan. Nil when the document has no sheets of its own (the default set plans every storey) or one
    /// of them plans the storey.
    static func standInPlanSheet(for storey: Storey, in document: ModelDocument) -> Sheet? {
        guard !document.sheets.isEmpty, planSheet(of: storey.id, in: document) == nil else { return nil }
        let below = Self.storey(below: storey, in: document).flatMap { planSheet(of: $0.id, in: document) }
        return Sheet(id: SheetID(storey.id.rawValue), number: "A-101", title: "\(storey.name) Plan",
                     paper: below?.paper ?? .archD, scale: below?.scale ?? .quarterInch,
                     views: [.floorPlan(storeyID: storey.id)])
    }

    static func planSheet(of storey: StoreyID, in document: ModelDocument) -> Sheet? {
        document.sheets.first { $0.views.contains(.floorPlan(storeyID: storey)) }
    }

    /// The plan sheet a new storey joins a document's own sheets with: titled for the storey, numbered after
    /// the set's highest A-1xx number, and on the paper and at the scale of the set's last plan sheet, just after
    /// it. Nil when the document has no sheets of its own.
    func planSheetCommand(for storey: StoreyID, named name: String) -> AddSheetCommand? {
        guard !document.sheets.isEmpty else { return nil }
        let numbers = Set(document.sheets.map(\.number))
        let used = numbers.compactMap { $0.hasPrefix("A-1") ? Int($0.dropFirst(2)) : nil }
        var next = (used.max() ?? 100) + 1
        while numbers.contains("A-\(next)") { next += 1 }
        let plans = document.sheets.indices.filter { index in
            document.sheets[index].views.contains { if case .floorPlan = $0 { return true } else { return false } }
        }
        let template = plans.last.map { document.sheets[$0] }
        return AddSheetCommand(sheetID: SheetID(UUID()), number: "A-\(next)", title: "\(name) Plan",
                               paper: template?.paper ?? .archD, scale: template?.scale ?? .quarterInch,
                               views: [.floorPlan(storeyID: storey)], index: plans.last.map { $0 + 1 })
    }
}
