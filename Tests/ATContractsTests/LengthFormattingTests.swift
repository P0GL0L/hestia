import ATContracts
import Foundation
import Testing

@Test func lengthOneMillimeter() throws {
    let length = try LengthFormatting.parse("1 mm")
    #expect(length == Length.millimeters(1))
    #expect(length.ticks == 320)
    #expect(LengthFormatting.format(length, style: .metric) == "1 mm")
}

@Test func lengthOneSixtyFourthInch() throws {
    let length = try LengthFormatting.parse("1/64")
    #expect(length == Length.sixtyFourthInches(1))
    #expect(length.ticks == 127)
}

@Test func lengthSixFeetZeroInches() throws {
    let length = try LengthFormatting.parse("6'-0\"")
    #expect(length == Length.feet(6))
    #expect(length.ticks == 585_216)
    #expect(LengthFormatting.format(length, style: .feetInchesFractions) == "6'-0\"")
}
