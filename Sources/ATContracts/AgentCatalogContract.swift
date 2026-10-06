import Foundation

/// Any JSON value, for tool schemas and tool-call arguments.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

/// Which provider account a request or key belongs to.
public struct ProviderID: Hashable, Codable, Sendable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let anthropic = ProviderID(rawValue: "anthropic")
    public static let openAI = ProviderID(rawValue: "openai")
    public static let xAI = ProviderID(rawValue: "xai")
    public static let gemini = ProviderID(rawValue: "gemini")
    public static let ollama = ProviderID(rawValue: "ollama")
}

/// A tool the model may call. `inputSchema` is a JSON Schema object.
public struct LLMToolDefinition: Codable, Hashable, Sendable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct LLMToolCall: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var arguments: JSONValue

    public init(id: String, name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public enum LLMContent: Codable, Hashable, Sendable {
    case text(String)
    case toolCall(LLMToolCall)
    case toolResult(callID: String, content: String, isError: Bool)
}

public enum LLMRole: String, Codable, Hashable, Sendable {
    case user, assistant
}

public struct LLMMessage: Codable, Hashable, Sendable {
    public var role: LLMRole
    public var content: [LLMContent]

    public init(role: LLMRole, content: [LLMContent]) {
        self.role = role
        self.content = content
    }
}

public struct LLMRequest: Codable, Hashable, Sendable {
    public var model: String
    public var system: String
    public var messages: [LLMMessage]
    public var tools: [LLMToolDefinition]
    public var maxOutputTokens: Int

    public init(model: String, system: String, messages: [LLMMessage], tools: [LLMToolDefinition], maxOutputTokens: Int) {
        self.model = model
        self.system = system
        self.messages = messages
        self.tools = tools
        self.maxOutputTokens = maxOutputTokens
    }
}

public enum LLMStopReason: String, Codable, Hashable, Sendable {
    case endTurn, toolUse, maxTokens
}

public struct LLMResponse: Codable, Hashable, Sendable {
    public var content: [LLMContent]
    public var stopReason: LLMStopReason

    public init(content: [LLMContent], stopReason: LLMStopReason) {
        self.content = content
        self.stopReason = stopReason
    }
}

public enum LLMStreamEvent: Hashable, Sendable {
    case textDelta(String)
    case toolCall(LLMToolCall)
    case finished(LLMResponse)
}

/// Provider failures, worded so the chat panel can show them directly. None of them touch the model.
public enum LLMError: Error, Sendable, Equatable {
    case missingKey(ProviderID)
    case network(String)
    case rateLimited(retryAfterSeconds: Int?)
    case http(status: Int, message: String)
    case invalidResponse(String)
}

/// One chat model backend. Implemented by ATAgent (Stream F).
public protocol LLMProvider: Sendable {
    var id: ProviderID { get }
    func complete(_ request: LLMRequest) async throws -> LLMResponse
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error>
}

extension LLMProvider {
    /// Non-streaming fallback: replays `complete` as stream events.
    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await complete(request)
                    for item in response.content {
                        switch item {
                        case let .text(text): continuation.yield(.textDelta(text))
                        case let .toolCall(call): continuation.yield(.toolCall(call))
                        case .toolResult: break
                        }
                    }
                    continuation.yield(.finished(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Reads and writes provider API keys. The app's Keychain implementation lives under Apps/.
public protocol KeyStore: Sendable {
    func key(for provider: ProviderID) throws -> String?
    /// Stores a key, or deletes it when `key` is nil.
    func setKey(_ key: String?, for provider: ProviderID) throws
}

/// A catalog item's stable slug, such as `kitchen/fridge-counter-depth`.
public struct CatalogItemID: Hashable, Codable, Sendable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum MountType: String, Codable, Hashable, Sendable, CaseIterable {
    case floor, wall, ceiling
}

/// The contents of a catalog item's `item.json`.
public struct CatalogItem: Codable, Hashable, Sendable {
    public var id: CatalogItemID
    public var name: String
    public var category: String
    public var width: Length
    public var depth: Length
    public var height: Length
    public var mount: MountType
    /// SPDX identifier or plain license name, such as `CC0-1.0`.
    public var license: String
    public var sourceURL: String?

    public init(
        id: CatalogItemID, name: String, category: String, width: Length, depth: Length, height: Length,
        mount: MountType, license: String, sourceURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.width = width
        self.depth = depth
        self.height = height
        self.mount = mount
        self.license = license
        self.sourceURL = sourceURL
    }
}

public enum CatalogAsset: String, Codable, Hashable, Sendable, CaseIterable {
    /// `model.glb`
    case model
    /// `thumb.png`
    case thumbnail
}

/// Furniture and fixture library. Implemented by ATCatalog (Stream G).
public protocol CatalogStore: Sendable {
    /// Items in a category, or every item when `category` is nil, sorted by name.
    func items(in category: String?) throws -> [CatalogItem]
    func item(_ id: CatalogItemID) throws -> CatalogItem?
    func asset(_ asset: CatalogAsset, for id: CatalogItemID) throws -> Data?
}
