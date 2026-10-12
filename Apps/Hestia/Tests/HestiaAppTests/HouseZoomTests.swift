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

    @Test("Every + and − press changes the count, so every press zooms, after any mix of other input")
    func everyPressCounts() {
        // The view zooms by the change in the count since it last looked. Wheel and pinch zooms move the camera
        // without touching the count, and New and Open reset the camera without touching it either, so a press
        // after any of them must still change it, in either direction, however far it has gone.
        var count = 0
        for _ in 0..<500 {
            let next = HouseZoom.pressed(count, by: 1)
            #expect(next == count + 1)
            count = next
        }
        // A wheel zoom out in between leaves the count alone; the next + press still registers.
        #expect(HouseZoom.wheel(walking: false, precise: false, option: false, deltaY: -3) == .zoom(1 / HouseZoom.step))
        #expect(HouseZoom.pressed(count, by: 1) != count)
        for _ in 0..<1_000 {
            let next = HouseZoom.pressed(count, by: -1)
            #expect(next == count - 1)
            count = next
        }
        #expect(HouseZoom.pressed(count, by: -1) != count)
    }
}
