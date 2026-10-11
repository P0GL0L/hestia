import Foundation

/// Metering for the walk-through camera, as a photographer meters: a small picture of what the camera sees is
/// measured, and the exposure moved until its mean brightness is near `target`. Rooms are lit very differently
/// from house to house, and the same scene comes out brighter on one Mac's GPU than another's, so no fixed
/// exposure suits them all.
enum Exposure {
    /// The mean luminance a walk aims for, 0 to 255: a little under the middle, as a room photograph sits.
    static let target = 118.0
    /// How near the target a picture must be to leave the exposure alone.
    static let near = 15.0

    /// How many stops to move the exposure for a picture of `mean` luminance, at most `largest` either way; nil
    /// when it is near enough. sRGB values are about the 2.2 power of light, so a picture twice too bright in its
    /// values is about 2.2 stops over. A clipped or black picture says only which way to go.
    static func step(mean: Double, largest: Double) -> Double? {
        guard abs(mean - target) > near else { return nil }
        let step: Double
        if mean >= 250 {
            step = -largest
        } else if mean <= 3 {
            step = largest
        } else {
            step = 2.2 * log2(target / mean)
        }
        return min(max(step, -largest), largest)
    }

    /// The mean luminance, 0 to 255, of 8-bit RGBA pixels.
    static func mean(_ bytes: [UInt8]) -> Double? {
        let count = bytes.count / 4
        guard count > 0 else { return nil }
        var sum = 0.0
        for index in 0..<count {
            let base = index * 4
            sum += 0.2126 * Double(bytes[base]) + 0.7152 * Double(bytes[base + 1]) + 0.0722 * Double(bytes[base + 2])
        }
        return sum / Double(count)
    }
}
