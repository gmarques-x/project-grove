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

/// Sample data more than one render draws from, invented for the public
/// repo (no real device's name or address).
@MainActor
enum BarPanelSamples {
    /// The Wi-Fi panel's Bluetooth section. GROVE_BLUETOOTH_SAMPLE picks the
    /// state: `on` (the default: three devices), `none` (on, nothing
    /// connected), `off`, `refused` (permission refused), `refused-read`
    /// (refused, the devices read anyway), `unknown` (no controller),
    /// `reading` (no reading yet).
    static func bluetooth(_ name: String) -> (state: BluetoothState?, permission: BluetoothPermission) {
        let devices = [
            BluetoothDevice(id: "00:00:00:00:00:01", name: "Headphones", kind: .headphones, battery: 60),
            BluetoothDevice(id: "00:00:00:00:00:02", name: "Keyboard", kind: .keyboard, battery: 45),
            BluetoothDevice(id: "00:00:00:00:00:03", name: "Mouse", kind: .mouse, battery: nil),
        ]
        switch name {
        case "none": return (BluetoothState(power: true, connected: []), .allowed)
        case "off": return (BluetoothState(power: false, connected: []), .allowed)
        case "refused": return (BluetoothState(power: nil, connected: []), .refused)
        case "refused-read": return (BluetoothState(power: true, connected: devices), .refused)
        case "unknown": return (BluetoothState(power: nil, connected: []), .allowed)
        case "reading": return (nil, .undetermined)
        default: return (BluetoothState(power: true, connected: devices), .allowed)
        }
    }
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
    /// Escape was pressed. True: the panel used it (a menu closing its
    /// submenu) and stays open; false, the default: the panel is put away.
    func escape() -> Bool
}

extension BarPanelModel {
    func key(_ key: BarPanelKey) -> Bool { false }
    func escape() -> Bool { false }
}

/// A panel beside an open panel: a menu's submenu. Same frame, its left
/// outline on the right outline of the panel before it (one shared line),
/// its first row level with the row it opens from, kept on the screen
/// (`MenuPlacement.submenu`). It is a child window of the main panel:
/// a click in it is not a click outside, it never takes the keyboard (the
/// keys stay the main panel's model's), and it goes when the panel does.
@MainActor
struct BarPanelSide {
    /// What tells one side panel's content from another's at the same
    /// depth; the host keeps the view while it stays the same.
    let id: AnyHashable
    /// A `BarPanel` of `size`.
    let view: AnyView
    let size: CGSize
    /// The row it opens from, in the coordinates of the panel before it
    /// (the main panel for the first side panel): points from that panel's
    /// top-left corner, y down.
    let row: CGRect
    /// From this panel's top to its first row.
    let firstRow: CGFloat
    /// Told where the host put it: true when there was no room at the right
    /// and it went to the left of the panel before it.
    var placed: (@MainActor (_ onLeft: Bool) -> Void)?
}

/// What the host gives a model that needs more of it than a view can ask
/// through `@Environment(\.barPanel)` (`BarPanelWithSides`).
@MainActor
struct BarPanelLink {
    /// The same actions the views get: for a row run from the keyboard.
    var actions = BarPanelActions()
    /// The model's `sides` changed: the host shows, moves and removes the
    /// side panels to match.
    var sidesChanged: @MainActor () -> Void = {}
    /// The main panel's outline on screen, in AppKit's coordinates; nil
    /// while it isn't shown.
    var frame: @MainActor () -> NSRect? = { nil }
}

/// A panel's model that shows side panels (a menu with submenus). The host
/// sets `link` at each opening, before `start()`, and reads `sides` after
/// showing the panel and whenever `link.sidesChanged()` is called. The
/// chain is in order: each side panel opens from a row of the one before.
@MainActor
protocol BarPanelWithSides: BarPanelModel {
    var link: BarPanelLink { get set }
    var sides: [BarPanelSide] { get }
}

/// A key as a panel's model is told it: the Grove menu's own keys
/// (`GroveMenuListKey`, from a key-down event), so a menu panel passes them on
/// as they are.
typealias BarPanelKey = GroveMenuListKey

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

    /// The same with its model, for a render that draws its side panels too.
    func sampleEntry() -> (model: any BarPanelModel, view: AnyView) { make(.sample) }
}

/// Every bar panel. A new panel is a file in this folder and a line here;
/// replacing a placeholder's body touches neither this list nor the host.
@MainActor
enum BarPanels {
    static let all: [BarPanelRegistration] = [
        ClockPanel.registration,
        SystemPanel.registration,
        CloudPanel.registration,
        BatteryPanel.registration,
        WifiPanel.registration,
        LabVPNPanel.registration,
        SoundPanel.registration,
        GroveMenuPanel.registration,
    ]

    static func named(_ name: String) -> BarPanelRegistration? {
        all.first { $0.name == name }
    }
}
