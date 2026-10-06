import Foundation

public enum LengthParseError: Error, Sendable, Equatable {
    case empty
    case invalidFormat(String)
    case overflow
}

public enum LengthFormatStyle: Sendable {
    case metric
    case feetInchesFractions
}

public enum LengthFormatting {
    private static let ticksPerInch: Int64 = 64 * Length.ticksPerSixtyFourthInch

    /// Parse metric (`1 mm`, `2500 mm`) or imperial feet-inches-fractions (`6'-0"`, `1/64"`).
    public static func parse(_ input: String) throws -> Length {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw LengthParseError.empty
        }

        if let metric = try parseMetric(trimmed) {
            return metric
        }
        if let imperial = try parseImperial(trimmed) {
            return imperial
        }
        throw LengthParseError.invalidFormat(trimmed)
    }

    public static func format(_ length: Length, style: LengthFormatStyle) -> String {
        switch style {
        case .metric:
            return formatMetric(length)
        case .feetInchesFractions:
            return formatFeetInchesFractions(length)
        }
    }

    private static func parseMetric(_ text: String) throws -> Length? {
        let lower = text.lowercased()
        guard lower.hasSuffix("mm") else { return nil }
        let numberPart = lower.dropLast(2).trimmingCharacters(in: .whitespaces)
        guard let mm = parsePositiveInteger(numberPart) else {
            throw LengthParseError.invalidFormat(text)
        }
        guard let ticks = multiply(mm, Length.ticksPerMillimeter) else {
            throw LengthParseError.overflow
        }
        return Length(ticks: ticks)
    }

    private static func parseImperial(_ text: String) throws -> Length? {
        var s = text
        if s.hasSuffix("\"") || s.hasSuffix("″") {
            s.removeLast()
        }
        s = s.trimmingCharacters(in: .whitespaces)

        if s.contains("'") || s.contains("′") {
            return try parseFeetInches(s)
        }

        if s.contains("/") {
            let ticks = try parseFractionToSixtyFourthTicks(s)
            guard let total = multiply(ticks, Length.ticksPerSixtyFourthInch) else {
                throw LengthParseError.overflow
            }
            return Length(ticks: total)
        }

        if let whole = parsePositiveInteger(s) {
            guard let ticks = multiply(whole * 64, Length.ticksPerSixtyFourthInch) else {
                throw LengthParseError.overflow
            }
            return Length(ticks: ticks)
        }

        return nil
    }

    private static func parseFeetInches(_ text: String) throws -> Length {
        let normalized = text
            .replacingOccurrences(of: "′", with: "'")
            .replacingOccurrences(of: "-", with: " ")
        let parts = normalized.split(separator: "'", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw LengthParseError.invalidFormat(text)
        }

        let feetPart = parts[0].trimmingCharacters(in: .whitespaces)
        guard let feet = parseNonNegativeInteger(feetPart) else {
            throw LengthParseError.invalidFormat(text)
        }

        var inchPart = String(parts[1]).trimmingCharacters(in: .whitespaces)
        if inchPart.hasSuffix("\"") || inchPart.hasSuffix("″") {
            inchPart.removeLast()
            inchPart = inchPart.trimmingCharacters(in: .whitespaces)
        }

        let inchTicks: Int64
        if inchPart.isEmpty {
            inchTicks = 0
        } else if inchPart.contains("/") {
            inchTicks = try parseFractionToSixtyFourthTicks(inchPart)
        } else {
            guard let inches = parseNonNegativeInteger(inchPart) else {
                throw LengthParseError.invalidFormat(text)
            }
            guard let ticks = multiply(inches * 64, Length.ticksPerSixtyFourthInch) else {
                throw LengthParseError.overflow
            }
            inchTicks = ticks / Length.ticksPerSixtyFourthInch
        }

        guard let footTicks = multiply(feet * 12 * 64, Length.ticksPerSixtyFourthInch) else {
            throw LengthParseError.overflow
        }
        guard let inchTotal = multiply(inchTicks, Length.ticksPerSixtyFourthInch) else {
            throw LengthParseError.overflow
        }
        guard let total = add(footTicks, inchTotal) else {
            throw LengthParseError.overflow
        }
        return Length(ticks: total)
    }

    private static func parseFractionToSixtyFourthTicks(_ text: String) throws -> Int64 {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true)
        var whole: Int64 = 0
        var fractionText = text

        if parts.count == 2, let w = parseNonNegativeInteger(String(parts[0])) {
            whole = w
            fractionText = String(parts[1])
        } else if parts.count == 1 {
            fractionText = String(parts[0])
            if !fractionText.contains("/") {
                guard let w = parseNonNegativeInteger(fractionText) else {
                    throw LengthParseError.invalidFormat(text)
                }
                return w * 64
            }
        } else {
            throw LengthParseError.invalidFormat(text)
        }

        let fracParts = fractionText.split(separator: "/", omittingEmptySubsequences: true)
        guard fracParts.count == 2,
              let num = parsePositiveInteger(String(fracParts[0])),
              let den = parsePositiveInteger(String(fracParts[1])),
              den != 0
        else {
            throw LengthParseError.invalidFormat(text)
        }

        guard num <= Int64.max / 64 else {
            throw LengthParseError.overflow
        }
        let fractionSixtyFourths = (num * 64) / den
        guard let wholeSixtyFourths = multiply(whole, 64) else {
            throw LengthParseError.overflow
        }
        guard let totalSixtyFourths = add(wholeSixtyFourths, fractionSixtyFourths) else {
            throw LengthParseError.overflow
        }
        return totalSixtyFourths
    }

    private static func formatMetric(_ length: Length) -> String {
        let mm = length.ticks / Length.ticksPerMillimeter
        return "\(mm) mm"
    }

    private static func formatFeetInchesFractions(_ length: Length) -> String {
        var remainder = length.ticks
        let feet = remainder / (12 * ticksPerInch)
        remainder -= feet * 12 * ticksPerInch
        let inches = remainder / ticksPerInch
        remainder -= inches * ticksPerInch
        let sixtyFourths = remainder / Length.ticksPerSixtyFourthInch

        if sixtyFourths == 0 {
            return "\(feet)'-\(inches)\""
        }
        if inches == 0 && feet == 0 {
            return "1/\(64 / sixtyFourths)"
        }
        return "\(feet)'-\(inches) \(sixtyFourths)/64\""
    }

    private static func parsePositiveInteger(_ text: String) -> Int64? {
        guard !text.isEmpty, text.allSatisfy(\.isNumber) else { return nil }
        return Int64(text)
    }

    private static func parseNonNegativeInteger(_ text: String) -> Int64? {
        parsePositiveInteger(text)
    }

    private static func multiply(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let (product, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        return overflow ? nil : product
    }

    private static func add(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? nil : sum
    }
}
