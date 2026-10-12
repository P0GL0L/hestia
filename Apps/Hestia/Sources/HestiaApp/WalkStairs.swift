import ATContracts
import Foundation

/// The whole house as a walk sees it: each storey's walls (`WalkBarriers`) and the stairs between storeys, so a
/// walk can climb from floor to floor.
///
/// A stair is walked as a ramp along its run, from its storey's floor at the first riser up to the floor its
/// risers reach at the top. A walker steps onto it only at an end, where it is level with the floor, and keeps
/// within its width while on it; from the floor below, the stair's high part blocks the way, and from the floor
/// above, its opening does. While climbing, the walls of the storey below count until halfway, then the
/// storey above's, so leaving at the top meets the upper floor's walls.
struct WalkHouse: Equatable, Sendable {
    /// One straight flight, in plan feet.
    struct Flight: Equatable, Sendable {
        var startX: Double
        var startY: Double
        var ux: Double
        var uy: Double
        var length: Double
        var halfWidth: Double
        /// Floor heights at the first riser and at the top, in feet.
        var bottom: Double
        var top: Double
        var lower: StoreyID
        var upper: StoreyID?

        /// How far along the run from the first riser, and how far to its left.
        func local(_ x: Double, _ y: Double) -> (along: Double, across: Double) {
            let (dx, dy) = (x - startX, y - startY)
            return (dx * ux + dy * uy, -dx * uy + dy * ux)
        }

        func point(along: Double, across: Double) -> (x: Double, y: Double) {
            (startX + ux * along - uy * across, startY + uy * along + ux * across)
        }

        /// Whether a plan point lies over the flight, or within `margin` of it.
        func covers(_ x: Double, _ y: Double, margin: Double = 0) -> Bool {
            let place = local(x, y)
            return place.along > -margin && place.along < length + margin && abs(place.across) < halfWidth + margin
        }

        /// The height of the walking line at `along`.
        func height(_ along: Double) -> Double {
            bottom + (top - bottom) * min(max(along / length, 0), 1)
        }
    }

    /// The tallest step up or down a walker takes onto a stair.
    static let stepLimit = 1.0
    /// How far the walker's middle stays from a stair's sides.
    static let sideRoom = 0.3

    var levels: [StoreyID: WalkBarriers]
    var flights: [Flight]

    init(levels: [StoreyID: WalkBarriers], flights: [Flight]) {
        self.levels = levels
        self.flights = flights
    }

    /// Every storey's walls and every straight stair with a run, each reaching the next storey up.
    init(document: ModelDocument) {
        var levels: [StoreyID: WalkBarriers] = [:]
        for storey in document.storeys {
            levels[storey.id] = WalkBarriers(document: document, storey: storey.id)
        }
        self.init(levels: levels, flights: Self.flights(document))
    }

    /// Every stair with a run and a rise, as a flight from its storey's floor to the next storey up.
    static func flights(_ document: ModelDocument) -> [Flight] {
        let storeys = document.storeys.sorted { $0.elevation.ticks < $1.elevation.ticks }
        var flights: [Flight] = []
        for stair in document.stairs {
            guard stair.kind == .straight else { continue }
            guard let storey = storeys.first(where: { $0.id == stair.storeyID }) else { continue }
            let (sx, sy) = (HouseScene.feet(stair.runStart.x), HouseScene.feet(stair.runStart.y))
            let (ex, ey) = (HouseScene.feet(stair.runEnd.x), HouseScene.feet(stair.runEnd.y))
            let length = ((ex - sx) * (ex - sx) + (ey - sy) * (ey - sy)).squareRoot()
            let rise = HouseScene.feet(stair.riserHeight) * Double(stair.riserCount)
            guard length > 0.5, rise > 0 else { continue }
            let bottom = HouseScene.feet(storey.elevation)
            guard let upper = storeys.first(where: {
                $0.buildingID == storey.buildingID && $0.elevation.ticks > storey.elevation.ticks
            }) else { continue }
            let top = HouseScene.feet(upper.elevation)
            guard abs(bottom + rise - top) < 0.05 else { continue }
            flights.append(Flight(startX: sx, startY: sy, ux: (ex - sx) / length, uy: (ey - sy) / length,
                                  length: length, halfWidth: HouseScene.feet(stair.width) / 2, bottom: bottom,
                                  top: top, lower: storey.id, upper: upper.id))
        }
        return flights
    }

    /// The walls a walker on `storey` cannot pass; none for a storey the house does not have.
    func barriers(_ storey: StoreyID?) -> WalkBarriers {
        storey.flatMap { levels[$0] } ?? WalkBarriers(segments: [])
    }

    /// The flight a walker standing at (x, y) on `floor` is on: over it, at its height.
    func flight(under x: Double, _ y: Double, floor: Double, storey: StoreyID?) -> Int? {
        flights.firstIndex { flight in
            (flight.lower == storey || flight.upper == storey) && flight.covers(x, y, margin: 1e-9)
                && abs(flight.height(flight.local(x, y).along) - floor) < 0.05
        }
    }

    /// One short move of a walker to (x, y): along a flight it is on, onto one it reaches level with its floor,
    /// or across its storey's floor, stopped by walls and kept a body's width from any flight it meets anywhere
    /// but level, sliding along it when it can.
    func move(_ walker: inout Walker, toX x: Double, y: Double) {
        if let index = flight(under: walker.x, walker.y, floor: walker.floor, storey: walker.storey) {
            climb(&walker, flights[index], toX: x, y: y)
            return
        }
        let barriers = barriers(walker.storey)
        let activeFlights = flights.filter { $0.lower == walker.storey || $0.upper == walker.storey }
        // Straight there, else along each axis alone, so a walk slides along a stair's side.
        for (tx, ty) in [(x, y), (x, walker.y), (walker.x, y)] {
            let (px, py) = barriers.resolve(x: tx, y: ty, radius: Walker.radius)
            if blocked(px, py, floor: walker.floor, flights: activeFlights) { continue }
            if activeFlights.contains(where: { flight in
                guard flight.covers(px, py, margin: Walker.radius) else { return false }
                let place = flight.local(px, py)
                let bottom = place.along <= Walker.radius
                    && abs(walker.floor - flight.bottom) <= Self.stepLimit
                let top = place.along >= flight.length - Walker.radius
                    && abs(walker.floor - flight.top) <= Self.stepLimit
                return !bottom && !top
            }) { continue }
            // A wall may push a walker, but never onto a stair it was not stepping onto.
            if activeFlights.contains(where: { $0.covers(px, py) && !$0.covers(tx, ty) }) { continue }
            for flight in activeFlights where flight.covers(px, py) {
                walker.floor = flight.height(flight.local(px, py).along)
                break
            }
            (walker.x, walker.y) = (px, py)
            return
        }
    }

    /// Whether a walker on `floor` at (x, y) would stand in a flight that is not level with it there: the side
    /// of a stair from below, or its opening from above, a body's width out.
    func blocked(_ x: Double, _ y: Double, floor: Double, flights: [Flight]) -> Bool {
        flights.contains { flight in
            guard flight.covers(x, y, margin: Walker.radius) else { return false }
            let height = flight.height(flight.local(x, y).along)
            // Over the flight itself it must be level; beside it, only a flight that rises past a step blocks.
            return abs(height - floor) > Self.stepLimit
        }
    }

    /// A move while on a flight: up or down it within its width, or off an end onto that end's floor, where
    /// the floor's walls count again; a wall there holds the walker at the end, never pushes it back down.
    private func climb(_ walker: inout Walker, _ flight: Flight, toX x: Double, y: Double) {
        let place = flight.local(x, y)
        let room = max(flight.halfWidth - Self.sideRoom, 0)
        let across = min(max(place.across, -room), room)
        let atTop = place.along >= flight.length
        guard place.along <= 0 || atTop else {
            let storey = place.along < flight.length / 2 ? flight.lower : (flight.upper ?? flight.lower)
            let target = flight.point(along: place.along, across: across)
            let resolved = barriers(storey).resolve(x: target.x, y: target.y, radius: Walker.radius)
            let shifted = abs(resolved.0 - target.x) > 1e-9 || abs(resolved.1 - target.y) > 1e-9
            let nearTop = place.along > flight.length - 2 * Walker.radius
            let nearBottom = place.along < 2 * Walker.radius
            if shifted, nearTop || nearBottom {
                let end = nearTop ? flight.length : 0
                let endStorey = nearTop ? (flight.upper ?? flight.lower) : flight.lower
                let endPoint = flight.point(along: end, across: across)
                let endResolved = barriers(endStorey).resolve(x: endPoint.x, y: endPoint.y, radius: Walker.radius)
                if abs(endResolved.0 - endPoint.x) > 1e-9 || abs(endResolved.1 - endPoint.y) > 1e-9 {
                    walker.storey = endStorey
                    walker.floor = nearTop ? flight.top : flight.bottom
                    (walker.x, walker.y) = endPoint
                    return
                }
            }
            let held = flight.local(resolved.0, resolved.1)
            let heldAlong = min(max(held.along, 0), flight.length)
            let heldAcross = min(max(held.across, -room), room)
            walker.storey = heldAlong < flight.length / 2 ? flight.lower : (flight.upper ?? flight.lower)
            walker.floor = flight.height(heldAlong)
            (walker.x, walker.y) = flight.point(along: heldAlong, across: heldAcross)
            return
        }
        let storey = atTop ? (flight.upper ?? flight.lower) : flight.lower
        let end = atTop ? flight.length : 0
        let off = flight.point(along: place.along, across: place.across)
        var (px, py) = barriers(storey).resolve(x: off.x, y: off.y, radius: Walker.radius)
        if abs(px - off.x) > 1e-9 || abs(py - off.y) > 1e-9 {
            (px, py) = flight.point(along: end, across: across)
        }
        walker.storey = storey
        walker.floor = atTop ? flight.top : flight.bottom
        (walker.x, walker.y) = (px, py)
    }
}
