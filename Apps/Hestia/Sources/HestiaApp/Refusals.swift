import ATContracts
import Foundation

/// Plain sentences for the errors a command or a file can raise, for the status line. The command layer names
/// what went wrong with IDs and parameter names; a person needs to read what to do instead.
enum Refusals {
    static func sentence(for error: CommandValidationError) -> String {
        missing(error) ?? broken(error) ?? "That change was refused."
    }

    /// An element the command names that is not in the model.
    private static func missing(_ error: CommandValidationError) -> String? {
        switch error {
        case .projectNotFound: return "That project is not in the model."
        case .buildingNotFound: return "That building is not in the model."
        case .storeyNotFound: return "That storey is not in the model."
        case .wallNotFound: return "That wall is not in the model."
        case .openingNotFound: return "That door or window is not in the model."
        case .roomNotFound: return "That room is not in the model."
        case .stairNotFound: return "That stair is not in the model."
        case .roofNotFound: return "That roof is not in the model."
        case .slabNotFound: return "That slab is not in the model."
        case .sheetNotFound: return "That sheet is not in the set."
        case .layerNotFound: return "That layer is not in the model."
        case .columnNotFound: return "That column is not in the model."
        case .beamNotFound: return "That beam is not in the model."
        case .placementNotFound: return "That item is not in the model."
        case .terrainPatchNotFound: return "That terrain patch is not in the model."
        case .mepSymbolNotFound: return "That electrical symbol is not in the model."
        case .elementNotFound: return "That element is not in the model."
        case .dimensionOverrideNotFound: return "That dimension has no override to clear."
        default: return nil
        }
    }

    /// A rule the change would break.
    private static func broken(_ error: CommandValidationError) -> String? {
        switch error {
        case .duplicateID: return "Something in the model already uses that ID."
        case .nameEmpty: return "A name is needed."
        case let .notPositive(parameter): return "The \(words(parameter)) must be more than zero."
        case let .negative(parameter): return "The \(words(parameter)) can't be less than zero."
        case .indexOutOfRange: return "That position is outside the list."
        case .zeroLengthWall: return "Both ends of the wall are the same point. Click farther apart."
        case .openingOutsideWall: return "That opening would run past the end of its wall. Click nearer the middle."
        case .openingAboveWall: return "That opening would be taller than its wall."
        case .openingsOverlap: return "That opening would overlap another one in the same wall."
        case .roomBoundaryInvalid: return "A room needs at least one wall, each listed once."
        case .wallOnOtherStorey: return "A wall in that room's boundary is on another storey."
        case .hasDependents: return "Something still depends on that. Remove it first."
        case let .unknownCommand(name): return "Hestia has no command named \(name)."
        case let .invalidValue(parameter): return "The \(words(parameter)) is out of range."
        case .polygonInvalid: return "That outline needs three or more points around some area."
        case .swingNotAllowed: return "Only hinged doors swing."
        case let .duplicateSheetNumber(number): return "Another sheet is already numbered \(number)."
        default: return nil
        }
    }

    static func sentence(for error: ModelDocumentError) -> String {
        switch error {
        case let .unsupportedSchemaVersion(found, supported):
            return "That file was saved by a newer Hestia (format \(found); this one reads up to \(supported))."
        }
    }

    /// A parameter name as words: `sillHeight` reads "sill height", `pitchRisePer12` "pitch rise per 12".
    static func words(_ parameter: String) -> String {
        var out = ""
        var previous: Character?
        for character in parameter {
            let startsNumber = character.isNumber && previous.map { !$0.isNumber } ?? false
            if character.isUppercase || startsNumber, !out.isEmpty { out.append(" ") }
            out.append(contentsOf: character.lowercased())
            previous = character
        }
        return out
    }
}
