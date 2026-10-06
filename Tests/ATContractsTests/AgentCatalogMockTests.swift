import ATContracts
import Foundation
import Testing

private let toolCall = LLMToolCall(
    id: "call_1", name: "rename_room",
    arguments: .object(["roomID": .string(Sample.room.rawValue.uuidString), "newName": .string("Office")])
)

private func request(_ text: String) -> LLMRequest {
    LLMRequest(
        model: "mock-1", system: "You edit Hestia house plans through tools.",
        messages: [LLMMessage(role: .user, content: [.text(text)])],
        tools: [LLMToolDefinition(name: "rename_room", description: RenameRoomCommand.toolDescription,
                                  inputSchema: .object(["type": .string("object")]))],
        maxOutputTokens: 1024
    )
}

@Test func mockProviderReplaysScriptAndRecordsRequests() async throws {
    let provider = MockLLMProvider(script: [
        .success(LLMResponse(content: [.text("Renaming."), .toolCall(toolCall)], stopReason: .toolUse)),
        .failure(.rateLimited(retryAfterSeconds: 30)),
    ])
    let first = try await provider.complete(request("Call bedroom 2 the office"))
    #expect(first.stopReason == .toolUse)
    await #expect(throws: LLMError.rateLimited(retryAfterSeconds: 30)) {
        try await provider.complete(request("again"))
    }
    await #expect(throws: LLMError.invalidResponse("mock script exhausted")) {
        try await provider.complete(request("and again"))
    }
    #expect(provider.requests.count == 3)
    #expect(provider.requests[0].messages[0].content == [.text("Call bedroom 2 the office")])
}

@Test func defaultStreamReplaysCompleteAsEvents() async throws {
    let response = LLMResponse(content: [.text("Renaming."), .toolCall(toolCall)], stopReason: .toolUse)
    let provider = MockLLMProvider(script: [.success(response)])
    var events: [LLMStreamEvent] = []
    for try await event in provider.stream(request("Call bedroom 2 the office")) {
        events.append(event)
    }
    #expect(events == [.textDelta("Renaming."), .toolCall(toolCall), .finished(response)])
}

@Test func toolCallArgumentsDecodeIntoACommand() throws {
    let envelope = JSONValue.object(["name": .string(toolCall.name), "parameters": toolCall.arguments])
    let data = try JSONEncoder().encode(envelope)
    let command = try JSONDecoder().decode(AnyCommand.self, from: data)
    #expect(command == RenameRoomCommand(roomID: Sample.room, newName: "Office").erased)
}

@Test func jsonValueRoundTrips() throws {
    let value = JSONValue.object([
        "a": .array([.number(1.5), .bool(true), .null]), "b": .string("x"), "c": .object([:]),
    ])
    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
}

@Test func inMemoryKeyStoreSetsAndClearsKeys() throws {
    let store = InMemoryKeyStore()
    #expect(try store.key(for: .anthropic) == nil)
    try store.setKey("test-key", for: .anthropic)
    #expect(try store.key(for: .anthropic) == "test-key")
    #expect(try store.key(for: .openAI) == nil)
    try store.setKey(nil, for: .anthropic)
    #expect(try store.key(for: .anthropic) == nil)
}

@Test func mockCatalogFiltersSortsAndServesAssets() throws {
    let sofa = CatalogItem(id: CatalogItemID(rawValue: "living/sofa-3-seat"), name: "Sofa", category: "living",
                           width: .millimeters(2100), depth: .millimeters(900), height: .millimeters(800),
                           mount: .floor, license: "CC0-1.0")
    let chair = CatalogItem(id: CatalogItemID(rawValue: "living/armchair"), name: "Armchair", category: "living",
                            width: .millimeters(800), depth: .millimeters(850), height: .millimeters(800),
                            mount: .floor, license: "CC0-1.0")
    let sconce = CatalogItem(id: CatalogItemID(rawValue: "lighting/sconce"), name: "Sconce", category: "lighting",
                             width: .millimeters(150), depth: .millimeters(120), height: .millimeters(250),
                             mount: .wall, license: "CC0-1.0", sourceURL: "https://example.org/sconce")
    let store = MockCatalogStore(items: [sofa, sconce, chair], assets: [sofa.id: [.thumbnail: Data([0x89])]])

    #expect(try store.items(in: "living").map(\.name) == ["Armchair", "Sofa"])
    #expect(try store.items(in: nil).count == 3)
    #expect(try store.item(sconce.id) == sconce)
    #expect(try store.asset(.thumbnail, for: sofa.id) == Data([0x89]))
    #expect(try store.asset(.model, for: sofa.id) == nil)

    let data = try JSONEncoder().encode(sconce)
    #expect(try JSONDecoder().decode(CatalogItem.self, from: data) == sconce)
}
