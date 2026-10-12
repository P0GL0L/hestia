import ATContracts
import Foundation

/// The live figures the plan shows while drawing and moving: a wall's length and direction, how far a drag has
/// moved, and where the pointer is, in the project's units.
enum PlanReadout {
    /// The direction from `a` to `b` in degrees counterclockwise from the plan's +x (east), from 0 up to 360, to
    /// a tenth of a degree, a whole degree written without the tenth: "30°", "112.5°". Empty when the points
    /// are the same.
    static func angle(from a: Point2, to b: Point2) -> String {
        let dx = Double(b.x.ticks - a.x.ticks), dy = Double(b.y.ticks - a.y.ticks)
        guard dx != 0 || dy != 0 else { return "" }
        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        var tenths = (degrees * 10).rounded()
        if tenths >= 3600 { tenths = 0 }
        let whole = tenths.truncatingRemainder(dividingBy: 10) == 0
        return (whole ? String(Int(tenths / 10)) : String(format: "%.1f", tenths / 10)) + "\u{00B0}"
    }

    /// A wall being drawn from `a` to `b`: its length, then its direction.
    static func wall(from a: Point2, to b: Point2, model: HestiaModel) -> String {
        let length = model.written(PlanGeometry.distance(a, b))
        let angle = angle(from: a, to: b)
        return angle.isEmpty ? length : length + "  " + angle
    }

    /// A drag from `a` to `b`: how far it moves and which way.
    static func move(from a: Point2, to b: Point2, model: HestiaModel) -> String {
        let angle = angle(from: a, to: b)
        let distance = "moved " + model.written(PlanGeometry.distance(a, b))
        return angle.isEmpty ? distance : distance + " at " + angle
    }

    /// Where a model point is: its x and y from the model's origin.
    static func position(_ point: Point2, model: HestiaModel) -> String {
        func signed(_ length: Length) -> String {
            let written = model.written(Length(ticks: abs(length.ticks)))
            return length.ticks < 0 ? "\u{2212}" + written : written
        }
        return "X " + signed(point.x) + "   Y " + signed(point.y)
    }
}
