import Foundation

/// Scripted chat model. Returns queued responses in order and records every request it was sent.
public final class MockLLMProvider: LLMProvider, @unchecked Sendable {
    public let id: ProviderID
    private let lock = NSLock()
    private var script: [Result<LLMResponse, LLMError>]
    private var sent: [LLMRequest] = []

    public init(id: ProviderID = ProviderID(rawValue: "mock"), script: [Result<LLMResponse, LLMError>]) {
        self.id = id
        self.script = script
    }

    /// Requests received so far, oldest first.
    public var requests: [LLMRequest] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let next: Result<LLMResponse, LLMError>? = {
            lock.lock()
            defer { lock.unlock() }
            sent.append(request)
            return script.isEmpty ? nil : script.removeFirst()
        }()
        guard let next else { throw LLMError.invalidResponse("mock script exhausted") }
        return try next.get()
    }
}

/// In-memory key store for tests and previews. Never persists anything.
public final class InMemoryKeyStore: KeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [ProviderID: String]

    public init(keys: [ProviderID: String] = [:]) {
        self.keys = keys
    }

    public func key(for provider: ProviderID) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return keys[provider]
    }

    public func setKey(_ key: String?, for provider: ProviderID) throws {
        lock.lock()
        defer { lock.unlock() }
        keys[provider] = key
    }
}

/// Fixed catalog for tests and previews.
public struct MockCatalogStore: CatalogStore {
    public var catalog: [CatalogItem]
    public var assets: [CatalogItemID: [CatalogAsset: Data]]

    public init(items: [CatalogItem], assets: [CatalogItemID: [CatalogAsset: Data]] = [:]) {
        self.catalog = items
        self.assets = assets
    }

    public func items(in category: String?) throws -> [CatalogItem] {
        catalog.filter { category == nil || $0.category == category }.sorted { $0.name < $1.name }
    }

    public func item(_ id: CatalogItemID) throws -> CatalogItem? {
        catalog.first { $0.id == id }
    }

    public func asset(_ asset: CatalogAsset, for id: CatalogItemID) throws -> Data? {
        assets[id]?[asset]
    }
}
