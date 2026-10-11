import Foundation

/// What the 3D view does with a scroll or a pinch, decided apart from AppKit so it can be tested.
///
/// While walking, nothing a wheel, trackpad, or pinch sends may zoom: the walk's camera is the walker's eye, and
/// SceneKit's own camera control would move it. Orbiting, a mouse wheel zooms in steps, and trackpad scrolling or
/// Option with the wheel keeps SceneKit's handling.
enum HouseZoom {
    enum Action: Equatable {
        /// Consumed: nothing moves.
        case ignore
        /// The orbiting camera moves to this many times its distance.
        case zoom(Double)
        /// Handed to SceneKit's camera control.
        case sceneKit
    }

    /// How much one zoom step or wheel notch moves the orbiting camera toward its target.
    static let step = 0.8
    /// How many + or − presses the view keeps count of either way: beyond the camera's 3 to 3,000 ft reach
    /// they would do nothing anyway.
    static let presses = 40

    static func wheel(walking: Bool, precise: Bool, option: Bool, deltaY: Double) -> Action {
        if walking { return .ignore }
        if precise || option { return .sceneKit }
        if deltaY == 0 { return .ignore }
        return .zoom(deltaY > 0 ? step : 1 / step)
    }

    /// A pinch: SceneKit zooms the orbit with it; while walking it is consumed.
    static func pinch(walking: Bool) -> Action {
        walking ? .ignore : .sceneKit
    }

    /// The press count after one more press `by` +1 or −1, kept within `presses` either way.
    static func pressed(_ count: Int, by change: Int) -> Int {
        min(max(count + change, -presses), presses)
    }
}
