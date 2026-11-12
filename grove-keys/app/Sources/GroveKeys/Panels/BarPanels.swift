import AppKit
import GroveKeysCore
import GroveUI
import SwiftUI

// The bar's panels: what a panel's file has to provide, and the list of
// them. The window, the placement and the closing are `BarPanelHost`'s.
// Spec: grove-dotfiles/docs/specs/2026-11-12-bar-panels-design.md ("For
// panel authors").

/// What a panel shows: the Mac's readings, or fixed sample data for
/// `GroveKeys --render-panel` (and nothing else: no timer, no process, no
/// system call, so the render is the same on every run).
enum BarPanelData {
    case live
    case sample
}

/// A panel's model. Made once, the first time its panel opens, and kept
/// (a speed test's last result outlives a closing).
///
/// `start()` runs each time the panel opens, before it is drawn: read what
/// the panel shows and start whatever keeps it current. `stop()` runs each
/// time it closes: every timer, process and observer stops there. Between
/// `stop()` and the next `start()` a panel costs nothing. Neither is called
/// on a `.sample` model.
@MainActor
protocol BarPanelModel: AnyObject {
    func start()
    func stop()
    /// A key pressed while the panel has the keyboard, before any control in
    /// it sees it. True: the panel used it. Escape never arrives (it closes
    /// the panel), nor does a key pressed with ⌘, ⌃ or ⌥.
    func key(_ key: BarPanelKey) -> Bool
}

extension BarPanelModel {
    func key(_ key: BarPanelKey) -> Bool { false }
}

/// A key as a panel's model is told it.
enum BarPanelKey: Equatable {
    case left, right, up, down, home, end, pageUp, pageDown, enter, space
    /// A typed character, lower-cased ("t").
    case character(String)

    init?(_ event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch event.keyCode {
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        case 115: self = .home
        case 119: self = .end
        case 116: self = .pageUp
        case 121: self = .pageDown
        case 36, 76: self = .enter
        case 49: self = .space
        default:
            guard let text = event.charactersIgnoringModifiers?.lowercased(), text.count == 1,
                  let scalar = text.unicodeScalars.first, scalar.properties.isAlphabetic || ("0"..."9").contains(scalar)
            else { return nil }
            self = .character(text)
        }
    }
}

/// What a panel's views can ask of the host: `@Environment(\.barPanel)`.
@MainActor
struct BarPanelActions {
    /// Puts the panel away; the app that was in front keeps the keyboard.
    var close: @MainActor () -> Void = {}
    /// Puts the panel away and runs `action`, which brings another app or
    /// window forward: the keyboard is left with whatever that is.
    var leave: @MainActor (_ action: @MainActor () -> Void) -> Void = { _ in }

    /// Opens a link in its app and puts the panel away: a Settings pane
    /// (`x-apple.systempreferences:com.apple.Battery-Settings.extension`).
    func open(_ url: URL) {
        leave { NSWorkspace.shared.open(url) }
    }

    /// Opens an app by bundle ID and puts the panel away ("Activity Monitor…").
    func openApp(bundleID: String) {
        leave {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(),
                                               completionHandler: nil)
        }
    }
}

private struct BarPanelActionsKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue = BarPanelActions()
}

extension EnvironmentValues {
    /// The host's actions for the panel under here; they do nothing in a render.
    var barPanel: BarPanelActions {
        get { self[BarPanelActionsKey.self] }
        set { self[BarPanelActionsKey.self] = newValue }
    }
}

/// One panel, as the host knows it: its link's name, the pill it hangs
/// from, its width, and how to make its model and its view. Each panel's
/// file declares one as `static let registration` and `BarPanels.all` lists it.
@MainActor
final class BarPanelRegistration {
    /// The `<name>` of `grovekeys://panel/<name>`.
    let name: String
    /// The bar's bracket the panel hangs from ("pill.clock").
    let pill: String
    let anchor: BarPanelAnchor
    /// The panel's width; its `BarPanel(width:)` must be given the same.
    let width: CGFloat
    private let make: @MainActor (BarPanelData) -> (model: any BarPanelModel, view: AnyView)
    private var live: (model: any BarPanelModel, view: AnyView)?

    /// - `anchor`: `.trailing` (the right edge on the pill's right outline)
    ///   for every panel but the Grove menu.
    /// - `model`: makes the model; `.live` once per run of the app, `.sample`
    ///   for each render.
    /// - `content`: the panel's view, a `BarPanel(width:)` of this width. It
    ///   is as tall as its content, and may change height while open: the
    ///   host follows, keeping the top and the anchored edge where they are.
    init<Model: BarPanelModel, Content: View>(
        _ name: String, pill: String, anchor: BarPanelAnchor = .trailing, width: CGFloat,
        model: @escaping @MainActor (BarPanelData) -> Model,
        @ViewBuilder content: @escaping @MainActor (Model) -> Content
    ) {
        precondition(KeysURL(URL(string: "grovekeys://panel/\(name)")!) == .panel(name: name), "not a panel name: \(name)")
        precondition(BarPanelFile.isItemName(pill), "not a bar item: \(pill)")
        self.name = name
        self.pill = pill
        self.anchor = anchor
        self.width = width
        make = { data in
            let model = model(data)
            return (model, AnyView(content(model)))
        }
    }

    /// The live model and its view, made at the first opening.
    func opened() -> (model: any BarPanelModel, view: AnyView) {
        if let live { return live }
        let made = make(.live)
        live = made
        return made
    }

    /// The panel on its sample data, for a render.
    func sample() -> AnyView { make(.sample).view }
}

/// Every bar panel. A new panel is a file in this folder and a line here;
/// replacing a placeholder's body touches neither this list nor the host.
@MainActor
enum BarPanels {
    static let all: [BarPanelRegistration] = [
        ClockPanel.registration,
        SystemPanel.registration,
        BatteryPanel.registration,
        WifiPanel.registration,
        SoundPanel.registration,
    ]

    static func named(_ name: String) -> BarPanelRegistration? {
        all.first { $0.name == name }
    }
}
