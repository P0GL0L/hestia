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

@Test func imperialFormattingReducesFractionsAndRounds() throws {
    #expect(LengthFormatting.format(.sixtyFourthInches(3024), style: .feetInchesFractions) == "3'-11 1/4\"")
    #expect(LengthFormatting.format(.sixtyFourthInches(3), style: .feetInchesFractions) == "0'-0 3/64\"")
    #expect(LengthFormatting.format(.inches(-18), style: .feetInchesFractions) == "-1'-6\"")
    // 1/320 mm short of 1/64" still rounds to 1/64".
    #expect(LengthFormatting.format(Length(ticks: 126), style: .feetInchesFractions) == "0'-0 1/64\"")
    for count: Int64 in [0, 1, 32, 100, 3024, 9999] {
        let length = Length.sixtyFourthInches(count)
        #expect(try LengthFormatting.parse(LengthFormatting.format(length, style: .feetInchesFractions)) == length)
    }
}

@Test func metricFormattingRoundsToWholeMillimeters() {
    #expect(LengthFormatting.format(Length(ticks: 479), style: .metric) == "1 mm")
    #expect(LengthFormatting.format(Length(ticks: 480), style: .metric) == "2 mm")
    #expect(LengthFormatting.format(.millimeters(-250), style: .metric) == "-250 mm")
}
