import Foundation
import GroveThemesCore

// The cloud pill's dropdown (spec 2026-11-14-bar-cloud-design): what each
// provider's section shows, the sample states `--render-panel cloud` draws,
// and the rules for reaching OneDrive's settings through Accessibility.
// The views are Grove Keys' (Panels/CloudPanel.swift).

extension CloudWords {
    /// A provider with nothing found yet while the first pass runs.
    public static let checking = "Checking…"
    /// No iCloud Drive and nothing in CloudStorage.
    public static let noFolders = "No cloud folders on this Mac"
    /// The can't-see line's button.
    public static let privacySettings = "Privacy Settings…"
}

extension CloudLinks {
    /// System Settings ▸ Privacy & Security ▸ Files and Folders, where a
    /// refused provider's files are allowed again.
    public static let filesPrivacy =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
    /// System Settings' bundle id: iCloud's fallback when its link doesn't open.
    public static let systemSettings = "com.apple.systempreferences"
}

/// How a line is coloured: quiet, a warning (yellow) or an error (red).
public enum CloudTone: Equatable, Sendable {
    case quiet, warning, error
}

/// One provider's section of the dropdown, as drawn.
public struct CloudSection: Equatable, Sendable, Identifiable {
    /// The header's cloud: its colour says the state.
    public enum Mark: Equatable, Sendable {
        /// Still looking (grey).
        case checking
        /// Up to date (green).
        case synced
        /// Files on their way (yellow).
        case syncing
        /// A problem or not running (red).
        case problem
        /// macOS refused its files (grey; the pill leaves it out).
        case unseen
    }

    /// Whose settings "Settings…" opens.
    public enum Settings: Equatable, Sendable {
        case iCloud, oneDrive
    }

    /// A pending or failed file.
    public struct Row: Equatable, Sendable, Identifiable {
        /// What the row's icon says.
        public enum Direction: Equatable, Sendable {
            case up, down, problem
        }

        /// The file's path.
        public let id: String
        public let name: String
        /// Its folder below the provider's (the provider's title at the top).
        public let folder: String
        /// The problem line, nil while just pending.
        public let problem: String?
        /// A provider's error or a conflict is red; a file stuck for 30
        /// minutes is a warning; pending is quiet.
        public let tone: CloudTone
        public let direction: Direction
        /// Grove Explorer at the file (its folder, the file selected).
        public let link: URL

        init(_ row: CloudRow) {
            id = row.id
            name = row.name
            folder = row.folder
            problem = row.problem
            let stuck = row.problem == CloudPending.stuckMessage || row.problem == CloudPending.stuckDownloadMessage
            tone = row.problem == nil ? .quiet : stuck ? .warning : .error
            switch row.state {
            case .uploading, .notUploaded: direction = .up
            case .downloading: direction = .down
            case .problem, .settled: direction = .problem
            }
            link = CloudLinks.explorer(row.url)
        }
    }

    /// The provider's folder.
    public let id: String
    public let name: String
    public let root: URL
    public let mark: Mark
    /// The status line under the name.
    public let line: String
    public let tone: CloudTone
    /// Up to five, in the summary's stable order.
    public let rows: [Row]
    /// "Settings…", for iCloud and OneDrive only.
    public let settings: Settings?
    /// The can't-see line has a button to Files and Folders.
    public let offersFilesPrivacy: Bool
    /// "Open in Grove Explorer": the provider's folder.
    public let opens: URL

    public var showsSettings: Bool { settings != nil }

    /// `checking`: the pill is still checking, so a provider with nothing
    /// found yet says "Checking…" rather than "Up to date".
    public init(_ provider: CloudProviderSummary, checking: Bool) {
        id = provider.id
        name = provider.name
        root = provider.place.url
        rows = provider.rows.map(Row.init)
        offersFilesPrivacy = provider.access == .cantSee
        opens = CloudLinks.explorer(provider.place.url)
        if provider.place.kind == .iCloudDrive {
            settings = .iCloud
        } else {
            settings = CloudProviderSummary.bundleID(for: provider.place) == OneDriveSettings.bundleID ? .oneDrive : nil
        }
        switch provider.access {
        case .cantSee:
            mark = .unseen
            line = provider.statusLine
            tone = .warning
        case .notRunning:
            mark = .problem
            line = provider.statusLine
            tone = .error
        case .ok where provider.problems > 0:
            mark = .problem
            line = provider.statusLine
            tone = .error
        case .ok where provider.pending > 0:
            mark = .syncing
            line = provider.statusLine
            tone = .quiet
        case .ok where checking || provider.needsRescan:
            mark = .checking
            line = CloudWords.checking
            tone = .quiet
        case .ok:
            mark = .synced
            line = provider.statusLine
            tone = .quiet
        }
    }

    /// Every provider's section, in the summary's order.
    public static func sections(_ summary: CloudSummary) -> [CloudSection] {
        summary.providers.map { CloudSection($0, checking: summary.pill == .checking) }
    }
}

/// The states `GroveKeys --render-panel cloud` draws (GROVE_CLOUD_SAMPLE),
/// on invented folders and file names (the repo is public): iCloud Drive and
/// OneDrive in `/Users/someone`.
public enum CloudSample {
    public static let home = URL(fileURLWithPath: "/Users/someone")
    public static let names = ["synced", "syncing", "problem", "notrunning", "cantsee", "checking", "none"]

    /// `synced` (the default), `syncing` (four files on their way),
    /// `problem` (an upload error, a conflict and a stuck file in OneDrive),
    /// `notrunning` (OneDrive's app quit), `cantsee` (OneDrive's files
    /// refused), `checking` (the first pass under way), `none` (no folders).
    public static func summary(_ name: String) -> CloudSummary {
        let iCloud = CloudProviders.iCloudDrivePlace(home: home)
        let oneDrive = CloudProviders.place(
            "OneDrive-Personal", CloudProviders.provider(folderName: "OneDrive-Personal")!, home: home)
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var pending = CloudPending()
        var access: CloudProviderAccess = .ok
        var firstPassDone = true
        func add(_ place: CloudProviders.CloudPlace, _ path: String, _ state: CloudItemState, _ second: Double) {
            pending.update(place.url.appendingPathComponent(path), root: place.url, state: state,
                           at: start.addingTimeInterval(second))
        }
        switch name {
        case "syncing":
            add(iCloud, "Notes/Garden plan.md", .uploading, 1)
            add(iCloud, "Photos/Seedlings.heic", .uploading, 2)
            add(iCloud, "Recipes/Bread.pdf", .downloading, 3)
            add(oneDrive, "Documents/Budget 2026.xlsx", .notUploaded, 4)
        case "problem":
            // Half an hour on, the old letter has stopped moving; then a new upload.
            add(oneDrive, "Documents/Budget 2026.xlsx", .problem("couldn't upload"), 2)
            add(oneDrive, "Documents/Trip notes.docx", .problem("unresolved conflict"), 3)
            add(oneDrive, "Archive/Old letter.txt", .notUploaded, 4)
            pending.expire(at: start.addingTimeInterval(CloudPending.stuckAfter + 10))
            add(iCloud, "Notes/Garden plan.md", .uploading, CloudPending.stuckAfter + 20)
        case "notrunning":
            access = .notRunning
        case "cantsee":
            access = .cantSee
        case "checking":
            firstPassDone = false
            add(iCloud, "Notes/Garden plan.md", .uploading, 1)
        case "none":
            return CloudSummary(places: [], pending: pending, access: { _ in .ok }, firstPassDone: true)
        default:
            break
        }
        let oneDriveAccess = access
        return CloudSummary(places: [iCloud, oneDrive], pending: pending,
                            access: { $0 == oneDrive ? oneDriveAccess : .ok }, firstPassDone: firstPassDone)
    }
}

/// OneDrive's "Settings…". OneDrive (`com.microsoft.OneDrive`) is a menu-bar
/// app with no URL or command for its settings, and the native menu bar is
/// behind the Grove bar, so Grove Keys presses its status item through
/// Accessibility, as the VPN's "Manage Tunnels…": a menu with a settings
/// item (or "Help & Settings" ▸ "Settings") is pressed through; an activity
/// window instead has its settings button found by role and words. What is
/// pure about it is here; the presses are Grove Keys' (OneDriveSettingsOpener).
public enum OneDriveSettings {
    public static let bundleID = CloudProviderSummary.oneDriveBundleID

    /// A title lower-cased, its spaces trimmed and collapsed, a trailing
    /// ellipsis ("…" or "...") dropped.
    static func plain(_ title: String?) -> String? {
        guard var text = title?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.hasSuffix("…") {
            text.removeLast()
        } else if text.hasSuffix("...") {
            text.removeLast(3)
        }
        let words = text.lowercased().split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// A menu item that opens the settings: "Settings" or "Preferences",
    /// any case, with or without an ellipsis. Nothing else.
    public static func isSettingsItem(_ title: String?) -> Bool {
        guard let text = plain(title) else { return false }
        return text == "settings" || text == "preferences"
    }

    /// The menu that holds Settings in OneDrive's menus: "Help & Settings".
    public static func isHelpAndSettings(_ title: String?) -> Bool {
        guard let text = plain(title) else { return false }
        return text == "help & settings" || text == "help and settings"
    }

    /// What to do in a menu: press its settings item, or open its "Help &
    /// Settings" submenu and look there.
    public enum MenuChoice: Equatable, Sendable {
        case press(Int)
        case open(Int)
    }

    /// A settings item first, wherever it is; else the help submenu; else nil.
    public static func menuChoice(in titles: [String?]) -> MenuChoice? {
        if let index = titles.firstIndex(where: isSettingsItem) { return .press(index) }
        if let index = titles.firstIndex(where: isHelpAndSettings) { return .open(index) }
        return nil
    }

    /// An element of OneDrive's activity window, as Accessibility tells it:
    /// its role and its words (title, description, help, identifier).
    public struct Element: Equatable, Sendable {
        public let role: String?
        public let texts: [String?]

        public init(role: String?, texts: [String?]) {
            self.role = role
            self.texts = texts
        }
    }

    static let buttonRoles: Set<String> = ["AXButton", "AXMenuButton", "AXPopUpButton"]
    static let settingsWords: Set<String> = ["settings", "preferences", "gear", "gearshape"]

    /// A button whose words have "settings", "preferences" or a gear (the
    /// symbol's name, which is what an icon-only button often says).
    public static func isSettingsButton(_ element: Element) -> Bool {
        guard let role = element.role, buttonRoles.contains(role) else { return false }
        return element.texts.contains { text in
            guard let text else { return false }
            return text.lowercased().split { !$0.isLetter }.contains { settingsWords.contains(String($0)) }
        }
    }

    /// The settings button among a window's elements: one that says just
    /// "Settings" or "Preferences" first, else the first settings button.
    public static func settingsButtonIndex(in elements: [Element]) -> Int? {
        let buttons = elements.indices.filter { isSettingsButton(elements[$0]) }
        return buttons.first { elements[$0].texts.contains(where: isSettingsItem) } ?? buttons.first
    }

    /// A window that is OneDrive's settings: its title has "Settings" or
    /// "Preferences" ("OneDrive Settings").
    public static func isSettingsWindow(_ title: String?) -> Bool {
        guard let text = plain(title) else { return false }
        return text.split(separator: " ").contains { $0 == "settings" || $0 == "preferences" }
    }

    /// The press took: the menu it was in went away, OneDrive has more
    /// windows than before, or one of them is its settings. (A press's own
    /// answer isn't trusted: in a tracking menu it can say it failed
    /// although it worked.)
    public static func pressTook(menuGone: Bool = false, windowsBefore: Int, windowsAfter: Int,
                                 titles: [String?]) -> Bool {
        menuGone || windowsAfter > windowsBefore || titles.contains(where: isSettingsWindow)
    }

    /// Why the settings couldn't be pressed. Either way OneDrive is brought
    /// forward and the dropdown says, in yellow, where its settings are.
    public enum Reason: Equatable, Sendable {
        /// Grove Keys may not use Accessibility: also says so, with a
        /// Privacy Settings… button.
        case notTrusted
        /// Anything else: not running after the launch, no status item,
        /// nothing opened, no settings item or button, or the press didn't take.
        case notFound

        public var line: String { CloudWords.oneDriveSettingsFallback }

        public var permissionLine: String? {
            self == .notTrusted ? WireGuardMenu.Reason.notTrusted.line : nil
        }
    }

    public enum Outcome: Equatable, Sendable {
        /// The settings item or button was pressed and its window came.
        case pressed
        case fallback(Reason)
    }

    public typealias Hint = FallbackHint<Reason>

    /// How far the press got. Every step defaults to failed.
    public struct Steps: Equatable, Sendable {
        /// Grove Keys may use Accessibility.
        public var trusted = false
        /// OneDrive was running (after a launch and a short wait).
        public var running = false
        /// OneDrive's status items (`StatusItemLocator`: on macOS 27 through MenuBarAgent).
        public var statusItems = 0
        /// One of them opened a menu or a window.
        public var opened = false
        /// That has a settings item or button.
        public var found = false
        /// Its press took (`pressTook`).
        public var pressed = false

        public init(trusted: Bool = false, running: Bool = false, statusItems: Int = 0, opened: Bool = false,
                    found: Bool = false, pressed: Bool = false) {
            self.trusted = trusted
            self.running = running
            self.statusItems = statusItems
            self.opened = opened
            self.found = found
            self.pressed = pressed
        }

        public var outcome: Outcome {
            guard trusted else { return .fallback(.notTrusted) }
            return running && statusItems > 0 && opened && found && pressed ? .pressed : .fallback(.notFound)
        }
    }
}
