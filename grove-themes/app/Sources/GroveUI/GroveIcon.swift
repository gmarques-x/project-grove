import SwiftUI

/// One of Grove's icons: an SF Symbol, set like the text beside it.
///
/// Decided by the owner from comparison renders on 2026-11-12: Grove's icons
/// are SF Symbols, not characters typed in the text face (− + ▾ ✓ ↩ ●, as
/// they were until then), the Return mark in a hint line included. Key
/// legends (⌥ ⇧ ⌘ ← in a key's name) are text and stay text, as does
/// anything in a tooltip, which can only hold text; Grove's own marks are
/// shapes (`PineShape`).
///
/// One sizing rule for every icon: the system font at the size of the text
/// the icon sits beside (a `GroveType` value), weight `.medium` (`.bold`
/// where that text is bold), in the colour of the role the caller gives it,
/// inline on the text's baseline. No icon is nudged or resized on its own;
/// a symbol that looks too big or too small is a question about the rule.
///
/// A symbol is as wide as it is drawn, not one character cell: where a column
/// has to line up, the caller gives the icon a fixed frame.
///
/// `GroveIcon(.remove, size: GroveType.label)` is a view, hidden from
/// VoiceOver (the control it sits in carries the label).
/// `GroveIcon.text(.menu, size: GroveType.label)` is the same drawing as a
/// `Text`, to join to the words it belongs to with `+`.
public struct GroveIcon: View {
    /// Every icon Grove uses, named by its job; the raw value is the SF
    /// Symbol's name. A new icon is a new case here, not a symbol name in a view.
    public enum Name: String, CaseIterable, Sendable {
        /// Take a row away (a binding row's button).
        case remove = "minus"
        /// Add one ("Add binding").
        case add = "plus"
        /// This opens a menu of values (`GroveSelectPill`, a Monitors cell).
        case menu = "chevron.down"
        /// The current one of several (a launcher row, a scheme tile).
        case current = "checkmark"
        /// Return runs this (the selected row of the searchable cheat sheet).
        case run = "return"
        /// A dot that carries a colour ("on"; the dot of `ThemeColors.marked`).
        case dot = "circle.fill"

        // The bar's panels (spec 2026-11-12-bar-panels-design): each bar
        // item's symbol, then what their rows need.
        /// The processor (the CPU & memory panel's first header).
        case cpu = "cpu"
        /// Memory.
        case memory = "memorychip"
        /// The battery, as the bar draws it: a bolt.
        case battery = "bolt.fill"
        /// Online through Wi-Fi.
        case wifi = "wifi"
        /// Online through a cable.
        case ethernet = "cable.connector"
        /// Online through a tunnel.
        case vpn = "lock.shield"
        /// Not online.
        case offline = "wifi.slash"
        /// Sound, at a middling level (the sound panel's header).
        case sound = "speaker.wave.2.fill"
        /// The quiet end of the volume slider.
        case soundLow = "speaker.fill"
        /// The loud end of the volume slider.
        case soundHigh = "speaker.wave.3.fill"
        /// Sound is muted.
        case muted = "speaker.slash.fill"
        /// A date.
        case calendar = "calendar"
        /// Arriving (a download rate).
        case down = "arrow.down"
        /// Leaving (an upload rate).
        case up = "arrow.up"
        /// Onwards: a row's submenu, the next month, a section to open.
        case forward = "chevron.right"
        /// Back: the previous month.
        case back = "chevron.left"
        /// A click copies this value.
        case copy = "doc.on.doc"
        /// Do it again ("Run again").
        case again = "arrow.clockwise"
        /// The Mac's own speakers or microphone.
        case laptop = "laptopcomputer"
        /// Earphones.
        case airpods = "airpodspro"
        /// A display (its speakers).
        case display = "display"
        /// Headphones or a headset.
        case headphones = "headphones"
        /// An AirPlay receiver.
        case airPlay = "airplayaudio"
        /// A sound device on USB.
        case usbAudio = "cable.connector.horizontal"
        /// A speaker that is none of the above (Bluetooth, an aggregate).
        case speaker = "hifispeaker"
        /// Sound input.
        case microphone = "mic"
        /// The Grove menu's Appearance row.
        case appearance = "paintpalette"
        /// The Grove menu's Grove Keys row.
        case keys = "keyboard"
        /// The Grove menu's Update row.
        case update = "arrow.triangle.2.circlepath"
        /// The Grove menu's Learn row.
        case learn = "book"
        /// The Grove menu's About row.
        case about = "info.circle"
        /// The Grove menu's System row (lock, sleep, shut down).
        case power = "power"
        /// The Grove menu's Global Menu row: the front app's menus.
        case globalMenu = "menubar.rectangle"
        /// The Grove menu's Files row: Grove Explorer.
        case folder = "folder"

        // Grove Explorer (spec 2026-11-12-grove-explorer-design).
        /// The column a list is sorted by, ascending; turned upside down
        /// (by the header that draws it) for descending.
        case sorted = "chevron.up"
        /// Close this (a tab's own button).
        case close = "xmark"
        /// Eject a disk.
        case eject = "eject.fill"
        /// The Trash.
        case trash = "trash"
        /// iCloud Drive.
        case cloud = "icloud"
        /// A cloud provider's folder (OneDrive, Google Drive…): the plain cloud.
        case cloudStorage = "cloud"
        /// The window shows one pane.
        case onePane = "rectangle"
        /// The window shows two panes side by side.
        case twoPanes = "rectangle.split.2x1"
        /// A field that filters or searches what is under it.
        case search = "magnifyingglass"
        /// A warning, in the orange accent: the mark that carries the colour
        /// where orange words would be too faint (a broken link's target).
        case warning = "exclamationmark.triangle.fill"
        /// A shared folder on a server (the sidebar's SHARED rows).
        case server = "server.rack"

        /// The SF Symbol's name.
        public var symbol: String { rawValue }
    }

    let name: Name
    let size: CGFloat
    let weight: Font.Weight

    /// `size`: the `GroveType` size of the text beside the icon.
    public init(_ name: Name, size: CGFloat, weight: Font.Weight = .medium) {
        self.name = name
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        Self.text(name, size: size, weight: weight).accessibilityHidden(true)
    }

    /// The icon as text, to join to its words (`Text("Escape ") + …`). The
    /// symbol says nothing to VoiceOver; label the control it is part of.
    public nonisolated static func text(_ name: Name, size: CGFloat, weight: Font.Weight = .medium) -> Text {
        Text(Image(systemName: name.symbol)).font(.system(size: size, weight: weight)).accessibilityLabel("")
    }
}
