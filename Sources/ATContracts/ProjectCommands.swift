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
