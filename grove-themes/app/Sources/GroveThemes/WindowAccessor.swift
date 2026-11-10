import AppKit
import SwiftUI

/// Hands the hosting `NSWindow` to `configure` once the view is in it: for
/// settings SwiftUI has no modifier for on macOS 14 (e.g.
/// `isMovableByWindowBackground`; `.windowBackgroundDragBehavior` is macOS 15).
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Probe(configure: configure) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        let configure: (NSWindow) -> Void

        init(configure: @escaping (NSWindow) -> Void) {
            self.configure = configure
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { configure(window) }
        }
    }
}
