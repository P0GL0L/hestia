import AppKit
import SwiftUI

/// What the plan view hears from the mouse, trackpad, and keyboard. Points are in the view, top left at zero.
enum PlanInput: Equatable {
    case moved(CGPoint)
    case down(CGPoint, clicks: Int)
    case dragged(CGPoint)
    case up(CGPoint)
    /// A right-click or Control-click.
    case secondary(CGPoint)
    case exited
    /// A scroll: `precise` for a trackpad, which pans; a wheel zooms.
    case scroll(dx: Double, dy: Double, precise: Bool, at: CGPoint)
    case magnify(Double, at: CGPoint)
    case key(PlanKey)
}

enum PlanKey: Equatable {
    case escape
    case delete
    case enter
    case backspace
    /// Any other typed text, such as a digit or a foot mark.
    case text(String)
}

/// A clear layer over the plan that reports the pointer, drags, scrolls, pinches, and keys.
struct PlanMouse: NSViewRepresentable {
    var onInput: @MainActor (PlanInput) -> Void

    func makeNSView(context: Context) -> PlanMouseView {
        let view = PlanMouseView()
        view.onInput = onInput
        return view
    }

    func updateNSView(_ view: PlanMouseView, context: Context) {
        view.onInput = onInput
    }
}

final class PlanMouseView: NSView {
    var onInput: @MainActor (PlanInput) -> Void = { _ in }
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private func location(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func mouseMoved(with event: NSEvent) {
        onInput(.moved(location(event)))
    }

    override func mouseExited(with event: NSEvent) {
        onInput(.exited)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.modifierFlags.contains(.control) {
            onInput(.secondary(location(event)))
            return
        }
        onInput(.down(location(event), clicks: event.clickCount))
    }

    override func mouseDragged(with event: NSEvent) {
        onInput(.dragged(location(event)))
    }

    override func mouseUp(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { return }
        onInput(.up(location(event)))
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onInput(.secondary(location(event)))
    }

    override func scrollWheel(with event: NSEvent) {
        onInput(.scroll(dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY),
                        precise: event.hasPreciseScrollingDeltas, at: location(event)))
    }

    override func magnify(with event: NSEvent) {
        onInput(.magnify(Double(event.magnification), at: location(event)))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onInput(.key(.escape))
        case 117: onInput(.key(.delete))
        case 51: onInput(.key(.backspace))
        case 36, 76: onInput(.key(.enter))
        default:
            guard let text = event.characters, !text.isEmpty,
                  !event.modifierFlags.contains(.command) else {
                super.keyDown(with: event)
                return
            }
            onInput(.key(.text(text)))
        }
    }
}
