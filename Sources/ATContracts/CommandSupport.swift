import Foundation

// Shared lookups and checks for the command catalog. Internal to ATContracts.

extension ModelDocument {
    func buildingIndex(_ id: BuildingID) throws -> Int {
        guard let index = buildings.firstIndex(where: { $0.id == id }) else {
            throw CommandValidationError.buildingNotFound(id)
        }
        return index
    }

    func storeyIndex(_ id: StoreyID) throws -> Int {
        guard let index = storeys.firstIndex(where: { $0.id == id }) else {
            throw CommandValidationError.storeyNotFound(id)
        }
        return index
    }

    func wallIndex(_ id: WallID) throws -> Int {
        guard let index = walls.firstIndex(where: { $0.id == id }) else {
            throw CommandValidationError.wallNotFound(id)
        }
        return index
    }

    func openingIndex(_ id: OpeningID) throws -> Int {
        guard let index = openings.firstIndex(where: { $0.id == id }) else {
            throw CommandValidationError.openingNotFound(id)
        }
        return index
    }

    func roomIndex(_ id: RoomID) throws -> Int {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else {
            throw CommandValidationError.roomNotFound(id)
        }
        return index
    }
}

enum CommandCheck {
    static func name(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw CommandValidationError.nameEmpty }
        return trimmed
    }

    static func positive(_ length: Length, _ parameter: String) throws {
        if length.ticks <= 0 { throw CommandValidationError.notPositive(parameter: parameter) }
    }

    static func nonNegative(_ length: Length, _ parameter: String) throws {
        if length.ticks < 0 { throw CommandValidationError.negative(parameter: parameter) }
    }

    /// Validates an optional insertion index for a collection of `count` elements.
    static func insertionIndex(_ index: Int?, count: Int) throws {
        if let index, index < 0 || index > count {
            throw CommandValidationError.indexOutOfRange(index)
        }
    }

    static func unique<ID: Equatable & RawRepresentable>(_ id: ID, in existing: [ID]) throws
    where ID.RawValue == UUID {
        if existing.contains(id) { throw CommandValidationError.duplicateID(id.rawValue) }
    }
}

extension Array {
    /// Inserts at `index`, or appends when `index` is nil.
    mutating func insert(_ element: Element, atOptional index: Int?) {
        insert(element, at: index ?? count)
    }
}

/// Description shared by every optional `index` parameter on add commands.
let insertIndexParameter = CommandParameter(
    "index", .integer, required: false,
    "Position in the model's list; omit to append. Undo uses it to restore order."
)
