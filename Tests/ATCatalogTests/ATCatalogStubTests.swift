import ATCatalog
import ATContracts
import Testing

@Test func emptyCatalogHasNoItems() throws {
    let store = EmptyCatalogStore()
    #expect(try store.items(in: nil).isEmpty)
    #expect(try store.item(CatalogItemID(rawValue: "living/sofa")) == nil)
    #expect(try store.asset(.model, for: CatalogItemID(rawValue: "living/sofa")) == nil)
}
