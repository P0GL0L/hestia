import ATContracts
import Foundation

/// Stream G lands the bundled catalog, terrain tools, and MEP symbol library here.
/// Until then the catalog is empty.
public struct EmptyCatalogStore: CatalogStore {
    public init() {}

    public func items(in category: String?) throws -> [CatalogItem] { [] }

    public func item(_ id: CatalogItemID) throws -> CatalogItem? { nil }

    public func asset(_ asset: CatalogAsset, for id: CatalogItemID) throws -> Data? { nil }
}
