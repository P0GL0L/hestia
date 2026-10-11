import Testing
@testable import HestiaApp

@Suite("3D view zoom input")
struct HouseZoomTests {
    @Test("While walking, no wheel, trackpad, Option-scroll, or pinch input zooms or reaches SceneKit")
    func walkingConsumesEveryZoomInput() {
        for precise in [false, true] {
            for option in [false, true] {
                for delta in [-3.0, -0.5, 0, 0.5, 3] {
                    let action = HouseZoom.wheel(walking: true, precise: precise, option: option, deltaY: delta)
                    #expect(action == .ignore, "precise \(precise), option \(option), delta \(delta)")
                }
            }
        }
        #expect(HouseZoom.pinch(walking: true) == .ignore)
    }

    @Test("Orbiting, a mouse wheel zooms in steps, and a trackpad, Option-scroll, or pinch goes to SceneKit")
    func orbitingZooms() {
        #expect(HouseZoom.wheel(walking: false, precise: false, option: false, deltaY: 2) == .zoom(HouseZoom.step))
        #expect(HouseZoom.wheel(walking: false, precise: false, option: false, deltaY: -2)
            == .zoom(1 / HouseZoom.step))
        #expect(HouseZoom.wheel(walking: false, precise: false, option: false, deltaY: 0) == .ignore)
        #expect(HouseZoom.wheel(walking: false, precise: true, option: false, deltaY: 2) == .sceneKit)
        #expect(HouseZoom.wheel(walking: false, precise: false, option: true, deltaY: 2) == .sceneKit)
        #expect(HouseZoom.pinch(walking: false) == .sceneKit)
    }

    @Test("The + and − press count stays within its bounds")
    func pressesAreBounded() {
        var count = 0
        for _ in 0..<100 { count = HouseZoom.pressed(count, by: 1) }
        #expect(count == HouseZoom.presses)
        for _ in 0..<300 { count = HouseZoom.pressed(count, by: -1) }
        #expect(count == -HouseZoom.presses)
        #expect(HouseZoom.pressed(0, by: 1) == 1)
    }
}
