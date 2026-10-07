import Foundation

/// Renames the project.
public struct RenameProjectCommand: Command {
    public var projectID: ProjectID
    public var newName: String

    public init(projectID: ProjectID, newName: String) {
        self.projectID = projectID
        self.newName = newName
    }

    public static let commandName = "rename_project"
    public static let toolDescription =
        "Rename the Hestia project by project ID; use when the user asks to change the project title."
    public static let parameters = [
        CommandParameter("projectID", .id, "ID of the project."),
        CommandParameter("newName", .string, "New project name; must not be blank."),
    ]

    public func validate(against document: ModelDocument) throws {
        guard document.project.id == projectID else {
            throw CommandValidationError.projectNotFound(projectID)
        }
        _ = try CommandCheck.name(newName)
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let previousName = document.project.name
        document.project.name = try CommandCheck.name(newName)
        return RenameProjectCommand(projectID: projectID, newName: previousName).erased
    }
}

/// Sets or clears the project's display units.
public struct SetProjectUnitsCommand: Command {
    public var projectID: ProjectID
    /// A `LengthFormatStyle` raw value, or nil to clear. Kept as text so an unknown value is refused by
    /// `validate` with `invalidValue` rather than failing to decode.
    public var units: String?

    public init(projectID: ProjectID, units: LengthFormatStyle?) {
        self.projectID = projectID
        self.units = units?.rawValue
    }

    public init(projectID: ProjectID, unitsValue: String?) {
        self.projectID = projectID
        units = unitsValue
    }

    public static let commandName = "set_project_units"
    public static let toolDescription =
        "Set how the project writes lengths, metric or feet-inches-fractions; omit units to clear the setting."
    public static let parameters = [
        CommandParameter("projectID", .id, "ID of the project."),
        CommandParameter("units", .choice, required: false, "Display units; omit to clear.",
                         allowedValues: LengthFormatStyle.allCases.map(\.rawValue)),
    ]

    /// The units this command sets; nil clears them.
    func style() throws -> LengthFormatStyle? {
        guard let units else { return nil }
        guard let style = LengthFormatStyle(rawValue: units) else {
            throw CommandValidationError.invalidValue(parameter: "units")
        }
        return style
    }

    public func validate(against document: ModelDocument) throws {
        guard document.project.id == projectID else {
            throw CommandValidationError.projectNotFound(projectID)
        }
        _ = try style()
    }

    public func apply(to document: inout ModelDocument) throws -> AnyCommand {
        try validate(against: document)
        let previous = document.project.displayUnits
        document.project.displayUnits = try style()
        return SetProjectUnitsCommand(projectID: projectID, units: previous).erased
    }
}
