import Foundation

/// Why this exists: the window borders are drawn by JankyBorders
/// (`borders`), and it draws each border as a window of its own. When
/// Mission Control, App Exposé or Show Desktop moves the real windows into
/// its overview, those border windows stay where the windows were, so green
/// and grey outlines hang over the overview. `borders` has no option for
/// it; Grove Keys makes them transparent while the overview is up and puts
/// the scheme's colours back when it ends.
public enum Borders {
    /// macOS 27 doesn't say when an overview comes up or ends: the Dock's
    /// old "AXExpose…" notifications are gone and WindowManager, which runs
    /// the overview now, refuses them. What can be seen is its shield window,
    /// on screen for as long as the overview is: `overviewIsUp`.
    ///
    /// Looking costs a few milliseconds (the bar alone is a hundred small
    /// windows), so nothing polls. The Dock and WindowManager do post these
    /// general Accessibility notifications when an overview opens and closes
    /// (and at other times): each is only a reason to look.
    public static let triggerNotifications = [
        "AXSelectedChildrenChanged",
        "AXFocusedUIElementChanged",
        "AXCreated",
        "AXUIElementDestroyed",
    ]
    /// Whose notifications: the Dock and WindowManager, by bundle ID.
    public static let triggerApps = ["com.apple.dock", "com.apple.WindowManager"]

    /// While an overview is up, how often to look for its end, in case the
    /// notification for it is missed.
    public static let recheck: TimeInterval = 0.5

    /// An overview (Mission Control, App Exposé, Show Desktop) is on screen:
    /// WindowManager has a window in the layers it uses only then (the
    /// Spaces bar at 14, app icons at 17, the shield at 19). At rest its
    /// windows are far below the desktop's. `windows` is the on-screen list
    /// as (owner's name, layer); names need no Screen Recording permission.
    public static func overviewIsUp(windows: [(owner: String, layer: Int)]) -> Bool {
        windows.contains { $0.owner == "WindowManager" && (10...20).contains($0.layer) }
    }

    /// Fully transparent, as `borders` takes colours (0xAARRGGBB).
    public static let transparent = "0x00000000"

    /// What `borders` is told to hide them: both colours transparent, and
    /// nothing else. The width stays (changing it would lay the windows out
    /// again) and the process stays (a running `borders` takes new
    /// arguments from a second invocation).
    public static let hideArguments = ["active_color=" + transparent, "inactive_color=" + transparent]

    /// With no exit this long after an enter, the borders come back anyway.
    public static let lastResort: TimeInterval = 60

    /// The rendered config (grove-themes writes it from the current
    /// scheme): `borders/bordersrc` in the config folder, `$XDG_CONFIG_HOME`
    /// first. Running it puts the colours back, a scheme switched to in the
    /// meantime included.
    public static func config(home: URL, environment: [String: String]) -> URL {
        KeysPaths.configDirectory(home: home, environment: environment).appendingPathComponent("borders/bordersrc")
    }

    /// Where `borders` is: Homebrew's folder first, then `PATH`; nil when
    /// it isn't installed.
    public static func binary(environment: [String: String], isExecutable: (String) -> Bool) -> String? {
        let folders = ["/opt/homebrew/bin"] + (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return folders.map { $0 + "/borders" }.first(where: isExecutable)
    }
}

/// What the borders should be now. Pure: the app feeds it what happens and
/// runs the command it answers with, if any. The commands are idempotent
/// (hiding twice or restoring twice changes nothing), so the machine errs
/// on the side of restoring.
public struct BordersMachine: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        /// Grove Keys started: whatever an earlier run left, the borders show.
        case started
        /// An overview came up.
        case entered
        /// The overview ended.
        case exited
        /// `Borders.lastResort` passed since the enter numbered `enter`.
        case timedOut(enter: Int)
        /// The Dock or WindowManager restarted (their notifications with it): an exit may have been missed.
        case dockRestarted
        /// Grove Keys is quitting or restarting.
        case shuttingDown
    }

    public enum Command: Equatable, Sendable {
        case hide
        case restore
    }

    /// The borders are transparent because of this machine.
    public private(set) var hidden = false
    /// Counts enters, so a timeout set by an earlier one does nothing.
    public private(set) var enters = 0

    public init() {}

    public mutating func handle(_ event: Event) -> Command? {
        switch event {
        case .started:
            hidden = false
            return .restore
        case .entered:
            // A second enter (Mission Control, then App Exposé from it)
            // hides nothing again, but the last resort counts from it.
            enters += 1
            guard !hidden else { return nil }
            hidden = true
            return .hide
        case .exited:
            // Also without an enter seen (Grove Keys started mid-overview).
            hidden = false
            return .restore
        case .timedOut(let enter):
            guard hidden, enter == enters else { return nil }
            hidden = false
            return .restore
        case .dockRestarted, .shuttingDown:
            guard hidden else { return nil }
            hidden = false
            return .restore
        }
    }
}
