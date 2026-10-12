import AppKit
import ATContracts
import SceneKit
import SwiftUI

/// How the 3D view is driven: orbiting the house from outside, or walking through it at eye height.
enum HouseViewMode: Equatable {
    case orbit
    case walk
}

/// The house in 3D: upright, in daylight, on its site.
///
/// Orbit turns the house like a turntable around its middle (drag), pans (two-finger or right drag), and zooms
/// (scroll or pinch); the roof can be hidden to look down into the rooms. Walk puts the camera at eye height in
/// the largest room: W A S D or the arrow keys move, a drag looks around, Shift runs, and Escape leaves. Walls
/// stop the walker; doors and cased openings let it through, and stairs take it up and down (`WalkHouse`).
///
/// With the asset library (`LiveLook`), surfaces wear photographed materials, furniture and planting are finished
/// models, and the sky photo lights the house; without it, the house draws in flat colors with simple shapes.
///
/// An edit refills the scene but keeps the camera where the person left it. New and Open start another session,
/// and the camera starts over.
struct HouseView: NSViewRepresentable {
    var scene: HouseScene
    var document: ModelDocument
    var meshes: [Mesh]
    var sessionID: UUID
    var mode: HouseViewMode
    var showRoof: Bool
    /// Zoom steps from the + and − buttons: each step closer or farther takes a fifth off or puts it back.
    var zoom: Int
    var walkStart: Walker
    var house: WalkHouse
    var onLeaveWalk: @MainActor () -> Void

    final class Coordinator {
        var scene: HouseScene?
        var document: ModelDocument?
        var meshes: [Mesh]?
        var shown: HouseScene?
        var sessionID: UUID?
        var mode = HouseViewMode.orbit
        /// The zoom presses already applied (`HouseZoom.Tracker`): a new coordinator starts with none noted.
        var zoom = HouseZoom.Tracker()
        let content = SCNNode()
        let orbitCamera = SCNNode()
        let roomLights = SCNNode()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> HouseSCNView {
        let view = HouseSCNView()
        view.backgroundColor = NSColor(calibratedRed: 0.68, green: 0.81, blue: 0.94, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.worldUp = SCNVector3(0, 1, 0)
        view.defaultCameraController.inertiaEnabled = true
        let world = SCNScene()
        let look = LiveLook.shared
        if let look {
            _ = look.light(world)
        } else {
            Self.addLights(to: world.rootNode)
        }
        world.rootNode.addChildNode(context.coordinator.content)
        world.rootNode.addChildNode(context.coordinator.roomLights)
        let camera = SCNCamera()
        camera.zNear = 0.3
        camera.fieldOfView = 50
        look?.tune(camera, inside: false)
        view.look = look
        context.coordinator.orbitCamera.camera = camera
        world.rootNode.addChildNode(context.coordinator.orbitCamera)
        view.scene = world
        return view
    }

    func updateNSView(_ view: HouseSCNView, context: Context) {
        let coordinator = context.coordinator
        view.onLeaveWalk = onLeaveWalk
        view.house = house
        let newSession = coordinator.sessionID != sessionID
        let changed = coordinator.scene != scene || coordinator.document != document || coordinator.meshes != meshes
        if newSession || changed || coordinator.shown == nil {
            let shown: HouseScene
            if let look = LiveLook.shared {
                shown = look.houseScene(document: document, meshes: meshes)
                look.fill(coordinator.content, with: shown)
                coordinator.roomLights.childNodes.forEach { $0.removeFromParentNode() }
                look.roomLights(document).forEach(coordinator.roomLights.addChildNode)
            } else {
                shown = scene
                Self.fill(coordinator.content, with: scene)
            }
            coordinator.scene = scene
            coordinator.document = document
            coordinator.meshes = meshes
            coordinator.shown = shown
        }
        if newSession {
            coordinator.sessionID = sessionID
            aim(coordinator.orbitCamera, at: coordinator.shown ?? scene, in: view)
        }
        if mode != coordinator.mode || newSession {
            // Lit for the mode first, so a walk meters its exposure in the light it will be seen in.
            if LiveLook.shared != nil {
                // The sky lights everything as if outdoors; inside, it is turned down and the rooms are lit.
                let sky = mode == .walk ? LiveLook.insideSky : LiveLook.outsideSky
                view.scene?.lightingEnvironment.intensity = sky
            }
            coordinator.roomLights.isHidden = mode != .walk
            Self.show(coordinator.content, walking: mode == .walk, roof: showRoof)
            if mode == .walk {
                view.startWalking(walkStart)
            } else {
                view.stopWalking()
                view.pointOfView = coordinator.orbitCamera
                view.allowsCameraControl = true
            }
            coordinator.mode = mode
        }
        // A new view, or a new session's camera, takes the count as it stands; only presses since then zoom.
        let steps = coordinator.zoom.steps(for: zoom, reset: newSession)
        if steps != 0 {
            view.zoom(by: pow(HouseSCNView.zoomStep, Double(steps)))
        }
        coordinator.roomLights.isHidden = mode != .walk
        Self.show(coordinator.content, walking: mode == .walk, roof: showRoof)
    }

    /// Looks at the middle of the house from the south-east, high enough to see over the roof, and turns the
    /// orbit around that middle.
    private func aim(_ camera: SCNNode, at scene: HouseScene, in view: SCNView) {
        let center = scene.center, span = CGFloat(scene.span)
        let target = SCNVector3(CGFloat(center.x), CGFloat(center.y), CGFloat(center.z))
        camera.camera?.zFar = Double(span * 40)
        camera.position = SCNVector3(target.x + span * 0.95, target.y + span * 0.8, target.z + span * 1.3)
        camera.look(at: target)
        view.pointOfView = camera
        view.defaultCameraController.pointOfView = camera
        view.defaultCameraController.target = target
    }

    /// Soft sky light everywhere and a low afternoon sun from the south-west that casts shadows.
    private static func addLights(to root: SCNNode) {
        let sky = SCNLight()
        sky.type = .ambient
        sky.intensity = 450
        sky.color = NSColor(calibratedRed: 0.92, green: 0.95, blue: 1, alpha: 1)
        let skyNode = SCNNode()
        skyNode.light = sky
        root.addChildNode(skyNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1050
        sun.color = NSColor(calibratedRed: 1, green: 0.97, blue: 0.9, alpha: 1)
        sun.castsShadow = true
        sun.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.35)
        sun.shadowSampleCount = 8
        sun.shadowRadius = 3
        sun.shadowMapSize = CGSize(width: 4096, height: 4096)
        sun.automaticallyAdjustsShadowProjection = true
        sun.maximumShadowDistance = 400
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.9, -0.7, 0)
        root.addChildNode(sunNode)
    }

    /// Replaces the content's children with a node per solid, named for its group.
    private static func fill(_ content: SCNNode, with scene: HouseScene) {
        for child in content.childNodes {
            child.removeFromParentNode()
        }
        for solid in scene.solids where !solid.indices.isEmpty {
            content.addChildNode(node(for: solid))
        }
    }

    static func name(_ group: SolidGroup) -> String {
        switch group {
        case .house: return "house"
        case .roof: return "roof"
        case .ceiling: return "ceiling"
        case .site: return "site"
        }
    }

    /// Ceilings only while walking, so orbiting looks down into the rooms when the roof is hidden.
    private static func show(_ content: SCNNode, walking: Bool, roof: Bool) {
        for child in content.childNodes {
            switch child.name {
            case "ceiling": child.isHidden = !walking
            case "roof": child.isHidden = !roof
            default: child.isHidden = false
            }
        }
    }

    private static func node(for solid: Solid) -> SCNNode {
        let positions = solid.positions.map { SCNVector3(CGFloat($0.x), CGFloat($0.y), CGFloat($0.z)) }
        let normals = solid.normals.map { SCNVector3(CGFloat($0.x), CGFloat($0.y), CGFloat($0.z)) }
        let sources = [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)]
        let data = solid.indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: solid.indices.count / 3,
                                         bytesPerIndex: MemoryLayout<UInt32>.size)
        let geometry = SCNGeometry(sources: sources, elements: [element])
        let material = SCNMaterial()
        let color = solid.look.rgb
        material.diffuse.contents = NSColor(calibratedRed: CGFloat(color.red), green: CGFloat(color.green),
                                            blue: CGFloat(color.blue), alpha: 1)
        material.specular.contents = NSColor(calibratedWhite: solid.look == .glass || solid.look == .water ? 0.6 : 0.08,
                                             alpha: 1)
        material.transparency = CGFloat(solid.look.opacity)
        // Ceilings face down only, so they never hide the rooms from a camera above them.
        material.isDoubleSided = solid.group != .ceiling
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = name(solid.group)
        node.castsShadow = solid.group != .ceiling && solid.group != .site && solid.look != .glass
        return node
    }
}

/// The 3D view, with walking: keys move the walker, a drag turns its head, and Escape hands back to orbit.
final class HouseSCNView: SCNView {
    var house = WalkHouse(levels: [:], flights: [])
    /// The finished look, when the app has its asset library; the walking camera is tuned for it.
    var look: LiveLook?
    var onLeaveWalk: @MainActor () -> Void = {}
    private(set) var walker: Walker?
    private var held = Set<UInt16>()
    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    private var lastMeter: TimeInterval = 0
    /// Draws the small pictures the walk's exposure is metered from.
    private var meterer: SCNRenderer?
    /// The walking eye's camera, for tests.
    var walkCamera: SCNCamera? { eye.camera }
    private var lastDrag: NSPoint?
    /// Turns with the walker's heading; the eye under it tilts with the pitch.
    private let body = SCNNode()
    private let eye = SCNNode()

    override var acceptsFirstResponder: Bool { true }

    func startWalking(_ start: Walker) {
        walker = start
        if eye.camera == nil {
            let camera = SCNCamera()
            camera.zNear = 0.2
            camera.zFar = 4000
            camera.fieldOfView = 70
            look?.tune(camera, inside: true)
            eye.camera = camera
            if look == nil {
                // Without the library's lighting, a lamp at the eye keeps the rooms readable.
                let lamp = SCNLight()
                lamp.type = .omni
                lamp.intensity = 320
                lamp.castsShadow = false
                eye.light = lamp
            }
            body.addChildNode(eye)
        }
        if body.parent == nil {
            scene?.rootNode.addChildNode(body)
        }
        place()
        allowsCameraControl = false
        pointOfView = eye
        // Every walk meters afresh from the same start, so an exposure the last walk ended on, in another
        // room or another house, is never carried in.
        eye.camera?.exposureOffset = LiveLook.insideExposure
        if look != nil, let world = scene {
            if meterer == nil { meterer = LiveLook.meteringRenderer() }
            LiveLook.meter(world, from: eye, renderer: meterer)
        }
        lastMeter = ProcessInfo.processInfo.systemUptime
        held.removeAll()
        window?.makeFirstResponder(self)
        lastTick = ProcessInfo.processInfo.systemUptime
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil,
                                     repeats: true)
    }

    /// How much one zoom step or wheel notch moves the orbiting camera toward its target.
    static let zoomStep = HouseZoom.step

    /// Moves the orbiting camera along its line to what it turns around, to `factor` times the distance, never
    /// closer than 3 feet or farther than 3,000.
    func zoom(by factor: Double) {
        guard walker == nil, let camera = pointOfView else { return }
        let target = defaultCameraController.target
        let (dx, dy, dz) = (camera.position.x - target.x, camera.position.y - target.y, camera.position.z - target.z)
        let distance = Double((dx * dx + dy * dy + dz * dz).squareRoot())
        guard distance > 1e-6 else { return }
        let scale = CGFloat(min(max(distance * factor, 3), 3000) / distance)
        camera.position = SCNVector3(target.x + dx * scale, target.y + dy * scale, target.z + dz * scale)
    }

    /// A mouse wheel zooms the orbiting view; with Option held, and on a trackpad, scrolling keeps SceneKit's
    /// own handling, and pinching zooms. While walking, no wheel or trackpad input reaches SceneKit (`HouseZoom`).
    override func scrollWheel(with event: NSEvent) {
        switch HouseZoom.wheel(walking: walker != nil, precise: event.hasPreciseScrollingDeltas,
                               option: event.modifierFlags.contains(.option),
                               deltaY: Double(event.scrollingDeltaY)) {
        case .ignore: return
        case let .zoom(factor): zoom(by: factor)
        case .sceneKit: super.scrollWheel(with: event)
        }
    }

    /// A pinch zooms the orbiting view through SceneKit; while walking it is consumed.
    override func magnify(with event: NSEvent) {
        guard HouseZoom.pinch(walking: walker != nil) == .sceneKit else { return }
        super.magnify(with: event)
    }

    func stopWalking() {
        timer?.invalidate()
        timer = nil
        walker = nil
        held.removeAll()
        lastDrag = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopWalking() }
    }

    @objc private func tick() {
        guard var current = walker else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let seconds = min(max(now - lastTick, 0), 0.1)
        lastTick = now
        current.step(input(), seconds: seconds, house: house)
        walker = current
        place()
        // Every half second, one gentle round of metering, so walking from a bright room into a dim one eases
        // the exposure over rather than jumping.
        if look != nil, now - lastMeter > 0.5, let world = scene {
            lastMeter = now
            LiveLook.meter(world, from: eye, rounds: 1, largest: 0.35, renderer: meterer)
        }
    }

    /// The keys held: W A S D or the arrows, Q and E to turn, Shift to run.
    private func input() -> WalkInput {
        var input = WalkInput()
        if held.contains(13) || held.contains(126) { input.forward += 1 }
        if held.contains(1) || held.contains(125) { input.forward -= 1 }
        if held.contains(2) { input.strafe += 1 }
        if held.contains(0) { input.strafe -= 1 }
        if held.contains(124) || held.contains(14) { input.turn += 1 }
        if held.contains(123) || held.contains(12) { input.turn -= 1 }
        input.fast = NSEvent.modifierFlags.contains(.shift)
        return input
    }

    private func place() {
        guard let walker else { return }
        let eyePoint = walker.eye
        body.position = SCNVector3(CGFloat(eyePoint.x), CGFloat(eyePoint.y), CGFloat(eyePoint.z))
        body.eulerAngles = SCNVector3(0, CGFloat(-walker.heading), 0)
        eye.eulerAngles = SCNVector3(CGFloat(walker.pitch), 0, 0)
    }

    override func keyDown(with event: NSEvent) {
        guard walker != nil else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            onLeaveWalk()
            return
        }
        held.insert(event.keyCode)
    }

    override func keyUp(with event: NSEvent) {
        guard walker != nil else {
            super.keyUp(with: event)
            return
        }
        held.remove(event.keyCode)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard walker != nil else {
            super.mouseDown(with: event)
            return
        }
        lastDrag = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = walker else {
            super.mouseDragged(with: event)
            return
        }
        let point = event.locationInWindow
        if let last = lastDrag {
            current.look(dx: Double(point.x - last.x), dy: -Double(point.y - last.y))
            walker = current
            place()
        }
        lastDrag = point
    }

    override func mouseUp(with event: NSEvent) {
        guard walker != nil else {
            super.mouseUp(with: event)
            return
        }
        lastDrag = nil
    }
}
