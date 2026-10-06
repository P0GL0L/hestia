import Foundation

public enum CommandValidationError: Error, Sendable, Equatable {
    case projectNotFound(ProjectID)
    case nameEmpty
}

/// Edits the model through validate → apply → inverse (returned from apply).
public protocol Command: Sendable {
    static var commandName: String { get }
    static var toolDescription: String { get }

    func validate(against document: ModelDocument) throws
    func apply(to document: inout ModelDocument) throws -> Self
}

/// Renames the project; inverse is returned from `apply`.
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

    public func validate(against document: ModelDocument) throws {
        guard document.project.id == projectID else {
            throw CommandValidationError.projectNotFound(projectID)
        }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw CommandValidationError.nameEmpty
        }
    }

    public func apply(to document: inout ModelDocument) throws -> RenameProjectCommand {
        let previousName = document.project.name
        document.project.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        return RenameProjectCommand(projectID: projectID, newName: previousName)
    }
}
