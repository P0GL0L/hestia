import ATContracts
import Foundation

/// Stream F lands provider adapters, tool definitions, the agent loop, and the MCP server here.
/// Until then this module only proves it builds on every platform against the contracts.
public enum ATAgent {
    /// The command catalog the agent will expose as tools.
    public static var commandNames: [String] {
        CommandCatalog.v1.map { $0.commandName }
    }
}
