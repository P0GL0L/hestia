import ATContracts
import Foundation

/// The one place drawings decide how to write a length.
///
/// The project's `displayUnits` wins everywhere. Without it, a view is imperial when its scale label carries an
/// inch mark, and sheet-wide text (schedules, section level marks) is imperial when any sheet's scale does.
enum DrawingUnits {
    /// Units for a view drawn at `scale`.
    static func style(_ document: ModelDocument, scale: DrawingScale?) -> LengthFormatStyle {
        if let units = document.project.displayUnits { return units }
        return isImperial(scale) ? .feetInchesFractions : .metric
    }

    /// Units for text that belongs to the whole set rather than one view.
    static func style(_ document: ModelDocument) -> LengthFormatStyle {
        if let units = document.project.displayUnits { return units }
        return document.sheets.contains { isImperial($0.scale) } ? .feetInchesFractions : .metric
    }

    static func isImperial(_ scale: DrawingScale?) -> Bool {
        scale?.label.contains("\"") ?? false
    }

    /// A model length rounded to 1/16" or 1 mm and written in `style`, the same rounding the printers use.
    static func label(_ length: Length, style: LengthFormatStyle) -> String {
        let unit = style == .feetInchesFractions ? Length.ticksPerSixtyFourthInch * 4 : Length.ticksPerMillimeter
        let rounded = Length(ticks: ((length.ticks + unit / 2) / unit) * unit)
        return LengthFormatting.format(rounded, style: style)
    }

    /// The text a dimension should carry: an override if one is stored, else the measured length in the
    /// project's units when it sets them. Nil leaves the printer to measure in the scale's units, as before.
    static func dimensionText(_ document: ModelDocument, length: Length, override: String?) -> String? {
        if let override { return override }
        guard let units = document.project.displayUnits else { return nil }
        return label(length, style: units)
    }
}
