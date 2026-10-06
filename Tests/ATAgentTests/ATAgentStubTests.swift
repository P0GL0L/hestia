import ATAgent
import ATContracts
import Testing

@Test func agentStubSeesTheCommandCatalog() {
    #expect(ATAgent.commandNames.count == CommandCatalog.v1.count)
    #expect(ATAgent.commandNames.contains("add_wall"))
}
