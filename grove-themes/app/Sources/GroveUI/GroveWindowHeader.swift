import AppKit
import GroveThemesCore
import SwiftUI

/// Where a window's header sits, from where its buttons (close, minimise,
/// zoom) are in a window without a title bar. Pure.
public struct WindowHeaderMetrics: Equatable, Sendable {
    /// The buttons' centre line, in points below the window's top edge.
    public var centerY: CGFloat
    /// The right edge of the last button, in points from the window's left edge.
    public var buttonsEnd: CGFloat

    public init(centerY: CGFloat, buttonsEnd: CGFloat) {
        self.centerY = centerY
        self.buttonsEnd = buttonsEnd
    }

    /// Where macOS 27 puts them (measured: 14 pt buttons from 9 to 23 below
    /// the top, the zoom button ending at 69). Worn until the window is
    /// there to be measured, and if it gives nothing usable.
    public static let standard = WindowHeaderMetrics(centerY: 16, buttonsEnd: 69)

    /// From the buttons' frames in the window's coordinates (origin at the
    /// bottom left, as AppKit has them) and the window's height. Without
    /// buttons, or with ones that aren't in the top left corner (a window
    /// still being put together), `standard`.
    public init(windowHeight: CGFloat, buttons: [CGRect]) {
        let frames = buttons.filter { !$0.isEmpty }
        guard let first = frames.first, let end = frames.map(\.maxX).max() else {
            self = .standard
            return
        }
        let centerY = windowHeight - first.midY
        guard (8...40).contains(centerY), (20...160).contains(end) else {
            self = .standard
            return
        }
        self.init(centerY: centerY, buttonsEnd: end)
    }

    /// The header's band: as far below the buttons' centre line as above
    /// it, so what is centred in the band is centred on the buttons.
    public var bandHeight: CGFloat { 2 * centerY }

    /// Where the app's name starts: clear of the buttons by `GroveSpace.s16`.
    public var nameLeading: CGFloat { buttonsEnd + GroveSpace.s16 }
}

/// What every Grove window shares besides its header.
public enum GroveWindow {
    /// The content's margin at the sides and the bottom.
    public static let margin = GroveSpace.s24
    /// The gap between the header's band and the content.
    public static let contentGap = GroveSpace.s8

    /// The app's name, wherever it is written (a window's header, a
    /// menu-bar dropdown's title): the heading size, semibold. Not the
    /// wordmark's face.
    public static var nameFont: Font { GroveFont.mono(GroveType.heading, .semibold) }
}

/// The header of a Grove window (no title bar, the window's buttons over
/// the content): the app's name in JetBrains Mono on the buttons' centre
/// line, then an optional middle slot (tabs) and an optional trailing slot
/// (a status), which ends at the content's margin (`GroveSpace.s24`). The
/// same band in every Grove window, measured from the window's own buttons
/// (`WindowHeaderMetrics`), not guessed. The content below starts
/// `GroveWindow.contentGap` under it and keeps `GroveWindow.margin` at the
/// sides and bottom.
///
/// Put it at the top of a view that ignores the top safe area.
public struct GroveWindowHeader<Middle: View, Trailing: View>: View {
    let name: String
    let middle: Middle
    let trailing: Trailing
    @Environment(\.theme) private var theme
    /// `State` used directly: the Command Line Tools ship no SwiftUI macros.
    private var metrics = State(initialValue: WindowHeaderMetrics.standard)

    public init(_ name: String, @ViewBuilder middle: () -> Middle, @ViewBuilder trailing: () -> Trailing) {
        self.name = name
        self.middle = middle()
        self.trailing = trailing()
    }

    public var body: some View {
        let metrics = metrics.wrappedValue
        HStack(spacing: 0) {
            Text(name)
                .font(GroveWindow.nameFont)
                .foregroundStyle(Color(theme.fg))
                .accessibilityAddTraits(.isHeader)
            middle.padding(.leading, GroveSpace.s24)
            Spacer(minLength: GroveSpace.s16)
            trailing
        }
        .padding(.leading, metrics.nameLeading)
        .padding(.trailing, GroveWindow.margin)
        .frame(height: metrics.bandHeight)
        .background(WindowAccessor { [state = self.metrics] window in
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            let frames = buttons.compactMap { window.standardWindowButton($0) }.map { $0.convert($0.bounds, to: nil) }
            let measured = WindowHeaderMetrics(windowHeight: window.frame.height, buttons: frames)
            if measured != state.wrappedValue { state.wrappedValue = measured }
        })
    }
}

extension GroveWindowHeader where Middle == EmptyView {
    /// Without a middle slot.
    public init(_ name: String, @ViewBuilder trailing: () -> Trailing) {
        self.init(name, middle: { EmptyView() }, trailing: trailing)
    }
}
