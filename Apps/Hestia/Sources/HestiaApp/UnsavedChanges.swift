import AppKit
import SwiftUI

/// Each open window's check before its document is dropped, so Quit can ask every window in turn.
@MainActor
final class UnsavedChanges {
    static let shared = UnsavedChanges()

    private var checks: [UUID: @MainActor () -> Bool] = [:]
    private var order: [UUID] = []

    /// Adds or replaces a window's check. The check asks about unsaved changes and returns whether to go ahead.
    func register(_ window: UUID, check: @escaping @MainActor () -> Bool) {
        if checks[window] == nil { order.append(window) }
        checks[window] = check
    }

    func remove(_ window: UUID) {
        checks[window] = nil
        order.removeAll { $0 == window }
    }

    /// Asks each window, in the order they opened, and stops at the first that stays. Returns whether every
    /// window may go.
    func confirmAll() -> Bool {
        for window in order {
            if let check = checks[window], !check() { return false }
        }
        return true
    }
}

/// Holds Quit until every window with unsaved changes has been asked.
@MainActor
final class HestiaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        UnsavedChanges.shared.confirmAll() ? .terminateNow : .terminateCancel
    }
}

/// Asks before its window closes, by the close button or Close. It stands in as the window's delegate and passes
/// every other delegate message on to the delegate SwiftUI set.
struct WindowCloseGuard: NSViewRepresentable {
    var shouldClose: @MainActor () -> Bool

    func makeNSView(context: Context) -> GuardView {
        let view = GuardView()
        view.shouldClose = shouldClose
        return view
    }

    func updateNSView(_ view: GuardView, context: Context) {
        view.shouldClose = shouldClose
    }

    final class GuardView: NSView {
        var shouldClose: @MainActor () -> Bool = { true }
        private var proxy: WindowDelegateProxy?

        /// It draws nothing and takes no clicks.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !(window.delegate is WindowDelegateProxy) else { return }
            let proxy = WindowDelegateProxy(original: window.delegate as? NSObject) { [weak self] in
                self?.shouldClose() ?? true
            }
            window.delegate = proxy
            self.proxy = proxy
        }
    }
}

/// A weak reference that can be read from any isolation; the object it names is only messaged on the main thread.
final class WeakObject: @unchecked Sendable {
    weak var value: NSObject?

    init(_ value: NSObject?) {
        self.value = value
    }
}

/// A window delegate that asks before closing and forwards everything else to the original delegate.
@MainActor
final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    private let original: WeakObject
    private let shouldClose: @MainActor () -> Bool

    init(original: NSObject?, shouldClose: @escaping @MainActor () -> Bool) {
        self.original = WeakObject(original)
        self.shouldClose = shouldClose
        super.init()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard shouldClose() else { return false }
        return (original.value as? NSWindowDelegate)?.windowShouldClose?(sender) ?? true
    }

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original.value?.responds(to: aSelector) ?? false)
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let target = original.value, target.responds(to: aSelector) { return target }
        return super.forwardingTarget(for: aSelector)
    }
}
