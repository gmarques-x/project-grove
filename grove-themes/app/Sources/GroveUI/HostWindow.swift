import AppKit

/// The window a view is in, watched for mouse clicks, key presses and the
/// window becoming or ceasing to be key. What decides when a keyboard focus
/// box shows (`KeyboardFocusRing`, Grove Themes' `KeyboardNavigation`).
@MainActor
public final class HostWindow {
    public enum Event {
        /// A mouse button went down in the window.
        case mouseDown
        /// A key went down in the window, before any view has it.
        case keyDown(NSEvent)
        case becameKey
        case resignedKey
        case willClose
    }

    private weak var window: NSWindow?
    // `nonisolated(unsafe)` for `deinit` only, which SwiftUI runs on the main
    // thread when the view goes (the window closed).
    private nonisolated(unsafe) var monitor: Any?
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    public init() {}

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// `childWindows`: clicks and keys in the window's popovers count too.
    public func attach(_ window: NSWindow, childWindows: Bool = false,
                       onEvent: @escaping @MainActor (Event) -> Void) {
        guard window !== self.window else { return }
        detach()
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak window] event in
            if let window, event.window === window || (childWindows && event.window?.parent === window) {
                MainActor.assumeIsolated { onEvent(event.type == .keyDown ? .keyDown(event) : .mouseDown) }
            }
            return event
        }
        let names = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willCloseNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    switch name {
                    case NSWindow.didBecomeKeyNotification: onEvent(.becameKey)
                    case NSWindow.didResignKeyNotification: onEvent(.resignedKey)
                    default: onEvent(.willClose)
                    }
                }
            }
        }
    }

    public func detach() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        window = nil
    }
}
