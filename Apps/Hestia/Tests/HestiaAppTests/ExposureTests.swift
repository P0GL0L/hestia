@testable import HestiaApp
import Foundation
import Testing

@Test func aPictureNearTheTargetKeepsItsExposure() {
    #expect(Exposure.step(mean: Exposure.target, largest: 3) == nil)
    #expect(Exposure.step(mean: Exposure.target + 10, largest: 3) == nil)
}

@Test func aBrightPictureIsStoppedDownAndADarkOneOpenedUp() throws {
    // Twice the target's values is about 2.2 stops too much light.
    let over = try #require(Exposure.step(mean: 236, largest: 3))
    #expect(abs(over + 2.2) < 0.01)
    let under = try #require(Exposure.step(mean: 59, largest: 3))
    #expect(abs(under - 2.2) < 0.01)
    // Clipped white or black says only which way, by the largest step.
    #expect(Exposure.step(mean: 254, largest: 3) == -3)
    #expect(Exposure.step(mean: 0, largest: 3) == 3)
    #expect(Exposure.step(mean: 250, largest: 0.5) == -0.5)
}

@Test func meanLuminanceWeighsGreenMost() throws {
    let green: [UInt8] = [0, 255, 0, 255], white: [UInt8] = [255, 255, 255, 255]
    #expect(abs(try #require(Exposure.mean(green)) - 0.7152 * 255) < 0.01)
    #expect(abs(try #require(Exposure.mean(white + white)) - 255) < 0.01)
    #expect(Exposure.mean([]) == nil)
}
